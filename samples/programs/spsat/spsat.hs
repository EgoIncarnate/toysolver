{-# LANGUAGE ScopedTypeVariables, CPP #-}
{-# OPTIONS_GHC -Wall #-}
module Main where

import Control.Concurrent
import qualified Data.Array.IArray as A
import qualified Language.CNF.Parse.ParseDIMACS as DIMACS
import System.Environment
import qualified System.Random.MWC as Rand

import qualified ToySolver.SAT.MessagePassing.SurveyPropagation as SP
import ToySolver.Internal.Util (setEncodingChar8)

main :: IO ()
main = do
#ifdef FORCE_CHAR8
  setEncodingChar8
#endif
  [fname] <- getArgs
  Right cnf <- DIMACS.parseFile fname
  solver <- SP.newSolver (DIMACS.numVars cnf) [A.elems clause | clause <- DIMACS.clauses cnf]
  SP.setNThreads solver =<< getNumCapabilities
  Rand.withSystemRandom $ SP.initializeRandom solver
  print =<< SP.solve solver

