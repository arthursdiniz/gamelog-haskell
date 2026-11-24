{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeOperators #-}

module Main where

import Control.Exception (bracket, try)
import Control.Monad.IO.Class (liftIO)
import Data.Aeson (FromJSON, Value, encode, object, (.=))
import Data.Scientific (Scientific)
import Data.Text (Text)
import qualified Data.Text as Texto
import Database.PostgreSQL.Simple
    (Connection, Only (Only), SqlError (SqlError), close, connectPostgreSQL, execute, query, query_)
import GHC.Generics (Generic)
import Network.HTTP.Types (hContentType, methodGet, methodHead, status200)
import Network.Wai (pathInfo, requestMethod, responseFile)
import Network.Wai.Handler.Warp (defaultSettings, runSettings, setHost, setPort)
import Paths_biblioteca_jogos (getDataFileName)
import Servant
import System.Environment (lookupEnv)
import System.IO.Error (tryIOError)
import Text.Read (readMaybe)

data DadosJogo = DadosJogo
    { nome :: Text
    , status :: Text
    , nota :: Maybe Scientific
    , review :: Maybe Text
    } deriving (Generic)

instance FromJSON DadosJogo

type Jogo = (Int, Text, Text, Maybe Scientific, Maybe Text)

type API =
    "api" :> "jogos" :>
        ( Get '[JSON] [Value]
        :<|> Capture "id" Int :> Get '[JSON] Value
        :<|> ReqBody '[JSON] DadosJogo :> PostCreated '[JSON] Value
        :<|> Capture "id" Int :> ReqBody '[JSON] DadosJogo :> PutNoContent
        :<|> Capture "id" Int :> DeleteNoContent
        )

main :: IO ()
main = do
    portaConfigurada <- lookupEnv "GAMELOG_PORT"
    let porta = case portaConfigurada >>= readMaybe of
            Just numero | numero > 0 && numero <= 65535 -> numero
            _ -> 8080
    let api = Proxy :: Proxy API
    let rotas = listar :<|> consultar :<|> cadastrar :<|> editar :<|> excluir
    let configuracao = setHost "127.0.0.1" (setPort porta defaultSettings)
    putStrLn ("Abra http://127.0.0.1:" <> show porta)
    runSettings configuracao (frontend (serve api rotas))

frontend :: Application -> Application
frontend api pedido responder
    | metodo == methodGet || metodo == methodHead =
        case pathInfo pedido of
            [] -> enviar "index.html" "text/html; charset=utf-8"
            ["jogos", _] -> enviar "index.html" "text/html; charset=utf-8"
            ["style.css"] -> enviar "style.css" "text/css; charset=utf-8"
            ["script.js"] -> enviar "script.js" "text/javascript; charset=utf-8"
            _ -> api pedido responder
    | otherwise = api pedido responder
  where
    metodo = requestMethod pedido
    enviar arquivo tipo = do
        caminho <- getDataFileName arquivo
        responder (responseFile status200 [(hContentType, tipo)] caminho Nothing)

falha :: ServerError -> Text -> Handler a
falha erro mensagem = throwError erro
    { errBody = encode (object ["erro" .= mensagem])
    , errHeaders = [(hContentType, "application/json")]
    }

comBanco :: (Connection -> IO a) -> Handler a
comBanco operacao = do
    banco <- liftIO (lookupEnv "PGDATABASE")
    let abrir = case banco of
            Nothing -> connectPostgreSQL "dbname=biblioteca_jogos connect_timeout=3"
            Just _ -> connectPostgreSQL "connect_timeout=3"
    resultado <- liftIO (tryIOError (try (bracket abrir close operacao)))
    case resultado of
        Right (Right valor) -> pure valor
        Right (Left SqlError {}) -> falha err500 "Falha no PostgreSQL."
        Left _ -> falha err500 "Não foi possível conectar ao PostgreSQL."

validar :: DadosJogo -> Handler DadosJogo
validar (DadosJogo nomeBruto categoria avaliacao comentario) = do
    let titulo = Texto.strip nomeBruto
    let texto = maybe "" Texto.strip comentario
    let notasPermitidas = [0, 0.5, 1, 1.5, 2, 2.5, 3, 3.5, 4, 4.5, 5]
    let notaValida = maybe True (\valor -> elem valor notasPermitidas) avaliacao
    if Texto.null titulo || Texto.length titulo > 100 || Texto.any (== '\NUL') titulo
        then falha err400 "Informe um nome válido de até 100 caracteres."
        else if not (elem categoria ["quero-jogar", "jogando", "jogados"])
            then falha err400 "Selecione uma categoria válida."
            else if not notaValida
                then falha err400 "Informe uma nota de 0 a 5 em passos de 0,5."
                else if Texto.length texto > 2000 || Texto.any (== '\NUL') texto
                    then falha err400 "Informe uma review válida de até 2000 caracteres."
                    else do
                        let reviewLimpa = if Texto.null texto then Nothing else Just texto
                        pure (DadosJogo titulo categoria avaliacao reviewLimpa)

jogoJSON :: Jogo -> Value
jogoJSON (identificador, titulo, categoria, avaliacao, comentario) = object
    [ "id" .= identificador, "nome" .= titulo, "status" .= categoria
    , "nota" .= avaliacao, "review" .= comentario
    ]

listar :: Handler [Value]
listar = do
    jogos <- comBanco (\conexao -> query_ conexao
        "SELECT id, nome, status, nota, review FROM jogos ORDER BY id DESC")
    pure (map jogoJSON jogos)

consultar :: Int -> Handler Value
consultar identificador = do
    jogos <- comBanco (\conexao -> query conexao
        "SELECT id, nome, status, nota, review FROM jogos WHERE id = ?"
        (Only identificador))
    case jogos of
        [jogo] -> pure (jogoJSON jogo)
        _ -> falha err404 "Jogo inexistente."

cadastrar :: DadosJogo -> Handler Value
cadastrar dados = do
    DadosJogo titulo categoria avaliacao comentario <- validar dados
    inseridos <- comBanco (\conexao -> query conexao
        "INSERT INTO jogos (nome, status, nota, review) VALUES (?, ?, ?, ?) RETURNING id"
        (titulo, categoria, avaliacao, comentario))
    case inseridos of
        [Only identificador] -> pure (object ["id" .= (identificador :: Int)])
        _ -> falha err500 "Não foi possível cadastrar o jogo."

editar :: Int -> DadosJogo -> Handler NoContent
editar identificador dados = do
    DadosJogo titulo categoria avaliacao comentario <- validar dados
    alterados <- comBanco (\conexao -> execute conexao
        "UPDATE jogos SET nome = ?, status = ?, nota = ?, review = ? WHERE id = ?"
        (titulo, categoria, avaliacao, comentario, identificador))
    if alterados == 0 then falha err404 "Jogo inexistente." else pure NoContent

excluir :: Int -> Handler NoContent
excluir identificador = do
    excluidos <- comBanco (\conexao -> execute conexao
        "DELETE FROM jogos WHERE id = ?" (Only identificador))
    if excluidos == 0 then falha err404 "Jogo inexistente." else pure NoContent
