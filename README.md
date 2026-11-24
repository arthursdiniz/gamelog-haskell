# GameLog

Biblioteca pessoal para organizar jogos em **Quero jogar**, **Jogando** e **Jogados**, com notas de meia em meia estrela e reviews pessoais. O servidor escuta em `127.0.0.1`, para uso local, em um único perfil.

O Servant oferece uma API JSON e serve `index.html`, `style.css` e `script.js` na mesma porta. O navegador usa `fetch` para ler e salvar jogos. Compilar o executável Haskell é o único passo de build.

## Executar no Windows 11

### 1. Instalar as ferramentas

Siga a instalação para Windows e selecione GHC, Cabal e MSys2. Abra um novo PowerShell ao terminar. [Instalação oficial do GHCup](https://www.haskell.org/ghcup/install/#how-to-install)

Instale o PostgreSQL com **PostgreSQL Server** e **Command Line Tools**. Guarde a senha definida para o usuário `postgres` e mantenha a porta padrão `5432` se estiver disponível. O projeto foi testado com PostgreSQL 18. [Instalador oficial para Windows](https://www.postgresql.org/download/windows/)

### 2. Configurar o PowerShell

Abra o PowerShell na pasta do projeto. Ajuste o caminho do PostgreSQL se a sua instalação estiver em outra pasta ou usar outra versão.

```powershell
$postgres = 'C:\Program Files\PostgreSQL\18'
$env:Path = "$postgres\bin;$env:Path"
$env:PGHOST = '127.0.0.1'
$env:PGPORT = '5432'
$env:PGUSER = 'postgres'

ghc --version
cabal --version
pg_config --version
pg_isready
```

### 3. Criar o banco e a tabela

Execute cada comando uma vez. O PostgreSQL pedirá a senha ao conectar.

```powershell
createdb -W biblioteca_jogos
psql -W -d biblioteca_jogos -v ON_ERROR_STOP=1 -f .\banco.sql
```

Se o banco já possui a tabela `jogos` com as colunas `id`, `nome`, `status`, `nota` e `review`, a troca para a API JSON usa os dados existentes diretamente. Para preparar um banco de uma versão anterior da tabela, use as migrações abaixo. A segunda desvincula os registros legados para preservá-los quando um jogo for excluído.

```powershell
psql -W -d biblioteca_jogos -v ON_ERROR_STOP=1 -f .\migracao-biblioteca.sql
psql -W -d biblioteca_jogos -v ON_ERROR_STOP=1 -f .\migracao-preservar-legado.sql
```

### 4. Configurar a senha do aplicativo

Abra o arquivo de senhas do PostgreSQL, que fica fora da pasta do projeto.

```powershell
New-Item -ItemType Directory -Path "$env:APPDATA\postgresql" -Force | Out-Null
notepad "$env:APPDATA\postgresql\pgpass.conf"
```

Se o Bloco de Notas perguntar se deve criar o arquivo, confirme. Acrescente a linha abaixo, trocando `SUA_SENHA` pela senha que você definiu. Se já houver uma linha genérica para a mesma conexão, coloque esta antes dela. Salve o arquivo com o nome `pgpass.conf`.

```text
127.0.0.1:5432:biblioteca_jogos:postgres:SUA_SENHA
```

Na senha, escreva `\:` para representar dois-pontos e `\\` para representar uma barra invertida. Confirme que a conexão funciona sem perguntar a senha. [Arquivo de senhas do PostgreSQL](https://www.postgresql.org/docs/18/libpq-pgpass.html)

```powershell
psql -w -d biblioteca_jogos -c "SELECT 1;"
```

### 5. Compilar e iniciar

```powershell
$pastaCliente = pg_config --bindir
$env:LDFLAGS = "-L$pastaCliente"
cabal update
cabal build "--extra-lib-dirs=$pastaCliente"
cabal run biblioteca-jogos "--extra-lib-dirs=$pastaCliente"
```

O Cabal baixa as dependências durante o build. As opções de compilação apontam para a biblioteca cliente do PostgreSQL. Acesse [GameLog](http://127.0.0.1:8080/). Use `Ctrl+C` para parar o servidor. Em outro PowerShell, refaça a configuração do passo 2 e as duas primeiras linhas do passo 5.

Se a porta 8080 estiver ocupada, defina `$env:GAMELOG_PORT = '18080'` antes de iniciar e abra `http://127.0.0.1:18080/`. Para usar outro banco, defina `PGDATABASE` antes de iniciar. O padrão é `biblioteca_jogos`.

## Uso e teste rápido

1. Em **Adicionar jogo**, digite um nome, escolha a categoria e clique em **Adicionar à biblioteca**.
2. A nota e a review são opcionais. Use as estrelas ou o seletor para escolher a nota.
3. Em **Minha Biblioteca**, filtre por categoria e digite parte de um nome para combinar os dois filtros.
4. Abra um card, expanda **Editar informações**, altere a categoria, escolha uma nota e escreva uma review. Escolha **Sem nota** para remover a avaliação ou esvazie a review para removê-la.
5. Use **Excluir da biblioteca** e confirme para remover um jogo.

As anotações são guardadas no PostgreSQL local. O aplicativo serve uma única biblioteca e permite acesso a ela a partir do próprio computador.

## API JSON

| Método e caminho | Resposta |
| --- | --- |
| `GET /api/jogos` | **200** e a lista de jogos. |
| `GET /api/jogos/:id` | **200** e o jogo, ou **404**. |
| `POST /api/jogos` | **201** e o ID criado. |
| `PUT /api/jogos/:id` | **204** ou **404**. |
| `DELETE /api/jogos/:id` | **204** ou **404**. |

No cadastro e na edição, envie `Content-Type: application/json` e um corpo como este.

```json
{"nome": "Ação e Aventura", "status": "jogando", "nota": 4.5, "review": "Ótima trilha sonora."}
```

Os valores de `status` são `quero-jogar`, `jogando` e `jogados`. Use `"nota": null` para deixar o jogo sem avaliação. `"nota": 0` registra uma avaliação de zero. Dados inválidos retornam **400**.
