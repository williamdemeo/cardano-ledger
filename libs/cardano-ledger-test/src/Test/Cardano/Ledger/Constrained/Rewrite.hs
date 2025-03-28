{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE PartialTypeSignatures #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}

module Test.Cardano.Ledger.Constrained.Rewrite (
  rewrite,
  rewriteGen,
  rewritePred,
  compile,
  compileGenWithSubst,
  removeSameVar,
  removeEqual,
  DependGraph (..),
  accumdep,
  OrderInfo (..),
  standardOrderInfo,
  initialOrder,
  showGraph,
  listEq,
  mkDependGraph,
  notBefore,
  cpeq,
  cteq,
  mkNewVar,
  addP,
  addPred,
  partitionE,
  rename,
) where

import Cardano.Ledger.Core (Era)
import qualified Data.Array as A
import Data.Foldable (toList)
import Data.Graph (Graph, SCC (AcyclicSCC, CyclicSCC), Vertex, graphFromEdges, stronglyConnComp)
import Data.HashSet (HashSet)
import qualified Data.HashSet as HashSet
import qualified Data.List as List
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Set (Set)
import qualified Data.Set as Set
import Test.Cardano.Ledger.Constrained.Ast
import Test.Cardano.Ledger.Constrained.Combinators (setSized)
import Test.Cardano.Ledger.Constrained.Env (
  Access (..),
  AnyF (..),
  Env (..),
  Field (..),
  Name (..),
  V (..),
  sameName,
 )
import Test.Cardano.Ledger.Constrained.Monad (HasConstraint (With), Typed (..), failT, monadTyped)
import Test.Cardano.Ledger.Constrained.Size (Size (SzExact), genFromSize)
import Test.Cardano.Ledger.Constrained.TypeRep
import Test.QuickCheck
import Type.Reflection (typeRep)

-- ============================================================
-- Conservative (approximate) Equality

-- | Test if two terms (of possibly different types) are equal
typedEq :: Era era => Term era a -> Term era b -> Bool
typedEq x y = case testEql (termRep x) (termRep y) of
  Just Refl -> cteq x y
  Nothing -> False

cEq :: (Eq c, Era era) => Term era c -> Term era a -> c -> a -> Bool
cEq t1 t2 c1 c2 = case testEql (termRep t1) (termRep t2) of
  Just Refl -> c1 == c2
  Nothing -> False

listEq :: (a -> b -> Bool) -> [a] -> [b] -> Bool
listEq _ [] [] = True
listEq eqf (x : xs) (y : ys) = eqf x y && listEq eqf xs ys
listEq _ _ _ = False

-- | Conservative Sum equality
csumeq :: Era era => Sum era t -> Sum era t -> Bool
csumeq (One x) (One y) = cteq x y
csumeq (SumMap x) (SumMap y) =
  case testEql (termRep x) (termRep y) of
    Just Refl -> cteq x y
    Nothing -> False
csumeq (SumList x) (SumList y) = cteq x y
csumeq _ _ = False

-- | Conservative (and unsound for Constr and Invert) Target equality
_ctareq :: Era era => RootTarget era r t -> RootTarget era r t -> Bool
_ctareq (Constr x _) (Constr y _) = x == y
_ctareq (Invert x _ _) (Invert y _ _) = x == y
_ctareq (Simple x) (Simple y) = cteq x y
_ctareq (x :$ (Simple xs)) (y :$ (Simple ys)) =
  case testEql (termRep xs) (termRep ys) of
    Just Refl -> _ctareq x y && cteq xs ys
    Nothing -> False
_ctareq _ _ = False

-- | Conservative Term equality
cteq :: Era era => Term era t -> Term era t -> Bool
cteq (Lit t1 x) (Lit t2 y) = case testEql t1 t2 of
  Just Refl ->
    case hasEq t1 t1 of
      Typed (Right (With _)) -> x == y
      _ -> False
  Nothing -> False
cteq (Var x) (Var y) = Name x == Name y
cteq (Dom x) (Dom y) = typedEq x y
cteq (Rng x) (Rng y) = typedEq x y
cteq (Elems x) (Elems y) = typedEq x y
cteq (Delta x) (Delta y) = typedEq x y
cteq (Negate x) (Negate y) = typedEq x y
cteq (HashD x) (HashD y) = typedEq x y
cteq (HashS x) (HashS y) = typedEq x y
cteq (Pair x a) (Pair y b) = typedEq x y && typedEq a b
cteq _ _ = False

-- | Conservative Pred equality
cpeq :: Era era => Pred era -> Pred era -> Bool
cpeq (Sized x a) (Sized y b) = cteq x y && typedEq a b
cpeq (x :=: a) (y :=: b) = typedEq x y && typedEq a b
cpeq (x :⊆: a) (y :⊆: b) = typedEq x y && typedEq a b
cpeq (Disjoint x a) (Disjoint y b) = typedEq x y && typedEq a b
cpeq (Random x) (Random y) = typedEq x y
cpeq (CanFollow x a) (CanFollow y b) = typedEq x y && typedEq a b
cpeq (SumsTo (Right i) x c xs) (SumsTo (Right j) y d ys) = cEq x y i j && typedEq x y && listEq cseq xs ys && c == d
cpeq (SumsTo (Left i) x c xs) (SumsTo (Left j) y d ys) = cEq x y i j && typedEq x y && listEq cseq xs ys && c == d
cpeq (SumSplit i x c xs) (SumSplit j y d ys) = cEq x y i j && typedEq x y && listEq cseq xs ys && c == d
cpeq (Component (Left x) xs) (Component (Left y) ys) = typedEq x y && listEq anyWeq xs ys
cpeq (Component (Right x) xs) (Component (Right y) ys) = typedEq x y && listEq anyWeq xs ys
cpeq (Member (Right x) xs) (Member (Right y) ys) = typedEq x y && typedEq xs ys
cpeq (Member (Left x) xs) (Member (Left y) ys) = typedEq x y && typedEq xs ys
cpeq (SubMap x xs) (SubMap y ys) = typedEq x y && typedEq xs ys
cpeq (NotMember x xs) (NotMember y ys) = typedEq x y && typedEq xs ys
{- TODO FIX ME
cpeq (x :<-: xs) (y :<-: ys) = case testEql (termRep x) (termRep y) of
  Just Refl -> typedEq x y && _ctareq xs ys
  Nothing -> False
-}
cpeq x y = sumsEq x y

-- |  Conservative SumsTo equality
sumsEq :: Era era => Pred era -> Pred era -> Bool
sumsEq (SumsTo (Left s1) x1 c1 ss1) (SumsTo (Left s2) x2 c2 ss2) =
  case testEql (termRep x1) (termRep x2) of
    Just Refl -> s1 == s2 && typedEq x1 x2 && c1 == c2 && listEq csumeq ss1 ss2
    Nothing -> False
sumsEq (SumsTo (Right s1) x1 c1 ss1) (SumsTo (Right s2) x2 c2 ss2) =
  case testEql (termRep x1) (termRep x2) of
    Just Refl -> s1 == s2 && typedEq x1 x2 && c1 == c2 && listEq csumeq ss1 ss2
    Nothing -> False
sumsEq _ _ = False

-- | Conservative Sum equality
cseq :: Era era => Sum era c -> Sum era d -> Bool
cseq (One x) (One y) = typedEq x y
cseq (SumMap x) (SumMap y) = typedEq x y
cseq (SumList x) (SumList y) = typedEq x y
cseq (ProjMap r1 _ x) (ProjMap r2 _ y) = case testEql r1 r2 of
  Just Refl -> typedEq x y
  Nothing -> False
cseq _ _ = False

anyWeq :: Era era => AnyF era t -> AnyF era s -> Bool
anyWeq (AnyF (Field x y z l)) (AnyF (Field a b c m)) = Name (V x y (Yes z l)) == Name (V a b (Yes c m))
anyWeq _ _ = False

-- ==================================================================================
-- Rewriting by replacing (Dom x) by a new varariabl xDom, and adding additional
-- [Pred], that relate xDom with other terms

mkNewVar :: forall era d r. Term era (Map d r) -> Term era (Set d)
mkNewVar (Var (V nm (MapR d _) _)) = newVar
  where
    newstring = nm ++ "Dom"
    newV = V newstring (SetR d) No
    newVar = Var newV
mkNewVar other = error ("mkNewVar should only be applied to variables: " ++ show other)

addP :: Era era => Pred era -> [Pred era] -> [Pred era]
addP p ps = List.nubBy cpeq (p : ps)

addPred ::
  Era era => HashSet (Name era) -> Pred era -> [Name era] -> [Pred era] -> [Pred era] -> [Pred era]
addPred bad orig names ans newps =
  if any (\x -> HashSet.member x bad) names
    then addP orig ans
    else foldr addP ans newps

removeSameVar :: Era era => [Pred era] -> [Pred era] -> [Pred era]
removeSameVar [] ans = reverse ans
removeSameVar ((Var v :=: Var u) : more) ans | Name v == Name u = removeSameVar more ans
removeSameVar ((Var v :⊆: Var u) : more) ans | Name v == Name u = removeSameVar more ans
removeSameVar (Disjoint (Var v@(V _ rep _)) (Var u) : more) ans | Name v == Name u = removeSameVar more ((Lit rep mempty :=: Var v) : ans)
removeSameVar (m : more) ans = removeSameVar more (m : ans)

removeEqual :: Era era => [Pred era] -> [Pred era] -> [Pred era]
removeEqual [] ans = reverse ans
removeEqual ((Var v :=: Var u) : more) ans | Name v == Name u = removeEqual more ans
removeEqual ((Var v :=: expr@Lit {}) : more) ans = removeEqual (map sub more) ((Var v :=: expr) : map sub ans)
  where
    sub = substPred (singleSubst v expr)
removeEqual ((expr@Lit {} :=: Var v) : more) ans = removeEqual (map sub more) ((expr :=: Var v) : map sub ans)
  where
    sub = substPred (singleSubst v expr)
removeEqual (m : more) ans = removeEqual more (m : ans)

removeTrivial :: Era era => [Pred era] -> [Pred era]
removeTrivial = filter (not . trivial)
  where
    trivial p | null (varsOfPred mempty p) =
      case runTyped $ runPred (Env mempty) p of
        Left {} -> False
        Right validx -> validx
    trivial (e1 :=: e2) = cteq e1 e2
    trivial _ = False

rewrite :: Era era => [Pred era] -> [Pred era]
rewrite cs = removeTrivial $ removeSameVar (removeEqual cs []) []

-- =========================================================
-- Expanding (Choose _ _ _) into several simpler [Pred era]

type SubItems era = [SubItem era]

fresh :: (Int, SubItems era) -> RootTarget era r t -> (Int, SubItems era)
fresh (n, sub) (Constr _ _) = (n, sub)
fresh (n, sub) (Invert _ _ _) = (n, sub)
fresh (n, sub) (Shift x _) = fresh (n, sub) x
fresh (n, sub) (Mask x) = fresh (n, sub) x
fresh (n, sub) (Simple (Var v@(V nm rep acc))) = (n + 1, SubItem v (Var (V (index nm n) rep acc)) : sub)
fresh (n, sub) (Simple expr) = mksub n (HashSet.toList (vars expr))
  where
    mksub m names = (n + length names, sub2 ++ sub)
      where
        sub2 = zipWith (\(Name v@(V nm r _)) m1 -> SubItem v (Var (V (index nm m1) r No))) names [m ..]
fresh (n, sub) (Lensed (Var v@(V nm rep acc)) _) = (n + 1, SubItem v (Var (V (index nm n) rep acc)) : sub)
fresh (n, sub) (Lensed expr _) = mksub n (HashSet.toList (vars expr))
  where
    mksub m names = (n + length names, sub2 ++ sub)
      where
        sub2 = zipWith (\(Name v@(V nm r _)) m1 -> SubItem v (Var (V (index nm m1) r No))) names [m ..]
fresh (n, sub) (Partial (Var v@(V nm rep acc)) _) = (n + 1, SubItem v (Var (V (index nm n) rep acc)) : sub)
fresh (n, sub) (Partial expr _) = mksub n (HashSet.toList (vars expr))
  where
    mksub m names = (n + length names, sub2 ++ sub)
      where
        sub2 = zipWith (\(Name v@(V nm r _)) m1 -> SubItem v (Var (V (index nm m1) r No))) names [m ..]
fresh (n, sub) (f :$ x) = fresh (fresh (n, sub) f) x
fresh (n, sub) (Virtual x _ _) = fresh (n, sub) (Simple x)

freshP :: (Int, SubItems era) -> Pat era t -> (Int, SubItems era)
freshP (n, sub) (Pat _ as) = List.foldl' freshA (n, sub) as

freshA :: (Int, SubItems era) -> Arg era t -> (Int, SubItems era)
freshA (n, sub) (Arg (Field nm r a l)) = (n + 1, SubItem (V nm r (Yes a l)) (Var (V (index nm n) r (Yes a l))) : sub)
freshA pair (Arg (FConst _ _ _ _)) = pair
freshA (n, sub) (ArgPs (Field nm r a l) ps) =
  List.foldl' freshP (n + 1, SubItem (V nm r (Yes a l)) (Var (V (index nm n) r (Yes a l))) : sub) ps
freshA pair (ArgPs (FConst _ _ _ _) ps) = List.foldl' freshP pair ps

freshVars :: Int -> Int -> V era [t] -> ([Term era t], Int)
freshVars m count (V nm (ListR rep) _) = ([Var (V (index nm c) rep No) | c <- [m .. m + (count - 1)]], m + count)

index :: String -> Int -> String
index nm c = nm ++ "." ++ show c

-- When we expect the variable to have a (FromList t a) constraint
freshVars2 :: FromList fs t => Int -> Int -> V era fs -> ([Term era t], Int)
freshVars2 m count (V nm lrep _) =
  let arep = tsRep lrep
   in ([Var (V (index nm c) arep No) | c <- [m .. m + (count - 1)]], m + count)

freshPairs ::
  ((Int, SubItems era), [(RootTarget era r t, [Pred era])]) ->
  (RootTarget era r t, [Pred era]) ->
  ((Int, SubItems era), [(RootTarget era r t, [Pred era])])
freshPairs (xx, ans) (tar, ps) = (yy, (target2, ps2) : ans)
  where
    yy@(_, subitems) = fresh xx tar
    subst = itemsToSubst subitems
    target2 = substTarget subst tar
    ps2 = map (substPred subst) ps

freshPair ::
  Int ->
  (RootTarget era r t, [Pred era]) ->
  (Int, SubItems era, RootTarget era r t, [Pred era])
freshPair m0 (tar, ps) = (m1, subitems, target2, ps2)
  where
    (m1, subitems) = fresh (m0, []) tar
    subst = itemsToSubst subitems
    target2 = substTarget subst tar
    ps2 = map (substPred subst) ps

-- | Used to rename targets and preds, where they are embeded in a Triple, where the first component is the frequency
_freshTriples ::
  ((Int, SubItems era), [(Int, RootTarget era r t, [Pred era])]) ->
  (Int, RootTarget era r t, [Pred era]) ->
  ((Int, SubItems era), [(Int, RootTarget era r t, [Pred era])])
_freshTriples (xx, ans) (i, tar, ps) = (yy, (i, target2, ps2) : ans)
  where
    yy@(_, subitems) = fresh xx tar
    subst = itemsToSubst subitems
    target2 = substTarget subst tar
    ps2 = map (substPred subst) ps

freshPats ::
  ((Int, SubItems era), [(Pat era t, [Pred era])]) ->
  (Pat era t, [Pred era]) ->
  ((Int, SubItems era), [(Pat era t, [Pred era])])
freshPats (xx, ans) (pat, ps) = (yy, (pat2, ps2) : ans)
  where
    yy@(_, sub) = freshP xx pat
    subst = itemsToSubst sub
    pat2 = substPat subst pat
    ps2 = map (substPred subst) ps

-- | We have something like (SumsTo x total EQL [One x]) and we want
--   something like: (SumsTo x total EQL [One x.1, One x.2, One x.3])
-- | Or something like (SumSplit x total EQL [One x]) which expands to
--   something like: (SumSplitx total EQL [One x.1, One x.2, One x.3])
--   So we find all the bindings for 'x' in the SubItems, and cons them together.
extendSum :: SubItems era -> Sum era c -> [Sum era c]
extendSum sub (ProjOne l r (Var v2)) = foldr accum [] sub
  where
    accum (SubItem v1 term) ans | Just Refl <- sameName v1 v2 = ProjOne l r term : ans
    accum _ ans = ans
extendSum sub (One (Var v2)) = foldr accum [] sub
  where
    accum (SubItem v1 term) ans | Just Refl <- sameName v1 v2 = One term : ans
    accum _ ans = ans
extendSum _sub other = error ("None One or ProjOne in Sum list: " ++ show other)

extendSums :: Era era => SubItems era -> [Pred era] -> [Pred era]
extendSums _ [] = []
extendSums sub (SumsTo c t cond [s] : more) = SumsTo c t cond (extendSum sub s) : extendSums sub more
extendSums sub (SumSplit c t cond [s] : more) = SumSplit c t cond (extendSum sub s) : extendSums sub more
extendSums _ (m : _more) = error ("Non extendableSumsTo in extendSums: " ++ show m)

rename :: Name era -> [Int] -> [Name era]
rename name@(Name (V nm r a)) ns = case takeWhile (/= '.') nm of
  (_ : _) -> map (\n -> Name (V (index nm n) r a)) ns
  _ -> [name]

nUniqueFromM :: Int -> Int -> Gen [Int]
nUniqueFromM n m
  | n == 0 = pure []
  | n > m = pure [0 .. m]
  | otherwise =
      Set.toList
        <$> setSized ["from Choose", "nUniqueFromM " ++ show n ++ " " ++ show m] n (choose (0, m))

_pickNunique :: Int -> [a] -> Gen [a]
_pickNunique n xs = do
  indexes <- nUniqueFromM n (length xs - 1)
  pure [xs !! i | i <- indexes]

-- | Make a GenFrom frequency Pred, from the input and output terms
freq :: forall era t. Term era t -> Term era [(Int, t)] -> Pred era
freq outVar inVar = GenFrom outVar (Constr "frequency" (frequency . map h) :$ (Simple inVar))
  where
    h (i, x) = (i, pure x)

-- | Where is an abstraction for ( term :<-: target : preds )
type Where era t = (Term era t, RootTarget era t t, [Pred era])

-- | Unfold (Where x tar ps) into (x :<-: tar' : ps'), renaming tar to tar' and ps to ps'
unfoldWhere :: forall era t. ([Where era t], Int) -> ([Pred era], Int)
unfoldWhere (ps0, m0) = List.foldl' accum ([], m0) ps0
  where
    accum :: ([Pred era], Int) -> Where era t -> ([Pred era], Int)
    accum (ans, mx) (t, tar, ps) = ((t :<-: tar2) : ps2 ++ ans, mx1)
      where
        (mx1, _, tar2, ps2) = freshPair mx (tar, ps)

rewritePred :: Era era => Int -> Pred era -> Gen ([Pred era], Int)
{-
OneOf x [(i,t1,p1),(j,t2,p2)] rewrites to
[ Where x.1 t1 p1, Where x.2 t2 p2, List xlist.3 [(i,x.1),(j,x.2)], GenFrom x frequency xlist.3]
where each (Where xi ti pi) is unfolded by renaming 'ti' and 'pi'
-}
rewritePred m0 (Oneof term@(Var (V nm rep _)) ps0) = do
  let count = length ps0
      (vs, m1) = freshVars m0 count (V nm (ListR rep) No)
      (vlist, m2) = (Var (V (index (nm ++ "Pairs") m1) (ListR (PairR IntR rep)) No), m1 + 1)
      params = zipWith (\param (i, _, _) -> Pair (Lit IntR i) param) vs ps0
      wheres = zipWith (\v (_, tar, ps) -> (v, tar, ps)) vs ps0
      (unfolded, m3) = unfoldWhere (wheres, m2)
  (expandedPred, m4) <- removeExpandablePred ([], m3) unfolded
  pure (expandedPred ++ [List vlist params, freq term vlist], m4)
rewritePred m0 (Choose (Lit SizeR sz) (Var v) ps0) = do
  let ps1 = filter (\(i, _, _) -> i > 0) ps0
  count <- genFromSize sz
  ps2 <-
    if count <= length ps1
      then take count <$> shuffle (map (\(_, t, p) -> (t, p)) ps1)
      else vectorOf count (frequency (map (\(i, t, p) -> (i, pure (t, p))) ps1))
  let ((m1, _), ps3) = List.foldl' freshPairs ((m0, []), []) ps2
      (xs, m2) = freshVars m1 count v
      renamedPred = map snd ps3
  (expandedPred, m3) <- removeExpandablePred ([], m2) (concat renamedPred)
  let newps = expandedPred ++ zipWith (:<-:) xs (map fst ps3) ++ [List (Var v) xs]
  pure (newps, m3)

{- ListWhere (Range 2 2) w target{a,b} [Member a x, Member b y] rewrites to
[ Member a1 x
, Member b1 y
, Member a2 x
, Member b2 y
, w1 :<-: target{a1,b1} a1 b1
, w2 :<-: target{a2,b2} a2 b2
List w [w1,w2]
] -}
rewritePred m0 (ListWhere (Lit SizeR sz) (Var v) tar ps) = do
  count <- genFromSize sz
  (ps1, m1) <- pure (ps, m0) -- removeExpandablePred ([], m0) ps
  let ((m2, _subb), ps3) = List.foldl' freshPairs ((m1, []), []) (take count (repeat (tar, ps1)))
      (vs, m3) = freshVars2 m2 count v -- [v.1, v.2, v.3 ...]
      renamedPred = map snd ps3
      renamedTargets = map fst ps3
  (expandedPred, m4) <- removeExpandablePred ([], m3) (concat renamedPred)
  let newps = expandedPred ++ zipWith (:<-:) vs renamedTargets ++ [List (Var v) vs]
  pure (newps, m4)
rewritePred m0 (ForEach (Lit SizeR sz) (Var v) tar ps) = do
  let (sumstoPred, otherPred) = List.partition (extendableSumsTo tar) ps
  count <- genFromSize sz
  let ((m1, subb), ps3) = List.foldl' freshPats ((m0, []), []) (take count (repeat (tar, otherPred)))
      (xs, m2) = freshVars2 m1 count v
      renamedPred = map snd ps3
  (expandedPred, m3) <- removeExpandablePred ([], m2) (concat renamedPred)
  pure $
    ( expandedPred
        ++ zipWith Component (map Right xs) (map (patToAnyF . fst) ps3)
        ++ [List (Var v) xs]
        ++ extendSums subb sumstoPred
    , m3
    )
rewritePred _ (ForEach sz t tar ps) =
  error ("Not a valid ForEach predicate " ++ show (ForEach sz t tar ps))
rewritePred m0 (Maybe (Var v) (target :: (RootTarget era r t)) preds) = do
  count <- chooseInt (0, 1) -- 0 is Nothing, 1 is Just
  if count == 0
    then pure ([Var v :<-: (Constr "(const Nothing)" (const Nothing) ^$ (Lit UnitR ()))], m0)
    else do
      let (m1, subs) = fresh (m0, []) target
          subst = itemsToSubst subs
          target2 = substTarget subst target
          renamedPred = map (substPred subst) preds
      (expandedPred, m2) <- removeExpandablePred ([], m1) renamedPred
      pure (expandedPred ++ [Var v :<-: (Invert "Just" (typeRep @r) Just :$ target2)], m2)
rewritePred m0 p = pure ([p], m0)

removeExpandablePred :: Era era => ([Pred era], Int) -> [Pred era] -> Gen ([Pred era], Int)
removeExpandablePred (ps, m) [] = pure (List.nubBy cpeq (reverse ps), m)
removeExpandablePred (ps, m) (p : more) = do
  (ps2, m1) <- rewritePred m p
  removeExpandablePred (ps2 ++ ps, m1) more

removeMetaSize :: Era era => [Pred era] -> [Pred era] -> Gen [Pred era]
removeMetaSize [] ans = pure $ reverse ans
removeMetaSize ((MetaSize sz t@(Var v)) : more) ans = do
  n <- genFromSize sz
  let sub = substPred (singleSubst v (Lit SizeR (SzExact n)))
  removeMetaSize (map sub more) ((t :<-: Simple (Lit SizeR (SzExact n))) : (map sub ans))
removeMetaSize (m : more) ans = removeMetaSize more (m : ans)

rewriteGen :: Era era => (Int, [Pred era]) -> Gen (Int, [Pred era])
rewriteGen (m, cs0) = do
  cs1 <- removeMetaSize cs0 []
  (cs2, m1) <- removeExpandablePred ([], m) cs1
  pure (m1, removeTrivial $ removeSameVar (removeEqual cs2 []) [])

notBefore :: Pred era -> Bool
notBefore (Before _ _) = False
notBefore _ = True

-- | Construct the DependGraph
compileGenWithSubst :: Era era => OrderInfo -> Subst era -> [Pred era] -> Gen (Int, DependGraph era)
compileGenWithSubst info subst0 cs = do
  (m, simple) <- rewriteGen (0, cs)
  let instanSimple = fmap (substPredWithVarTest subst0) simple
  graph <- monadTyped $ do
    orderedNames <- initialOrder info instanSimple
    mkDependGraph (length orderedNames) [] HashSet.empty orderedNames [] (filter notBefore instanSimple)
  pure (m, graph)

-- ==============================================================
-- Build a Dependency Graph that extracts an ordering on the
-- variables in the [Pred] we are trying to solve. The idea is that
-- solving for for a [Pred] will be easier if it contains only
-- one variable, and all other Terms are constants (Fixed (Lit rep x))

-- | An Ordering
newtype DependGraph era = DependGraph [([Name era], [Pred era])]

instance Era era => Show (DependGraph era) where
  show (DependGraph xs) = unlines (map f xs)
    where
      f (nm, cs) = pad n (showL shName " " nm) ++ " | " ++ showL show ", " cs
      n = maximum (map (length . (showL shName " ") . fst) xs) + 2
      shName :: Name era -> String
      shName (Name (V v _ _)) = v

-- =========================================================
-- Sketch of algorithm for creating a DependGraph
--
-- for every pair (name,[cond]) the variables of [cond] only contain name, and names
-- defined in previous pairs in the DependGraph. Can we find such an order?
-- To compute this from a [Pred era] we implement this algorithm
-- try prev choices constraints =
--   (c,more) <- pick choices
--   possible <- filter (only mentions (c:prev)) constraints
--   if null possible
--      then try prev (more ++ [(c,possible)]) constraints
--      else possible ++ try (c:prev) more (constraints - possible)
--
-- ===================================================================
-- Find an order to solve the variables in

-- | Three possible cases
-- 1) Many predicates that define the same Name
-- 2) One predicate that defines many Names
-- 3) Some other bad combination
splitMultiName ::
  Era era =>
  Name era ->
  [([Name era], Pred era)] ->
  ([Pred era], Maybe ([Name era], Pred era), [String]) ->
  ([Pred era], Maybe ([Name era], Pred era), [String])
splitMultiName _ [] (unary, nary, bad) = (unary, nary, bad)
splitMultiName n@(Name vn) (([m@(Name vm)], p) : more) (unary, nary, bad) =
  if n == m
    then splitMultiName n more (p : unary, nary, bad)
    else
      splitMultiName
        n
        more
        ( unary
        , nary
        , ( "A unary MultiName "
              ++ show vm
              ++ " does not match the search name "
              ++ show vn
              ++ " "
              ++ show p
          )
            : bad
        )
splitMultiName n ((ms, p) : more) (unary, Nothing, bad) =
  if elem n ms
    then splitMultiName n more (unary, Just (ms, p), bad)
    else
      splitMultiName
        n
        more
        ( unary
        , Nothing
        , ("A set of nary Multinames " ++ show ms ++ " does not contain the search name " ++ show n) : bad
        )
splitMultiName n ((ms, p) : more) (unary, Just first, bad) =
  splitMultiName
    n
    more
    (unary, Just first, ("More than one Multiname: " ++ show first ++ " and " ++ show (ms, p)) : bad)

mkDependGraph ::
  forall era.
  Era era =>
  Int ->
  [([Name era], [Pred era])] ->
  HashSet (Name era) ->
  [Name era] ->
  [Name era] ->
  [Pred era] ->
  Typed (DependGraph era)
mkDependGraph _ prev _ _ _ [] = pure (DependGraph (reverse prev))
mkDependGraph count prev _ choices badchoices specs
  | count <= 0 =
      failT
        [ "\nFailed to find an Ordering of variables to solve for.\nHandled Constraints\n"
        , show (DependGraph (reverse prev))
        , "\n  vars to be processed"
        , show choices
        , "\n  vars bad "
        , show badchoices
        , "\n  Still to be processed\n"
        , unlines (map show specs)
        ]
mkDependGraph count prev prevNames [] badchoices cs = mkDependGraph (count - 1) prev prevNames (reverse badchoices) [] cs
mkDependGraph count prev prevNames (n : more) badchoices cs =
  case partitionE okE cs of
    ([], _) -> mkDependGraph count prev prevNames more (n : badchoices) cs
    (possible, notPossible) -> case splitMultiName n possible ([], Nothing, []) of
      (ps, Nothing, []) ->
        mkDependGraph
          count
          (([n], ps) : prev)
          (HashSet.insert n prevNames)
          (reverse badchoices ++ more)
          []
          notPossible
      ([], Just (ns, p), []) ->
        mkDependGraph
          count
          ((ns, [p]) : prev)
          (HashSet.union (HashSet.fromList ns) prevNames)
          (reverse badchoices ++ more)
          []
          notPossible
      (unary, binary, bad) ->
        error
          ( "SOMETHING IS WRONG in partionE \nunary = "
              ++ show unary
              ++ "\nbinary = "
              ++ show binary
              ++ "\nbad = "
              ++ unlines bad
          )
  where
    !defined = HashSet.insert n prevNames
    okE :: Pred era -> Either ([Name era], Pred era) (Pred era)
    okE p@(SumSplit _ t _ ns) =
      let rhsNames = List.foldl' varsOfSum HashSet.empty ns
       in if HashSet.isSubsetOf (varsOfTerm HashSet.empty t) prevNames
            && hashSetDisjoint prevNames rhsNames
            && HashSet.member n rhsNames
            then Left (HashSet.toList rhsNames, p)
            else Right p
    okE constraint =
      if HashSet.isSubsetOf (varsOfPred HashSet.empty constraint) defined
        then Left ([n], constraint)
        else Right constraint

partitionE :: (a -> Either b a) -> [a] -> ([b], [a])
partitionE _ [] = ([], [])
partitionE f (x : xs) = case (f x, partitionE f xs) of
  (Left b, (bs, as)) -> (b : bs, as)
  (Right a, (bs, as)) -> (bs, a : as)

_firstE :: (a -> Either b a) -> [a] -> (Maybe b, [a])
_firstE _ [] = (Nothing, [])
_firstE f (x : xs) = case f x of
  Left b -> (Just b, xs)
  Right a -> case _firstE f xs of
    (Nothing, as) -> (Nothing, a : as)
    (Just b, as) -> (Just b, a : as)

-- ============================================================
-- Create a Graph from which we can extract a DependGraph

-- | Add to the dependency map 'answer' constraints such that every Name in 'before'
--   preceeds every Name in 'after' in the order in which Names are solved for.
mkDeps ::
  HashSet (Name era) ->
  HashSet (Name era) ->
  Map (Name era) (HashSet (Name era)) ->
  Map (Name era) (HashSet (Name era))
mkDeps before after answer = HashSet.foldl' accum answer after
  where
    accum ans left = Map.insertWith (HashSet.union) left before ans

data OrderInfo = OrderInfo
  { sumBeforeParts :: Bool
  , sizeBeforeArg :: Bool
  , setBeforeSubset :: Bool
  }
  deriving (Show, Eq)

standardOrderInfo :: OrderInfo
standardOrderInfo =
  OrderInfo
    { sumBeforeParts = False
    , sizeBeforeArg = True
    , setBeforeSubset = True
    }

accumdep ::
  Era era =>
  OrderInfo ->
  Map (Name era) (HashSet (Name era)) ->
  Pred era ->
  Map (Name era) (HashSet (Name era))
accumdep info answer c = case c of
  sub :⊆: set ->
    if setBeforeSubset info
      then mkDeps (vars set) (vars sub) answer
      else mkDeps (vars sub) (vars set) answer
  lhs :=: rhs -> mkDeps (vars lhs) (vars rhs) answer
  Disjoint left right -> mkDeps (vars left) (vars right) answer
  Sized size argx ->
    if sizeBeforeArg info
      then mkDeps (vars size) (vars argx) answer
      else mkDeps (vars argx) (vars size) answer
  SumsTo (Left _) sm _ parts -> mkDeps (vars sm) (List.foldl' varsOfSum HashSet.empty parts) answer
  SumsTo (Right _) sm _ parts -> mkDeps (List.foldl' varsOfSum HashSet.empty parts) (vars sm) answer
  SumSplit _ sm _ parts -> mkDeps (vars sm) (List.foldl' varsOfSum HashSet.empty parts) answer
  Component (Right t) cs -> mkDeps (componentVars cs) (vars t) answer
  Component (Left t) cs -> mkDeps (vars t) (componentVars cs) answer
  Member (Left t) cs -> mkDeps (vars t) (vars cs) answer
  Member (Right t) cs -> mkDeps (vars cs) (vars t) answer
  NotMember t cs -> mkDeps (vars t) (vars cs) answer
  MapMember k v (Left m) -> mkDeps (vars v) (vars k) (mkDeps (vars k) (vars m) answer)
  MapMember k v (Right m) -> mkDeps (vars m) (vars k) (mkDeps (vars k) (vars v) answer)
  t :<-: ts -> mkDeps (varsOfTarget HashSet.empty ts) (vars t) answer
  GenFrom t ts -> mkDeps (varsOfTarget HashSet.empty ts) (vars t) answer
  List t cs -> mkDeps (List.foldl' varsOfTerm HashSet.empty cs) (vars t) answer
  Maybe t target ps -> mkDeps (vars t) (varsOfPairs HashSet.empty [(target, ps)]) answer
  ForEach sz x pat ps ->
    mkDeps
      (vars sz)
      (vars x)
      (mkDeps (vars x) (varsOfPats HashSet.empty [(pat, ps)]) answer)
  ListWhere sz x tar ps ->
    mkDeps
      (vars sz)
      (vars x)
      (mkDeps (vars x) (varsOfPairs HashSet.empty [(tar, ps)]) answer)
  Choose sz x xs ->
    mkDeps (vars sz) (vars x) (mkDeps (vars x) (varsOfTrips HashSet.empty xs) answer)
  SubMap left right -> mkDeps (vars left) (vars right) answer
  If t x y ->
    ( mkDeps
        (varsOfTarget HashSet.empty t)
        (varsOfPred HashSet.empty x)
        (mkDeps (varsOfTarget HashSet.empty t) (varsOfPred HashSet.empty y) answer)
    )
  Before x y -> mkDeps (vars x) (vars y) answer
  other -> HashSet.foldl' accum answer (varsOfPred HashSet.empty other)
    where
      accum ans v = Map.insertWith (HashSet.union) v HashSet.empty ans

componentVars :: [AnyF era s] -> HashSet (Name era)
componentVars [] = HashSet.empty
componentVars (AnyF (Field n r a l) : cs) = HashSet.insert (Name $ V n r (Yes a l)) $ componentVars cs
componentVars (AnyF (FConst _ _ _ _) : cs) = componentVars cs

-- =========================================================================
-- Create an initial Ordering. Build a Graph, then extract the Ordering

initialOrder :: forall era. Era era => OrderInfo -> [Pred era] -> Typed [Name era]
initialOrder info cs0 = do
  mmm <- flatOrError (stronglyConnComp listDep)
  pure $ map getname mmm
  where
    allvs = List.foldl' varsOfPred HashSet.empty cs0
    noDepMap = HashSet.foldl' (\ans n -> Map.insert n HashSet.empty ans) Map.empty allvs
    mapDep = List.foldl' (accumdep info) noDepMap cs0
    listDep = zipWith (\(x, m) n -> (n, x, HashSet.toList m)) (Map.toList mapDep) [0 ..]
    (_graph1, nodeFun, _keyf) = graphFromEdges listDep
    getname :: Vertex -> Name era
    getname x = n where (_node, n, _children) = nodeFun x
    flatOrError [] = pure []
    flatOrError (AcyclicSCC x : more) = (x :) <$> flatOrError more
    flatOrError (CyclicSCC xs : _) = failT [message, show info, unlines (map (("  " ++) . show) usesNames)]
      where
        names = map getname xs
        namesSet = Set.fromList names
        usesNames =
          [pr | pr <- cs0, any (`Set.member` namesSet) (varsOfPred HashSet.empty pr)]
        theCycle = case names of
          [] -> map show names
          (x : _) -> map show (names ++ [x])
        message = "Cycle in dependencies: " ++ List.intercalate " <= " theCycle

-- | Construct the DependGraph
compile :: Era era => OrderInfo -> [Pred era] -> Typed (DependGraph era)
compile info cs = do
  let simple = rewrite cs
  orderedNames <- initialOrder info simple
  mkDependGraph (length orderedNames) [] HashSet.empty orderedNames [] (filter notBefore simple)

showGraph :: (Vertex -> String) -> Graph -> String
showGraph nameof g = unlines (map show (zip names (toList zs)))
  where
    (lo, hi) = A.bounds g
    names = map nameof [lo .. hi]
    zs = fmap (map nameof) g
