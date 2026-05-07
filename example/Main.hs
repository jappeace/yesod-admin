{-# LANGUAGE QuasiQuotes #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE ViewPatterns #-}
{-# LANGUAGE TypeOperators #-}
{-# OPTIONS_GHC -Wno-missing-signatures -Wno-orphans #-}

module Main (main) where

import Control.Monad.Logger (runStderrLoggingT)
import Data.Pool (Pool)
import Database.Persist.Sql (SqlBackend, runSqlPool, runMigration)
import Database.Persist.Sqlite (createSqlitePool)
import Network.Wai.Handler.Warp (run)
import Yesod.Core
import Yesod.Form (FormMessage, defaultFormMessage)
import Yesod.Persist (YesodPersist(..))
import Yesod.Admin (YesodAdmin(..))
import Model
  ( migrateAll
  , UserAdmin(..), BlogPostAdmin(..)
  , getUserAdmin, getBlogPostAdmin
  , Route(UserListR, BlogPostListR)
  )

data App = App
  { appConnPool :: Pool SqlBackend
  }

mkYesod "App" [parseRoutes|
/ HomeR GET
/admin/users    UserAdminR     UserAdmin     getUserAdmin
/admin/posts    PostAdminR     BlogPostAdmin getBlogPostAdmin
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

getHomeR :: HandlerFor App Html
getHomeR = defaultLayout [whamlet|
  <h1>Example App
  <ul>
    <li><a href=@{UserAdminR UserListR}>Manage Users
    <li><a href=@{PostAdminR BlogPostListR}>Manage Blog Posts
  |]

main :: IO ()
main = do
  pool <- runStderrLoggingT $ createSqlitePool "example.db" 5
  runSqlPool (runMigration migrateAll) pool
  let app = App pool
  waiApp <- toWaiApp app
  putStrLn "Running on http://localhost:3000"
  run 3000 waiApp
