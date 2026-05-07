{-# LANGUAGE GADTs #-}
{-# LANGUAGE QuasiQuotes #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE UndecidableInstances #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE StandaloneDeriving #-}
{-# LANGUAGE ViewPatterns #-}
{-# LANGUAGE TypeOperators #-}
{-# OPTIONS_GHC -Wno-missing-signatures -Wno-orphans #-}

module Model where

import Data.Text (Text)
import Database.Persist.TH (share, mkPersist, mkMigrate, sqlSettings, persistLowerCase)
import Yesod.Admin.TH (mkAdmin)

share
  [ mkPersist sqlSettings
  , mkMigrate "migrateAll"
  , mkAdmin
  ] [persistLowerCase|
User
    name Text
    email Text
    age Int Maybe
    deriving Show Eq

BlogPost
    title Text
    body Text
    authorId UserId
    deriving Show Eq
|]
