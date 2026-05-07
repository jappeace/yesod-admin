{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE ScopedTypeVariables #-}

-- | Template Haskell engine for generating per-entity admin subsites
--   from Persistent 'UnboundEntityDef's.
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
import Web.PathPieces (PathPiece(..))
import Yesod.Admin.Class (YesodAdmin)
import Yesod.Admin.Config (AdminConfig(..), AdminEntityConfig(..))
import Yesod.Admin.Views (adminListWidget, adminFormWidget)
import Yesod.Core
  ( defaultLayout, redirect
  , getRouteToParent, liftHandler
  , YesodSubDispatch(..), mkYesodSubDispatch
  , SubHandlerFor
  , Route, RenderRoute(..), ParseRoute(..)
  )
import Yesod.Form
  ( areq, aopt, textField, intField, doubleField, checkBoxField
  , dayField, timeField, textareaField
  , generateFormPost, runFormPost, renderDivs
  , FormResult(..)
  )
import Yesod.Persist (runDB, get404)
import Yesod.Routes.TH.Types
  ( ResourceTree(..), Resource(..), Piece(..), Dispatch(..)
  )

-- | Generate per-entity admin subsites from Persistent entity definitions.
--   Intended for use with 'share':
--
-- @
-- share [mkPersist sqlSettings, mkMigrate "migrateAll", mkAdmin]
--       [persistLowerCase| ... |]
-- @
--
--   For each entity @User@, generates:
--
--   * @data UserAdmin = UserAdmin@
--   * @getUserAdmin :: a -> UserAdmin@
--   * Route data instance with @UserListR@, @UserCreateR@, @UserEditR@, @UserDeleteR@
--   * CRUD handler functions
--   * @YesodSubDispatch UserAdmin master@ instance
mkAdmin :: [UnboundEntityDef] -> Q [Dec]
mkAdmin = mkAdminWith defaultAdminConfigQ

-- | Like 'mkAdmin' but with per-entity customisation.
mkAdminWith :: AdminConfig -> [UnboundEntityDef] -> Q [Dec]
mkAdminWith config entities =
  concat <$> mapM (mkEntityAdmin config) entities

defaultAdminConfigQ :: AdminConfig
defaultAdminConfigQ = AdminConfig { acEntityConfigs = Map.empty }

-- ------------------------------------------------------------------
-- Per-entity admin subsite generation
-- ------------------------------------------------------------------

mkEntityAdmin :: AdminConfig -> UnboundEntityDef -> Q [Dec]
mkEntityAdmin config entity = do
  let entityName   = getEntityName entity          -- "User"
      adminTypeStr = T.unpack entityName ++ "Admin" -- "UserAdmin"
      adminConName = mkName adminTypeStr
      getterName   = mkName $ "get" ++ adminTypeStr -- "getUserAdmin"
      routes       = mkEntityRoutes entityName

  -- 1. data UserAdmin = UserAdmin
  let adminDataDec = DataD [] adminConName [] Nothing
                       [NormalC adminConName []]
                       []

  -- 2. getUserAdmin :: a -> UserAdmin ; getUserAdmin _ = UserAdmin
  aVar <- newName "a"
  let getterSig = SigD getterName
        (ForallT [PlainTV aVar SpecifiedSpec] []
          (ArrowT `AppT` VarT aVar `AppT` ConT adminConName))
      getterDec = FunD getterName
        [Clause [WildP] (NormalB (ConE adminConName)) []]

  -- 3. Route data family instance + RenderRoute + ParseRoute
  routeDecs <- generateRouteInstances adminConName entityName

  -- 4. Form + list helpers + handlers
  formDecs    <- generateEntityForm config entity
  listDecs    <- generateEntityListHelpers entity
  handlerDecs <- generateEntityHandlers config entity adminConName

  -- 5. YesodSubDispatch instance
  dispatchDec <- generateSubDispatchInstance adminConName routes

  return $ [adminDataDec, getterSig, getterDec]
        ++ routeDecs
        ++ formDecs
        ++ listDecs
        ++ handlerDecs
        ++ dispatchDec

-- ------------------------------------------------------------------
-- Route resource tree (for mkYesodSubDispatch only)
-- ------------------------------------------------------------------

-- | Build the route resource tree for an entity.
mkEntityRoutes :: Text -> [ResourceTree String]
mkEntityRoutes entityName =
  let prefix = T.unpack entityName
  in [ ResourceLeaf $ Resource
         { resourceName     = prefix ++ "ListR"
         , resourcePieces   = []
         , resourceDispatch = Methods Nothing ["GET"]
         , resourceAttrs    = []
         , resourceCheck    = True
         }
     , ResourceLeaf $ Resource
         { resourceName     = prefix ++ "CreateR"
         , resourcePieces   = [Static "create"]
         , resourceDispatch = Methods Nothing ["GET", "POST"]
         , resourceAttrs    = []
         , resourceCheck    = True
         }
     , ResourceLeaf $ Resource
         { resourceName     = prefix ++ "EditR"
         , resourcePieces   = [Dynamic "Int64", Static "edit"]
         , resourceDispatch = Methods Nothing ["GET", "POST"]
         , resourceAttrs    = []
         , resourceCheck    = True
         }
     , ResourceLeaf $ Resource
         { resourceName     = prefix ++ "DeleteR"
         , resourcePieces   = [Dynamic "Int64", Static "delete"]
         , resourceDispatch = Methods Nothing ["POST"]
         , resourceAttrs    = []
         , resourceCheck    = True
         }
     ]

-- ------------------------------------------------------------------
-- Manual route instance generation
-- ------------------------------------------------------------------

-- | Generate Route data instance, RenderRoute, and ParseRoute for an entity admin subsite.
--   Uses exact TH Names ('renderRoute, 'parseRoute, etc.) so the generated code
--   doesn't require yesod-core imports at the splice site.
generateRouteInstances :: Name -> Text -> Q [Dec]
generateRouteInstances adminConName entityName = do
  let listR   = routeName entityName "ListR"
      createR = routeName entityName "CreateR"
      editR   = routeName entityName "EditR"
      deleteR = routeName entityName "DeleteR"
      routeAppType = AppT (ConT ''Route) (ConT adminConName)
      int64Bang = (Bang NoSourceUnpackedness NoSourceStrictness, ConT ''Int64)

  -- data instance Route UserAdmin = ... (inside RenderRoute instance)
  let dataInstDec = DataInstD [] Nothing routeAppType Nothing
        [ NormalC listR []
        , NormalC createR []
        , NormalC editR [int64Bang]
        , NormalC deleteR [int64Bang]
        ]
        [DerivClause Nothing [ConT ''Show, ConT ''Read, ConT ''Eq]]

  -- instance RenderRoute UserAdmin where
  --   data Route UserAdmin = ...
  --   renderRoute = ...
  eidVar <- newName "eid"
  let renderClauses =
        [ Clause [ConP listR [] []]
            (NormalB (TupE [Just (ListE []), Just (ListE [])]))
            []
        , Clause [ConP createR [] []]
            (NormalB (TupE [ Just (ListE [packStr "create"])
                           , Just (ListE [])]))
            []
        , Clause [ConP editR [] [VarP eidVar]]
            (NormalB (TupE [ Just (ListE [ AppE (VarE 'toPathPiece) (VarE eidVar)
                                         , packStr "edit"])
                           , Just (ListE [])]))
            []
        , Clause [ConP deleteR [] [VarP eidVar]]
            (NormalB (TupE [ Just (ListE [ AppE (VarE 'toPathPiece) (VarE eidVar)
                                         , packStr "delete"])
                           , Just (ListE [])]))
            []
        ]
      renderInst = InstanceD Nothing []
        (AppT (ConT ''RenderRoute) (ConT adminConName))
        [dataInstDec, FunD 'renderRoute renderClauses]

  -- instance ParseRoute UserAdmin
  eidVar2 <- newName "eid"
  wildVar <- newName "_x"
  let parseClauses =
        [ Clause [TupP [ListP [], WildP]]
            (NormalB (AppE (ConE 'Just) (ConE listR)))
            []
        , Clause [TupP [ListP [LitP (StringL "create")], WildP]]
            (NormalB (AppE (ConE 'Just) (ConE createR)))
            []
        , Clause [TupP [InfixP (VarP eidVar2) '(:) (ListP [LitP (StringL "edit")]), WildP]]
            (NormalB (AppE (AppE (VarE 'fmap) (ConE editR))
                          (AppE (VarE 'fromPathPiece) (VarE eidVar2))))
            []
        , Clause [TupP [InfixP (VarP eidVar2) '(:) (ListP [LitP (StringL "delete")]), WildP]]
            (NormalB (AppE (AppE (VarE 'fmap) (ConE deleteR))
                          (AppE (VarE 'fromPathPiece) (VarE eidVar2))))
            []
        , Clause [VarP wildVar]
            (NormalB (ConE 'Nothing))
            []
        ]
      parseInst = InstanceD Nothing []
        (AppT (ConT ''ParseRoute) (ConT adminConName))
        [FunD 'parseRoute parseClauses]

  return [renderInst, parseInst]

-- | Generate a Text literal using Data.Text.pack (properly qualified via TH Name)
packStr :: String -> Exp
packStr s = AppE (VarE 'T.pack) (LitE (StringL s))

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

-- | Route constructor name for an entity: e.g. "UserListR"
routeName :: Text -> String -> Name
routeName entityName suffix = mkName $ T.unpack entityName ++ suffix

-- | Generate a type signature for a subsite handler.
subHandlerSig :: Name -> Name -> [Q Type] -> Q [Dec]
subHandlerSig fnName adminConName paramTypes = do
  masterTv <- newName "master"
  paramTys <- sequence paramTypes
  let masterType   = VarT masterTv
      constraint   = AppT (ConT ''YesodAdmin) masterType
      subHandler   = AppT (AppT (AppT (ConT ''SubHandlerFor) (ConT adminConName)) masterType) (ConT ''Html)
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

generateEntityHandlers :: AdminConfig -> UnboundEntityDef -> Name -> Q [Dec]
generateEntityHandlers config entity adminConName = do
  let entityName = getEntityName entity
  listGet    <- generateListGetHandler entityName adminConName
  createGet  <- generateCreateGetHandler config entityName adminConName
  createPost <- generateCreatePostHandler config entityName adminConName
  editGet    <- generateEditGetHandler config entityName adminConName
  editPost   <- generateEditPostHandler config entityName adminConName
  deletePost <- generateDeletePostHandler entityName adminConName
  return $ listGet ++ createGet ++ createPost
        ++ editGet ++ editPost ++ deletePost

generateListGetHandler :: Text -> Name -> Q [Dec]
generateListGetHandler entityName adminConName = do
  let fnName   = mkName $ "get" ++ T.unpack entityName ++ "ListR"
      fieldsFn = entityFnName "adminListFields" entityName
      valuesFn = entityFnName "adminListValues" entityName
      createR  = routeName entityName "CreateR"
      editR    = routeName entityName "EditR"
      deleteR  = routeName entityName "DeleteR"

  sig <- subHandlerSig fnName adminConName []
  body <- [|
    do toParent <- getRouteToParent
       entities <- liftHandler $ runDB $ selectList [] []
       let columns = $(varE fieldsFn)
           rows    = map (\(Entity key val) ->
                       (fromSqlKey key, $(varE valuesFn) val)) entities
       liftHandler $ defaultLayout $
         adminListWidget $(litE (stringL (T.unpack entityName)))
                         columns rows
                         (toParent $(conE createR))
                         (\i -> toParent ($(conE editR) i))
                         (\i -> toParent ($(conE deleteR) i))
    |]
  return $ sig ++ [FunD fnName [Clause [] (NormalB body) []]]

generateCreateGetHandler :: AdminConfig -> Text -> Name -> Q [Dec]
generateCreateGetHandler config entityName adminConName = do
  let fnName  = mkName $ "get" ++ T.unpack entityName ++ "CreateR"
      formFn  = getFormFnName config entityName
      createR = routeName entityName "CreateR"
      listR   = routeName entityName "ListR"
  sig <- subHandlerSig fnName adminConName []
  body <- [|
    do toParent <- getRouteToParent
       (formBody, enctype) <- liftHandler $
         generateFormPost (renderDivs ($(varE formFn) Nothing))
       liftHandler $ defaultLayout $
         adminFormWidget $(litE (stringL (T.unpack entityName)))
                         "Create"
                         (toParent $(conE createR))
                         formBody
                         enctype
                         (toParent $(conE listR))
    |]
  return $ sig ++ [FunD fnName [Clause [] (NormalB body) []]]

generateCreatePostHandler :: AdminConfig -> Text -> Name -> Q [Dec]
generateCreatePostHandler config entityName adminConName = do
  let fnName  = mkName $ "post" ++ T.unpack entityName ++ "CreateR"
      formFn  = getFormFnName config entityName
      createR = routeName entityName "CreateR"
      listR   = routeName entityName "ListR"
  sig <- subHandlerSig fnName adminConName []
  body <- [|
    do toParent <- getRouteToParent
       ((result, formBody), enctype) <- liftHandler $
         runFormPost (renderDivs ($(varE formFn) Nothing))
       case result of
         FormSuccess record -> do
           _ <- liftHandler $ runDB $ insert record
           liftHandler $ redirect $ toParent $(conE listR)
         FormMissing ->
           liftHandler $ defaultLayout $
             adminFormWidget $(litE (stringL (T.unpack entityName)))
                             "Create"
                             (toParent $(conE createR))
                             formBody
                             enctype
                             (toParent $(conE listR))
         FormFailure _ ->
           liftHandler $ defaultLayout $
             adminFormWidget $(litE (stringL (T.unpack entityName)))
                             "Create"
                             (toParent $(conE createR))
                             formBody
                             enctype
                             (toParent $(conE listR))
    |]
  return $ sig ++ [FunD fnName [Clause [] (NormalB body) []]]

generateEditGetHandler :: AdminConfig -> Text -> Name -> Q [Dec]
generateEditGetHandler config entityName adminConName = do
  let fnName = mkName $ "get" ++ T.unpack entityName ++ "EditR"
      formFn = getFormFnName config entityName
      editR  = routeName entityName "EditR"
      listR  = routeName entityName "ListR"
  entityIdName <- newName "entityId"
  sig <- subHandlerSig fnName adminConName [conT ''Int64]
  body <- [|
    do toParent <- getRouteToParent
       record <- liftHandler $ runDB $ get404 (toSqlKey $(varE entityIdName))
       (formBody, enctype) <- liftHandler $
         generateFormPost (renderDivs ($(varE formFn) (Just record)))
       liftHandler $ defaultLayout $
         adminFormWidget $(litE (stringL (T.unpack entityName)))
                         "Edit"
                         (toParent ($(conE editR) $(varE entityIdName)))
                         formBody
                         enctype
                         (toParent $(conE listR))
    |]
  return $ sig ++ [FunD fnName [Clause [VarP entityIdName] (NormalB body) []]]

generateEditPostHandler :: AdminConfig -> Text -> Name -> Q [Dec]
generateEditPostHandler config entityName adminConName = do
  let fnName = mkName $ "post" ++ T.unpack entityName ++ "EditR"
      formFn = getFormFnName config entityName
      editR  = routeName entityName "EditR"
      listR  = routeName entityName "ListR"
  entityIdName <- newName "entityId"
  sig <- subHandlerSig fnName adminConName [conT ''Int64]
  body <- [|
    do toParent <- getRouteToParent
       ((result, formBody), enctype) <- liftHandler $
         runFormPost (renderDivs ($(varE formFn) Nothing))
       case result of
         FormSuccess record -> do
           liftHandler $ runDB $ replace (toSqlKey $(varE entityIdName)) record
           liftHandler $ redirect $ toParent $(conE listR)
         FormMissing ->
           liftHandler $ defaultLayout $
             adminFormWidget $(litE (stringL (T.unpack entityName)))
                             "Edit"
                             (toParent ($(conE editR) $(varE entityIdName)))
                             formBody
                             enctype
                             (toParent $(conE listR))
         FormFailure _ ->
           liftHandler $ defaultLayout $
             adminFormWidget $(litE (stringL (T.unpack entityName)))
                             "Edit"
                             (toParent ($(conE editR) $(varE entityIdName)))
                             formBody
                             enctype
                             (toParent $(conE listR))
    |]
  return $ sig ++ [FunD fnName [Clause [VarP entityIdName] (NormalB body) []]]

generateDeletePostHandler :: Text -> Name -> Q [Dec]
generateDeletePostHandler entityName adminConName = do
  let fnName = mkName $ "post" ++ T.unpack entityName ++ "DeleteR"
      conTy  = mkName (T.unpack entityName)
      listR  = routeName entityName "ListR"
  entityIdName <- newName "entityId"
  sig <- subHandlerSig fnName adminConName [conT ''Int64]
  body <- [|
    do toParent <- getRouteToParent
       liftHandler $ runDB $ delete (toSqlKey $(varE entityIdName) :: Key $(conT conTy))
       liftHandler $ redirect $ toParent $(conE listR)
    |]
  return $ sig ++ [FunD fnName [Clause [VarP entityIdName] (NormalB body) []]]

getFormFnName :: AdminConfig -> Text -> Name
getFormFnName config entityName =
  case lookupOverrideForm config entityName of
    Just overrideName -> overrideName
    Nothing           -> entityFnName "adminForm" entityName

-- ------------------------------------------------------------------
-- YesodSubDispatch instance
-- ------------------------------------------------------------------

generateSubDispatchInstance :: Name -> [ResourceTree String] -> Q [Dec]
generateSubDispatchInstance adminConName routes = do
  masterTv <- newName "master"
  let masterType = VarT masterTv
      constraint = AppT (ConT ''YesodAdmin) masterType
      instanceType = AppT (AppT (ConT ''YesodSubDispatch) (ConT adminConName)) masterType
  dispatchBody <- mkYesodSubDispatch routes
  let method = FunD 'yesodSubDispatch [Clause [] (NormalB dispatchBody) []]
  return [InstanceD Nothing [constraint] instanceType [method]]
