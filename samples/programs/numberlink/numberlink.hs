{-# LANGUAGE FlexibleContexts, OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}
module Main where

import Control.Applicative hiding (many)
import Control.Monad
import Data.Array.IArray
import qualified Data.ByteString.Lazy.Char8 as BL
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Maybe
import qualified Data.PseudoBoolean as PB
import Text.Parsec hiding (try)
import qualified Text.Parsec.ByteString.Lazy as ParsecBL
import System.Environment
import qualified ToySolver.SAT as SAT
import qualified ToySolver.SAT.Store.PB as PBStore

data Problem
  = Problem
  { probSize :: (Int,Int)
  , probLineNum :: Int
  , probLines :: [(Number, Cell, Cell)]
  }
  deriving (Show)

type Number = Int
type Cell = (Int,Int)

parser ::  Stream s m Char => ParsecT s u m Problem
parser = do
  _ <- string "SIZE"
  spaces
  w <- num
  _ <- char 'X'
  h <- num
  _ <- endOfLine
  
  _ <- string "LINE_NUM"
  spaces
  n <- num
  _ <- endOfLine

  xs <- many $ do
    _ <- string "LINE#"
    i <- num
    spaces
    src <- cell
    _ <- char '-'
    dst <- cell
    _ <- endOfLine
    return (i,src,dst)

  return $ Problem (w,h) n xs
    
  where
    num = read <$> many digit

    cell = do
      _ <- char '('
      x <- num
      _ <- char ','
      y <- num
      _ <- char ')'
      return (x,y)


encode :: SAT.AddPBLin m enc => enc -> Problem -> m (Array Cell (Array Number SAT.Var))
encode enc Problem{ probSize = (w,h), probLineNum = n, probLines = ls }= do
  let bnd = ((0,0), (w-1,h-1))
      cells = range bnd
      edges = [(a,b) | a@(x,y) <- cells, b <- [(x+1,y),(x,y+1)], inRange bnd b]
      adjacentEdges a@(x,y) =
        [(a,b) | b <- [(x+1,y),(x,y+1)], inRange bnd b] ++
        [(b,a) | b <- [(x-1,y),(x,y-1)], inRange bnd b]
      ks = [1..n]

  -- 各マスへの数字の割り当てを表す変数
  vs <- liftM (array bnd) $ forM cells $ \(x,y) -> do
    zs <- liftM (array (1,n)) $ forM ks $ \k -> do
      v <- SAT.newVar enc
      return (k,v)
    return ((x,y), zs)
  -- 各辺の有無を表す変数
  evs <- liftM Map.fromList $ forM edges $ \e -> do
    v <- SAT.newVar enc
    return (e,v)

  -- 初期数字
  let m0 = Map.fromList [(c,k) | (k,src,dst) <- ls, c <- [src,dst]]
  forM_ (Map.toList m0) $ \(c,k) -> do
    SAT.addClause enc [vs!c!k]

  -- 各マスには高々ひとつしか数字が入らない
  forM_ (range bnd) $ \a -> do
    SAT.addAtMost enc [vs!a!k | k <- ks] 1
  -- 辺で連結されるマスは同じ数字
  forM_ (Map.toList evs) $ \((a,b),v) ->
    forM_ ks $ \k -> do
      SAT.addClause enc [-v, -(vs!a!k), vs!b!k]
      SAT.addClause enc [-v, -(vs!b!k), vs!a!k]

  -- 初期数字の入っているマスの次数は1
  forM_ (Map.toList m0) $ \(a,_) -> do
    SAT.addExactly enc [evs Map.! e | e <- adjacentEdges a] 1
  -- 初期数字の入っていないマスの次数は0か2
  forM_ (range bnd) $ \a -> do
    forM_ ks $ \k -> do
      when (a `Map.notMember` m0) $ do
        v <- SAT.newVar enc
        SAT.addPBExactlySoft enc (-v) [(1, evs Map.! e) | e <- adjacentEdges a] 0
        SAT.addPBExactlySoft enc v [(1, evs Map.! e) | e <- adjacentEdges a] 2

  -- 同一数字のマスが４個、田の字に凝ってはいけない
  forM_ [0..w-2] $ \x -> do
    forM_ [0..h-2] $ \y -> do
      forM_ ks $ \k -> do
        SAT.addAtMost enc [vs!a!k | a <- [(x,y),(x+1,y),(x,y+1),(x+1,y+1)]] 3

  return vs

decode :: Array Cell (Array Number SAT.Var) -> SAT.Model -> Map Cell Number
decode vs m = Map.fromList $ catMaybes [f (x,y) | (x,y) <- range (bounds vs)]
  where
    f (x,y) =
      case [k | (k,v) <- assocs (vs!(x,y)), SAT.evalLit m v] of
        k:_ -> Just ((x,y),k)
        [] -> Nothing

solve :: Problem -> IO (Maybe (Map Cell Number))
solve prob = do
  solver <- SAT.newSolver
  SAT.setLogger solver putStrLn  
  vs <- encode solver prob  
  ret <- SAT.solve solver
  if ret then do
    m <- SAT.getModel solver
    return $ Just $ decode vs m
  else
    return Nothing

printBoard :: Problem -> Map Cell Number -> IO ()
printBoard prob sol = do
  let (w,h) = probSize prob
  forM_ [0 .. h-1] $ \y -> do
    putStrLn $ unwords
     [ case Map.lookup (x,y) sol of
         Nothing -> replicate width '_'
         Just k -> replicate (width - length (show k)) ' ' ++ show k
     | x <- [0 .. w-1]
     ]
  where
    width = length $ show (probLineNum prob)

main :: IO ()
main = do
  args <- getArgs
  case args of
    [fname] -> do
      r <- ParsecBL.parseFromFile parser fname
      case r of
        Left err -> error (show err)
        Right prob -> do
          -- printBoard prob $ Map.fromList [(c,k) | (k,src,dst) <- probLines prob, c <- [src,dst]]
          r <- solve prob
          case r of
            Nothing -> putStrLn "UNSATISFIABLE"
            Just sol -> do
              putStrLn "SATISFIABLE"
              printBoard prob sol
    [fname, fname2] -> do
      r <- ParsecBL.parseFromFile parser fname
      case r of
        Left err -> error (show err)
        Right prob -> do
          store <- PBStore.newPBStore
          vs <- encode store prob
          -- print vs
          opb <- PBStore.getPBFormula store
          PB.writeOPBFile fname2 opb

sampleFile :: BL.ByteString
sampleFile = BL.unlines
  [ "SIZE 15X15"
  , "LINE_NUM 12"
  , "LINE#1 (10,0)-(4,14)"
  , "LINE#2 (9,5)-(9,14)"
  , "LINE#3 (2,7)-(4,12)"
  , "LINE#4 (2,5)-(7,13)"
  , "LINE#5 (2,4)-(4,10)"
  , "LINE#6 (2,2)-(5,5)"
  , "LINE#7 (6,5)-(5,10)"
  , "LINE#8 (5,0)-(7,9)"
  , "LINE#9 (10,2)-(12,7)"
  , "LINE#10 (7,1)-(12,9)"
  , "LINE#11 (9,8)-(12,12)"
  , "LINE#12 (8,9)-(12,10)"
  ]

sample :: Problem
Right sample = parse parser "sample" sampleFile