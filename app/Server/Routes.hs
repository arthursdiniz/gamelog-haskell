{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeOperators #-}
module Server.Routes (app) where

import Api.Model (DadosJogo (DadosJogo), Erro (Erro), Jogo (Jogo), JogoCriado (JogoCriado))
import Control.Exception (try)
import Control.Monad.IO.Class (liftIO)
import Data.Aeson (encode)
import Data.Text (Text)
import qualified Data.Text as Texto
import Database.PostgreSQL.Simple
    (Connection, Only (Only), SqlError (SqlError), execute, query, query_)
import Network.HTTP.Types (hContentType, methodGet, methodHead, status200)
import Network.Wai (pathInfo, requestMethod, responseFile)
import Paths_biblioteca_jogos (getDataFileName)
import Servant

type API =
    "api" :> "jogos" :>
        ( Get '[JSON] [Jogo]
        :<|> Capture "id" Int :> Get '[JSON] Jogo
        :<|> ReqBody '[JSON] DadosJogo :> PostCreated '[JSON] JogoCriado
        :<|> Capture "id" Int :> ReqBody '[JSON] DadosJogo :> PutNoContent
        :<|> Capture "id" Int :> DeleteNoContent
        )

server :: Connection -> Server API
server conn = listar conn :<|> consultar conn :<|> cadastrar conn
    :<|> editar conn :<|> excluir conn

app :: Connection -> Application
app conn = frontend (serve (Proxy :: Proxy API) (server conn))

listar :: Connection -> Handler [Jogo]
listar conn = do
    linhas <- executarBanco $ query_ conn
        "SELECT id, nome, status, nota, review FROM jogos ORDER BY id DESC"
    pure (map (\(identificador, titulo, categoria, avaliacao, comentario) ->
        Jogo identificador titulo categoria avaliacao comentario) linhas)

consultar :: Connection -> Int -> Handler Jogo
consultar conn identificador = do
    linhas <- executarBanco $ query conn
        "SELECT id, nome, status, nota, review FROM jogos WHERE id = ?"
        (Only identificador)
    case linhas of
        [(codigo, titulo, categoria, avaliacao, comentario)] ->
            pure (Jogo codigo titulo categoria avaliacao comentario)
        _ -> falha err404 "Jogo inexistente."

cadastrar :: Connection -> DadosJogo -> Handler JogoCriado
cadastrar conn dados = do
    DadosJogo titulo categoria avaliacao comentario <- validar dados
    linhas <- executarBanco $ query conn
        "INSERT INTO jogos (nome, status, nota, review) VALUES (?, ?, ?, ?) RETURNING id"
        (titulo, categoria, avaliacao, comentario)
    case linhas of
        [Only identificador] -> pure (JogoCriado identificador)
        _ -> falha err500 "Não foi possível cadastrar o jogo."

editar :: Connection -> Int -> DadosJogo -> Handler NoContent
editar conn identificador dados = do
    DadosJogo titulo categoria avaliacao comentario <- validar dados
    alterados <- executarBanco $ execute conn
        "UPDATE jogos SET nome = ?, status = ?, nota = ?, review = ? WHERE id = ?"
        (titulo, categoria, avaliacao, comentario, identificador)
    if alterados == 0 then falha err404 "Jogo inexistente." else pure NoContent

excluir :: Connection -> Int -> Handler NoContent
excluir conn identificador = do
    excluidos <- executarBanco $ execute conn
        "DELETE FROM jogos WHERE id = ?" (Only identificador)
    if excluidos == 0 then falha err404 "Jogo inexistente." else pure NoContent

executarBanco :: IO a -> Handler a
executarBanco operacao = do
    resultado <- liftIO (try operacao)
    case resultado of
        Left SqlError {} -> falha err500 "Falha no PostgreSQL."
        Right valor -> pure valor

falha :: ServerError -> Text -> Handler a
falha erro mensagem = throwError erro
    { errBody = encode (Erro mensagem)
    , errHeaders = [(hContentType, "application/json")]
    }

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
