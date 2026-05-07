-- | Yesod admin subsite: auto-generates CRUD pages from Persistent models.
--
-- @
-- share
--     [ mkPersist sqlSettings
--     , mkMigrate "migrateAll"
--     , mkAdmin
--     ] [persistLowerCase|
-- User
--     name Text
--     email Text
-- |]
-- @
module Yesod.Admin
  ( -- * Subsite foundation
    Admin(..)
  , getAdmin
  , Route(..)
    -- * Typeclass
  , YesodAdmin(..)
    -- * Configuration
  , AdminConfig(..)
  , AdminEntityConfig(..)
  , defaultAdminConfig
  , defaultAdminEntityConfig
    -- * TH splices
  , mkAdmin
  , mkAdminWith
    -- * Views (for custom overrides)
  , adminDashboardWidget
  , adminListWidget
  , adminFormWidget
  , adminDeleteConfirmWidget
  ) where

import Yesod.Admin.Foundation (Admin(..), getAdmin, Route(..))
import Yesod.Admin.Class (YesodAdmin(..))
import Yesod.Admin.Config
  ( AdminConfig(..)
  , AdminEntityConfig(..)
  , defaultAdminConfig
  , defaultAdminEntityConfig
  )
import Yesod.Admin.Views
  ( adminDashboardWidget
  , adminListWidget
  , adminFormWidget
  , adminDeleteConfirmWidget
  )
import Yesod.Admin.TH (mkAdmin, mkAdminWith)
