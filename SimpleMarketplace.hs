-- ############################
-- Project          : CNFT
-- Smart Contract   : Simple Marketplace Contract
-- Author           : Cherrybyte Technologies
-- Purpose          : Buy and Sell NFTs on Cardano Blockchain
-- ############################


-- Declarations
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE EmptyDataDecls #-}
{-# LANGUAGE NoImplicitPrelude  #-}
{-# LANGUAGE TemplateHaskell    #-}
{-# OPTIONS_GHC -fno-ignore-interface-pragmas #-}
{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE FlexibleContexts  #-}
{-# LANGUAGE NumericUnderscores#-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TupleSections #-}
{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE AllowAmbiguousTypes #-}
module Plutus.Contracts.V2.SimpleMarketplace(
  simpleMarketplacePlutusV2,
  simpleMarketplaceScript,
  MarketRedeemer(..),
  SimpleSale(..)
)
where
--  importing necessary utilities

import GHC.Generics (Generic)
import PlutusTx.Prelude
import Prelude(Show)
import qualified Prelude
import  PlutusTx hiding( txOutDatum)
import Data.Aeson (FromJSON, ToJSON)
import qualified PlutusTx.AssocMap as AssocMap
import qualified Data.Bifunctor
import Plutus.V2.Ledger.Api
import Plutus.V2.Ledger.Contexts (valuePaidTo, ownHash, valueLockedBy, findOwnInput, findDatum,txSignedBy)
import qualified Data.ByteString.Short as SBS
import qualified Data.ByteString.Lazy  as LBS
import Cardano.Api.Shelley (PlutusScript (..), PlutusScriptV2)
import Codec.Serialise ( serialise )
import Plutus.V1.Ledger.Value (assetClassValueOf, AssetClass (AssetClass))


-- Method to calculate number of UTXOs given as input to the call to the smart contract

{-# INLINABLE allScriptInputsCount #-}
allScriptInputsCount:: ScriptContext ->Integer
allScriptInputsCount ctx@(ScriptContext info purpose)=
    foldl (\c txOutTx-> c + countTxOut txOutTx) 0 (txInfoInputs  info)
  where
  countTxOut (TxInInfo _ (TxOut addr _ _ _)) = case addr of { Address cre m_sc -> case cre of
                                                              PubKeyCredential pkh -> 0
                                                              ScriptCredential vh -> 1  } 

--  A Simple Indexed Struct to hold `Buy` or `Withdraw` data
data MarketRedeemer =  Buy | Withdraw
    deriving (Generic,FromJSON,ToJSON,Show,Prelude.Eq)
PlutusTx.makeIsDataIndexed ''MarketRedeemer [('Buy, 0), ('Withdraw,1)]

--  Struct for Simple Sale object
data SimpleSale=SimpleSale{
    sellerAddress:: Address, -- The person who has listed the NFT on the CNFT marketplace
    priceOfAsset:: Integer  -- How much ada the seller is willing to sell on
  } deriving(Show,Generic)

PlutusTx.makeIsDataIndexed ''SimpleSale [('SimpleSale, 0)]    

{-# INLINABLE mkMarket #-}
mkMarket ::  SimpleSale   -> MarketRedeemer -> ScriptContext    -> Bool
mkMarket  ds@SimpleSale{sellerAddress,priceOfAsset}  action ctx =
  case sellerPkh of 
    Nothing -> traceError "Script Address in seller"
    Just pkh -> case  action of
        Buy       -> traceIfFalse "Multiple script inputs" (allScriptInputsCount  ctx == 1)  && 
                     traceIfFalse "Seller not paid" (assetClassValueOf   (valuePaidTo info pkh) adaAsset >= priceOfAsset)
        Withdraw -> traceIfFalse "Seller Signature Missing" $ txSignedBy info pkh

    where
      sellerPkh= case sellerAddress of { Address cre m_sc -> case cre of
                                                           PubKeyCredential pkh -> Just pkh
                                                           ScriptCredential vh -> Nothing  }
      info  =  scriptContextTxInfo ctx
      adaAsset=AssetClass (adaSymbol,adaToken )

{-# INLINABLE mkWrappedMarket #-}
mkWrappedMarket ::  BuiltinData -> BuiltinData -> BuiltinData -> ()
mkWrappedMarket  d r c = check $ mkMarket (parseData d "Invalid data") (parseData r "Invalid redeemer") (parseData c "Invalid context")
  where
    parseData md s = case fromBuiltinData  md of 
      Just datum -> datum
      _      -> traceError s


simpleMarketValidator ::   Validator
simpleMarketValidator = mkValidatorScript  $
            $$(PlutusTx.compile [|| mkWrappedMarket ||])

simpleMarketplaceScript ::   Script
simpleMarketplaceScript  =  unValidatorScript  simpleMarketValidator

marketScriptSBS :: SBS.ShortByteString
marketScriptSBS  =  SBS.toShort . LBS.toStrict $ serialise $ simpleMarketplaceScript 
--  seriliazing our script

simpleMarketplacePlutusV2 ::  PlutusScript PlutusScriptV2
simpleMarketplacePlutusV2  = PlutusScriptSerialised $ marketScriptSBS
