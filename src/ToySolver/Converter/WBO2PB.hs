{-# OPTIONS_GHC -Wall #-}
-----------------------------------------------------------------------------
-- |
-- Module      :  ToySolver.Converter.WBO2PB
-- Copyright   :  (c) Masahiro Sakai 2013
-- License     :  BSD-style
-- 
-- Maintainer  :  masahiro.sakai@gmail.com
-- Stability   :  experimental
-- Portability :  portable
--
-----------------------------------------------------------------------------
module ToySolver.Converter.WBO2PB (convert) where

import Data.Array.IArray
import qualified ToySolver.SAT.Types as SAT
import qualified Data.PseudoBoolean as PBFile

convert :: PBFile.SoftFormula -> (PBFile.Formula, SAT.Model -> SAT.Model)
convert wbo = (formula, SAT.restrictModel nv)
  where
    nv = PBFile.wboNumVars wbo

    cm  = zip [nv+1..] (PBFile.wboConstraints wbo)
    obj = [(w, [i]) | (i, (Just w,_)) <- cm]

    f :: (PBFile.Var, PBFile.SoftConstraint) -> [PBFile.Constraint]
    f (_, (Nothing, c)) = return c
    f (i, (Just _, c))  = relax i c

    relax :: PBFile.Var -> PBFile.Constraint -> [PBFile.Constraint]
    relax i (lhs, PBFile.Ge, rhs) = [((d, [i]) : lhs, PBFile.Ge, rhs)]
      where
        d = rhs - SAT.pbLowerBound [(c,1) | (c,_) <- lhs]
    relax i (lhs, PBFile.Eq, rhs) =
      relax i (lhs, PBFile.Ge, rhs) ++
      relax i ([(-c,ls) | (c,ls) <- lhs], PBFile.Ge, - rhs)

    topConstr :: [PBFile.Constraint]
    topConstr = 
     case PBFile.wboTopCost wbo of
       Nothing -> []
       Just t -> [([(-c,ls) | (c,ls) <- obj], PBFile.Ge, - (t - 1))]

    formula =
      PBFile.Formula
      { PBFile.pbObjectiveFunction = Just obj
      , PBFile.pbConstraints = cs
      , PBFile.pbNumVars = nv + PBFile.wboNumConstraints wbo
      , PBFile.pbNumConstraints = length cs
      }
      where
        cs = topConstr ++ concatMap f cm
