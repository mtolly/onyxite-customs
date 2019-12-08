{-# LANGUAGE DeriveFunctor      #-}
{-# LANGUAGE DeriveGeneric      #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE DerivingVia        #-}
{-# LANGUAGE FlexibleInstances  #-}
{-# LANGUAGE LambdaCase         #-}
{-# LANGUAGE OverloadedStrings  #-}
{-# LANGUAGE RecordWildCards    #-}
module RockBand.Codec.Lipsync where

import           Control.Monad.Codec
import qualified Data.EventList.Relative.TimeBody as RTB
import qualified Data.Text                        as T
import           Data.Word
import           DeriveHelpers
import           GHC.Generics                     (Generic)
import           RockBand.Codec
import           RockBand.Common
import           Text.Read                        (readMaybe)

newtype LipsyncTrack t = LipsyncTrack
  { lipEvents :: RTB.T t (VisemeEvent T.Text)
  } deriving (Eq, Ord, Show, Generic)
    deriving (Semigroup, Monoid, Mergeable) via GenericMerge (LipsyncTrack t)

instance TraverseTrack LipsyncTrack where
  traverseTrack fn (LipsyncTrack a) = LipsyncTrack <$> fn a

instance ParseTrack LipsyncTrack where
  parseTrack = do
    lipEvents <- lipEvents =. command
    return LipsyncTrack{..}

data VisemeEvent a = VisemeEvent
  { visemeKey    :: a
  , visemeWeight :: Word8
  } deriving (Eq, Ord, Show, Functor)

instance Command (VisemeEvent T.Text) where
  toCommand = \case
    [v, w] -> VisemeEvent v <$> readMaybe (T.unpack w)
    _      -> Nothing
  fromCommand (VisemeEvent v w) = [v, T.pack $ show w]

data MagmaViseme
  = Viseme_Blink
  | Viseme_Brow_aggressive
  | Viseme_Brow_down
  | Viseme_Brow_pouty
  | Viseme_Brow_up
  | Viseme_Bump_hi
  | Viseme_Bump_lo
  | Viseme_Cage_hi
  | Viseme_Cage_lo
  | Viseme_Church_hi
  | Viseme_Church_lo
  | Viseme_Earth_hi
  | Viseme_Earth_lo
  | Viseme_Eat_hi
  | Viseme_Eat_lo
  | Viseme_Fave_hi
  | Viseme_Fave_lo
  | Viseme_If_hi
  | Viseme_If_lo
  | Viseme_New_hi
  | Viseme_New_lo
  | Viseme_Oat_hi
  | Viseme_Oat_lo
  | Viseme_Ox_hi
  | Viseme_Ox_lo
  | Viseme_Roar_hi
  | Viseme_Roar_lo
  | Viseme_Size_hi
  | Viseme_Size_lo
  | Viseme_Squint
  | Viseme_Though_hi
  | Viseme_Though_lo
  | Viseme_Told_hi
  | Viseme_Told_lo
  | Viseme_Wet_hi
  | Viseme_Wet_lo
  deriving (Eq, Ord, Show, Read, Enum, Bounded)

data BeatlesViseme
  = Viseme_head_rot_neg_x
  | Viseme_head_rot_neg_y
  | Viseme_head_rot_neg_z
  | Viseme_head_rot_pos_x
  | Viseme_head_rot_pos_y
  | Viseme_head_rot_pos_z
  | Viseme_jaw_fwd
  | Viseme_jaw_left
  | Viseme_jaw_open
  | Viseme_jaw_right
  | Viseme_l_brow_dn
  | Viseme_l_brow_up
  | Viseme_l_cheek_puff
  | Viseme_l_frown
  | Viseme_l_lids
  | Viseme_l_lip_pull
  | Viseme_l_lolid_up
  | Viseme_l_lolip_dn
  | Viseme_l_lolip_roll
  | Viseme_l_lolip_up
  | Viseme_l_mouth_pucker
  | Viseme_l_open_pucker
  | Viseme_l_smile_closed
  | Viseme_l_smile_open
  | Viseme_l_sneer_narrow
  | Viseme_l_squint
  | Viseme_l_uplip_roll
  | Viseme_l_uplip_up
  | Viseme_m_brow_dn
  | Viseme_m_brow_up
  | Viseme_m_lips_close
  | Viseme_r_brow_dn
  | Viseme_r_brow_up
  | Viseme_r_cheek_puff
  | Viseme_r_frown
  | Viseme_r_lids
  | Viseme_r_lip_pull
  | Viseme_r_lolid_up
  | Viseme_r_lolip_dn
  | Viseme_r_lolip_roll
  | Viseme_r_lolip_up
  | Viseme_r_mouth_pucker
  | Viseme_r_open_pucker
  | Viseme_r_smile_closed
  | Viseme_r_smile_open
  | Viseme_r_sneer_narrow
  | Viseme_r_squint
  | Viseme_r_uplip_roll
  | Viseme_r_uplip_up
  | Viseme_tongue_dn
  | Viseme_tongue_out
  | Viseme_tongue_roll
  | Viseme_tongue_up
  deriving (Eq, Ord, Show, Read, Enum, Bounded)
