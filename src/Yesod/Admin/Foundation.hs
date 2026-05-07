{-# LANGUAGE QuasiQuotes #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE ViewPatterns #-}

module Yesod.Admin.Foundation
  ( Admin(..)
  , getAdmin
  , Route(..)
  , resourcesAdmin
  ) where

import Data.Int (Int64)
import Data.Text (Text)
import Yesod.Core

-- | The admin subsite value. Holds no state.
data Admin = Admin

-- | Extract the admin subsite from any parent. Typically used in the
--   parent site's foundation:
--
-- @
-- instance YesodSubDispatch Admin App where ...
-- @
getAdmin :: a -> Admin
getAdmin = const Admin

mkYesodSubData "Admin" [parseRoutes|
/                           AdminDashboardR    GET
/#Text                      AdminEntityListR   GET
/#Text/create               AdminEntityCreateR GET POST
/#Text/#Int64/edit          AdminEntityEditR   GET POST
/#Text/#Int64/delete        AdminEntityDeleteR POST
|]
