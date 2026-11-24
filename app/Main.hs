{-# LANGUAGE OverloadedStrings #-}
module Main (main) where

import Control.Exception (bracket)
import Database.PostgreSQL.Simple (close, connectPostgreSQL)
import Network.Wai.Handler.Warp (defaultSettings, runSettings, setHost, setPort)
import Server.Routes (app)
import System.Environment (lookupEnv)
import Text.Read (readMaybe)

main :: IO ()
main = do
    banco <- lookupEnv "PGDATABASE"
    portaConfigurada <- lookupEnv "GAMELOG_PORT"
    let abrir = case banco of
            Nothing -> connectPostgreSQL "dbname=biblioteca_jogos connect_timeout=3"
            Just _ -> connectPostgreSQL "connect_timeout=3"
        porta = case portaConfigurada >>= readMaybe of
            Just numero | numero > 0 && numero <= 65535 -> numero
            _ -> 8080
        configuracao = setHost "127.0.0.1" (setPort porta defaultSettings)
    bracket abrir close $ \conn -> do
        putStrLn ("Abra http://127.0.0.1:" ++ show porta)
        runSettings configuracao (app conn)
