{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE ScopedTypeVariables #-}

-- | Template Haskell engine for generating an admin subsite from
--   Persistent 'UnboundEntityDef's.
module Yesod.Admin.TH
  ( mkAdmin
  , mkAdminWith
  ) where

import Data.Char (toLower, toUpper)
import Data.Int (Int64)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T
import Database.Persist
  ( Entity(..), selectList, insert, replace, delete
  , Key
  )
import Database.Persist.Names (unEntityNameHS, unFieldNameHS)
import Database.Persist.Quasi.Internal
  ( UnboundEntityDef
  , UnboundFieldDef
  , getUnboundEntityNameHS
  , unboundEntityFields
  , unboundFieldNameHS
  , unboundFieldType
  , unboundFieldAttrs
  )
import Database.Persist.Sql (toSqlKey, fromSqlKey)
import Database.Persist.Types (FieldType(..), FieldAttr(FieldAttrMaybe))
import Language.Haskell.TH
import Text.Blaze.Html (Html)
import Yesod.Admin.Class (YesodAdmin)
import Yesod.Admin.Config (AdminConfig(..), AdminEntityConfig(..))
import Yesod.Admin.Foundation
  ( Admin(..)
  , Route(AdminDashboardR, AdminEntityListR, AdminEntityCreateR, AdminEntityEditR, AdminEntityDeleteR)
  , resourcesAdmin
  )
import Yesod.Admin.Views (adminDashboardWidget, adminListWidget, adminFormWidget)
import Yesod.Core
  ( defaultLayout, redirect, notFound
  , getRouteToParent, liftHandler
  , YesodSubDispatch(..), mkYesodSubDispatch
  , SubHandlerFor
  )
import Yesod.Form
  ( areq, aopt, textField, intField, doubleField, checkBoxField
  , dayField, timeField, textareaField
  , generateFormPost, runFormPost, renderDivs
  , FormResult(..)
  )
import Yesod.Persist (runDB, get404)

-- | Generate a complete admin subsite from Persistent entity definitions.
--   Intended for use with 'share':
--
-- @
-- share [mkPersist sqlSettings, mkMigrate "migrateAll", mkAdmin]
--       [persistLowerCase| ... |]
-- @
mkAdmin :: [UnboundEntityDef] -> Q [Dec]
mkAdmin = mkAdminWith defaultAdminConfigQ

-- | Like 'mkAdmin' but with per-entity customisation.
mkAdminWith :: AdminConfig -> [UnboundEntityDef] -> Q [Dec]
mkAdminWith config entities = do
  let entityNames = map getEntityName entities
  formDecs        <- concat <$> mapM (generateEntityForm config) entities
  listDecs        <- concat <$> mapM generateEntityListHelpers entities
  handlerDecs     <- concat <$> mapM (generateEntityHandlers config) entities
  dispatchDecs    <- generateDispatchHandlers entityNames
  dashboardDec    <- generateDashboardHandler entityNames
  subDispatchDec  <- generateSubDispatchInstance
  return $ formDecs
        ++ listDecs
        ++ handlerDecs
        ++ dispatchDecs
        ++ dashboardDec
        ++ subDispatchDec

defaultAdminConfigQ :: AdminConfig
defaultAdminConfigQ = AdminConfig { acEntityConfigs = Map.empty }

-- ------------------------------------------------------------------
-- Helpers
-- ------------------------------------------------------------------

getEntityName :: UnboundEntityDef -> Text
getEntityName = unEntityNameHS . getUnboundEntityNameHS

getFieldName :: UnboundFieldDef -> Text
getFieldName = unFieldNameHS . unboundFieldNameHS

isNullable :: UnboundFieldDef -> Bool
isNullable field = FieldAttrMaybe `elem` unboundFieldAttrs field

lowerFirst :: String -> String
lowerFirst []     = []
lowerFirst (c:cs) = toLower c : cs

entityFnName :: String -> Text -> Name
entityFnName prefix entityName =
  mkName $ prefix ++ T.unpack entityName

fieldAccessorName :: Text -> Text -> Name
fieldAccessorName entityName fieldName =
  mkName $ lowerFirst (T.unpack entityName) ++ T.unpack (capitalise fieldName)
  where
    capitalise t = case T.uncons t of
      Nothing      -> t
      Just (c, cs) -> T.cons (toUpper c) cs

-- | Generate a type signature for a subsite handler.
--   @paramTypes@ lists additional leading parameters (e.g. @[Int64]@).
subHandlerSig :: Name -> [Q Type] -> Q [Dec]
subHandlerSig fnName paramTypes = do
  masterTv <- newName "master"
  paramTys <- sequence paramTypes
  let masterType   = VarT masterTv
      constraint   = AppT (ConT ''YesodAdmin) masterType
      subHandler   = AppT (AppT (AppT (ConT ''SubHandlerFor) (ConT ''Admin)) masterType) (ConT ''Html)
      fullType     = foldr (\p acc -> ArrowT `AppT` p `AppT` acc) subHandler paramTys
  return [SigD fnName (ForallT [PlainTV masterTv SpecifiedSpec] [constraint] fullType)]

-- ------------------------------------------------------------------
-- Field type -> form field mapping
-- ------------------------------------------------------------------

fieldTypeToFormField :: FieldType -> Q Exp
fieldTypeToFormField = \case
  FTTypeCon Nothing "Text"      -> varE 'textField
  FTTypeCon Nothing "String"    -> varE 'textField
  FTTypeCon Nothing "Int"       -> varE 'intField
  FTTypeCon Nothing "Int64"     -> varE 'intField
  FTTypeCon Nothing "Double"    -> varE 'doubleField
  FTTypeCon Nothing "Bool"      -> varE 'checkBoxField
  FTTypeCon Nothing "Day"       -> varE 'dayField
  FTTypeCon Nothing "TimeOfDay" -> varE 'timeField
  FTTypeCon Nothing "UTCTime"   -> varE 'textField
  FTTypeCon Nothing "Textarea"  -> varE 'textareaField
  FTTypeCon Nothing name
    | "Id" `T.isSuffixOf` name  -> varE 'intField
  FTTypeCon _ _                 -> varE 'textField
  FTApp _ _                     -> varE 'textField
  FTList _                      -> varE 'textField
  FTLit _                       -> varE 'textField
  FTTypePromoted _              -> varE 'textField

-- ------------------------------------------------------------------
-- Form generation
-- ------------------------------------------------------------------

generateEntityForm :: AdminConfig -> UnboundEntityDef -> Q [Dec]
generateEntityForm config entity = do
  let entityName = getEntityName entity
      fnName     = entityFnName "adminForm" entityName
      fields     = unboundEntityFields entity
      conName    = mkName (T.unpack entityName)

  case lookupOverrideForm config entityName of
    Just overrideName -> do
      body <- varE overrideName
      return [FunD fnName [Clause [] (NormalB body) []]]
    Nothing -> do
      mvalName <- newName "mval"
      fieldExps <- mapM (generateFieldExpr mvalName entityName) fields
      let bodyExpr = foldl (\acc f -> InfixE (Just acc) (VarE '(<*>)) (Just f))
                          (AppE (VarE 'pure) (ConE conName))
                          fieldExps
      return [FunD fnName [Clause [VarP mvalName] (NormalB bodyExpr) []]]

generateFieldExpr :: Name -> Text -> UnboundFieldDef -> Q Exp
generateFieldExpr mvalName entityName field = do
  let fieldName    = getFieldName field
      fieldType    = unboundFieldType field
      nullable     = isNullable field
      accessorName = fieldAccessorName entityName fieldName
      label        = T.unpack fieldName
      isForeignKey = isFkField fieldType
  formField <- fieldTypeToFormField fieldType
  let reqFn = if nullable then 'aopt else 'areq
  if isForeignKey
    then do
      -- For FK fields: fmap toSqlKey (areq intField "label" (fmap (fromSqlKey . accessor) mval))
      let extractExpr = AppE (AppE (VarE 'fmap)
                               (InfixE (Just (VarE 'fromSqlKey)) (VarE '(.)) (Just (VarE accessorName))))
                             (VarE mvalName)
          formExpr    = AppE (AppE (AppE (VarE reqFn) formField) (LitE (StringL label))) extractExpr
      return $ AppE (AppE (VarE 'fmap) (VarE 'toSqlKey)) formExpr
    else do
      let fmapExpr = AppE (AppE (VarE 'fmap) (VarE accessorName)) (VarE mvalName)
      return $ AppE (AppE (AppE (VarE reqFn) formField) (LitE (StringL label))) fmapExpr

-- | Check if a FieldType is a foreign key reference (name ends in "Id")
isFkField :: FieldType -> Bool
isFkField (FTTypeCon Nothing name) = "Id" `T.isSuffixOf` name && name /= "Id"
isFkField _                        = False

lookupOverrideForm :: AdminConfig -> Text -> Maybe Name
lookupOverrideForm config entityName =
  Map.lookup entityName (acEntityConfigs config) >>= aecFormOverride

-- ------------------------------------------------------------------
-- List helpers
-- ------------------------------------------------------------------

generateEntityListHelpers :: UnboundEntityDef -> Q [Dec]
generateEntityListHelpers entity = do
  let entityName = getEntityName entity
      fields     = unboundEntityFields entity
      fieldsFnName = entityFnName "adminListFields" entityName
      valuesFnName = entityFnName "adminListValues" entityName

  let fieldNamesList = ListE [ LitE (StringL (T.unpack (getFieldName f)))
                             | f <- fields
                             ]
  let fieldsDec = FunD fieldsFnName
        [Clause [] (NormalB fieldNamesList) []]

  valName <- newName "val"
  let valuesList = ListE
        [ AppE (VarE 'tshow) (AppE (VarE (fieldAccessorName entityName (getFieldName f))) (VarE valName))
        | f <- fields
        ]
  let valuesDec = FunD valuesFnName
        [Clause [VarP valName] (NormalB valuesList) []]

  return [fieldsDec, valuesDec]

tshow :: Show a => a -> Text
tshow = T.pack . show

-- ------------------------------------------------------------------
-- Per-entity CRUD handlers
-- ------------------------------------------------------------------

generateEntityHandlers :: AdminConfig -> UnboundEntityDef -> Q [Dec]
generateEntityHandlers config entity = do
  let entityName = getEntityName entity
  listGet    <- generateListGetHandler entityName
  createGet  <- generateCreateGetHandler config entityName
  createPost <- generateCreatePostHandler config entityName
  editGet    <- generateEditGetHandler config entityName
  editPost   <- generateEditPostHandler config entityName
  deletePost <- generateDeletePostHandler entityName
  return $ listGet ++ createGet ++ createPost
        ++ editGet ++ editPost ++ deletePost

generateListGetHandler :: Text -> Q [Dec]
generateListGetHandler entityName = do
  let fnName   = mkName $ "handle" ++ T.unpack entityName ++ "ListGet"
      fieldsFn = entityFnName "adminListFields" entityName
      valuesFn = entityFnName "adminListValues" entityName

  sig <- subHandlerSig fnName []
  body <- [|
    do toParent <- getRouteToParent
       entities <- liftHandler $ runDB $ selectList [] []
       let columns = $(varE fieldsFn)
           rows    = map (\(Entity key val) ->
                       (fromSqlKey key, $(varE valuesFn) val)) entities
       liftHandler $ defaultLayout $
         adminListWidget $(litE (stringL (T.unpack entityName)))
                         columns rows
                         (toParent . $(conE 'AdminEntityCreateR))
                         (\nm i -> toParent ($(conE 'AdminEntityEditR) nm i))
                         (\nm i -> toParent ($(conE 'AdminEntityDeleteR) nm i))
                         (toParent $(conE 'AdminDashboardR))
    |]
  return $ sig ++ [FunD fnName [Clause [] (NormalB body) []]]

generateCreateGetHandler :: AdminConfig -> Text -> Q [Dec]
generateCreateGetHandler config entityName = do
  let fnName = mkName $ "handle" ++ T.unpack entityName ++ "CreateGet"
      formFn = getFormFnName config entityName
  sig <- subHandlerSig fnName []
  body <- [|
    do toParent <- getRouteToParent
       (formBody, enctype) <- liftHandler $
         generateFormPost (renderDivs ($(varE formFn) Nothing))
       liftHandler $ defaultLayout $
         adminFormWidget $(litE (stringL (T.unpack entityName)))
                         "Create"
                         (toParent ($(conE 'AdminEntityCreateR) $(litE (stringL (T.unpack entityName)))))
                         formBody
                         enctype
                         (toParent . $(conE 'AdminEntityListR))
    |]
  return $ sig ++ [FunD fnName [Clause [] (NormalB body) []]]

generateCreatePostHandler :: AdminConfig -> Text -> Q [Dec]
generateCreatePostHandler config entityName = do
  let fnName = mkName $ "handle" ++ T.unpack entityName ++ "CreatePost"
      formFn = getFormFnName config entityName
  sig <- subHandlerSig fnName []
  body <- [|
    do toParent <- getRouteToParent
       ((result, formBody), enctype) <- liftHandler $
         runFormPost (renderDivs ($(varE formFn) Nothing))
       case result of
         FormSuccess record -> do
           _ <- liftHandler $ runDB $ insert record
           liftHandler $ redirect $ toParent
             ($(conE 'AdminEntityListR) $(litE (stringL (T.unpack entityName))))
         FormMissing ->
           liftHandler $ defaultLayout $
             adminFormWidget $(litE (stringL (T.unpack entityName)))
                             "Create"
                             (toParent ($(conE 'AdminEntityCreateR) $(litE (stringL (T.unpack entityName)))))
                             formBody
                             enctype
                             (toParent . $(conE 'AdminEntityListR))
         FormFailure _ ->
           liftHandler $ defaultLayout $
             adminFormWidget $(litE (stringL (T.unpack entityName)))
                             "Create"
                             (toParent ($(conE 'AdminEntityCreateR) $(litE (stringL (T.unpack entityName)))))
                             formBody
                             enctype
                             (toParent . $(conE 'AdminEntityListR))
    |]
  return $ sig ++ [FunD fnName [Clause [] (NormalB body) []]]

generateEditGetHandler :: AdminConfig -> Text -> Q [Dec]
generateEditGetHandler config entityName = do
  let fnName = mkName $ "handle" ++ T.unpack entityName ++ "EditGet"
      formFn = getFormFnName config entityName
  entityIdName <- newName "entityId"
  sig <- subHandlerSig fnName [conT ''Int64]
  body <- [|
    do toParent <- getRouteToParent
       record <- liftHandler $ runDB $ get404 (toSqlKey $(varE entityIdName))
       (formBody, enctype) <- liftHandler $
         generateFormPost (renderDivs ($(varE formFn) (Just record)))
       liftHandler $ defaultLayout $
         adminFormWidget $(litE (stringL (T.unpack entityName)))
                         "Edit"
                         (toParent ($(conE 'AdminEntityEditR)
                           $(litE (stringL (T.unpack entityName)))
                           $(varE entityIdName)))
                         formBody
                         enctype
                         (toParent . $(conE 'AdminEntityListR))
    |]
  return $ sig ++ [FunD fnName [Clause [VarP entityIdName] (NormalB body) []]]

generateEditPostHandler :: AdminConfig -> Text -> Q [Dec]
generateEditPostHandler config entityName = do
  let fnName = mkName $ "handle" ++ T.unpack entityName ++ "EditPost"
      formFn = getFormFnName config entityName
  entityIdName <- newName "entityId"
  sig <- subHandlerSig fnName [conT ''Int64]
  body <- [|
    do toParent <- getRouteToParent
       ((result, formBody), enctype) <- liftHandler $
         runFormPost (renderDivs ($(varE formFn) Nothing))
       case result of
         FormSuccess record -> do
           liftHandler $ runDB $ replace (toSqlKey $(varE entityIdName)) record
           liftHandler $ redirect $ toParent
             ($(conE 'AdminEntityListR) $(litE (stringL (T.unpack entityName))))
         FormMissing ->
           liftHandler $ defaultLayout $
             adminFormWidget $(litE (stringL (T.unpack entityName)))
                             "Edit"
                             (toParent ($(conE 'AdminEntityEditR)
                               $(litE (stringL (T.unpack entityName)))
                               $(varE entityIdName)))
                             formBody
                             enctype
                             (toParent . $(conE 'AdminEntityListR))
         FormFailure _ ->
           liftHandler $ defaultLayout $
             adminFormWidget $(litE (stringL (T.unpack entityName)))
                             "Edit"
                             (toParent ($(conE 'AdminEntityEditR)
                               $(litE (stringL (T.unpack entityName)))
                               $(varE entityIdName)))
                             formBody
                             enctype
                             (toParent . $(conE 'AdminEntityListR))
    |]
  return $ sig ++ [FunD fnName [Clause [VarP entityIdName] (NormalB body) []]]

generateDeletePostHandler :: Text -> Q [Dec]
generateDeletePostHandler entityName = do
  let fnName = mkName $ "handle" ++ T.unpack entityName ++ "DeletePost"
      conTy  = mkName (T.unpack entityName)
  entityIdName <- newName "entityId"
  sig <- subHandlerSig fnName [conT ''Int64]
  body <- [|
    do toParent <- getRouteToParent
       liftHandler $ runDB $ delete (toSqlKey $(varE entityIdName) :: Key $(conT conTy))
       liftHandler $ redirect $ toParent
         ($(conE 'AdminEntityListR) $(litE (stringL (T.unpack entityName))))
    |]
  return $ sig ++ [FunD fnName [Clause [VarP entityIdName] (NormalB body) []]]

getFormFnName :: AdminConfig -> Text -> Name
getFormFnName config entityName =
  case lookupOverrideForm config entityName of
    Just overrideName -> overrideName
    Nothing           -> entityFnName "adminForm" entityName

-- ------------------------------------------------------------------
-- Dispatch handlers (Text pattern matching)
-- ------------------------------------------------------------------

generateDispatchHandlers :: [Text] -> Q [Dec]
generateDispatchHandlers entityNames = do
  listDec       <- generateTextDispatch "getAdminEntityListR"
                     entityNames
                     (\en -> mkName $ "handle" ++ T.unpack en ++ "ListGet")
  createGetDec  <- generateTextDispatch "getAdminEntityCreateR"
                     entityNames
                     (\en -> mkName $ "handle" ++ T.unpack en ++ "CreateGet")
  createPostDec <- generateTextDispatch "postAdminEntityCreateR"
                     entityNames
                     (\en -> mkName $ "handle" ++ T.unpack en ++ "CreatePost")
  editGetDec    <- generateTextDispatchWithId "getAdminEntityEditR"
                     entityNames
                     (\en -> mkName $ "handle" ++ T.unpack en ++ "EditGet")
  editPostDec   <- generateTextDispatchWithId "postAdminEntityEditR"
                     entityNames
                     (\en -> mkName $ "handle" ++ T.unpack en ++ "EditPost")
  deletePostDec <- generateTextDispatchWithId "postAdminEntityDeleteR"
                     entityNames
                     (\en -> mkName $ "handle" ++ T.unpack en ++ "DeletePost")
  return $ listDec ++ createGetDec ++ createPostDec
        ++ editGetDec ++ editPostDec ++ deletePostDec

generateTextDispatch :: String -> [Text] -> (Text -> Name) -> Q [Dec]
generateTextDispatch fnNameStr entityNames handlerFn = do
  let fnName  = mkName fnNameStr
      clauses = [ Clause [LitP (StringL (T.unpack en))]
                         (NormalB (VarE (handlerFn en)))
                         []
                | en <- entityNames
                ]
  fallbackBody <- [| liftHandler notFound |]
  nm <- newName "_entityName"
  let fallbackClause = Clause [VarP nm] (NormalB fallbackBody) []
  sig <- subHandlerSig fnName [conT ''Text]
  return $ sig ++ [FunD fnName (clauses ++ [fallbackClause])]

generateTextDispatchWithId :: String -> [Text] -> (Text -> Name) -> Q [Dec]
generateTextDispatchWithId fnNameStr entityNames handlerFn = do
  entityIdVar <- newName "entityId"
  let fnName  = mkName fnNameStr
      clauses = [ Clause [LitP (StringL (T.unpack en)), VarP entityIdVar]
                         (NormalB (AppE (VarE (handlerFn en)) (VarE entityIdVar)))
                         []
                | en <- entityNames
                ]
  fallbackBody <- [| liftHandler notFound |]
  nm1 <- newName "_entityName"
  nm2 <- newName "_entityId"
  let fallbackClause = Clause [VarP nm1, VarP nm2] (NormalB fallbackBody) []
  sig <- subHandlerSig fnName [conT ''Text, conT ''Int64]
  return $ sig ++ [FunD fnName (clauses ++ [fallbackClause])]

-- ------------------------------------------------------------------
-- Dashboard handler
-- ------------------------------------------------------------------

generateDashboardHandler :: [Text] -> Q [Dec]
generateDashboardHandler entityNames = do
  let fnName = mkName "getAdminDashboardR"
  sig <- subHandlerSig fnName []
  body <- [|
    do toParent <- getRouteToParent
       liftHandler $ defaultLayout $
         adminDashboardWidget
           $(listE [litE (stringL (T.unpack en)) | en <- entityNames])
           (toParent . $(conE 'AdminEntityListR))
    |]
  return $ sig ++ [FunD fnName [Clause [] (NormalB body) []]]

-- ------------------------------------------------------------------
-- YesodSubDispatch instance
-- ------------------------------------------------------------------

generateSubDispatchInstance :: Q [Dec]
generateSubDispatchInstance = do
  masterTv <- newName "master"
  let masterType = VarT masterTv
      constraint = AppT (ConT ''YesodAdmin) masterType
      instanceType = AppT (AppT (ConT ''YesodSubDispatch) (ConT ''Admin)) masterType
  dispatchBody <- [| $(mkYesodSubDispatch resourcesAdmin) |]
  let method = FunD 'yesodSubDispatch [Clause [] (NormalB dispatchBody) []]
  return [InstanceD Nothing [constraint] instanceType [method]]
