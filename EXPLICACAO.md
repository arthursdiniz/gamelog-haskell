# Entendendo o GameLog

A página enviada pelo Haskell contém os formulários e os cards da biblioteca. O Servant recebe as requisições, o PostgreSQL guarda os dados e o JavaScript cuida da busca externa, dos filtros e das estrelas clicáveis.

## Banco de dados e formulários

A tabela `jogos` guarda o nome, a capa e os dados pessoais. A migração preserva as colunas e os valores antigos de gênero e plataforma, agora opcionais no banco. Novos cadastros deixam essas colunas nulas.

| Campo | Como funciona |
| --- | --- |
| `status` | Texto obrigatório com um dos valores `quero-jogar`, `jogando` ou `jogados`. |
| `nota` | `numeric` exato. `NULL` significa sem nota. A restrição exige que o dobro da nota seja um inteiro entre 0 e 10. Assim, 0 e 3,5 são válidos. |
| `review` | Texto pessoal opcional, com até 2.000 caracteres. Um campo vazio vira `NULL`. |
| `cheapshark_id` | Identificador externo opcional. A restrição `UNIQUE` impede que a mesma entrada da CheapShark seja guardada duas vezes. Formulários manuais deixam o valor nulo. |

O navegador envia um formulário com `POST`. `FromForm` converte os pares de campos em `DadosJogo` e usa `Left` para comunicar entradas inválidas. O Servant devolve HTTP 400 nesse caso. As consultas do `postgresql-simple` recebem os valores separados do SQL. Cada `?` é preenchido com o parâmetro correspondente.

- `SELECT` lê todos os jogos da biblioteca ou um único jogo pelo ID. `trim_scale(nota)::text` transforma a nota em texto para o formulário e remove zeros à direita, por exemplo `3.50` vira `3.5`.
- `INSERT` salva os campos do novo jogo. `ON CONFLICT (cheapshark_id) DO NOTHING` protege contra duas inclusões do mesmo identificador, inclusive se dois pedidos chegarem juntos. Nesse caso, o handler devolve 409.
- `UPDATE` grava nome, categoria, nota e review pelo ID. O identificador externo e a capa cadastrada são preservados na edição.
- `DELETE` remove a linha pelo ID e volta à biblioteca. A nota e a review fazem parte dessa mesma linha. O handler também remove as capturas ligadas ao jogo.

## Como o Servant funciona

`API` descreve as rotas e seus tipos. `serveWithContext` conecta a descrição às funções que atendem os pedidos e entrega ao Servant as opções do multipart. O Warp escuta em `127.0.0.1:8080`.

| Rota | Função |
| --- | --- |
| `GET /` | `listar` cria a página inicial. Com `?editar=7`, abre os detalhes do jogo 7 com o formulário de edição expandido. |
| `GET /jogos/7` | `detalhes` busca o jogo 7 e renderiza a página individual. |
| `POST /jogos` | `cadastrar` insere um jogo. |
| `POST /jogos/7/editar` | `editar` atualiza o jogo 7. |
| `POST /jogos/7/excluir` | `excluir` remove o jogo 7 e suas capturas. |
| `POST /jogos/7/screenshots` | `enviarCaptura` recebe uma imagem para o jogo 7. |
| `GET /jogos/7/screenshots/3` | `verCaptura` entrega a imagem 3 se ela pertencer ao jogo 7. |
| `POST /jogos/7/screenshots/3/excluir` | `excluirCaptura` remove a captura 3 do jogo 7. |

`Capture "id" Int32` lê o número de um segmento da URL. `QueryParam "editar" Int32` entrega um valor opcional. `ReqBody '[FormUrlEncoded] DadosJogo` indica o formato padrão dos formulários. Ao concluir um `POST`, o servidor responde com HTTP 303 e um cabeçalho `Location`. O navegador faz um novo `GET`, então atualizar a página repete a leitura.

## Funções em `Main.hs`

| Função | O que faz |
| --- | --- |
| `main` | Localiza o CSS e o JavaScript com `getDataFileName`, lê os arquivos e inicia o Warp. `withFile` fecha o arquivo automaticamente e `hSetEncoding arquivo utf8` preserva os acentos do script no Windows. |
| `servidor` | Liga cada rota ao seu handler, na ordem em que aparece em `API`. |
| `comBanco` | Recebe uma função que usa uma conexão. `bracket` abre e fecha a conexão. Os dois `try` permitem responder 503 em falhas de conexão e 500 em falhas da consulta. |
| `fromForm` | Lê os campos com `parseUnique` e `lookupMaybe`, valida o status, aceita as meias estrelas de `notasPermitidas` e converte campos opcionais vazios em `Nothing`. |
| `validarCampo` | Remove espaços nas bordas e recusa texto vazio, longo demais ou que contenha o caractere nulo. |
| `capaValida` | Mantém uma URL de capa opcional com prefixo HTTPS e tamanho permitido. |
| `listar` | Consulta a biblioteca para a página principal ou encaminha uma URL de edição para `detalhes`. |
| `detalhes` | Consulta o jogo e os identificadores de suas capturas com `Only identificador` e gera a página individual. Responde 404 quando o jogo não existe. |
| `cadastrar` | Insere um `DadosJogo` e volta à biblioteca. Retorna 409 quando já existe o identificador externo. |
| `editar` | Atualiza o jogo que tem o ID da URL. Retorna 404 quando nenhuma linha foi alterada. |
| `excluir` | Remove um jogo pelo ID e usa `voltarInicio` se houver uma linha excluída. |
| `voltarInicio` | Envia o 303 com o caminho `/`. |
| `documentoHtml` | Monta o documento HTML compartilhado com cabeçalho, CSS, JavaScript e conteúdo. |
| `pagina` | Mostra os filtros, os cards e o formulário de cadastro. |
| `paginaJogo` | Mostra os dados do jogo, a review pessoal e as opções de editar e excluir. O parâmetro booleano indica se a edição deve começar aberta. |
| `buscaCatalogo` | Monta o campo de busca externa e a área de resultados. |
| `formulario` | Gera os controles de cadastro ou edição e escolhe a rota que recebe o formulário. |
| `nomeStatus` | Busca o rótulo de uma categoria pela sua chave interna. |
| `opcoesStatus` | Escreve as opções de categoria e marca a opção atual. |
| `opcaoNota` | Escreve uma opção de nota, com vírgula na interface e ponto no valor enviado ao servidor. |
| `mostrarNota` | Distingue **Sem nota** de uma nota real, inclusive zero. Exibe estrelas e o valor registrado. |
| `mostrarCapa` | Monta uma imagem HTTPS quando disponível e um fundo **Sem capa**. |
| `mostrarJogo` | Gera um card com link para a página individual e atributos `data-*` que o JavaScript usa nos filtros. |

`categorias` guarda os pares de chave e rótulo. `notasPermitidas` guarda as onze notas aceitas. `DadosJogo` reúne os campos do formulário; `Jogo` é a tupla com os campos lidos do banco, na ordem do `SELECT`. Os campos de texto usam `Text`. `Int32` representa o ID inteiro que vem do PostgreSQL.

## Tipos e operadores para a apresentação

- `::` apresenta um tipo e `->` indica os argumentos e o retorno. `Int32 -> Handler NoContent` recebe um ID e descreve a ação de uma rota sem corpo de sucesso.
- `Maybe a` significa valor opcional. `Just "0"` contém uma nota zero. `Nothing` representa uma nota ausente e vira `NULL` no banco.
- `Either Text a` tem `Left` para erro e `Right` para um resultado válido.
- `do` encadeia ações. `<-` dá um nome ao resultado de uma ação e `pure` devolve um valor no contexto usado, como `Handler` ou `Either`.
- `$ ` aplica uma função à expressão à direita. `form_ [...] $ do` envolve o conteúdo do bloco no formulário. `<>` junta textos ou listas de atributos.
- `:>` conecta partes de uma rota. `:<|>` separa rotas e liga suas implementações.
- `\conexao -> ...` declara uma função sem nome. `_` em um padrão ignora um valor. `[jogo]` reconhece uma lista com exatamente um elemento.
- `==`, `<=`, `>=`, `>` e `&&` comparam valores e combinam condições. `elem` e `notElem` consultam se algo pertence a uma lista. As guardas com `|` testam condições na ordem em que aparecem.
- `map` transforma os elementos de uma lista. `mapM_` aplica uma ação a cada elemento, por exemplo renderizar cada card do HTML.
- `show` converte o ID em `String`. `Texto.pack` produz `Text` para o HTML e `fromString` constrói o tipo de texto do cabeçalho de redirecionamento.

Os recursos de linguagem no início do arquivo habilitam literais e listas no nível dos tipos (`DataKinds`), operadores em tipos (`TypeOperators`), literais em vários tipos de texto (`OverloadedStrings`) e anotações de tipos nas exceções (`ScopedTypeVariables`).

## JavaScript no navegador

A busca externa usa `fetch` para consultar o endpoint `/api/1.0/games` da CheapShark. O resultado fornece `external` (nome), `thumb` (capa) e `gameID` (identificador). O script cria os resultados com `textContent`. Ao selecionar um, preenche os campos do formulário. O jogo só é guardado quando você envia o cadastro. Se a API falhar, o formulário manual permanece disponível. [Documentação da CheapShark](https://apidocs.cheapshark.com/)

Em `filtrarBiblioteca`, o JavaScript combina o nome digitado com a categoria selecionada e esconde os cards que não correspondem. Nas estrelas clicáveis, cada estrela oferece duas regiões, cada qual valendo meia estrela. O clique altera o mesmo campo `nota` que pode ser usado pelo teclado. A opção **Sem nota** envia um campo vazio e a opção **0** envia o valor zero.

## Perguntas para a avaliação oral

1. **O que indica `Capture "id" Int32`?** Que parte da URL vira o número do jogo.
2. **Por que as notas usam `numeric` no banco?** Para avaliar as restrições de faixa e de meia estrela com valores exatos.
3. **Como o jogo sem nota é reconhecido?** O banco retorna `NULL`, que vira `Nothing` em Haskell.
4. **Como limpar uma review?** Apague seu texto no formulário e salve. O formulário vazio vira `Nothing` e a consulta grava `NULL`.
5. **O que `UNIQUE` garante?** Só uma linha pode conter determinado ID da CheapShark.
6. **Por que existe uma restrição no banco além da validação Haskell?** A validação dá uma resposta clara. A restrição também protege o banco quando outro cliente grava diretamente.
7. **Quando a busca grava um jogo?** Só ao enviar o formulário para `POST /jogos`.
8. **Por que os filtros são rápidos?** O JavaScript trabalha nos cards que a página já recebeu.
9. **O que faz `bracket`?** Abre a conexão, roda a ação e fecha a conexão, mesmo se a ação falhar.
10. **Por que o servidor usa 303?** Para fazer o navegador abrir uma página com `GET` após a alteração.
11. **Onde a review é salva?** Na coluna `review` da mesma linha do jogo.
12. **Como o jogo muda de categoria?** O formulário envia o novo valor e o `UPDATE` troca a coluna `status` do ID selecionado.

## Capturas de tela

Selecione um PNG, JPG ou WebP em **Minhas capturas de tela** e clique em **Adicionar captura**. O navegador envia um `multipart/form-data`, que inclui os bytes da imagem e o nome do campo `imagem`. O Servant usa `MultipartForm Mem` para ler um arquivo por envio, com limite de 5 MB. Repetir o envio adiciona outras capturas ao mesmo jogo.

O Haskell identifica o formato pelos bytes iniciais. Em seguida, o FFmpeg tenta decodificar a imagem usando apenas o formato identificado e acesso ao arquivo local. O tempo de decodificação é limitado a 15 segundos e o decodificador usa um limite de 40 milhões de pixels por imagem. No banco, a chave estrangeira `screenshots.jogo_id` aponta para `jogos.id`. O banco guarda apenas o nome gerado para o arquivo, que fica em `uploads/`. O nome original informado pelo navegador é ignorado.

A página carrega apenas os IDs das capturas do jogo. O navegador usa a rota de imagem para buscar as miniaturas e pode abrir a mesma imagem em um diálogo maior. A rota procura pela combinação de IDs do jogo e da captura. O Servant nunca recebe um caminho de arquivo pela URL.

A exclusão da captura usa `DELETE ... RETURNING caminho` para remover o vínculo e descobrir qual arquivo apagar. A exclusão do jogo trava a linha dele com `FOR UPDATE`, obtém os nomes e apaga os registros em uma transação. Depois, o Haskell remove os arquivos locais. `ON DELETE CASCADE` também protege os vínculos se um jogo for excluído por outro comando SQL.

| Nova função | O que faz |
| --- | --- |
| `opcoesMultipart` | Configura o máximo de um arquivo e 5 MB no leitor de formulários. |
| `comDisco` | Executa uma ação de E/S e devolve erro HTTP 500 se o sistema de arquivos ou a chamada do FFmpeg gerar uma exceção. |
| `formatoImagem` | Inspeciona a assinatura do arquivo e devolve a extensão e o formato esperado pelo FFmpeg. |
| `enviarCaptura` | Lê o único arquivo enviado, inspeciona o tamanho e o formato e chama `salvarCaptura`. |
| `salvarCaptura` | Cria um nome único, grava o arquivo, testa a decodificação e registra o vínculo. Remove o arquivo em caso de imagem inválida ou falha no registro. |
| `tipoImagem` | Aceita somente nomes simples e extensões conhecidas. Informa o tipo HTTP da imagem. |
| `removerCaptura` | Apaga pelo nome gerado dentro de `uploads/`. Um arquivo que já desapareceu conta como removido. |
| `excluirCaptura` | Remove apenas a captura do jogo informado e redireciona para os detalhes. |
| `lerCaptura` | Busca o arquivo pelo par de IDs, recusa links simbólicos e checa tamanho e formato antes de devolvê-lo. |
| `verCaptura` | Responde `GET` e `HEAD` com os bytes e o tipo da imagem. O ponto de entrada `Raw` permite escolher esse tipo conforme o arquivo armazenado. |
| `galeriaCapturas` | Renderiza o formulário de upload e as miniaturas. O JavaScript cria o diálogo das imagens. |
| `mostrarCaptura` | Monta o link de uma miniatura e seu botão de exclusão. |
| `voltarJogo` | Após salvar ou excluir uma captura, envia um redirecionamento para a página do jogo. |

`ByteString` representa bytes de arquivo. `</>` combina partes de um caminho. `bracketOnError` chama a limpeza quando há uma exceção. `runHandler` transforma o resultado de uma ação do Servant em `Either`, para que `verCaptura` envie a resposta HTTP adequada.

### Perguntas sobre as capturas

1. **O nome do arquivo enviado é usado?** O Haskell gera o nome e escolhe a extensão pelo conteúdo.
2. **Como o aplicativo sabe se é uma imagem?** Confere a assinatura e confirma que o FFmpeg consegue decodificar os dados.
3. **Por que há dois IDs na rota de imagem?** Para devolver uma captura apenas quando ela pertence ao jogo da URL.
4. **Onde os bytes são guardados?** Em `uploads/`. O PostgreSQL guarda o nome do arquivo e o ID do jogo.
5. **O que acontece ao excluir um jogo pelo aplicativo?** As linhas de capturas saem do banco e seus arquivos são removidos de `uploads/`.
