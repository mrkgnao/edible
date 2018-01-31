{-# LANGUAGE DeriveAnyClass            #-}
{-# LANGUAGE DeriveFoldable            #-}
{-# LANGUAGE DeriveFunctor             #-}
{-# LANGUAGE DeriveGeneric             #-}
{-# LANGUAGE DeriveTraversable         #-}
{-# LANGUAGE ExistentialQuantification #-}
{-# LANGUAGE FlexibleContexts          #-}
{-# LANGUAGE FlexibleInstances         #-}
{-# LANGUAGE GADTs                     #-}
{-# LANGUAGE InstanceSigs              #-}
{-# LANGUAGE KindSignatures            #-}
{-# LANGUAGE LambdaCase                #-}
{-# LANGUAGE MultiParamTypeClasses     #-}
{-# LANGUAGE RankNTypes                #-}
{-# LANGUAGE ScopedTypeVariables       #-}
{-# LANGUAGE TemplateHaskell           #-}
{-# LANGUAGE TypeOperators             #-}
{-# LANGUAGE TypeSynonymInstances      #-}

module Types where

import           Edible.Prelude
import           Unbound.Generics.LocallyNameless
import           Unbound.Generics.LocallyNameless.Internal.Fold (toListOf)
import           Control.Monad.Trans

data DepQ = MatPi | UnMatPi
  deriving (Show, Generic, Alpha, Eq, Subst a)

data Rel = Rel | Irrel
  deriving (Show, Generic, Alpha, Eq, Subst a)

type TmVar = Name Tm
type CoVar = Name Co

type Kd = Tm
type Ty = Tm

data HetEq = HetEq Ty Kd Kd Ty
  deriving (Show, Generic, Alpha, Subst Tm, Subst Co)

data PrimTy = TyInt | TyBool | TyChar
  deriving (Show, Generic, Alpha, Subst Co, Subst Tm)

data PrimExp = ExpInt Int | ExpBool Bool | ExpChar Char
  deriving (Show, Generic, Alpha, Subst Co, Subst Tm)

data PrimBinop = OpIntAdd | OpIntMul
  deriving (Show, Generic, Alpha, Subst Co, Subst Tm)

data TmArg = TmArgTm Tm | TmArgCo Co
  deriving (Show, Generic, Alpha, Subst Co, Subst Tm)

data CoArg = CoArgTm Tm | CoArgCo Co | CoArgCoPair Co Co
  deriving (Show, Generic, Alpha, Subst Co, Subst Tm)

data Bdr = BdrTm TmVar (Embed Rel) (Embed Kd) | BdrCo CoVar (Embed HetEq)
  deriving (Show, Generic, Alpha, Subst Co, Subst Tm)

type Tele = [Bdr]

data Tm
  = TmVar TmVar
  | TmApp Tm TmArg
  | TmPi DepQ (Bind Bdr Tm)
  | TmLam (Bind Bdr Tm)
  | TmConst Konst [Tm]
  | TmCast Tm Co
  | TmCase Tm Kd [TmAlt]
  | TmFix Tm
  | TmAbsurd Co Tm
  | TmPrimTy PrimTy
  | TmPrimExp PrimExp
  | TmPrimBinop PrimBinop Tm Tm
  deriving (Show, Generic, Alpha, Subst Co)

data TmAlt = TmAlt { _tmAltPat :: Pat, _tmAltBody :: Tm }
  deriving (Show, Generic, Alpha, Subst Tm, Subst Co)

data Pat = PatWild | PatCon Konst
  deriving (Eq, Show, Generic, Alpha, Subst Tm, Subst Co)

data CoAlt = CoAlt { _coAltPat :: Pat, _coAltBody :: Co }
  deriving (Show, Generic, Alpha, Subst Tm, Subst Co)

type Eta = Co

data Co
  = CoVar CoVar
  | CoRefl Tm
  | CoSym Co
  | CoTrans Co Co
  | CoConst Konst [Co]
  | CoApp Co CoArg
  | CoPi Rel Eta (Bind TmVar Co)
  | CoCPi Eta Eta (Bind CoVar Co)
  | CoCase Eta Co [CoAlt]
  | CoFix Co
  | CoLam Rel Eta (Bind TmVar Co)
  | CoCApp Eta Eta (Bind CoVar Co)
  | CoAbsurd Eta Eta Co
  | CoCoh Tm Co Tm
  | CoArgk Co
  | CoArgkN Int Co
  | CoRes Int Co
  | CoIrrelApp Co CoArg
  | CoNth Int Co
  | CoLeft Eta Co
  | CoRight Eta Co
  | CoKind Co
  | CoStep Tm
  deriving (Show, Generic, Alpha, Subst Tm)

data Konst = KTyCon String | KDtCon String | KType
  deriving (Eq, Generic, Alpha, Subst Tm, Subst Co)

instance Show Konst where
  show = \case
    KTyCon s -> s
    KDtCon s -> "_" ++ s
    KType -> "Type"

instance Subst Tm Tm where
  isvar (TmVar v) = Just (SubstName v)
  isvar _         = Nothing

instance Subst Co Co where
  isvar (CoVar v) = Just (SubstName v)
  isvar _         = Nothing

_TmAppTm :: Prism' Tm (Tm, Tm)
_TmAppTm = prism (\(f, x) -> TmApp f (TmArgTm x)) $ \case
  TmApp f (TmArgTm x) -> Right (f, x)
  x                   -> Left x

_TmAppCo :: Prism' Tm (Tm, Co)
_TmAppCo = prism (\(f, x) -> TmApp f (TmArgCo x)) $ \case
  TmApp f (TmArgCo x) -> Right (f, x)
  x                   -> Left x

_TmLamCo :: Prism' Tm (HetEq, Bind CoVar Tm)
_TmLamCo = prism fw bw
 where
  fw (h, bd) = runFreshM $ do
    (v, b) <- unbind bd
    pure (TmLam (bind (BdrCo v (Embed h)) b))
  bw t = case t of
    TmLam bd -> runFreshM $ do
      (vv, b) <- unbind bd
      case vv of
        BdrCo v (Embed h) -> pure (Right (h, bind v b))
        _                 -> pure (Left t)
    _ -> Left t

_TmLamTm :: Rel -> Prism' Tm (Kd, Bind TmVar Tm)
_TmLamTm rel = prism fw bw
 where
  fw (kd, bd) = runFreshM $ do
    (v, b) <- unbind bd
    pure (TmLam (bind (BdrTm v (Embed rel) (Embed kd)) b))
  bw t = case t of
    TmLam bd -> runFreshM $ do
      (vv, b) <- unbind bd
      case vv of
        BdrTm v (Embed rel') (Embed kd) | rel == rel' -> pure
          (Right (kd, bind v b))
        _ -> pure (Left t)
    _ -> Left t

_TmRelLam :: Prism' Tm (Kd, Bind TmVar Tm)
_TmRelLam = _TmLamTm Rel

_TmIrrelLam :: Prism' Tm (Kd, Bind TmVar Tm)
_TmIrrelLam = _TmLamTm Irrel

data StepEnv = StepEnv { _stepContext :: Tele , _stepRecursionDepth :: Int}

-- makePrisms ''DepQ
-- makePrisms ''Rel
makePrisms ''Tm
makePrisms ''Co
makePrisms ''TmArg
makePrisms ''CoArg
makePrisms ''Bdr
makeLenses ''TmAlt
makeLenses ''CoAlt
-- makePrisms ''Pat
makePrisms ''PrimTy
makePrisms ''PrimExp
makePrisms ''PrimBinop

makeLenses ''StepEnv

------------------------------------------------------------
-- Useful prisms
------------------------------------------------------------

_TmExpInt :: Prism' Tm Int
_TmExpInt = _TmPrimExp . _ExpInt

_TmValue :: Prism' Tm Tm
_TmValue = prism id $ \tm -> if runFreshM (go tm) then Right tm else Left tm
 where
  go :: Tm -> FreshM Bool
  go x = case x of
    -- TODO add H case
    TmPi{} -> pure True
    -- TmLam (BdrTm Rel   _ _   ) -> pure True
    -- TmLam (BdrTm Irrel _ body) -> do
    --   (_, b) <- unbind body
    --   go b
    -- TmLam BdrCo{} -> pure True
    _      -> pure False

_TmApps :: Iso' Tm (Tm, [TmArg])
_TmApps = iso bw (uncurry fw)
 where
  fw :: Tm -> [TmArg] -> Tm
  fw = foldl' (curry (review _TmApp))

  bw :: Tm -> (Tm, [TmArg])
  bw = \case
    TmApp t arg@TmArgCo{} -> (t, [arg])
    TmApp t arg@TmArgTm{} -> bw t & _2 %~ (|> arg)
    tm                    -> (tm, [])

------------------------------------------------------------
-- Smart constructors
------------------------------------------------------------

tmExpInt :: Int -> Tm
tmExpInt = review _TmExpInt
