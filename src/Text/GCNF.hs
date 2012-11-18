{-# OPTIONS_GHC -Wall #-}
-----------------------------------------------------------------------------
-- |
-- Module      :  Text.GCNF
-- Copyright   :  (c) Masahiro Sakai 2012
-- License     :  BSD-style
-- 
-- Maintainer  :  masahiro.sakai@gmail.com
-- Stability   :  provisional
-- Portability :  portable
-- 
-- References:
-- 
-- * <http://www.satcompetition.org/2011/rules.pdf>
--
-- TODO:
--
-- * Error handling
--
-----------------------------------------------------------------------------
module Text.GCNF
  (
    GCNF (..)
  , GroupIndex
  , GClause

  -- * Parsing .gcnf files
  , parseString
  , parseFile
  ) where

import qualified SAT.Types as SAT

data GCNF
  = GCNF
  { nbvar          :: !Int
  , nbclauses      :: !Int
  , lastgroupindex :: !GroupIndex
  , clauses        :: [GClause]
  }

type GroupIndex = Int

type GClause = (GroupIndex, SAT.Clause)

parseString :: String -> GCNF
parseString s =
  case words l of
    (["p","gcnf", nbvar', nbclauses', lastgroupindex']) ->
      GCNF
      { nbvar          = read nbvar'
      , nbclauses      = read nbclauses'
      , lastgroupindex = read lastgroupindex'
      , clauses        = map parseLine ls
      }
    _ -> error "parse error"
  where
    (l:ls) = filter (not . isComment) (lines s)

parseFile :: FilePath -> IO GCNF
parseFile filename = do
  s <- readFile filename
  return $! parseString s

isComment :: String -> Bool
isComment ('c':_) = True
isComment _ = False

parseLine :: String -> GClause
parseLine s =
  case words s of
    (('{':w):xs) ->
        let ys  = map read $ init xs
            idx = read $ init w
        in seq idx $ seqList ys $ (idx, ys)
    _ -> error "parse error"

seqList :: [a] -> b -> b
seqList [] b = b
seqList (x:xs) b = seq x $ seqList xs b