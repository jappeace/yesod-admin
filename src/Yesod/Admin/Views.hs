{-# LANGUAGE QuasiQuotes #-}

module Yesod.Admin.Views
  ( adminDashboardWidget
  , adminListWidget
  , adminFormWidget
  , adminDeleteConfirmWidget
  ) where

import Data.Int (Int64)
import Data.Text (Text)
import Yesod.Core (WidgetFor, whamlet, Route)
import Yesod.Form (Enctype)

-- | Dashboard widget: lists all registered entity names with links.
adminDashboardWidget
  :: [Text]
  -- ^ Entity names
  -> (Text -> Route master)
  -- ^ Build a list-route from an entity name
  -> WidgetFor master ()
adminDashboardWidget entityNames toListRoute = [whamlet|
<div .admin-dashboard>
  <h1>Admin Dashboard
  <ul>
    $forall entityName <- entityNames
      <li>
        <a href=@{toListRoute entityName}>#{entityName}
|]

-- | List widget: shows a table of entities.
adminListWidget
  :: Text
  -- ^ Entity name
  -> [Text]
  -- ^ Column headers (field names)
  -> [(Int64, [Text])]
  -- ^ Rows: (entity id, field values)
  -> (Text -> Route master)
  -- ^ Build create-route from entity name
  -> (Text -> Int64 -> Route master)
  -- ^ Build edit-route from entity name and id
  -> (Text -> Int64 -> Route master)
  -- ^ Build delete-route from entity name and id
  -> Route master
  -- ^ Dashboard route
  -> WidgetFor master ()
adminListWidget entityName columns rows toCreateRoute toEditRoute toDeleteRoute dashboardRoute = [whamlet|
<div .admin-list>
  <h1>#{entityName} list
  <p>
    <a href=@{dashboardRoute}>&larr; Dashboard
    \ |
    <a href=@{toCreateRoute entityName}>Create new #{entityName}
  <table .admin-table>
    <thead>
      <tr>
        <th>ID
        $forall col <- columns
          <th>#{col}
        <th>Actions
    <tbody>
      $forall (entityId, vals) <- rows
        <tr>
          <td>#{entityId}
          $forall val <- vals
            <td>#{val}
          <td>
            <a href=@{toEditRoute entityName entityId}>Edit
            \
            <form method=post action=@{toDeleteRoute entityName entityId} style="display:inline">
              <button type=submit onclick="return confirm('Delete?')">Delete
|]

-- | Form widget: renders an entity creation/edit form.
--   The form body widget is embedded via @^{formBody}@.
adminFormWidget
  :: Text
  -- ^ Entity name
  -> Text
  -- ^ Action label ("Create" or "Edit")
  -> Route master
  -- ^ Form post target
  -> WidgetFor master ()
  -- ^ Form body widget (from renderDivs)
  -> Enctype
  -- ^ Form encoding type
  -> (Text -> Route master)
  -- ^ Build list-route from entity name
  -> WidgetFor master ()
adminFormWidget entityName actionLabel postTarget formBody enctype listRoute = [whamlet|
<div .admin-form>
  <h1>#{actionLabel} #{entityName}
  <p>
    <a href=@{listRoute entityName}>&larr; Back to #{entityName} list
  <form method=post action=@{postTarget} enctype=#{enctype}>
    ^{formBody}
    <button type=submit>#{actionLabel}
|]

-- | Delete confirmation widget (used as fallback, main path uses JS confirm).
adminDeleteConfirmWidget
  :: Text
  -- ^ Entity name
  -> Int64
  -- ^ Entity id
  -> Route master
  -- ^ Delete post target
  -> (Text -> Route master)
  -- ^ Build list-route from entity name
  -> WidgetFor master ()
adminDeleteConfirmWidget entityName entityId deleteTarget listRoute = [whamlet|
<div .admin-delete>
  <h1>Delete #{entityName} ##{show entityId}?
  <p>This action cannot be undone.
  <form method=post action=@{deleteTarget}>
    <button type=submit>Confirm Delete
  <p>
    <a href=@{listRoute entityName}>Cancel
|]
