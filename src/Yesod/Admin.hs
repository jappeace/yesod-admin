-- | Yesod admin subsite: auto-generates per-entity CRUD pages from
--   Persistent models.
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
--
-- This generates @UserAdmin@ subsite (with @getUserAdmin@) that you
-- mount in your parent site's routes:
--
-- @
-- /admin/user UserAdminR UserAdmin getUserAdmin
-- @
module Yesod.Admin
  ( -- * Typeclass
    YesodAdmin(..)
    -- * Configuration
  , AdminConfig(..)
  , AdminEntityConfig(..)
  , defaultAdminConfig
  , defaultAdminEntityConfig
    -- * TH splices
  , mkAdmin
  , mkAdminWith
    -- * Views (for custom overrides)
  , adminListWidget
  , adminFormWidget
  ) where

import Yesod.Admin.Class (YesodAdmin(..))
import Yesod.Admin.Config
  ( AdminConfig(..)
  , AdminEntityConfig(..)
  , defaultAdminConfig
  , defaultAdminEntityConfig
  )
import Yesod.Admin.Views
  ( adminListWidget
  , adminFormWidget
  )
import Yesod.Admin.TH (mkAdmin, mkAdminWith)
