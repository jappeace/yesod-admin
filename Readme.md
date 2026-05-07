# yesod-admin

Auto-generate per-entity CRUD admin pages from
[Persistent](https://hackage.haskell.org/package/persistent) models using
Template Haskell.

## Usage

### 1. Define models (Model.hs)

`mkAdmin` plugs into `share` alongside `mkPersist` / `mkMigrate`.
It generates a subsite per entity (e.g. `UserAdmin`, `BlogPostAdmin`)
with list, create, edit, and delete routes.

A separate module is required for Template Haskell staging.

```haskell
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
```

### 2. Mount subsites (Main.hs)

Import the generated subsite types and mount them in your Yesod routes:

```haskell
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
```

Each entity gets four routes:

| Route             | Method   | Description            |
|-------------------|----------|------------------------|
| `UserListR`       | GET      | List all records       |
| `UserCreateR`     | GET/POST | Create form + handler  |
| `UserEditR eid`   | GET/POST | Edit form + handler    |
| `UserDeleteR eid` | POST     | Delete handler         |

### Generated types per entity

For an entity `User`, `mkAdmin` generates:

- `data UserAdmin = UserAdmin` -- subsite type
- `getUserAdmin :: a -> UserAdmin` -- subsite getter
- `Route UserAdmin` data family with `UserListR`, `UserCreateR`, `UserEditR Int64`, `UserDeleteR Int64`
- CRUD handlers and form definitions
- `YesodSubDispatch UserAdmin master` instance

## Running the example

A working example lives in `example/`:

```
nix-shell --run "cabal run example"
```

Then visit <http://localhost:3000>.

## Building

```
nix-shell --run "cabal build"
nix-shell --run "cabal test"
nix-build nix/ci.nix -A all-builds
```
