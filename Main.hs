{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeOperators #-}

module Main where

import Control.Exception (IOException, bracket, bracketOnError, try)
import Control.Monad (forM_)
import Control.Monad.IO.Class (liftIO)
import qualified Data.ByteString as Bytes
import qualified Data.ByteString.Lazy as Arquivo
import Data.Int (Int32)
import Data.Maybe (fromMaybe)
import Data.String (fromString)
import Data.Text (Text)
import qualified Data.Text as Texto
import qualified Data.Text.IO as ArquivoTexto
import Database.PostgreSQL.Simple
    (Connection, Only (Only), SqlError, close, connectPostgreSQL, execute, query, query_, withTransaction)
import Lucid
import Network.HTTP.Types (mkStatus, status200, status404, status405)
import qualified Network.Wai as Wai
import Network.Wai.Handler.Warp (defaultSettings, runSettings, setHost, setPort)
import Network.Wai.Parse (setMaxRequestFileSize, setMaxRequestFilesSize, setMaxRequestNumFiles)
import Paths_biblioteca_jogos (getDataFileName)
import Servant
import Servant.HTML.Lucid (HTML)
import Servant.Multipart (FileData (..), Mem, MultipartData (..), MultipartForm, MultipartOptions (..), defaultMultipartOptions)
import System.Directory (createDirectoryIfMissing, doesFileExist, pathIsSymbolicLink, removeFile)
import System.Exit (ExitCode (ExitSuccess))
import System.FilePath (takeExtension, takeFileName, (</>))
import System.IO (IOMode (ReadMode), hClose, hSetEncoding, openBinaryTempFile, utf8, withBinaryFile, withFile)
import System.IO.Error (isDoesNotExistError)
import System.Process (readProcessWithExitCode)
import System.Timeout (timeout)
import Web.FormUrlEncoded (FromForm (fromForm), lookupMaybe, parseUnique)

data DadosJogo = DadosJogo Text (Maybe Text) Text (Maybe Text) (Maybe Text) (Maybe Text)
type Jogo = (Int32, Text, Maybe Text, Text, Maybe Text, Maybe Text)

limiteCaptura :: Int
limiteCaptura = 5 * 1024 * 1024

pastaCapturas :: FilePath
pastaCapturas = "uploads"

opcoesMultipart :: MultipartOptions Mem
opcoesMultipart =
    let opcoes = defaultMultipartOptions (Proxy :: Proxy Mem)
        limite = fromIntegral limiteCaptura
    in opcoes {generalOptions = setMaxRequestNumFiles 1
        (setMaxRequestFilesSize limite (setMaxRequestFileSize limite (generalOptions opcoes)))}

categorias :: [(Text, Text)]
categorias = [("quero-jogar", "Quero jogar"), ("jogando", "Jogando"), ("jogados", "Jogados")]

notasPermitidas :: [Text]
notasPermitidas = ["0", "0.5", "1", "1.5", "2", "2.5", "3", "3.5", "4", "4.5", "5"]

instance FromForm DadosJogo where
    fromForm campos = do
        nomeBruto <- parseUnique "nome" campos
        nome <- validarCampo "Nome" 100 nomeBruto
        capa <- lookupMaybe "capa_url" campos
        status <- parseUnique "status" campos
        if status `notElem` map fst categorias
            then Left "Selecione uma categoria válida."
            else pure ()
        nota <- lookupMaybe "nota" campos
        notaLimpa <- case fromMaybe "" nota of
            "" -> Right Nothing
            valor | valor `elem` notasPermitidas -> Right (Just valor)
            _ -> Left "Selecione uma nota de 0 a 5 em passos de meia estrela."
        review <- lookupMaybe "review" campos
        reviewLimpa <- case Texto.strip (fromMaybe "" review) of
            "" -> Right Nothing
            texto -> do
                valido <- validarCampo "Review" 2000 texto
                Right (Just valido)
        idExterno <- lookupMaybe "cheapshark_id" campos
        idLimpo <- case fromMaybe "" idExterno of
            "" -> Right Nothing
            valor | Texto.length valor <= 12 && Texto.all (\c -> c >= '0' && c <= '9') valor ->
                Right (Just valor)
            _ -> Left "Identificador do catálogo inválido."
        pure (DadosJogo nome (capaValida capa) status notaLimpa reviewLimpa idLimpo)

capaValida :: Maybe Text -> Maybe Text
capaValida (Just url)
    | Texto.length url <= 2048
    , Texto.length url > 8
    , Texto.isPrefixOf "https://" url
    , not (Texto.any (<= ' ') url) = Just url
capaValida _ = Nothing

validarCampo :: Text -> Int -> Text -> Either Text Text
validarCampo rotulo limite valor
    | Texto.null limpo = Left (rotulo <> ": preencha este campo.")
    | Texto.length limpo > limite = Left (rotulo <> ": limite de " <> Texto.pack (show limite) <> " caracteres.")
    | Texto.any (== '\NUL') limpo = Left (rotulo <> ": caractere inválido.")
    | otherwise = Right limpo
  where
    limpo = Texto.strip valor

type API =
       QueryParam "editar" Int32 :> Get '[HTML] (Html ())
  :<|> "jogos" :> ReqBody '[FormUrlEncoded] DadosJogo :> Post '[HTML] NoContent
  :<|> "jogos" :> Capture "id" Int32 :> "editar" :> ReqBody '[FormUrlEncoded] DadosJogo :> Post '[HTML] NoContent
  :<|> "jogos" :> Capture "id" Int32 :> "excluir" :> Post '[HTML] NoContent
  :<|> "jogos" :> Capture "id" Int32 :> Get '[HTML] (Html ())
  :<|> "jogos" :> Capture "id" Int32 :> "screenshots" :> MultipartForm Mem (MultipartData Mem) :> Post '[HTML] NoContent
  :<|> "jogos" :> Capture "id" Int32 :> "screenshots" :> Capture "captura" Int32 :> "excluir" :> Post '[HTML] NoContent
  :<|> "jogos" :> Capture "id" Int32 :> "screenshots" :> Capture "captura" Int32 :> Raw

main :: IO ()
main = do
    createDirectoryIfMissing True pastaCapturas
    pastaEhLink <- pathIsSymbolicLink pastaCapturas
    if pastaEhLink then ioError (userError "A pasta uploads nao pode ser um link.") else pure ()
    caminhoCSS <- getDataFileName "style.css"
    css <- ArquivoTexto.readFile caminhoCSS
    caminhoJS <- getDataFileName "script.js"
    javascript <- withFile caminhoJS ReadMode $ \arquivo -> do
        hSetEncoding arquivo utf8
        ArquivoTexto.hGetContents arquivo
    let configuracao = setHost "127.0.0.1" (setPort 8080 defaultSettings)
    putStrLn "Abra http://127.0.0.1:8080"
    runSettings configuracao (serveWithContext (Proxy :: Proxy API)
        (opcoesMultipart :. EmptyContext) (servidor css javascript))

servidor :: Text -> Text -> Server API
servidor css javascript = listar css javascript :<|> cadastrar :<|> editar :<|> excluir
    :<|> detalhes css javascript False :<|> enviarCaptura :<|> excluirCaptura :<|> verCaptura

comBanco :: (Connection -> IO a) -> Handler a
comBanco operacao = do
    resultado <- comDisco (try (bracket abrir close executar))
    case resultado of
        Left (_ :: SqlError) -> throwError err503 {errBody = "Banco de dados indisponivel."}
        Right (Left (_ :: SqlError)) -> throwError err500 {errBody = "Erro ao executar a consulta."}
        Right (Right valor) -> pure valor
  where
    abrir = connectPostgreSQL "dbname=biblioteca_jogos connect_timeout=3"
    executar conexao = try (operacao conexao)

listar :: Text -> Text -> Maybe Int32 -> Handler (Html ())
listar css javascript (Just identificador) = detalhes css javascript True identificador
listar css javascript Nothing = do
    jogos <- comBanco (\conexao -> query_ conexao
        "SELECT id, nome, capa_url, status, trim_scale(nota)::text, review FROM jogos ORDER BY id DESC")
    pure (pagina css javascript jogos)

detalhes :: Text -> Text -> Bool -> Int32 -> Handler (Html ())
detalhes css javascript editando identificador = do
    jogos <- comBanco (\conexao -> query conexao
        "SELECT id, nome, capa_url, status, trim_scale(nota)::text, review FROM jogos WHERE id = ?"
        (Only identificador))
    case jogos of
        [jogo] -> do
            capturas <- comBanco (\conexao -> query conexao
                "SELECT id FROM screenshots WHERE jogo_id = ? ORDER BY id DESC" (Only identificador))
            pure (paginaJogo css javascript editando jogo capturas)
        _ -> throwError err404 {errBody = "Jogo inexistente."}

cadastrar :: DadosJogo -> Handler NoContent
cadastrar (DadosJogo nome capa status nota review idExterno) = do
    inseridos <- comBanco (\conexao -> execute conexao
        "INSERT INTO jogos (nome, capa_url, status, nota, review, cheapshark_id) \
        \VALUES (?, ?, ?, ?::numeric, ?, ?) ON CONFLICT (cheapshark_id) DO NOTHING"
        (nome, capa, status, nota, review, idExterno))
    if inseridos == 0
        then throwError err409 {errBody = "Este jogo ja esta na sua biblioteca."}
        else voltarInicio

editar :: Int32 -> DadosJogo -> Handler NoContent
editar identificador (DadosJogo nome _ status nota review _) = do
    alterados <- comBanco (\conexao -> execute conexao
        "UPDATE jogos SET nome = ?, status = ?, nota = ?::numeric, review = ? WHERE id = ?"
        (nome, status, nota, review, identificador))
    if alterados == 0
        then throwError err404 {errBody = "Jogo inexistente."}
        else voltarJogo identificador

excluir :: Int32 -> Handler NoContent
excluir identificador = do
    jogoRemovido <- comBanco $ \conexao -> withTransaction conexao $ do
        jogos <- query conexao "SELECT id FROM jogos WHERE id = ? FOR UPDATE" (Only identificador)
        case jogos :: [Only Int32] of
            [] -> pure Nothing
            _ -> do
                arquivos <- query conexao "DELETE FROM screenshots WHERE jogo_id = ? RETURNING caminho" (Only identificador)
                _ <- execute conexao "DELETE FROM jogos WHERE id = ?" (Only identificador)
                pure (Just arquivos)
    case jogoRemovido of
        Nothing -> throwError err404 {errBody = "Jogo inexistente."}
        Just arquivos -> do
            forM_ arquivos $ \(Only caminho) -> comDisco (removerCaptura caminho)
            voltarInicio

voltarJogo :: Int32 -> Handler NoContent
voltarJogo identificador =
    throwError err303 {errHeaders = [("Location", "/jogos/" <> fromString (show identificador))]}

voltarInicio :: Handler NoContent
voltarInicio = throwError err303 {errHeaders = [("Location", "/")]}

comDisco :: IO a -> Handler a
comDisco acao = do
    resultado <- liftIO (try acao)
    case resultado of
        Left (_ :: IOException) ->
            throwError err500 {errBody = "Falha ao acessar os arquivos ou o FFmpeg."}
        Right valor -> pure valor

formatoImagem :: Arquivo.ByteString -> Maybe (String, String)
formatoImagem conteudo
    | "\137PNG\r\n\SUB\n" `Arquivo.isPrefixOf` conteudo = Just (".png", "png_pipe")
    | "\255\216\255" `Arquivo.isPrefixOf` conteudo = Just (".jpg", "jpeg_pipe")
    | "RIFF" `Arquivo.isPrefixOf` conteudo
    , Arquivo.take 4 (Arquivo.drop 8 conteudo) == "WEBP" = Just (".webp", "webp_pipe")
    | otherwise = Nothing

enviarCaptura :: Int32 -> MultipartData Mem -> Handler NoContent
enviarCaptura jogo formularioUpload =
    case files formularioUpload of
        [arquivo] | fdInputName arquivo == "imagem" -> do
            let conteudo = fdPayload arquivo
            if Arquivo.length conteudo > fromIntegral limiteCaptura
                then throwError err413 {errBody = "A imagem deve ter ate 5 MB."}
                else case formatoImagem conteudo of
                    Nothing -> throwError err400 {errBody = "Envie uma imagem PNG, JPG ou WebP."}
                    Just (extensao, formato) -> do
                        resultado <- comBanco (\conexao -> salvarCaptura conexao jogo extensao formato conteudo)
                        case resultado of
                            Left erro -> throwError erro
                            Right () -> voltarJogo jogo
        _ -> throwError err400 {errBody = "Selecione uma imagem por envio."}

salvarCaptura :: Connection -> Int32 -> String -> String -> Arquivo.ByteString -> IO (Either ServerError ())
salvarCaptura conexao jogo extensao formato conteudo =
    bracketOnError (openBinaryTempFile pastaCapturas ("captura" <> extensao)) limpar $ \(caminho, arquivo) -> do
        Arquivo.hPut arquivo conteudo
        hClose arquivo
        valido <- timeout 15000000 (readProcessWithExitCode "ffmpeg"
            ["-nostdin", "-v", "error", "-xerror", "-err_detect", "explode", "-threads", "1",
             "-max_pixels", "40000000", "-protocol_whitelist", "file", "-f", formato,
             "-i", caminho, "-f", "null", "-"] "")
        case valido of
            Just (ExitSuccess, _, "") -> do
                let nomeArquivo = takeFileName caminho
                inseridos <- execute conexao
                    "INSERT INTO screenshots (jogo_id, caminho) SELECT id, ? FROM jogos WHERE id = ?"
                    (nomeArquivo, jogo)
                if inseridos == 1
                    then pure (Right ())
                    else do
                        removerCaptura nomeArquivo
                        pure (Left err404 {errBody = "Jogo inexistente."})
            _ -> do
                removerCaptura (takeFileName caminho)
                pure (Left err400 {errBody = "Imagem invalida ou grande demais para decodificar."})
  where
    limpar (caminho, arquivo) = do
        hClose arquivo
        removerCaptura (takeFileName caminho)

tipoImagem :: FilePath -> Maybe Bytes.ByteString
tipoImagem nome
    | takeFileName nome /= nome = Nothing
    | not (all (\c -> c == '.' || c == '-' || c >= '0' && c <= '9'
        || c >= 'a' && c <= 'z' || c >= 'A' && c <= 'Z') nome) = Nothing
    | otherwise = lookup (takeExtension nome)
        [(".png", "image/png"), (".jpg", "image/jpeg"), (".webp", "image/webp")]

removerCaptura :: FilePath -> IO ()
removerCaptura nome =
    case tipoImagem nome of
        Nothing -> ioError (userError "Caminho da captura invalido.")
        Just _ -> do
            resultado <- try (removeFile (pastaCapturas </> nome))
            case resultado of
                Left erro | not (isDoesNotExistError erro) -> ioError erro
                _ -> pure ()

excluirCaptura :: Int32 -> Int32 -> Handler NoContent
excluirCaptura jogo captura = do
    arquivos <- comBanco (\conexao -> query conexao
        "DELETE FROM screenshots WHERE jogo_id = ? AND id = ? RETURNING caminho" (jogo, captura))
    case arquivos of
        [Only nome] -> do
            comDisco (removerCaptura nome)
            voltarJogo jogo
        _ -> throwError err404 {errBody = "Captura inexistente."}

lerCaptura :: Int32 -> Int32 -> Handler (Bytes.ByteString, Bytes.ByteString)
lerCaptura jogo captura = do
    arquivos <- comBanco (\conexao -> query conexao
        "SELECT caminho FROM screenshots WHERE jogo_id = ? AND id = ?" (jogo, captura))
    case arquivos of
        [Only nome] | Just tipo <- tipoImagem nome -> do
            let caminho = pastaCapturas </> nome
            existe <- comDisco (doesFileExist caminho)
            if not existe
                then throwError err404
                else do
                    ehLink <- comDisco (pathIsSymbolicLink caminho)
                    if ehLink
                        then throwError err404
                        else do
                            conteudo <- comDisco (withBinaryFile caminho ReadMode
                                (\arquivo -> Bytes.hGet arquivo (limiteCaptura + 1)))
                            case formatoImagem (Arquivo.fromStrict conteudo) of
                                Just (extensao, _) | extensao == takeExtension nome && Bytes.length conteudo <= limiteCaptura ->
                                    pure (tipo, conteudo)
                                _ -> throwError err404
        _ -> throwError err404

verCaptura :: Int32 -> Int32 -> Tagged Handler Wai.Application
verCaptura jogo captura = Tagged $ \pedido responder ->
    if not (null (Wai.pathInfo pedido))
        then responder (Wai.responseLBS status404 [] "")
        else if Wai.requestMethod pedido `notElem` ["GET", "HEAD"]
            then responder (Wai.responseLBS status405 [("Allow", "GET, HEAD")] "")
            else do
                resultado <- runHandler (lerCaptura jogo captura)
                case resultado of
                    Left erro -> responder (Wai.responseLBS
                        (mkStatus (errHTTPCode erro) (fromString (errReasonPhrase erro))) (errHeaders erro) (errBody erro))
                    Right (tipo, conteudo) -> responder (Wai.responseLBS status200
                        [("Content-Type", tipo), ("X-Content-Type-Options", "nosniff"), ("Cache-Control", "no-store")]
                        (Arquivo.fromStrict conteudo))

documentoHtml :: Text -> Text -> Html () -> Html ()
documentoHtml css javascript conteudo = do
    doctype_
    html_ [lang_ "pt-BR"] $ do
        head_ $ do
            meta_ [charset_ "utf-8"]
            meta_ [name_ "viewport", content_ "width=device-width, initial-scale=1"]
            meta_ [name_ "referrer", content_ "no-referrer"]
            meta_ [name_ "theme-color", content_ "#0e1314"]
            title_ "GameLog | Minha Biblioteca"
            link_ [rel_ "preconnect", href_ "https://fonts.googleapis.com"]
            link_ [rel_ "preconnect", href_ "https://fonts.gstatic.com", crossorigin_ "anonymous"]
            link_ [rel_ "stylesheet", href_ "https://fonts.googleapis.com/css2?family=DM+Sans:wght@400;500;600;700&family=Space+Grotesk:wght@500;600;700&display=swap"]
            style_ css
        body_ $ do
            a_ [href_ "#conteudo", class_ "pular"] "Ir para o conteúdo"
            header_ [class_ "topo"] $ div_ [class_ "topo-conteudo"] $ do
                a_ [href_ "/", class_ "marca"] "GameLog"
                nav_ $ do
                    a_ [href_ "/#biblioteca", class_ "nav-biblioteca"] "Biblioteca"
                    a_ [href_ "/#adicionar", class_ "botao-principal nav-adicionar"] "Adicionar jogo"
            main_ [id_ "conteudo", tabindex_ "-1"] conteudo
            script_ javascript

pagina :: Text -> Text -> [Jogo] -> Html ()
pagina css javascript jogos = documentoHtml css javascript $ do
    div_ [class_ "cabecalho-biblioteca"] $ do
        h1_ "Minha biblioteca"
        p_ [class_ "total-biblioteca", role_ "status"] $ do
            strong_ [id_ "total-jogos"] (toHtml (show (length jogos)))
            span_ [id_ "rotulo-total"] (if length jogos == 1 then "jogo" else "jogos")
    div_ [class_ "layout-biblioteca"] $ do
        section_ [class_ "biblioteca", id_ "biblioteca"] $ do
            h2_ [class_ "visualmente-oculto"] "Jogos da biblioteca"
            div_ [class_ "filtros"] $ do
                div_ [class_ "campo-pesquisa"] $ do
                    label_ [for_ "filtro-nome", class_ "visualmente-oculto"] "Pesquisar na biblioteca"
                    input_ [id_ "filtro-nome", name_ "q", type_ "search", autocomplete_ "off", placeholder_ "Pesquisar na biblioteca…"]
                div_ [class_ "controle-categoria"] $ do
                    label_ [for_ "filtro-status"] "Categoria"
                    select_ [id_ "filtro-status", name_ "categoria"] $ do
                        option_ [value_ ""] "Todos"
                        opcoesStatus ""
            if null jogos
                then p_ [class_ "vazio"] "Sua biblioteca está vazia."
                else do
                    ul_ [class_ "grade"] (mapM_ mostrarJogo jogos)
                    p_ [id_ "filtro-vazio", class_ "vazio", role_ "status", hidden_ ""] "Nenhum jogo corresponde aos filtros."
        aside_ [id_ "adicionar", class_ "adicionar"] $ do
            h2_ "Adicionar jogo"
            buscaCatalogo
            section_ [class_ "painel", id_ "cadastro"] $ do
                h3_ "Novo registro"
                formulario "/jogos" "" "quero-jogar" Nothing Nothing "Adicionar à biblioteca"
            footer_ $ a_ [href_ "https://www.cheapshark.com/"] "Pesquisa por CheapShark"

paginaJogo :: Text -> Text -> Bool -> Jogo -> [Only Int32] -> Html ()
paginaJogo css javascript editando (identificador, nome, capa, status, nota, review) capturas =
    documentoHtml css javascript $ do
        let endereco = "/jogos/" <> Texto.pack (show identificador)
        a_ [href_ "/", class_ "voltar"] "Voltar à biblioteca"
        section_ [class_ "detalhe painel", data_ "status" status] $ do
            mostrarCapa capa
            div_ [class_ "detalhe-info"] $ do
                span_ [class_ "categoria"] (toHtml (nomeStatus status))
                h1_ (toHtml nome)
                mostrarNota nota
        div_ [class_ "layout-detalhe"] $ do
            galeriaCapturas endereco capturas
            div_ [class_ "coluna-pessoal"] $ do
                section_ [class_ "painel painel-review"] $ do
                    h2_ "Review pessoal"
                    p_ [class_ "review"] (toHtml (fromMaybe "Nenhuma review registrada." review))
                details_ ([class_ "painel editar"] <> if editando then [open_ ""] else []) $ do
                    summary_ "Editar informações"
                    formulario (endereco <> "/editar") nome status nota review "Salvar alterações"
        form_ [method_ "post", action_ (endereco <> "/excluir"), class_ "acao-excluir", data_ "confirmar" "jogo"] $
            button_ [type_ "submit", class_ "excluir"] "Excluir da biblioteca"

galeriaCapturas :: Text -> [Only Int32] -> Html ()
galeriaCapturas endereco capturas = section_ [class_ "painel", id_ "screenshots"] $ do
    h2_ "Minhas capturas de tela"
    form_ [id_ "enviar-captura", method_ "post", action_ (endereco <> "/screenshots"), enctype_ "multipart/form-data"] $ do
        label_ [for_ "imagem"] "Imagem PNG, JPG ou WebP de até 5 MB"
        div_ [class_ "linha-upload"] $ do
            input_ [id_ "imagem", name_ "imagem", type_ "file", accept_ "image/png,image/jpeg,image/webp", required_ ""]
            button_ [type_ "submit"] "Adicionar captura"
        p_ [id_ "status-captura", role_ "status"] mempty
    if null capturas
        then p_ [class_ "capturas-vazio"] "Nenhuma captura ainda."
        else ul_ [class_ "grade grade-capturas"] (mapM_ (mostrarCaptura endereco) capturas)

mostrarCaptura :: Text -> Only Int32 -> Html ()
mostrarCaptura endereco (Only captura) = do
    let url = endereco <> "/screenshots/" <> Texto.pack (show captura)
    li_ [class_ "captura"] $ do
        a_ [href_ url, class_ "link-captura"] $
            img_ [src_ url, alt_ "Ampliar captura de tela", width_ "320", height_ "180", loading_ "lazy"]
        form_ [method_ "post", action_ (url <> "/excluir"), data_ "confirmar" "captura"] $
            button_ [type_ "submit", class_ "excluir"] "Excluir captura"

buscaCatalogo :: Html ()
buscaCatalogo = section_ [class_ "painel descoberta"] $ do
    h3_ "Descubra jogos"
    form_ [id_ "busca-catalogo"] $ do
        label_ [for_ "busca"] "Nome do jogo"
        div_ [class_ "linha-busca"] $ do
            input_ [id_ "busca", name_ "busca", type_ "search", placeholder_ "Ex.: Elden Ring…", autocomplete_ "off", required_ "", maxlength_ "100"]
            button_ [type_ "submit"] "Buscar"
    p_ [id_ "status-busca", role_ "status"] mempty
    noscript_ $ p_ "Ative o JavaScript para pesquisar. O cadastro manual está disponível."
    ul_ [id_ "resultados", class_ "grade"] mempty


formulario :: Text -> Text -> Text -> Maybe Text -> Maybe Text -> Text -> Html ()
formulario destino nome status nota review textoBotao =
    form_ [method_ "post", action_ destino] $ do
        input_ [id_ "capa_url", name_ "capa_url", type_ "hidden"]
        input_ [id_ "cheapshark_id", name_ "cheapshark_id", type_ "hidden"]
        div_ [class_ "campo-nome"] $ do
            label_ [for_ "nome"] "Nome"
            input_ [id_ "nome", name_ "nome", value_ nome, autocomplete_ "off", required_ "", maxlength_ "100"]
        div_ [class_ "campos-pessoais"] $ do
            div_ $ do
                label_ [for_ "status"] "Categoria do jogo"
                select_ [id_ "status", name_ "status"] (opcoesStatus status)
            div_ $ do
                label_ [for_ "nota"] "Nota pessoal"
                select_ [id_ "nota", name_ "nota"] $ do
                    option_ [value_ ""] "Sem nota"
                    mapM_ (opcaoNota nota) notasPermitidas
                div_ [id_ "seletor-estrelas"] mempty
        label_ [for_ "review"] "Review pessoal"
        textarea_ [id_ "review", name_ "review", autocomplete_ "off", maxlength_ "2000", rows_ "4"]
            (toHtml (fromMaybe "" review))
        button_ [type_ "submit"] (toHtml textoBotao)

nomeStatus :: Text -> Text
nomeStatus valor = fromMaybe valor (lookup valor categorias)

opcoesStatus :: Text -> Html ()
opcoesStatus atual = mapM_ opcao categorias
  where
    opcao :: (Text, Text) -> Html ()
    opcao (valor, rotulo) =
        option_ ([value_ valor] <> if valor == atual then [selected_ ""] else []) (toHtml rotulo)

opcaoNota :: Maybe Text -> Text -> Html ()
opcaoNota atual valor =
    option_ ([value_ valor] <> if Just valor == atual then [selected_ ""] else []) (toHtml (Texto.replace "." "," valor))

mostrarNota :: Maybe Text -> Html ()
mostrarNota Nothing = p_ [class_ "nota"] "Sem nota"
mostrarNota (Just nota) = p_ [class_ "nota"] $ do
    span_ [class_ "estrelas-nota", data_ "nota" nota] "★★★★★"
    toHtml (Texto.replace "." "," nota <> " / 5")

mostrarCapa :: Maybe Text -> Html ()
mostrarCapa capa =
    div_ [class_ "capa"] $ do
        span_ "Sem capa"
        case capaValida capa of
            Nothing -> pure ()
            Just url -> img_ [src_ url, alt_ "", width_ "460", height_ "215", loading_ "lazy"]

mostrarJogo :: Jogo -> Html ()
mostrarJogo (identificador, nome, capa, status, nota, _) = do
    let endereco = "/jogos/" <> Texto.pack (show identificador)
    li_ [class_ "card", data_ "nome" nome, data_ "status" status] $
        a_ [href_ endereco, class_ "card-link"] $ do
            mostrarCapa capa
            div_ [class_ "card-info"] $ do
                span_ [class_ "categoria"] (toHtml (nomeStatus status))
                h3_ (toHtml nome)
                mostrarNota nota
