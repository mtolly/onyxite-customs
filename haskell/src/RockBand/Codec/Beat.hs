{-# LANGUAGE DeriveGeneric      #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE DerivingVia        #-}
{-# LANGUAGE LambdaCase         #-}
{-# LANGUAGE RecordWildCards    #-}
module RockBand.Codec.Beat where

import           Control.Monad.Codec
import qualified Data.EventList.Relative.TimeBody as RTB
import           DeriveHelpers
import           GHC.Generics                     (Generic)
import           RockBand.Codec
import           RockBand.Common
import qualified Sound.MIDI.Util                  as U

data BeatEvent = Bar | Beat
  deriving (Eq, Ord, Show, Enum, Bounded)

newtype BeatTrack t = BeatTrack { beatLines :: RTB.T t BeatEvent }
  deriving (Eq, Ord, Show, Generic)
  deriving (Semigroup, Monoid, Mergeable) via GenericMerge (BeatTrack t)

instance ChopTrack BeatTrack where
  chopTake t = mapTrack $ U.trackTake t
  chopDrop t = mapTrack $ U.trackDrop t

instance ParseTrack BeatTrack where
  parseTrack = do
    beatLines <- (beatLines =.) $ statusBlips $ condenseMap_ $ eachKey each $ blip . \case
      Bar  -> 12
      Beat -> 13
    return BeatTrack{..}

instance TraverseTrack BeatTrack where
  traverseTrack fn (BeatTrack a) = BeatTrack <$> fn a
