module Main (main) where

import Database.Persist.Sql qualified as Sql
import Test.Tasty (TestTree, defaultMain, testGroup)
import Test.Tasty.HUnit (testCase, (@?=))
import TestAdmin (makeTestApp)
import TestModel (User(..), Post(..), UserId)

main :: IO ()
main = defaultMain tests

tests :: TestTree
tests = testGroup "Admin"
  [ testGroup "Model compilation"
      [ testCase "User constructor is available" $ do
          let user = User "alice" "alice@example.com" (Just 30)
          userName user @?= "alice"
      , testCase "Post constructor is available" $ do
          let authorKey = Sql.toSqlKey 1 :: UserId
              title = postTitle (Post "Hello" "World" authorKey)
          title @?= "Hello"
      ]
  , testGroup "Admin subsite compilation"
      [ testCase "makeTestApp initialises without error" $ do
          _app <- makeTestApp
          -- If we get here, the TH splice compiled, the routes work,
          -- and the database migrated successfully.
          return ()
      ]
  ]
