# Minha Biblioteca de Jogos

Site local para cadastrar, listar, editar e excluir jogos. Cada jogo tem nome, gênero e plataforma.

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

As opções de compilação apontam para a biblioteca cliente do PostgreSQL instalada no Windows. Com o terminal aberto, acesse [Minha Biblioteca de Jogos](http://127.0.0.1:8080/). Use `Ctrl+C` para parar o servidor. Em um novo PowerShell, repita o passo 2 e as duas primeiras linhas do passo 5 antes do comando `cabal run`.

## Teste rápido

1. Cadastre `Celeste`, `Plataforma` e `PC`. Confira a entrada na lista.
2. Use **Editar**, mude a plataforma para `Switch` e salve.
3. Reinicie o aplicativo e confirme que a edição ficou gravada.
4. Use **Excluir** e confirme que a entrada saiu da lista.

O material para a avaliação oral está no [EXPLICACAO.md](EXPLICACAO.md).
