{-# LANGUAGE QuasiQuotes #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE ViewPatterns #-}
{-# LANGUAGE TypeOperators #-}
{-# OPTIONS_GHC -Wno-missing-signatures -Wno-orphans #-}

-- | Test application that mounts per-entity admin subsites.
module TestAdmin where

import Control.Monad.Logger (runNoLoggingT)
import Data.Pool (Pool)
import Database.Persist.Sql (SqlBackend, runSqlPool, runMigration)
import Database.Persist.Sqlite (createSqlitePool)
import Yesod.Core
import Yesod.Form (FormMessage, defaultFormMessage)
import Yesod.Persist (YesodPersist(..))
import Yesod.Admin (YesodAdmin(..))
import TestModel (migrateAll, UserAdmin(..), PostAdmin(..), getUserAdmin, getPostAdmin)

-- | Parent site with per-entity admin subsites
data App = App
  { appConnPool :: Pool SqlBackend
  }

mkYesod "App" [parseRoutes|
/admin/user UserAdminR UserAdmin getUserAdmin
/admin/post PostAdminR PostAdmin getPostAdmin
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
