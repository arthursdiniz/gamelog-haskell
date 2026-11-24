{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DuplicateRecordFields #-}
module Api.Model where

import Data.Aeson (FromJSON, ToJSON)
import Data.Scientific (Scientific)
import Data.Text (Text)
import GHC.Generics (Generic)
import Prelude hiding (id)

data DadosJogo = DadosJogo
    { nome :: Text
    , status :: Text
    , nota :: Maybe Scientific
    , review :: Maybe Text
    } deriving (Show, Generic)

instance FromJSON DadosJogo

data Jogo = Jogo
    { id :: Int
    , nome :: Text
    , status :: Text
    , nota :: Maybe Scientific
    , review :: Maybe Text
    } deriving (Show, Generic)

instance ToJSON Jogo

newtype JogoCriado = JogoCriado { id :: Int }
    deriving (Show, Generic)

instance ToJSON JogoCriado

newtype Erro = Erro { erro :: Text }
    deriving (Show, Generic)

instance ToJSON Erro
