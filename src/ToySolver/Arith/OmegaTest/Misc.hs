{-# OPTIONS_GHC -Wall #-}
module ToySolver.Arith.OmegaTest.Misc
  ( checkRealByCAD
  , checkRealByVS
  , checkRealBySimplex
  ) where

import Control.Monad
import qualified Data.IntMap as IM
import qualified Data.IntSet as IS
import Data.Maybe
import qualified Data.Set as Set
import System.IO.Unsafe

import qualified ToySolver.Data.LA as LA
import qualified ToySolver.Data.Polynomial as P
import ToySolver.Data.Var
import qualified ToySolver.Arith.CAD as CAD
import qualified ToySolver.Arith.Simplex2 as Simplex2
import qualified ToySolver.Arith.VirtualSubstitution as VS

checkRealByCAD :: VarSet -> [LA.Atom Rational] -> Bool
checkRealByCAD vs as = isJust $ CAD.solve vs2 (map (fmap f) as)
  where
    vs2 = Set.fromAscList $ IS.toAscList vs

    f :: LA.Expr Rational -> P.Polynomial Rational Int
    f t = sum [ if x == LA.unitVar
                then P.constant c
                else P.constant c * P.var x
              | (c,x) <- LA.terms t ]

checkRealByVS :: VarSet -> [LA.Atom Rational] -> Bool
checkRealByVS vs as = isJust $ VS.solve vs as

checkRealBySimplex :: VarSet -> [LA.Atom Rational] -> Bool
checkRealBySimplex vs as = unsafePerformIO $ do
  solver <- Simplex2.newSolver
  s <- liftM IM.fromList $ forM (IS.toList vs) $ \v -> do
    v2 <- Simplex2.newVar solver
    return (v, LA.var v2)
  forM_ as $ \a -> do
    Simplex2.assertAtomEx solver (fmap (LA.applySubst s) a)
  Simplex2.check solver