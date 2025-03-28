{-# LANGUAGE DataKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeApplications #-}

module Test.Cardano.Ledger.Babbage.Serialisation.Tripping where

import Cardano.Ledger.Babbage (BabbageEra)
import Cardano.Ledger.Babbage.Rules (BabbageUtxoPredFailure)
import Cardano.Ledger.Block (Block)
import Cardano.Ledger.Core
import Cardano.Protocol.Crypto (StandardCrypto)
import Cardano.Protocol.TPraos.BHeader (BHeader)
import Test.Cardano.Ledger.Babbage.Arbitrary ()
import Test.Cardano.Ledger.Babbage.Serialisation.Generators ()
import Test.Cardano.Ledger.Binary.RoundTrip
import Test.Cardano.Ledger.ShelleyMA.Serialisation.Generators ()
import Test.Tasty
import Test.Tasty.QuickCheck

tests :: TestTree
tests =
  testGroup
    "Babbage CBOR round-trip"
    [ testProperty "babbage/BabbageUtxoPredFailure" $
        roundTripCborRangeExpectation @(BabbageUtxoPredFailure BabbageEra)
          (eraProtVerLow @BabbageEra)
          (eraProtVerHigh @BabbageEra)
    , testProperty "babbage/Block (Annotator)" $
        roundTripAnnRangeExpectation @(Block (BHeader StandardCrypto) BabbageEra)
          (eraProtVerLow @BabbageEra)
          (eraProtVerHigh @BabbageEra)
    , testProperty "babbage/Block" $
        roundTripCborRangeExpectation @(Block (BHeader StandardCrypto) BabbageEra)
          (eraProtVerLow @BabbageEra)
          (eraProtVerHigh @BabbageEra)
    ]
