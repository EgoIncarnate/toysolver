{-# LANGUAGE BangPatterns #-}
{-# OPTIONS_GHC -Wall -fno-warn-unused-do-bind #-}
-----------------------------------------------------------------------------
-- |
-- Module      :  ToySolver.SAT.PBO.BCD2
-- Copyright   :  (c) Masahiro Sakai 2014
-- License     :  BSD-style
-- 
-- Maintainer  :  masahiro.sakai@gmail.com
-- Stability   :  provisional
-- Portability :  portable
--
-- Reference:
--
-- * Federico Heras, Antonio Morgado, João Marques-Silva,
--   Core-Guided binary search algorithms for maximum satisfiability,
--   Twenty-Fifth AAAI Conference on Artificial Intelligence, 2011.
--   <http://www.aaai.org/ocs/index.php/AAAI/AAAI11/paper/view/3713>
--
-- * A. Morgado, F. Heras, and J. Marques-Silva,
--   Improvements to Core-Guided binary search for MaxSAT,
--   in Theory and Applications of Satisfiability Testing (SAT 2012),
--   pp. 284-297.
--   <http://dx.doi.org/10.1007/978-3-642-31612-8_22>
--   <http://ulir.ul.ie/handle/10344/2771>
-- 
-----------------------------------------------------------------------------
module ToySolver.SAT.PBO.BCD2
  ( Options (..)
  , defaultOptions
  , solve
  ) where

import Control.Concurrent.STM
import Control.Monad
import Data.Default.Class
import qualified Data.IntSet as IntSet
import qualified Data.IntMap as IntMap
import qualified Data.Vector.Unboxed as VU
import qualified ToySolver.SAT as SAT
import qualified ToySolver.SAT.Types as SAT
import qualified ToySolver.SAT.PBO.Context as C
import qualified ToySolver.Combinatorial.SubsetSum as SubsetSum
import Text.Printf

data Options
  = Options
  { optEnableHardening :: Bool
  , optEnableBiasedSearch :: Bool
  , optSolvingNormalFirst :: Bool
  }

instance Default Options where
  def = defaultOptions

defaultOptions :: Options
defaultOptions
  = Options
  { optEnableHardening = True
  , optEnableBiasedSearch = True
  , optSolvingNormalFirst = True
  }

data CoreInfo
  = CoreInfo
  { coreLits :: SAT.LitSet
  , coreLB   :: !Integer
  }

solve :: C.Context cxt => cxt -> SAT.Solver -> Options -> IO ()
solve cxt solver opt = solveWBO (C.normalize cxt) solver opt

solveWBO :: C.Context cxt => cxt -> SAT.Solver -> Options -> IO ()
solveWBO cxt solver opt = do
  SAT.setEnableBackwardSubsumptionRemoval solver True
  let unrelaxed = IntSet.fromList [lit | (lit,_) <- sels]
      relaxed   = IntSet.empty
      hardened  = IntSet.empty
      cnt = (1,1)
  best <- atomically $ C.getBestModel cxt
  case best of
    Just m -> do
      loop (unrelaxed, relaxed, hardened) weights [] (C.evalObjectiveFunction cxt m - 1) (Just m) cnt
    Nothing
      | optSolvingNormalFirst opt -> do
          ret <- SAT.solve solver
          if ret then do
            m <- SAT.getModel solver
            let val = C.evalObjectiveFunction cxt m
            let ub' = val - 1
            C.logMessage cxt $ printf "BCD2: updating upper bound: %d -> %d" (SAT.pbUpperBound obj) ub'
            C.addSolution cxt m
            SAT.addPBAtMost solver obj ub'
            loop (unrelaxed, relaxed, hardened) weights [] ub' (Just m) cnt
          else
            C.setFinished cxt
      | otherwise -> do
          loop (unrelaxed, relaxed, hardened) weights [] (SAT.pbUpperBound obj) Nothing cnt
  where
    obj :: SAT.PBLinSum
    obj = C.getObjectiveFunction cxt

    sels :: [(SAT.Lit, Integer)]
    sels = [(-lit, w) | (w,lit) <- obj]

    weights :: SAT.LitMap Integer
    weights = IntMap.fromList sels

    coreCostFun :: CoreInfo -> SAT.PBLinSum
    coreCostFun c = [(weights IntMap.! lit, -lit) | lit <- IntSet.toList (coreLits c)]

    computeLB :: [CoreInfo] -> Integer
    computeLB cores = sum [coreLB info | info <- cores]

    loop :: (SAT.LitSet, SAT.LitSet, SAT.LitSet) -> SAT.LitMap Integer -> [CoreInfo] -> Integer -> Maybe SAT.Model -> (Integer,Integer) -> IO ()
    loop (unrelaxed, relaxed, hardened) deductedWeight cores ub lastModel (!nsat,!nunsat) = do
      let lb = computeLB cores
      C.logMessage cxt $ printf "BCD2: %d <= obj <= %d" lb ub
      C.logMessage cxt $ printf "BCD2: #cores=%d, #unrelaxed=%d, #relaxed=%d, #hardened=%d" 
        (length cores) (IntSet.size unrelaxed) (IntSet.size relaxed) (IntSet.size hardened)

      when (optEnableBiasedSearch opt) $ do
        C.logMessage cxt $ printf "BCD2: bias = %d/%d" nunsat (nunsat + nsat)

      sels <- liftM IntMap.fromList $ forM cores $ \info -> do
        sel <- SAT.newVar solver
        let ep = case lastModel of
                   Nothing -> sum [weights IntMap.! lit | lit <- IntSet.toList (coreLits info)]
                   Just m  -> SAT.evalPBLinSum m (coreCostFun info)
            mid
              | optEnableBiasedSearch opt = coreLB info + (ep - coreLB info) * nunsat `div` (nunsat + nsat)
              | otherwise = (coreLB info + ep) `div` 2
        SAT.addPBAtMostSoft solver sel (coreCostFun info) mid
        return (sel, (info,mid))

      ret <- SAT.solveWith solver (IntMap.keys sels ++ IntSet.toList unrelaxed)

      if ret then do
        m <- SAT.getModel solver
        let val = C.evalObjectiveFunction cxt m
        let ub' = val - 1
        C.logMessage cxt $ printf "BCD2: updating upper bound: %d -> %d" ub ub'
        C.addSolution cxt m
        SAT.addPBAtMost solver obj ub'
        forM_ (IntMap.keys sels) $ \sel -> SAT.addClause solver [-sel] -- delete temporary constraints
        cont (unrelaxed, relaxed, hardened) deductedWeight cores ub' (Just m) (nsat+1,nunsat)
      else do
        core <- SAT.getFailedAssumptions solver
        case core of
          [] -> C.setFinished cxt
          [sel] | Just (info,mid) <- IntMap.lookup sel sels -> do
            let newLB  = refine [weights IntMap.! lit | lit <- IntSet.toList (coreLits info)] (mid + 1)
                info'  = info{ coreLB = newLB }
                cores' = IntMap.elems $ IntMap.insert sel info' $ IntMap.map fst sels
                lb'    = computeLB cores'
                deductedWeight' = IntMap.unionWith (+) deductedWeight $
                  IntMap.fromList [(lit, - d)  | let d = lb' - lb, d /= 0, lit <- IntSet.toList (coreLits info)]
            C.logMessage cxt $ printf "BCD2: updating lower bound of a core"
            C.logMessage cxt $ printf "BCD2: refine %d -> %d" (mid + 1) newLB
            SAT.addPBAtLeast solver (coreCostFun info') (coreLB info') -- redundant, but useful for direct search
            forM_ (IntMap.keys sels) $ \sel -> SAT.addClause solver [-sel] -- delete temporary constraints
            cont (unrelaxed, relaxed, hardened) deductedWeight' cores' ub lastModel (nsat,nunsat+1)
          _ -> do
            let coreSet     = IntSet.fromList core
                torelax     = unrelaxed `IntSet.intersection` coreSet
                unrelaxed'  = unrelaxed `IntSet.difference` torelax
                relaxed'    = relaxed `IntSet.union` torelax
                intersected = [(info,mid) | (sel,(info,mid)) <- IntMap.toList sels, sel `IntSet.member` coreSet]
                rest        = [info | (sel,(info,_)) <- IntMap.toList sels, sel `IntSet.notMember` coreSet]
                delta       = minimum $ [mid - coreLB info + 1 | (info,mid) <- intersected] ++ 
                                        [weights IntMap.! lit | lit <- IntSet.toList torelax]
                newLits     = IntSet.unions $ torelax : [coreLits info | (info,_) <- intersected]
                mergedLB    = sum [coreLB info | (info,_) <- intersected] + delta
                mergedCore  = CoreInfo
                              { coreLits = newLits
                              , coreLB = refine [weights IntMap.! lit | lit <- IntSet.toList relaxed'] mergedLB
                              }
                cores'      = mergedCore : rest
                lb'         = computeLB cores'
                deductedWeight' = IntMap.unionWith (+) deductedWeight $
                                    IntMap.fromList [(lit, - d) | let d = lb' - lb, d /= 0, lit <- IntSet.toList newLits]
            if null intersected then do
              C.logMessage cxt $ printf "BCD2: found a new core of size %d" (IntSet.size torelax)              
            else do
              C.logMessage cxt $ printf "BCD2: merging cores"
            C.logMessage cxt $ printf "BCD2: refine %d -> %d" mergedLB (coreLB mergedCore)
            SAT.addPBAtLeast solver (coreCostFun mergedCore) (coreLB mergedCore) -- redundant, but useful for direct search
            forM_ (IntMap.keys sels) $ \sel -> SAT.addClause solver [-sel] -- delete temporary constraints
            cont (unrelaxed', relaxed', hardened) deductedWeight' cores' ub lastModel (nsat,nunsat+1)

    cont :: (SAT.LitSet, SAT.LitSet, SAT.LitSet) -> SAT.LitMap Integer -> [CoreInfo] -> Integer -> Maybe SAT.Model -> (Integer,Integer) -> IO ()
    cont (unrelaxed, relaxed, hardened) deductedWeight cores ub lastModel (!nsat,!nunsat)
      | lb > ub = C.setFinished cxt
      | optEnableHardening opt = do
          let lits = IntMap.keysSet $ IntMap.filter (\w -> lb + w > ub) deductedWeight
          forM_ (IntSet.toList lits) $ \lit -> SAT.addClause solver [lit]
          let unrelaxed' = unrelaxed `IntSet.difference` lits
              relaxed'   = relaxed   `IntSet.difference` lits
              hardened'  = hardened  `IntSet.union` lits
              cores'     = map (\core -> core{ coreLits = coreLits core `IntSet.difference` lits }) cores
          loop (unrelaxed', relaxed', hardened') deductedWeight cores' ub lastModel (nsat,nunsat)
      | otherwise = 
          loop (unrelaxed, relaxed, hardened) deductedWeight cores ub lastModel (nsat,nunsat)
      where
        lb = computeLB cores

-- | The smallest integer greater-than or equal-to @n@ that can be obtained by summing a subset of @ws@.
-- Note that the definition is different from the one in Morgado et al.
refine
  :: [Integer] -- ^ @ws@
  -> Integer   -- ^ @n@
  -> Integer
refine ws n
  | sum ws <= fromIntegral (maxBound :: Int) && n <= fromIntegral (maxBound :: Int) =
      case SubsetSum.minSubsetSum (VU.fromList (map fromIntegral ws)) (fromIntegral n) of
        Nothing -> n
        Just (obj, _) -> fromIntegral obj
  | otherwise = n
