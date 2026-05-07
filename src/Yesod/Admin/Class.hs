{-# LANGUAGE TypeOperators #-}

module Yesod.Admin.Class
  ( YesodAdmin(..)
  ) where

import Database.Persist.Sql (SqlBackend)
import Yesod.Core (Yesod, HandlerFor, AuthResult(Authorized), RenderMessage)
import Yesod.Form (FormMessage)
import Yesod.Persist (YesodPersist(..), YesodPersistBackend)

-- | Typeclass for parent sites that embed the admin subsite.
--
--   Minimal: nothing — the default allows all access.
--   Override 'isAdminAuthorized' to add authentication checks.
class ( Yesod master
      , YesodPersist master
      , YesodPersistBackend master ~ SqlBackend
      , RenderMessage master FormMessage
      ) => YesodAdmin master where

  -- | Check whether the current user is authorized to access the admin.
  --   Runs before every admin handler.
  isAdminAuthorized :: HandlerFor master AuthResult
  isAdminAuthorized = return Authorized
