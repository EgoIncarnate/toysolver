{-# LANGUAGE TemplateHaskell, ScopedTypeVariables #-}
module Test.Misc (miscTestGroup) where

import Prelude hiding (all)

import Control.Applicative
import Control.Arrow
import Control.Monad
import Data.Foldable (all)
import Data.IntSet (IntSet)
import qualified Data.IntSet as IntSet
import Data.Ratio
import Data.Set (Set)
import qualified Data.Set as Set
import qualified Data.Vector as V
import qualified Data.Vector.Unboxed as VU
import Data.VectorSpace ((*^))
import Test.QuickCheck.Function
import Test.Tasty
import Test.Tasty.QuickCheck hiding ((.&&.), (.||.))
import Test.Tasty.HUnit
import Test.Tasty.TH
import ToySolver.Data.Boolean
import ToySolver.Data.BoolExpr
import ToySolver.Data.Delta (Delta (..))
import qualified ToySolver.Data.Delta as Delta
import qualified ToySolver.Internal.Data.Vec as Vec
import ToySolver.Internal.Util
import ToySolver.Internal.TextUtil
import qualified ToySolver.Combinatorial.Knapsack.BB as KnapsackBB
import qualified ToySolver.Combinatorial.Knapsack.DPDense as KnapsackDPDense
import qualified ToySolver.Combinatorial.Knapsack.DPSparse as KnapsackDPSparse
import qualified ToySolver.Combinatorial.HittingSet.Simple as HittingSet
import qualified ToySolver.Combinatorial.HittingSet.FredmanKhachiyan1996 as FredmanKhachiyan1996
import qualified ToySolver.Combinatorial.HittingSet.GurvichKhachiyan1999 as GurvichKhachiyan1999
import qualified ToySolver.Combinatorial.SubsetSum as SubsetSum
import qualified ToySolver.Wang as Wang

case_showRationalAsDecimal :: IO ()
case_showRationalAsDecimal = do
  showRationalAsFiniteDecimal 0      @?= Just "0.0"
  showRationalAsFiniteDecimal 1      @?= Just "1.0"
  showRationalAsFiniteDecimal (-1)   @?= Just "-1.0"
  showRationalAsFiniteDecimal 0.1    @?= Just "0.1"
  showRationalAsFiniteDecimal (-0.1) @?= Just "-0.1"
  showRationalAsFiniteDecimal 1.1    @?= Just "1.1"
  showRationalAsFiniteDecimal (-1.1) @?= Just "-1.1"
  showRationalAsFiniteDecimal (5/4)  @?= Just "1.25"
  showRationalAsFiniteDecimal (-5/4) @?= Just "-1.25"
  showRationalAsFiniteDecimal (4/3)  @?= Nothing
  showRationalAsFiniteDecimal (-4/3) @?= Nothing

case_readUnsignedInteger_maxBound_bug :: IO ()
case_readUnsignedInteger_maxBound_bug =
  readUnsignedInteger "006666666666666667" @?= 6666666666666667

prop_readUnsignedInteger = 
  forAll (choose (0, 2^(128::Int))) $ \i -> 
    readUnsignedInteger (show i) == i

-- ---------------------------------------------------------------------
-- Knapsack problems

case_knapsack_BB_1 :: IO ()
case_knapsack_BB_1 = KnapsackBB.solve [(5,4), (6,5), (3,2)] 9 @?= (11, 9, [True,True,False])

case_knapsack_BB_2 :: IO ()
case_knapsack_BB_2 = KnapsackBB.solve [(16,2), (19,3), (23,4), (28,5)] 7 @?= (44, 7, [True,False,False,True])

case_knapsack_DPDense_1 :: IO ()
case_knapsack_DPDense_1 = KnapsackDPDense.solve [(5,4), (6,5), (3,2)] 9 @?= (11, 9, [True,True,False])

case_knapsack_DPDense_2 :: IO ()
case_knapsack_DPDense_2 = KnapsackDPDense.solve [(16,2), (19,3), (23,4), (28,5)] 7 @?= (44, 7, [True,False,False,True])

prop_knapsack_DPDense_equals_BB =
  forAll knapsackProblems $ \(items,lim) ->
    let items' = [(v, fromIntegral w) | (v,w) <- items]
        lim' = fromIntegral lim
        (v1,_,_) = KnapsackBB.solve items' lim'
        (v2,_,_) = KnapsackDPDense.solve items lim
    in v1 == v2
      
case_knapsack_DPSparse_1 :: IO ()
case_knapsack_DPSparse_1 = KnapsackDPSparse.solve [(5,4), (6,5), (3,2)] 9 @?= (11, 9, [True,True,False])

case_knapsack_DPSparse_2 :: IO ()
case_knapsack_DPSparse_2 = KnapsackDPSparse.solve [(16,2), (19,3), (23,4), (28,5)] 7 @?= (44, 7, [True,False,False,True])

prop_knapsack_DPSparse_equals_BB =
  forAll knapsackProblems $ \(items,lim) ->
    let -- items' :: Num a => [(Rational, a)]
        items' = [(v, fromIntegral w) | (v,w) <- items]
        (v1,_,_) = KnapsackBB.solve items' (fromIntegral lim)
        (v2,_,_) = KnapsackDPSparse.solve items' (fromIntegral lim)
    in v1 == v2

knapsackProblems :: Gen ([(KnapsackDPDense.Value, KnapsackDPDense.Weight)], KnapsackDPDense.Weight)
knapsackProblems = do
  lim <- choose (0,30)
  items <- listOf $ do
    v <- liftM abs arbitrary
    w <- choose (0,30)
    return (v,w)
  return (items, lim)

-- ---------------------------------------------------------------------
-- Hitting sets

case_minimalHittingSets_1 = actual @?= expected
  where
    actual    = HittingSet.minimalHittingSets $ Set.fromList $ map IntSet.fromList [[1], [2,3,5], [2,3,6], [2,4,5], [2,4,6]]
    expected  = Set.fromList $ map IntSet.fromList [[1,2], [1,3,4], [1,5,6]]

-- an example from http://kuma-san.net/htcbdd.html
case_minimalHittingSets_2 = actual @?= expected
  where
    actual    = HittingSet.minimalHittingSets $ Set.fromList $ map IntSet.fromList [[2,4,7], [7,8], [9], [9,10]]
    expected  = Set.fromList $ map IntSet.fromList [[7,9], [4,8,9], [2,8,9]]

hyperGraph :: Gen (Set IntSet)
hyperGraph = do
  nv <- choose (0, 10)
  ne <- if nv==0 then return 0 else choose (0, 20)
  liftM Set.fromList $ replicateM ne $ do
    n <- choose (1,nv)
    liftM IntSet.fromList $ replicateM n $ choose (1, nv)

isHittingSetOf :: IntSet -> Set IntSet -> Bool
isHittingSetOf s g = all (\e -> not (IntSet.null (s `IntSet.intersection` e))) g

prop_minimalHittingSets_duality =
  forAll hyperGraph $ \g ->
    let h = HittingSet.minimalHittingSets g
    in h == HittingSet.minimalHittingSets (HittingSet.minimalHittingSets h)

prop_minimalHittingSets_isHittingSet =
  forAll hyperGraph $ \g ->
    all (`isHittingSetOf` g) (HittingSet.minimalHittingSets g)

prop_minimalHittingSets_minimality =
  forAll hyperGraph $ \g ->
    forAll (elements (Set.toList (HittingSet.minimalHittingSets g))) $ \s ->
      if IntSet.null s then
        property True
      else
        forAll (elements (IntSet.toList s)) $ \v ->
          not $ IntSet.delete v s `isHittingSetOf` g

mutuallyDualHypergraphs :: Gen (Set IntSet, Set IntSet)
mutuallyDualHypergraphs = do
  g <- liftM HittingSet.minimalHittingSets hyperGraph
  let f = HittingSet.minimalHittingSets g
  return (f,g)

mutuallyDualDNFs :: Gen (Set IntSet, Set IntSet)
mutuallyDualDNFs = do
  (f,g) <- mutuallyDualHypergraphs
  let xs = IntSet.unions $ Set.toList $ f `Set.union` g
  if IntSet.null xs then
    return (f,g)
  else do
    let xs' = IntSet.toList xs
    let mutate h = liftM Set.unions $ do
          forM (Set.toList h) $ \is -> oneof $
            [ return $ Set.singleton is
            , do i <- elements xs'
                 return $ Set.fromList [is, IntSet.insert i is]
            ]
    f' <- mutate f
    g' <- mutate g
    return (f',g')

-- Pair of DNFs that are nearly dual.
pairOfDNFs :: Gen (Set IntSet, Set IntSet)
pairOfDNFs = do
  (f,g) <- mutuallyDualDNFs
  let mutate h = liftM Set.unions $ do
        forM (Set.toList h) $ \is -> oneof $
          [return Set.empty, return (Set.singleton is)] ++
          [ do x <- elements (IntSet.toList is)
               return $ Set.singleton $ IntSet.delete x is
          | not (IntSet.null is)
          ]
  return (f,g)

prop_FredmanKhachiyan1996_checkDualityA_prop1 =
  forAll mutuallyDualDNFs $ \(f,g) ->
    FredmanKhachiyan1996.checkDualityA f g == Nothing

prop_FredmanKhachiyan1996_checkDualityA_prop2 =
  forAll pairOfDNFs $ \(f,g) ->
    case FredmanKhachiyan1996.checkDualityA f g of
      Nothing -> True
      Just xs -> xs `FredmanKhachiyan1996.isCounterExampleOf` (f,g)

prop_FredmanKhachiyan1996_checkDualityB_prop1 =
  forAll mutuallyDualDNFs $ \(f,g) ->
    FredmanKhachiyan1996.checkDualityA f g == Nothing

prop_FredmanKhachiyan1996_checkDualityB_prop2 =
  forAll pairOfDNFs $ \(f,g) ->
    case FredmanKhachiyan1996.checkDualityB f g of
      Nothing -> True
      Just xs -> xs `FredmanKhachiyan1996.isCounterExampleOf` (f,g)

prop_FredmanKhachiyan1996_lemma_1 =
  forAll mutuallyDualHypergraphs $ \(f,g) ->
    let e :: Rational
        e = sum [1 % (2 ^ IntSet.size i) | i <- Set.toList f] +
            sum [1 % (2 ^ IntSet.size j) | j <- Set.toList g]
    in e >= 1

prop_FredmanKhachiyan1996_corollary_1 =
  forAll mutuallyDualHypergraphs $ \(f,g) ->
    let n = Set.size f + Set.size g
        m = minimum [IntSet.size is | is <- Set.toList (f `Set.union` g)]
    in fromIntegral m <= logBase 2 (fromIntegral n)

prop_FredmanKhachiyan1996_lemma_2 =
  forAll mutuallyDualHypergraphs $ \(f,g) ->
    let n = Set.size f + Set.size g
        epsilon :: Double
        epsilon = 1 / logBase 2 (fromIntegral n)
        vs = IntSet.unions $ Set.toList $ f `Set.union` g
    in (Set.size f * Set.size g >= 1)
       ==> any (\v -> FredmanKhachiyan1996.occurFreq v f >= epsilon || FredmanKhachiyan1996.occurFreq v g >= epsilon) (IntSet.toList vs)

prop_FredmanKhachiyan1996_lemma_3_a =
  forAll mutuallyDualHypergraphs $ \(f,g) ->
    let vs = IntSet.unions $ Set.toList $ f `Set.union` g
        x = IntSet.findMin vs
        -- f = x f0 ∨ f1
        (f0, f1) = Set.map (IntSet.delete x) *** id $ Set.partition (x `IntSet.member`) f
        -- g = x g0 ∨ g1
        (g0, g1) = Set.map (IntSet.delete x) *** id $ Set.partition (x `IntSet.member`) g
    in not (IntSet.null vs)
       ==>
         HittingSet.minimalHittingSets f1 == FredmanKhachiyan1996.deleteRedundancy (g0 `Set.union` g1) &&
         HittingSet.minimalHittingSets g1 == FredmanKhachiyan1996.deleteRedundancy (f0 `Set.union` f1)

prop_FredmanKhachiyan1996_to_selfDuality =
  forAll mutuallyDualHypergraphs $ \(f,g) ->
    let vs = IntSet.unions $ Set.toList $ f `Set.union` g
        y = if IntSet.null vs then 0 else IntSet.findMax vs + 1
        z = y + 1
        h = FredmanKhachiyan1996.deleteRedundancy $ Set.unions
              [ Set.map (IntSet.insert y) f
              , Set.map (IntSet.insert z) g
              , Set.singleton (IntSet.fromList [y,z])
              ] 
    in HittingSet.minimalHittingSets h == h

case_FredmanKhachiyan1996_condition_1_1_solve_L = (xs `FredmanKhachiyan1996.isCounterExampleOf` (f,g)) @?= True
  where
    Just xs = FredmanKhachiyan1996.condition_1_1_solve f g
    f = Set.fromList $ map IntSet.fromList [[2,4,7], [7,8], [9], [4]]
    g = Set.fromList $ map IntSet.fromList [[7,9], [4,8,9], [2,8,9]]

case_FredmanKhachiyan1996_condition_1_1_solve_R = (xs `FredmanKhachiyan1996.isCounterExampleOf` (f,g)) @?= True
  where
    Just xs = FredmanKhachiyan1996.condition_1_1_solve f g
    f = Set.fromList $ map IntSet.fromList [[2,4,7], [7,8], [9]]
    g = Set.fromList $ map IntSet.fromList [[7,9], [4,8,9], [2,8,9], [4,7,8]]

case_FredmanKhachiyan1996_condition_1_2_solve_L = (xs `FredmanKhachiyan1996.isCounterExampleOf` (f,g)) @?= True
  where
    Just xs = FredmanKhachiyan1996.condition_1_2_solve f g
    f = Set.fromList $ map IntSet.fromList [[2,4,7], [7,8], [9,10]]
    g = Set.fromList $ map IntSet.fromList [[7,9], [4,8,9], [2,8,9]]

case_FredmanKhachiyan1996_condition_1_2_solve_R = (xs `FredmanKhachiyan1996.isCounterExampleOf` (f,g)) @?= True
  where
    Just xs = FredmanKhachiyan1996.condition_1_2_solve f g
    f = Set.fromList $ map IntSet.fromList [[2,4,7], [7,8], [9]]
    g = Set.fromList $ map IntSet.fromList [[7,9], [4,8,9], [2,8,9,10]]

case_FredmanKhachiyan1996_condition_1_3_solve_L = (xs `FredmanKhachiyan1996.isCounterExampleOf` (f,g)) @?= True
  where
    Just xs = FredmanKhachiyan1996.condition_1_3_solve f g
    f = Set.fromList $ map IntSet.fromList [[2,4,7,10], [7,8], [9]]
    g = Set.fromList $ map IntSet.fromList [[7,9,10], [4,8,9], [2,8,9]]

case_FredmanKhachiyan1996_condition_1_3_solve_R = (xs `FredmanKhachiyan1996.isCounterExampleOf` (f,g)) @?= True
  where
    Just xs = FredmanKhachiyan1996.condition_1_3_solve f g
    f = Set.fromList $ map IntSet.fromList [[2,4,7], [7,8], [9,10]]
    g = Set.fromList $ map IntSet.fromList [[7,9], [4,8,9], [2,8,9,10]]

case_FredmanKhachiyan1996_condition_2_1_solve_L = (xs `FredmanKhachiyan1996.isCounterExampleOf` (f,g)) @?= True
  where
    Just xs = FredmanKhachiyan1996.condition_2_1_solve f g
    f = Set.fromList $ map IntSet.fromList [[2,4,7], [4,7,9], [7,8,9]]
    g = Set.fromList $ map IntSet.fromList [[2,4,7], [2,8,9], [4,8,9]]

case_FredmanKhachiyan1996_condition_2_1_solve_R = (xs `FredmanKhachiyan1996.isCounterExampleOf` (f,g)) @?= True
  where
    Just xs = FredmanKhachiyan1996.condition_2_1_solve f g
    g = Set.fromList $ map IntSet.fromList [[2,4,7], [4,7,9], [7,8,9]]
    f = Set.fromList $ map IntSet.fromList [[2,4,7], [2,8,9], [4,8,9]]

case_FredmanKhachiyan1996_checkDualityA = FredmanKhachiyan1996.checkDualityA f g @?= Nothing
  where
    f = Set.fromList $ map IntSet.fromList [[2,4,7], [7,8], [9]]
    g = Set.fromList $ map IntSet.fromList [[7,9], [4,8,9], [2,8,9]]

case_FredmanKhachiyan1996_checkDualityB = FredmanKhachiyan1996.checkDualityB f g @?= Nothing
  where
    f = Set.fromList $ map IntSet.fromList [[2,4,7], [7,8], [9]]
    g = Set.fromList $ map IntSet.fromList [[7,9], [4,8,9], [2,8,9]]

prop_GurvichKhachiyan1999_generateCNFAndDNF =
  forAll hyperGraph $ \g ->
    let vs = IntSet.unions $ Set.toList g
        f xs = any (\is -> not $ IntSet.null $ xs `IntSet.intersection` is) (Set.toList g)
        dual f is = not $ f (vs `IntSet.difference` is)
        is `isImplicantOf` f = f is
        is `isImplicateOf` f = is `isImplicantOf` dual f
        is `isPrimeImplicantOf` f = is `isImplicantOf` f && all (\i -> not (IntSet.delete i is `isImplicantOf` f)) (IntSet.toList is)
        is `isPrimeImplicateOf` f = is `isImplicateOf` f && all (\i -> not (IntSet.delete i is `isImplicateOf` f)) (IntSet.toList is)
        (cnf,dnf) = GurvichKhachiyan1999.generateCNFAndDNF vs f Set.empty Set.empty
    in all (`isPrimeImplicantOf` f) (Set.toList dnf) &&
       all (`isPrimeImplicateOf` f) (Set.toList cnf)

prop_GurvichKhachiyan1999_minimalHittingSets_duality =
  forAll hyperGraph $ \g ->
    let h = GurvichKhachiyan1999.minimalHittingSets g
    in h == GurvichKhachiyan1999.minimalHittingSets (GurvichKhachiyan1999.minimalHittingSets h)

prop_GurvichKhachiyan1999_minimalHittingSets_isHittingSet =
  forAll hyperGraph $ \g ->
    all (`isHittingSetOf` g) (GurvichKhachiyan1999.minimalHittingSets g)

prop_GurvichKhachiyan1999_minimalHittingSets_minimality =
  forAll hyperGraph $ \g ->
    forAll (elements (Set.toList (GurvichKhachiyan1999.minimalHittingSets g))) $ \s ->
      if IntSet.null s then
        property True
      else
        forAll (elements (IntSet.toList s)) $ \v ->
          not $ IntSet.delete v s `isHittingSetOf` g

-- ---------------------------------------------------------------------
-- SubsetSum

evalSubsetSum :: [Integer] -> [Bool] -> Integer
evalSubsetSum ws bs = sum [w | (w,b) <- zip ws bs, b]

prop_maxSubsetSum_soundness =
  forAll arbitrary $ \c ->
    forAll arbitrary $ \ws ->
      case SubsetSum.maxSubsetSum (V.fromList ws) c of
        Just (obj, bs) -> obj == evalSubsetSum ws (VU.toList bs) && obj <= c
        Nothing -> True

prop_maxSubsetSum_completeness =
  forAll arbitrary $ \c ->
    forAll g $ \ws ->
      case SubsetSum.maxSubsetSum (V.fromList ws) c of
        Just (obj, bs) -> VU.length bs == length ws && obj == evalSubsetSum ws (VU.toList bs) && obj <= c
        Nothing -> and [c < evalSubsetSum ws bs | bs <- replicateM (length ws) [False,True]]
  where
    g = do
      n <- choose (0,10)
      replicateM n arbitrary

prop_maxSubsetSum_isEqualToKnapsackBBSolver =
  forAll (liftM abs arbitrary) $ \c ->
    forAll (liftM (map abs) arbitrary) $ \ws ->
      let Just (obj1, bs1) = SubsetSum.maxSubsetSum (V.fromList ws) c
          (obj2, _, bs2) = KnapsackBB.solve [(fromIntegral w, fromIntegral w) | w <- ws] (fromIntegral c)
      in fromIntegral obj1 == obj2

case_maxSubsetSum_regression_test_1 =
  SubsetSum.maxSubsetSum (V.fromList [4,28,5,6,18]) 25 @?= Just (24, VU.fromList [False,False,False,True,True])

case_maxSubsetSum_regression_test_2 =
  SubsetSum.maxSubsetSum (V.fromList [10,15]) 18 @?= Just (15, VU.fromList [False,True])

prop_minSubsetSum_soundness =
  forAll arbitrary $ \c ->
    forAll arbitrary $ \ws ->
      case SubsetSum.minSubsetSum (V.fromList ws) c of
        Just (obj, bs) -> obj == evalSubsetSum ws (VU.toList bs) && c <= obj
        Nothing -> True

prop_minSubsetSum_completeness =
  forAll arbitrary $ \c ->
    forAll g $ \ws ->
      case SubsetSum.minSubsetSum (V.fromList ws) c of
        Just (obj, bs) -> VU.length bs == length ws && obj == evalSubsetSum ws (VU.toList bs) && c <= obj
        Nothing -> and [evalSubsetSum ws bs < c | bs <- replicateM (length ws) [False,True]]
  where
    g = do
      n <- choose (0,10)
      replicateM n arbitrary

prop_subsetSum_soundness =
  forAll arbitrary $ \c ->
    forAll arbitrary $ \ws ->
      case SubsetSum.subsetSum (V.fromList ws) c of
        Just bs -> VU.length bs == length ws && evalSubsetSum ws (VU.toList bs) == c
        Nothing -> True

prop_subsetSum_completeness =
  forAll arbitrary $ \c ->
    forAll g $ \ws ->
      case SubsetSum.subsetSum (V.fromList ws) c of
        Just bs -> VU.length bs == length ws && evalSubsetSum ws (VU.toList bs) == c
        Nothing -> and [c /= evalSubsetSum ws bs | bs <- replicateM (length ws) [False,True]]
  where
    g = do
      n <- choose (0,10)
      replicateM n arbitrary

-- ---------------------------------------------------------------------
-- Delta
      
instance Arbitrary r => Arbitrary (Delta r) where
  arbitrary = do
    r <- arbitrary
    k <- arbitrary
    return (Delta r k)

prop_Delta_add_comm =
  forAll arbitrary $ \(a :: Delta Rational) ->
  forAll arbitrary $ \b ->
    a + b == b + a

prop_Delta_add_assoc =
  forAll arbitrary $ \(a :: Delta Rational) ->
  forAll arbitrary $ \b ->
  forAll arbitrary $ \c ->
    a + (b + c) == (a + b) + c

prop_Delta_add_unitL =
  forAll arbitrary $ \(a :: Delta Rational) ->
    0 + a == a

prop_Delta_add_unitR =
  forAll arbitrary $ \(a :: Delta Rational) ->
    a + 0 == a

prop_Delta_mult_comm =
  forAll arbitrary $ \(a :: Delta Rational) ->
  forAll arbitrary $ \b ->
    a * b == b * a

prop_Delta_mult_assoc =
  forAll arbitrary $ \(a :: Delta Rational) ->
  forAll arbitrary $ \b ->
  forAll arbitrary $ \c ->
    a * (b * c) == (a * b) * c

prop_Delta_mult_unitL =
  forAll arbitrary $ \(a :: Delta Rational) ->
    1 * a == a

prop_Delta_mult_unitR =
  forAll arbitrary $ \(a :: Delta Rational) ->
    a * 1 == a

prop_Delta_mult_dist =
  forAll arbitrary $ \(a :: Delta Rational) ->
  forAll arbitrary $ \b ->
  forAll arbitrary $ \c ->
    a * (b + c) == a * b + a * c

prop_Delta_mult_zero = 
  forAll arbitrary $ \(a :: Delta Rational) ->
    0 * a ==  0

prop_Delta_scale_mult = 
  forAll arbitrary $ \(a :: Delta Rational) ->
  forAll arbitrary $ \b ->
    Delta.fromReal a * b ==  a *^ b

prop_Delta_signum_abs =
  forAll arbitrary $ \(x :: Delta Rational) ->
    abs x * signum x == x
    
prop_Delta_floor =
  forAll arbitrary $ \(x :: Delta Rational) ->
    let y = Delta.floor' x
    in fromIntegral y <= x && x < fromIntegral (y+1)

prop_Delta_ceiling =
  forAll arbitrary $ \(x :: Delta Rational) ->
    let y = Delta.ceiling' x
    in fromIntegral (y-1) < x && x <= fromIntegral y

prop_Delta_properFraction =
  forAll arbitrary $ \(x :: Delta Rational) ->
    let (n,f) = properFraction x
    in and
       [ abs f < 1
       , not (x >= 0) || (n >= 0 && f >= 0)
       , not (x <= 0) || (n <= 0 && f <= 0)
       ]

-- ---------------------------------------------------------------------
-- Vec

case_Vec :: IO ()
case_Vec = do
  (v::Vec.UVec Int) <- Vec.new
  let xs = [0..100]
  forM_ xs $ \i -> Vec.push v i
  ys <- Vec.getElems v
  ys @?= xs

  Vec.resize v 4
  zs <- Vec.getElems v
  zs @?= take 4 xs

  Vec.push v 1
  Vec.push v 2
  Vec.push v 3

  ws <- Vec.getElems v
  ws @?= take 4 xs ++ [1,2,3]

  x3 <- Vec.unsafePop v
  x3 @?= 3
  s <- Vec.getSize v
  s @?= 6
  ws <- Vec.getElems v
  ws @?= take 4 xs ++ [1,2]

case_Vec_clone :: IO ()
case_Vec_clone = do
  (v::Vec.UVec Int) <- Vec.new  
  Vec.push v 0
  v2 <- Vec.clone v
  Vec.write v2 0 1

  a <- Vec.read v 0
  a @?= 0

  b <- Vec.read v2 0
  b @?= 1

-- ---------------------------------------------------------------------
-- BoolExpr

instance Arbitrary a => Arbitrary (BoolExpr a) where
  arbitrary = sized f
    where
      f n | n <= 0 = Atom <$> arbitrary
      f n =
        oneof
        [ Atom <$> arbitrary
        , And <$> list (n-1)
        , Or <$> list (n-1)
        , Not <$> (f (n-1))
        , uncurry Imply <$> pair (n-1)
        , uncurry Equiv <$> pair (n-1)
        , triple (n-1) >>= \(c,t,e) -> return (ITE c t e)
        ]

      pair n | n <= 0 = do
        a <- f 0
        b <- f 0
        return (a,b)
      pair n = do
        m <- choose (0,n)
        a <- f m
        b <- f (n-m)
        return (a,b)

      triple n | n <= 0 = do
        a <- f 0
        b <- f 0
        c <- f 0
        return (a,b,c)
      triple n = do
        m <- choose (0, n)
        o <- choose (0, n-m)
        a <- f m
        b <- f o
        c <- f (n - m - o)
        return (a,b,c)

      list n | n <= 0 = return []
      list n = oneof $
        [ return []
        , do m <- choose (0,n)
             x  <- f m
             xs <- list (n-m-1)
             return (x:xs)
        ]

prop_BoolExpr_Functor_identity =
  forAll arbitrary $ \(b :: BoolExpr Int) ->
    fmap id b == b

prop_BoolExpr_Functor_compsition =
  forAll arbitrary $ \(b :: BoolExpr Int) ->
    forAll arbitrary $ \(f :: Fun Int Int) ->
      forAll arbitrary $ \(g :: Fun Int Int) ->
        fmap (apply f . apply g) b == fmap (apply f) (fmap (apply g) b)

prop_BoolExpr_Applicative_identity =
  forAll arbitrary $ \(b :: BoolExpr Int) ->
    (pure id <*> b) == b

prop_BoolExpr_Applicative_composition =
  forAll arbitrary $ \(w :: BoolExpr Int) ->
    forAll arbitrary $ \(u :: BoolExpr (Fun Int Int)) ->
      forAll arbitrary $ \(v :: BoolExpr (Fun Int Int)) ->
        (pure (.) <*> fmap apply u <*> fmap apply v <*> w) == (fmap apply u <*> (fmap apply v <*> w))

prop_BoolExpr_Applicative_homomorphism =
  forAll arbitrary $ \(x :: Int) ->
    forAll arbitrary $ \(f :: Fun Int Int) ->
      (pure (apply f) <*> pure x) == (pure (apply f x) :: BoolExpr Int)

prop_BoolExpr_Applicative_interchange =
  forAll arbitrary $ \(y :: Int) ->
    forAll arbitrary $ \(u :: BoolExpr (Fun Int Int)) ->
      (fmap apply u <*> pure y) == (pure ($ y) <*> fmap apply u)

prop_BoolExpr_Monad_left_identity =
  forAll arbitrary $ \(b :: BoolExpr Int) ->
    forAll arbitrary $ \(f :: Fun Int (BoolExpr Int)) ->
        (b >>= (\x -> return x >>= apply f)) == (b >>= apply f)

prop_BoolExpr_Monad_bind_right_identity =
  forAll arbitrary $ \(b :: BoolExpr Int) ->
    forAll arbitrary $ \(f :: Fun Int (BoolExpr Int)) ->
        (b >>= (\x -> apply f x >>= return)) == (b >>= apply f)

prop_BoolExpr_Monad_bind_associativity =
  forAll arbitrary $ \(b :: BoolExpr Int) ->
    forAll arbitrary $ \(f :: Fun Int (BoolExpr Int)) ->
      forAll arbitrary $ \(g :: Fun Int (BoolExpr Int)) ->
        (b >>= apply f >>= apply g) == (b >>= (\x -> apply f x >>= apply g))


-- ---------------------------------------------------------------------
-- Wang

-- (x1 ∨ x2) ∧ (x1 ∨ ¬x2) ∧ (¬x1 ∨ ¬x2) is satisfiable
-- ¬((x1 ∨ x2) ∧ (x1 ∨ ¬x2) ∧ (¬x1 ∨ ¬x2)) is invalid
case_Wang_1 =
  Wang.isValid ([], [phi]) @?= False
  where
    phi = notB $ andB [x1 .||. x2, x1 .||. notB x2, notB x1 .||. notB x2]
    x1 = Atom 1
    x2 = Atom 2

-- (x1 ∨ x2) ∧ (¬x1 ∨ x2) ∧ (x1 ∨ ¬x2) ∧ (¬x1 ∨ ¬x2) is unsatisfiable
-- ¬((x1 ∨ x2) ∧ (¬x1 ∨ x2) ∧ (x1 ∨ ¬x2) ∧ (¬x1 ∨ ¬x2)) is valid
case_Wang_2 =
  Wang.isValid ([], [phi]) @?= True
  where
    phi = notB $ andB [x1 .||. x2, notB x1 .||. x2, x1 .||. notB x2, notB x1 .||. notB x2]
    x1 = Atom 1
    x2 = Atom 2

case_Wang_EM =
  Wang.isValid ([], [phi]) @?= True
  where
    phi = x1 .||. notB x1
    x1 = Atom 1

case_Wang_DNE =
  Wang.isValid ([], [phi]) @?= True
  where
    phi = notB (notB x1) .<=>. x1
    x1 = Atom 1

case_Wang_Peirces_Law =
  Wang.isValid ([], [phi]) @?= True
  where
    phi = ((x1 .=>. x2) .=>. x1) .=>. x1
    x1 = Atom 1
    x2 = Atom 2

------------------------------------------------------------------------
-- Test harness

miscTestGroup :: TestTree
miscTestGroup = $(testGroupGenerator)
