{-# LANGUAGE QuasiQuotes #-}

module Yesod.Admin.Views
  ( adminListWidget
  , adminFormWidget
  ) where

import Data.Int (Int64)
import Data.Text (Text)
import Yesod.Core (WidgetFor, whamlet, Route)
import Yesod.Form (Enctype)

-- | List widget: shows a table of entities.
adminListWidget
  :: Text
  -- ^ Entity name (for display)
  -> [Text]
  -- ^ Column headers (field names)
  -> [(Int64, [Text])]
  -- ^ Rows: (entity id, field values)
  -> Route master
  -- ^ Create route
  -> (Int64 -> Route master)
  -- ^ Build edit-route from id
  -> (Int64 -> Route master)
  -- ^ Build delete-route from id
  -> WidgetFor master ()
adminListWidget entityName columns rows createRoute toEditRoute toDeleteRoute = [whamlet|
<div .admin-list>
  <h1>#{entityName} list
  <p>
    <a href=@{createRoute}>Create new #{entityName}
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
            <a href=@{toEditRoute entityId}>Edit
            \
            <form method=post action=@{toDeleteRoute entityId} style="display:inline">
              <button type=submit onclick="return confirm('Delete?')">Delete
|]

-- | Form widget: renders an entity creation/edit form.
adminFormWidget
  :: Text
  -- ^ Entity name (for display)
  -> Text
  -- ^ Action label ("Create" or "Edit")
  -> Route master
  -- ^ Form post target
  -> WidgetFor master ()
  -- ^ Form body widget (from renderDivs)
  -> Enctype
  -- ^ Form encoding type
  -> Route master
  -- ^ Back/list route
  -> WidgetFor master ()
adminFormWidget entityName actionLabel postTarget formBody enctype listRoute = [whamlet|
<div .admin-form>
  <h1>#{actionLabel} #{entityName}
  <p>
    <a href=@{listRoute}>&larr; Back to #{entityName} list
  <form method=post action=@{postTarget} enctype=#{enctype}>
    ^{formBody}
    <button type=submit>#{actionLabel}
|]
