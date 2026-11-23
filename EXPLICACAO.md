# Entendendo Minha Biblioteca de Jogos

O navegador mostra uma página HTML. Quando você abre a página ou envia um formulário, o Servant escolhe a função que deve responder. Essa função consulta o PostgreSQL ou altera a tabela `jogos`. O [README](README.md) contém as instruções de instalação.

## Os tipos em `Main.hs`

- `data DadosJogo = DadosJogo Text Text Text` cria um tipo e um construtor com o mesmo nome. O construtor reúne nome, gênero e plataforma. `cadastrar (DadosJogo nome genero plataforma)` retira os três valores na mesma ordem em que foram guardados.
- `type Jogo = (Int32, Text, Text, Text)` dá um nome à tupla de quatro valores que vem do banco. O primeiro é o identificador. `Int32` é um inteiro com sinal de 32 bits, a mesma faixa do `INTEGER` que o PostgreSQL usa para o `SERIAL`. Já `Int` é o tipo do limite de caracteres em `validarCampo`.
- `Text` guarda texto, inclusive acentos. `String` é uma lista de caracteres. `show identificador` devolve uma `String` e `Texto.pack` converte essa `String` em `Text` para montar a URL.
- `Maybe Jogo` representa uma edição opcional. `Nothing` mostra o cadastro vazio e `Just jogo` preenche o formulário com o jogo selecionado.
- `Either Text Text` representa erro ou acerto. `Left mensagem` carrega a mensagem da validação e `Right valor` carrega o texto aceito.
- `type API = ...` dá um nome ao conjunto de rotas. O Servant usa esse tipo para conferir os argumentos, métodos e retornos das funções ligadas a ele.

## O que cada importação traz

| Importação | Uso no projeto |
| --- | --- |
| `Control.Exception` | `bracket` abre e fecha a conexão em torno de uma operação. `try` converte uma exceção do tipo indicado em `Left` e um resultado normal em `Right`. |
| `Control.Monad.IO.Class` | `liftIO` permite fazer uma ação de `IO`, como acessar o banco, dentro de um `Handler`. |
| `Data.Int` | Fornece `Int32` para o identificador. |
| `Data.List` | `find` procura na lista o primeiro jogo com o ID pedido. |
| `Data.Text` e `Data.Text.IO` | A primeira fornece o tipo `Text` e operações como `strip`, `length` e `pack`. A segunda lê `style.css` como texto. Os apelidos `Texto` e `ArquivoTexto` deixam a origem das funções visível. |
| `Database.PostgreSQL.Simple` | Abre e fecha conexões, consulta linhas com `query_` e executa alterações com `execute`. `Only` envolve um parâmetro único e `SqlError` descreve falhas reportadas pela biblioteca. |
| `Lucid` | Monta HTML com funções que correspondem a tags e atributos. `toHtml` escreve o texto de um jogo com o escape exigido pelo HTML. |
| `Network.Wai.Handler.Warp` | Inicia o servidor HTTP e configura endereço e porta. |
| `Paths_biblioteca_jogos` | Módulo gerado pelo Cabal. `getDataFileName` localiza o CSS declarado em `data-files`. |
| `Servant` | Exporta os tipos de rota, `Handler`, `Server`, `serve`, `Proxy` e os códigos HTTP usados no projeto. |
| `Servant.HTML.Lucid` | Liga `Html ()` ao formato de resposta `HTML` do Servant. |
| `Web.FormUrlEncoded` | Fornece `FromForm` para converter o formulário e `parseUnique` para ler exatamente um valor de cada campo. |
| `Prelude` (automática) | Fornece tipos e funções básicos como `Int`, `Maybe`, `Either`, `pure`, `show`, `null` e `mapM_`. |

## Funções do backend

| Função | O que recebe e o que devolve |
| --- | --- |
| `main` | Começa a execução. Lê o CSS, anuncia o endereço, liga a definição `API` a `servidor css` com `serve` e inicia o Warp em `127.0.0.1:8080`. `IO ()` indica uma ação cujo resultado final é a unidade `()`. |
| `servidor` | Recebe o CSS e devolve `Server API`, com as quatro funções na mesma ordem das rotas. `listar css` deixa apenas o argumento opcional da edição para o Servant preencher. |
| `fromForm` | Recebe os campos brutos do formulário. Lê os campos pelos nomes usados no HTML, valida cada um e devolve `Right (DadosJogo ...)` ou `Left mensagem`. A declaração `instance FromForm DadosJogo` ensina ao Servant a fazer essa conversão para o nosso tipo. |
| `validarCampo` | Recebe o rótulo, o limite e o texto digitado. `limpo` é o texto com os espaços das pontas removidos. O resultado é um `Left` se vazio, longo demais ou com caractere nulo, e um `Right` com o texto limpo se válido. |
| `comBanco` | Recebe uma função que usa uma `Connection` e devolve uma ação `Handler a`. O `a` representa o tipo do resultado de cada operação. `abrir` cria a conexão. A função local `executar` recebe a conexão e usa `try` sobre a consulta. O `try` externo envolve o `bracket`, que fecha a conexão ao sair. |
| `listar` | Recebe o CSS e um ID opcional. Busca todos os jogos e devolve `Html ()`. Se houver um ID, `find` procura o jogo na lista para preencher a edição. Se o ID não estiver na lista, responde com 404. |
| `cadastrar` | Recebe `DadosJogo`, executa o `INSERT`, descarta a contagem de linhas e redireciona para a página inicial. |
| `editar` | Recebe o ID e os novos `DadosJogo`. O `UPDATE` devolve o número de linhas afetadas. Se for zero, responde com 404. Se alterar uma linha, redireciona. |
| `excluir` | Recebe o ID. O `DELETE` devolve o número de linhas removidas. Se for zero, responde com 404. Se remover uma linha, redireciona. |
| `voltarInicio` | Devolve a resposta HTTP 303 com o cabeçalho `Location: /`. `throwError` finaliza o `Handler` com a resposta HTTP escolhida. `NoContent` é o tipo declarado dos handlers de alteração, que encerram a operação pelo redirecionamento sem renderizar uma página nesse passo. |
| `pagina` | Recebe CSS, a lista de jogos e o jogo opcional da edição. Devolve o documento HTML completo e mostra uma mensagem se a lista estiver vazia. |
| `formulario` | Recebe URL de destino, nome, gênero, plataforma e texto do botão. Devolve o mesmo HTML de formulário para cadastro ou edição. |
| `mostrarJogo` | Recebe uma tupla `Jogo`. Devolve um item da lista com nome, gênero, plataforma, link de edição e formulário de exclusão. |

## Sintaxe Haskell usada no código

| Símbolo ou palavra | Como ler no projeto |
| --- | --- |
| `::` e `->` | `excluir :: Int32 -> Handler NoContent` se lê “excluir recebe um `Int32` e devolve um `Handler NoContent`”. Nas alternativas de `case`, `->` aponta para o que será feito quando o padrão aparecer. |
| `=` e `let` | `=` define um valor ou uma função. `let idTexto = ...` dá um nome a um valor local dentro de `do`. |
| `do`, `<-` e `pure` | `do` encadeia passos. `css <- ArquivoTexto.readFile caminhoCSS` executa a leitura e dá o nome `css` ao resultado. `pure` coloca um valor no contexto esperado, por exemplo `Right` na conversão do formulário ou uma resposta normal em `Handler`. |
| `\|`, `where`, `otherwise` | As guardas de `validarCampo` são testadas de cima para baixo. `otherwise` cobre o caso restante. `where` define nomes locais, como `limpo`. |
| `==` e `>` | Comparam dois valores. `alterados == 0` verifica se nenhuma linha mudou. `Texto.length limpo > limite` detecta texto acima do limite. |
| `<>` | Junta trechos de texto, por exemplo `"/?editar=" <> idTexto`. |
| `$` | Aplica a função à esquerda à expressão inteira à direita. `head_ $ do ...` é uma forma de escrever `head_ (do ...)`. |
| `\` e `_` | `\conexao -> ...` define uma função sem nome com um argumento. `_` ignora um valor, como as três colunas que `find` deixa de lado ao comparar IDs. O sublinhado final em `h1_` e `query_` faz parte do nome dessas funções. |
| `[]`, `'[...]`, `()` e tuplas | `[Jogo]` é o tipo de uma lista de jogos. `[("Location", "/")]` é uma lista com um par. `'[HTML]` é uma lista no nível dos tipos. `()` é o valor sem informação, por exemplo em `IO ()`. A tupla `Jogo` reúne quatro valores em uma ordem fixa. |
| `{...}` | `err404 {errBody = "Jogo inexistente."}` copia uma resposta padrão alterando o campo `errBody`. O mesmo formato define `errHeaders` no 303. |
| `:>` e `:<\|>` | `:>` liga partes de uma rota. `:<\|>` separa rotas no tipo `API` e liga os handlers na definição de `servidor`. |

As quatro linhas `LANGUAGE` no começo habilitam recursos específicos. `DataKinds` permite dizer, no tipo da rota, quais são os caminhos e formatos. `TypeOperators` permite escrever operadores como `:>` em tipos. `OverloadedStrings` permite usar literais entre aspas como `Text`, HTML ou SQL conforme o contexto. `ScopedTypeVariables` permite declarar o tipo `SqlError` nos padrões `Left`.

## Como Servant e HTML se encontram

`serve (Proxy :: Proxy API) (servidor css)` entrega ao Servant a descrição das URLs e a implementação correspondente. `Proxy` identifica qual tipo usar. Um `Handler` pode produzir o resultado esperado da rota ou terminar com uma resposta HTTP específica.

| Método e caminho | Como o Servant interpreta | Resultado |
| --- | --- | --- |
| `GET /` ou `GET /?editar=3` | `QueryParam "editar" Int32` lê a parte depois de `?` como número opcional. `Get '[HTML]` pede uma página HTML. | Lista os jogos e, com um ID existente, apresenta o formulário de edição. |
| `POST /jogos` | `ReqBody '[FormUrlEncoded] DadosJogo` lê os campos do corpo. | Cadastra e redireciona. |
| `POST /jogos/3/editar` | `Capture "id" Int32` lê o `3` do caminho. `ReqBody` lê os três campos enviados. | Edita e redireciona. |
| `POST /jogos/3/excluir` | `Capture` lê o ID. O caminho já indica o jogo que será excluído. | Exclui e redireciona. |

`Get` atende a leitura de páginas. `Post` recebe as alterações porque um formulário HTML pode enviar `POST` diretamente. A tag `form` informa o `method` e o `action`. Os nomes em `name_` viram as chaves do corpo, como `nome=Celeste&genero=Plataforma&plataforma=PC`. O próprio navegador envia o formulário e segue o redirecionamento. Ele interpreta o CSS do elemento `<style>`, preenchido com `style.css` ao gerar a página. As tags de `Lucid` ficam em `Main.hs` junto com os valores que o servidor deve preencher.

O Servant responde com 400 quando o formulário não passa pela conversão ou quando o parâmetro de consulta é inválido. Para um jogo inexistente, os handlers respondem com 404. Uma falha ao abrir a conexão retorna 503. Uma falha SQL durante a consulta retorna 500.

## Conexão e consultas SQL

`connectPostgreSQL "dbname=biblioteca_jogos connect_timeout=3"` indica o banco e o tempo limite em segundos para estabelecer a conexão a um endereço. A biblioteca cliente do PostgreSQL lê host, porta e usuário de `PGHOST`, `PGPORT` e `PGUSER`. A senha vem do arquivo de senhas configurado no Windows. Para cada operação, `bracket` abre uma conexão, roda a consulta e fecha a conexão mesmo em caso de erro durante a operação.

`banco.sql` cria a tabela `jogos`. A coluna `id SERIAL PRIMARY KEY` identifica cada linha e recebe um valor automaticamente no cadastro. As outras colunas exigem um valor e têm limites de 100, 50 e 50 caracteres.

- `SELECT id, nome, genero, plataforma FROM jogos ORDER BY id` devolve as quatro colunas, ordenadas pelo ID. `query_` executa a consulta sem parâmetros e cada linha vira uma tupla `Jogo`.
- `INSERT INTO jogos (nome, genero, plataforma) VALUES (?, ?, ?)` usa a tupla `(nome, genero, plataforma)` para preencher os três lugares. O PostgreSQL gera o ID.
- `UPDATE jogos SET nome = ?, genero = ?, plataforma = ? WHERE id = ?` usa os três novos valores e o ID. O `WHERE` escolhe a linha que será alterada.
- `DELETE FROM jogos WHERE id = ?` usa `Only identificador` para enviar o único parâmetro. O `WHERE` limita a exclusão ao jogo selecionado.

Em `execute`, os `?` recebem valores fornecidos separadamente do texto SQL. `postgresql-simple` codifica esses valores para uso na consulta. Assim, um nome como `D'Arc` é tratado como texto do jogo.

## Cadastro passo a passo

1. O navegador pede `GET /`. O Servant chama `listar`, que lê os jogos e entrega o HTML com o formulário vazio.
2. Você digita `Celeste`, `Plataforma` e `PC` e clica em **Cadastrar**. O navegador envia `POST /jogos` com três campos.
3. `fromForm` lê e valida os campos. Se tudo estiver correto, entrega `DadosJogo "Celeste" "Plataforma" "PC"` ao handler `cadastrar`.
4. `comBanco` abre a conexão. `execute` faz o `INSERT` e o PostgreSQL gera o ID. `bracket` fecha a conexão.
5. `voltarInicio` envia o 303. O navegador segue `Location: /` com um novo `GET`. A listagem é consultada de novo e agora contém `Celeste`.

## Perguntas que o professor pode fazer

1. **Por que há `data DadosJogo`?** Para agrupar os três textos que o formulário envia em um valor que o handler pode receber.
2. **Qual é a diferença entre `DadosJogo` e `Jogo`?** `DadosJogo` tem os três campos editáveis. `Jogo` é o nome da tupla que também inclui o ID retornado pelo banco.
3. **O que significa `IO` na assinatura de `main`?** Quer dizer que executar `main` pode interagir com o ambiente, como ler um arquivo e abrir um servidor.
4. **O que `do` faz em `main`?** Encadeia as ações de localizar e ler o CSS, imprimir a URL e iniciar o Warp.
5. **Por que se usa `<-` em `jogos <- comBanco (...)`?** Para obter a lista que a ação do banco devolve e usá-la no restante do handler.
6. **O que `pure (DadosJogo ...)` devolve?** Nesse bloco de validação, devolve um resultado bem-sucedido, equivalente a `Right (DadosJogo ...)`.
7. **Por que o parâmetro de `listar` é `Maybe Int32`?** Porque a URL pode trazer `?editar=3` ou abrir a página inicial sem esse parâmetro.
8. **O que `Left` representa em `validarCampo`?** Uma mensagem explicando o erro que impede aceitar aquele campo.
9. **Por que aparecem `show` e `Texto.pack` juntos?** `show` escreve o número como `String` e `Texto.pack` produz o `Text` exigido pelo atributo do link.
10. **O que `:>` significa em `"jogos" :> Capture "id" Int32`?** O caminho começa com `jogos` e o próximo trecho é interpretado como um ID inteiro.
11. **O que `:<|>` faz em `servidor`?** Liga os handlers na ordem em que as rotas foram declaradas.
12. **Para que serve `Proxy :: Proxy API`?** Ele informa que `serve` deve usar a descrição de rotas `API`.
13. **O que é `Handler`?** É o tipo da ação usada pelo Servant para executar a lógica de uma rota e retornar seu resultado ou uma resposta HTTP específica.
14. **Por que o cadastro usa `POST`?** O clique envia os campos no corpo do pedido e resulta na criação de um registro.
15. **Por que voltar com 303?** Para que o navegador consulte a página inicial com `GET` depois da alteração. Atualizar a página então repete a leitura.
16. **Como o programa encontra a senha do banco?** A biblioteca cliente lê a entrada correspondente à conexão no arquivo de senhas do PostgreSQL.
17. **O que `bracket abrir close executar` garante?** Que uma conexão aberta com sucesso seja fechada depois da operação, inclusive se a operação falhar.
18. **Por que `query_` devolve quatro valores por linha?** O `SELECT` pede quatro colunas e `Jogo` tem quatro posições compatíveis.
19. **Como o `INSERT` sabe qual ID usar?** A coluna `SERIAL` gera o valor automaticamente quando o `INSERT` fornece apenas os outros campos.
20. **Por que `Only identificador` é usado no `DELETE`?** `Only` é a forma que a biblioteca usa para agrupar um único parâmetro do SQL.
21. **O que acontece se o jogo for excluído antes de salvar uma edição?** O `UPDATE` afeta zero linhas e o handler responde com 404.
22. **Por que o servidor valida o comprimento se o campo já tem `maxlength`?** O navegador aplica o atributo durante a digitação, e o servidor também pode receber pedidos HTTP produzidos por outras ferramentas.
23. **O que `find` usa para selecionar um jogo?** A função `\(idJogo, _, _, _) -> idJogo == identificador` compara apenas o ID da tupla.
24. **Como `mapM_ mostrarJogo jogos` monta a lista?** Chama `mostrarJogo` para cada item em ordem e coloca o HTML produzido dentro de `ul_`.
25. **Como o HTML exibe sinais como `<` digitados no nome?** `toHtml` faz o escape desses caracteres, de modo que o navegador os mostre como texto.
