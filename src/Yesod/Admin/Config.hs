module Yesod.Admin.Config
  ( AdminConfig(..)
  , AdminEntityConfig(..)
  , defaultAdminConfig
  , defaultAdminEntityConfig
  ) where

import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Language.Haskell.TH (Name)

-- | Top-level configuration for the admin subsite TH splice.
data AdminConfig = AdminConfig
  { acEntityConfigs :: Map Text AdminEntityConfig
    -- ^ Per-entity overrides, keyed by entity name (e.g. @"User"@).
  }

-- | Per-entity customisation hooks. Each field accepts a TH 'Name'
--   pointing at the user's function; the generated code will call it
--   instead of the auto-generated default.
data AdminEntityConfig = AdminEntityConfig
  { aecFormOverride       :: Maybe Name
    -- ^ @Maybe record -> AForm Handler record@ — custom form builder.
  , aecListWidgetOverride :: Maybe Name
    -- ^ Custom list widget function.
  , aecEditWidgetOverride :: Maybe Name
    -- ^ Custom edit widget function.
  }

-- | No per-entity overrides.
defaultAdminConfig :: AdminConfig
defaultAdminConfig = AdminConfig
  { acEntityConfigs = Map.empty
  }

-- | All auto-generated, no overrides.
defaultAdminEntityConfig :: AdminEntityConfig
defaultAdminEntityConfig = AdminEntityConfig
  { aecFormOverride       = Nothing
  , aecListWidgetOverride = Nothing
  , aecEditWidgetOverride = Nothing
  }
