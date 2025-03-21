{-# LANGUAGE DataKinds #-}

-- |
-- Module      : Test.Cardano.Ledger.Mary.Examples.Cast
-- Description : Cast of characters for Mary ledger examples
--
-- The cast of Characters for Mary Ledger Examples
module Test.Cardano.Ledger.Mary.Examples.Cast (
  alicePay,
  aliceStake,
  aliceAddr,
  bobPay,
  bobStake,
  bobAddr,
  carlPay,
  carlStake,
  carlAddr,
  dariaPay,
  dariaStake,
  dariaAddr,
) where

import Cardano.Ledger.Address (Addr (..))
import Cardano.Ledger.Keys (KeyRole (..))
import Test.Cardano.Ledger.Core.KeyPair (KeyPair (..), mkAddr)
import Test.Cardano.Ledger.Shelley.Utils (RawSeed (..), mkKeyPair)

-- | Alice's payment key pair
alicePay :: KeyPair 'Payment
alicePay = KeyPair vk sk
  where
    (sk, vk) = mkKeyPair (RawSeed 0 0 0 0 0)

-- | Alice's stake key pair
aliceStake :: KeyPair 'Staking
aliceStake = KeyPair vk sk
  where
    (sk, vk) = mkKeyPair (RawSeed 1 1 1 1 1)

-- | Alice's base address
aliceAddr :: Addr
aliceAddr = mkAddr alicePay aliceStake

-- | Bob's payment key pair
bobPay :: KeyPair 'Payment
bobPay = KeyPair vk sk
  where
    (sk, vk) = mkKeyPair (RawSeed 2 2 2 2 2)

-- | Bob's stake key pair
bobStake :: KeyPair 'Staking
bobStake = KeyPair vk sk
  where
    (sk, vk) = mkKeyPair (RawSeed 3 3 3 3 3)

-- | Bob's address
bobAddr :: Addr
bobAddr = mkAddr bobPay bobStake

-- Carl's payment key pair
carlPay :: KeyPair 'Payment
carlPay = KeyPair vk sk
  where
    (sk, vk) = mkKeyPair (RawSeed 4 4 4 4 4)

-- | Carl's stake key pair
carlStake :: KeyPair 'Staking
carlStake = KeyPair vk sk
  where
    (sk, vk) = mkKeyPair (RawSeed 5 5 5 5 5)

-- | Carl's address
carlAddr :: Addr
carlAddr = mkAddr carlPay carlStake

-- | Daria's payment key pair
dariaPay :: KeyPair 'Payment
dariaPay = KeyPair vk sk
  where
    (sk, vk) = mkKeyPair (RawSeed 6 6 6 6 6)

-- | Daria's stake key pair
dariaStake :: KeyPair 'Staking
dariaStake = KeyPair vk sk
  where
    (sk, vk) = mkKeyPair (RawSeed 7 7 7 7 7)

-- | Daria's address
dariaAddr :: Addr
dariaAddr = mkAddr dariaPay dariaStake
