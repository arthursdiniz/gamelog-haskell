# GameLog

Biblioteca pessoal para organizar jogos em **Quero jogar**, **Jogando** e **Jogados**, com notas de meia em meia estrela e reviews pessoais. O servidor escuta em `127.0.0.1`, para uso local, em um único perfil.

## Executar no Windows 11

### 1. Instalar as ferramentas

Siga a instalação para Windows e selecione GHC, Cabal e MSys2. Abra um novo PowerShell ao terminar. [Instalação oficial do GHCup](https://www.haskell.org/ghcup/install/#how-to-install)

Instale o FFmpeg e coloque a pasta do executável no `PATH` para validar as capturas. Verifique com `ffmpeg -version` em um novo PowerShell. [Downloads do FFmpeg](https://ffmpeg.org/download.html)

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

Se o banco já possui a tabela `jogos`, use as migrações abaixo antes de iniciar a nova versão. Elas podem ser executadas novamente e preservam os dados antigos.

```powershell
psql -W -d biblioteca_jogos -v ON_ERROR_STOP=1 -f .\migracao-biblioteca.sql
psql -W -d biblioteca_jogos -v ON_ERROR_STOP=1 -f .\migracao-screenshots.sql
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

## Uso e teste rápido

1. Em **Adicionar jogo**, busque `Elden Ring` e selecione um resultado. O nome, a capa e o identificador do resultado são associados ao formulário. A CheapShark oferece pesquisa pública diretamente no navegador. [Documentação da CheapShark](https://apidocs.cheapshark.com/)
2. Escolha uma categoria e clique em **Adicionar à biblioteca**. O mesmo resultado da CheapShark só pode ser salvo uma vez. É possível preencher o formulário manualmente em qualquer momento.
3. Em **Minha Biblioteca**, filtre por categoria e digite parte de um nome para combinar os dois filtros.
4. Abra um card, expanda **Editar informações**, altere a categoria, escolha uma nota e escreva uma review. Escolha **Sem nota** para remover a avaliação ou esvazie a review para removê-la.
5. Abra um jogo e, em **Minhas capturas de tela**, selecione um PNG, JPG ou WebP e clique em **Adicionar captura**. O limite é de 5 MB por imagem (5.242.880 bytes). Repita para adicionar outras imagens.
6. Clique numa miniatura para ampliá-la. Use **Excluir captura** para remover somente essa imagem ou **Excluir da biblioteca** para remover o jogo e suas capturas.

Os arquivos ficam na pasta `uploads/` do diretório de onde o aplicativo foi iniciado. O PostgreSQL guarda o vínculo com o jogo e o nome do arquivo. Para preservar as capturas ao mover a instalação, mantenha o banco e essa pasta juntos. A pasta é ignorada pelo Git.

As anotações são guardadas no PostgreSQL local. O aplicativo serve uma única biblioteca e permite acesso a ela a partir do próprio computador.

O material para a avaliação oral está no [EXPLICACAO.md](EXPLICACAO.md).
