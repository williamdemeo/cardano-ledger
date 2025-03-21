{-# LANGUAGE EmptyCase #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE FunctionalDependencies #-}
{-# LANGUAGE ImportQualifiedPost #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE StandaloneDeriving #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE UndecidableInstances #-}
{-# OPTIONS_GHC -fno-warn-orphans #-}

-- | This module provides some necessary instances
-- of `Functions` that aren't needed in `Constrained.Base`
-- (which is already big enough) but which are necessary
-- to use the framework.
module Constrained.Instances where

import Data.Typeable

import Constrained.Base
import Constrained.Core
import Constrained.List
import Constrained.Spec.Generics ()
import Constrained.Univ

instance
  ( Typeable fn
  , Functions (fn (Fix fn)) (Fix fn)
  ) =>
  Functions (Fix fn) (Fix fn)
  where
  propagateSpecFun (Fix fn) ctx spec = propagateSpecFun fn ctx spec
  rewriteRules (Fix fn) = rewriteRules fn
  mapTypeSpec (Fix fn) = mapTypeSpec fn

instance
  ( Typeable fn
  , Typeable fn'
  , Typeable fnU
  , Functions (fn fnU) fnU
  , Functions (fn' fnU) fnU
  ) =>
  Functions (Oneof fn fn' fnU) fnU
  where
  propagateSpecFun (OneofLeft fn) = propagateSpecFun fn
  propagateSpecFun (OneofRight fn) = propagateSpecFun fn

  rewriteRules (OneofLeft fn) = rewriteRules fn
  rewriteRules (OneofRight fn) = rewriteRules fn

  mapTypeSpec (OneofLeft fn) = mapTypeSpec fn
  mapTypeSpec (OneofRight fn) = mapTypeSpec fn

instance BaseUniverse fn => Functions (EqFn fn) fn where
  propagateSpecFun _ _ (ErrorSpec err) = ErrorSpec err
  propagateSpecFun fn (ListCtx pre HOLE suf) (SuspendedSpec v ps) =
    constrained $ \v' ->
      let args = appendList (mapList (\(Value a) -> Lit a) pre) (v' :> mapList (\(Value a) -> Lit a) suf)
       in Let (App (injectFn fn) args) (v :-> ps)
  propagateSpecFun Equal ctx spec
    | HOLE :? Value a :> Nil <- ctx =
        propagateSpecFun @(EqFn fn) @fn Equal (Value a :! NilCtx HOLE) spec
    | Value a :! NilCtx HOLE <- ctx = caseBoolSpec spec $ \case
        True -> equalSpec a
        False -> notEqualSpec a

  rewriteRules Equal (t :> t' :> Nil)
    | t == t' = Just $ lit True
    | otherwise = Nothing

  mapTypeSpec f _ = case f of {}

instance BaseUniverse fn => Functions (BoolFn fn) fn where
  propagateSpecFun _ _ (ErrorSpec err) = ErrorSpec err
  propagateSpecFun fn (ListCtx pre HOLE suf) (SuspendedSpec v ps) =
    constrained $ \v' ->
      let args = appendList (mapList (\(Value a) -> Lit a) pre) (v' :> mapList (\(Value a) -> Lit a) suf)
       in Let (App (injectFn fn) args) (v :-> ps)
  propagateSpecFun Not (NilCtx HOLE) spec = caseBoolSpec spec (equalSpec . not)
  propagateSpecFun Or (HOLE :? Value (s :: Bool) :> Nil) spec = caseBoolSpec spec (okOr s)
  propagateSpecFun Or (Value (s :: Bool) :! NilCtx HOLE) spec = caseBoolSpec spec (okOr s)

  mapTypeSpec Not (SumSpec h a b) = typeSpec $ SumSpec h b a

-- | We have something like ('constant' ||. HOLE) must evaluate to 'need'. Return a (Specification fn Bool) for HOLE, that makes that True.
okOr :: Bool -> Bool -> Specification fn Bool
okOr constant need = case (constant, need) of
  (True, True) -> TrueSpec
  (True, False) ->
    ErrorSpec
      (pure ("(" ++ show constant ++ "||. HOLE) must equal False. That cannot be the case."))
  (False, False) -> MemberSpec (pure False)
  (False, True) -> MemberSpec (pure True)
