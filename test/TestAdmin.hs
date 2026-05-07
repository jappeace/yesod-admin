{-# LANGUAGE QuasiQuotes #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE ViewPatterns #-}
{-# LANGUAGE TypeOperators #-}
{-# OPTIONS_GHC -Wno-missing-signatures -Wno-orphans #-}

-- | Test application that verifies the admin subsite compiles and
--   integrates with a Yesod parent site.
module TestAdmin where

import Control.Monad.Logger (runNoLoggingT)
import Data.Pool (Pool)
import Database.Persist.Sql (SqlBackend, runSqlPool, runMigration)
import Database.Persist.Sqlite (createSqlitePool)
import Yesod.Core
import Yesod.Form (FormMessage, defaultFormMessage)
import Yesod.Persist (YesodPersist(..))
import Yesod.Admin (Admin(..), getAdmin, YesodAdmin(..))
import TestModel (migrateAll)

-- | Parent site with admin subsite
data App = App
  { appConnPool :: Pool SqlBackend
  }

mkYesod "App" [parseRoutes|
/admin AdminR Admin getAdmin
|]

instance Yesod App

instance YesodPersist App where
  type YesodPersistBackend App = SqlBackend
  runDB action = do
    pool <- appConnPool <$> getYesod
    runSqlPool action pool

instance RenderMessage App FormMessage where
  renderMessage _ _ = defaultFormMessage

instance YesodAdmin App

-- | Create a test App with an in-memory SQLite database.
makeTestApp :: IO App
makeTestApp = do
  pool <- runNoLoggingT $ createSqlitePool ":memory:" 1
  runSqlPool (runMigration migrateAll) pool
  return App { appConnPool = pool }
