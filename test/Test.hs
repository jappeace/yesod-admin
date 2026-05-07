{-# LANGUAGE ScopedTypeVariables #-}

module Main (main) where

import Control.Monad.IO.Class (liftIO)
import Data.Int (Int64)
import Data.Text qualified as T
import Database.Persist (Entity(..), selectList, insert)
import Database.Persist.Sql (fromSqlKey, runSqlPool)
import Test.Hspec (hspec)
import TestAdmin (App(..), Route(UserAdminR, PostAdminR), makeTestApp)
import TestModel
  ( User(..), Post(..)
  , Route(UserListR, UserCreateR, UserEditR, UserDeleteR)
  , Route(PostCreateR)
  )
import Yesod.Test
  ( yesodSpec, yit, ydescribe
  , request, setMethod, setUrl, addToken, byLabelExact
  , get, statusIs, bodyContains
  , getTestYesod, assertEq
  )

main :: IO ()
main = do
  app <- makeTestApp
  hspec $ yesodSpec app $ do

    ydescribe "Create User" $ do
      yit "creates a user with all fields" $ do
        get (UserAdminR UserCreateR)
        statusIs 200

        request $ do
          setMethod "POST"
          setUrl (UserAdminR UserCreateR)
          addToken
          byLabelExact "name" "alice"
          byLabelExact "email" "alice@example.com"
          byLabelExact "age" "30"
        statusIs 303

        testApp <- getTestYesod
        users <- liftIO $ runSqlPool (selectList [] []) (appConnPool testApp)
        case users of
          [] -> liftIO $ fail "expected at least one user"
          (Entity _ (user :: User) : _) -> do
            assertEq "name" (userName user) "alice"
            assertEq "email" (userEmail user) "alice@example.com"
            assertEq "age" (userAge user) (Just 30)

    ydescribe "Create User with nullable field omitted" $ do
      yit "creates a user without age" $ do
        get (UserAdminR UserCreateR)
        statusIs 200

        request $ do
          setMethod "POST"
          setUrl (UserAdminR UserCreateR)
          addToken
          byLabelExact "name" "bob"
          byLabelExact "email" "bob@example.com"
        statusIs 303

        testApp <- getTestYesod
        users <- liftIO $ runSqlPool (selectList [] []) (appConnPool testApp)
        case reverse users of
          [] -> liftIO $ fail "expected at least one user"
          (Entity _ (user :: User) : _) -> do
            assertEq "name" (userName user) "bob"
            assertEq "age is Nothing" (userAge user) Nothing

    ydescribe "Create Post with FK" $ do
      yit "creates a post linked to an existing user" $ do
        testApp <- getTestYesod
        userId <- liftIO $ runSqlPool (insert (User "author" "author@example.com" Nothing)) (appConnPool testApp)
        let userIdText = T.pack (show (fromSqlKey userId :: Int64))

        get (PostAdminR PostCreateR)
        statusIs 200

        request $ do
          setMethod "POST"
          setUrl (PostAdminR PostCreateR)
          addToken
          byLabelExact "title" "My Post"
          byLabelExact "body" "Post content"
          byLabelExact "authorId" userIdText
        statusIs 303

        posts <- liftIO $ runSqlPool (selectList [] []) (appConnPool testApp)
        case posts of
          [] -> liftIO $ fail "expected at least one post"
          (Entity _ (post :: Post) : _) -> do
            assertEq "title" (postTitle post) "My Post"
            assertEq "body" (postBody post) "Post content"
            assertEq "authorId" (postAuthorId post) userId

    ydescribe "Edit User" $ do
      yit "edits an existing user" $ do
        testApp <- getTestYesod
        userId <- liftIO $ runSqlPool (insert (User "charlie" "charlie@example.com" (Just 25))) (appConnPool testApp)
        let userIdInt = fromSqlKey userId

        get (UserAdminR (UserEditR userIdInt))
        statusIs 200

        request $ do
          setMethod "POST"
          setUrl (UserAdminR (UserEditR userIdInt))
          addToken
          byLabelExact "name" "charlie-updated"
          byLabelExact "email" "charlie-new@example.com"
          byLabelExact "age" "26"
        statusIs 303

        users <- liftIO $ runSqlPool (selectList [] []) (appConnPool testApp)
        let matching = [ u | Entity key u <- users, key == userId ]
        case matching of
          [] -> liftIO $ fail "expected edited user to still exist"
          (matchingUser : _) -> do
            assertEq "name updated" (userName matchingUser) "charlie-updated"
            assertEq "email updated" (userEmail matchingUser) "charlie-new@example.com"
            assertEq "age updated" (userAge matchingUser) (Just 26)

    ydescribe "Delete User" $ do
      yit "deletes an existing user" $ do
        testApp <- getTestYesod
        userId <- liftIO $ runSqlPool (insert (User "deleteme" "delete@example.com" Nothing)) (appConnPool testApp)
        let userIdInt = fromSqlKey userId

        request $ do
          setMethod "POST"
          setUrl (UserAdminR (UserDeleteR userIdInt))
        statusIs 303

        users <- liftIO $ runSqlPool (selectList [] []) (appConnPool testApp)
        let matching = [ u | Entity key u <- users, key == userId ]
        assertEq "user deleted" matching []

    ydescribe "List page" $ do
      yit "shows created entities on the list page" $ do
        testApp <- getTestYesod
        _ <- liftIO $ runSqlPool (insert (User "visible-user" "visible@example.com" (Just 99))) (appConnPool testApp)

        get (UserAdminR UserListR)
        statusIs 200
        bodyContains "visible-user"
        bodyContains "visible@example.com"
