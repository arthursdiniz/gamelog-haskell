{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeOperators #-}

module Main where

import Control.Exception (bracket, try)
import Control.Monad.IO.Class (liftIO)
import Data.Int (Int32)
import Data.List (find)
import Data.Text (Text)
import qualified Data.Text as Texto
import qualified Data.Text.IO as ArquivoTexto
import Database.PostgreSQL.Simple
    (Connection, Only (Only), SqlError, close, connectPostgreSQL, execute, query_)
import Lucid
import Network.Wai.Handler.Warp (defaultSettings, runSettings, setHost, setPort)
import Paths_biblioteca_jogos (getDataFileName)
import Servant
import Servant.HTML.Lucid (HTML)
import Web.FormUrlEncoded (FromForm (fromForm), parseUnique)

data DadosJogo = DadosJogo Text Text Text
type Jogo = (Int32, Text, Text, Text)

instance FromForm DadosJogo where
    fromForm campos = do
        nome <- parseUnique "nome" campos
        genero <- parseUnique "genero" campos
        plataforma <- parseUnique "plataforma" campos
        nomeLimpo <- validarCampo "Nome" 100 nome
        generoLimpo <- validarCampo "Gênero" 50 genero
        plataformaLimpa <- validarCampo "Plataforma" 50 plataforma
        pure (DadosJogo nomeLimpo generoLimpo plataformaLimpa)

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

main :: IO ()
main = do
    caminhoCSS <- getDataFileName "style.css"
    css <- ArquivoTexto.readFile caminhoCSS
    let configuracao = setHost "127.0.0.1" (setPort 8080 defaultSettings)
    putStrLn "Abra http://127.0.0.1:8080"
    runSettings configuracao (serve (Proxy :: Proxy API) (servidor css))

servidor :: Text -> Server API
servidor css = listar css :<|> cadastrar :<|> editar :<|> excluir

comBanco :: (Connection -> IO a) -> Handler a
comBanco operacao = do
    resultado <- liftIO (try (bracket abrir close executar))
    case resultado of
        Left (_ :: SqlError) -> throwError err503 {errBody = "Banco de dados indisponivel."}
        Right (Left (_ :: SqlError)) -> throwError err500 {errBody = "Erro ao executar a consulta."}
        Right (Right valor) -> pure valor
  where
    abrir = connectPostgreSQL "dbname=biblioteca_jogos connect_timeout=3"
    executar conexao = try (operacao conexao)

listar :: Text -> Maybe Int32 -> Handler (Html ())
listar css idEdicao = do
    jogos <- comBanco (\conexao -> query_ conexao "SELECT id, nome, genero, plataforma FROM jogos ORDER BY id")
    case idEdicao of
        Nothing -> pure (pagina css jogos Nothing)
        Just identificador ->
            case find (\(idJogo, _, _, _) -> idJogo == identificador) jogos of
                Nothing -> throwError err404 {errBody = "Jogo inexistente."}
                Just jogo -> pure (pagina css jogos (Just jogo))

cadastrar :: DadosJogo -> Handler NoContent
cadastrar (DadosJogo nome genero plataforma) = do
    _ <- comBanco (\conexao -> execute conexao
        "INSERT INTO jogos (nome, genero, plataforma) VALUES (?, ?, ?)"
        (nome, genero, plataforma))
    voltarInicio

editar :: Int32 -> DadosJogo -> Handler NoContent
editar identificador (DadosJogo nome genero plataforma) = do
    alterados <- comBanco (\conexao -> execute conexao
        "UPDATE jogos SET nome = ?, genero = ?, plataforma = ? WHERE id = ?"
        (nome, genero, plataforma, identificador))
    if alterados == 0
        then throwError err404 {errBody = "Jogo inexistente."}
        else voltarInicio

excluir :: Int32 -> Handler NoContent
excluir identificador = do
    excluidos <- comBanco (\conexao -> execute conexao
        "DELETE FROM jogos WHERE id = ?" (Only identificador))
    if excluidos == 0
        then throwError err404 {errBody = "Jogo inexistente."}
        else voltarInicio

voltarInicio :: Handler NoContent
voltarInicio = throwError err303 {errHeaders = [("Location", "/")]}

pagina :: Text -> [Jogo] -> Maybe Jogo -> Html ()
pagina css jogos jogoEdicao = do
    doctype_
    html_ [lang_ "pt-BR"] $ do
        head_ $ do
            meta_ [charset_ "utf-8"]
            meta_ [name_ "viewport", content_ "width=device-width, initial-scale=1"]
            title_ "Minha Biblioteca de Jogos"
            style_ css
        body_ $ main_ $ do
            h1_ "Minha Biblioteca de Jogos"
            section_ $ case jogoEdicao of
                Nothing -> do
                    h2_ "Cadastrar jogo"
                    formulario "/jogos" "" "" "" "Cadastrar"
                Just (identificador, nome, genero, plataforma) -> do
                    h2_ "Editar jogo"
                    formulario ("/jogos/" <> Texto.pack (show identificador) <> "/editar")
                        nome genero plataforma "Salvar"
                    a_ [href_ "/"] "Cancelar"
            section_ $ do
                h2_ "Jogos cadastrados"
                if null jogos
                    then p_ "Nenhum jogo cadastrado."
                    else ul_ (mapM_ mostrarJogo jogos)

formulario :: Text -> Text -> Text -> Text -> Text -> Html ()
formulario destino nome genero plataforma textoBotao =
    form_ [method_ "post", action_ destino] $ do
        label_ [for_ "nome"] "Nome"
        input_ [id_ "nome", name_ "nome", value_ nome, required_ "", maxlength_ "100"]
        label_ [for_ "genero"] "Gênero"
        input_ [id_ "genero", name_ "genero", value_ genero, required_ "", maxlength_ "50"]
        label_ [for_ "plataforma"] "Plataforma"
        input_ [id_ "plataforma", name_ "plataforma", value_ plataforma, required_ "", maxlength_ "50"]
        button_ [type_ "submit"] (toHtml textoBotao)

mostrarJogo :: Jogo -> Html ()
mostrarJogo (identificador, nome, genero, plataforma) = do
    let idTexto = Texto.pack (show identificador)
    li_ $ do
        div_ $ do
            h3_ (toHtml nome)
            p_ (toHtml (genero <> " · " <> plataforma))
        div_ [class_ "acoes"] $ do
            a_ [href_ ("/?editar=" <> idTexto)] "Editar"
            form_ [method_ "post", action_ ("/jogos/" <> idTexto <> "/excluir")]
                (button_ [type_ "submit", class_ "excluir"] "Excluir")
