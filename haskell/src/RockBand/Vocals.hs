{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE PatternSynonyms #-}
{-# LANGUAGE ViewPatterns #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE OverloadedStrings #-}
module RockBand.Vocals where

import qualified Sound.MIDI.File.Event as E
import qualified Sound.MIDI.File.Event.Meta as Meta
import qualified Data.EventList.Relative.TimeBody as RTB
import qualified Numeric.NonNegative.Class as NNC
import RockBand.Common
import RockBand.Parse
import qualified Data.Text as T
import Data.Monoid ((<>))

data Event
  = LyricShift
  | Mood Mood
  | Lyric T.Text
  | Percussion -- ^ playable percussion note
  | PercussionSound -- ^ nonplayable percussion note, only triggers sound sample
  | PercussionAnimation PercussionType Bool
  | Phrase     Bool -- ^ General phrase marker (RB3) or Player 1 phrases (pre-RB3)
  | Phrase2    Bool -- ^ Pre-RB3, used for 2nd player phrases in Tug of War
  | Overdrive  Bool
  | RangeShift Bool
  | Note       Bool Pitch
  deriving (Eq, Ord, Show, Read)

data Pitch
  = Octave36 Key
  | Octave48 Key
  | Octave60 Key
  | Octave72 Key
  | Octave84C
  deriving (Eq, Ord, Show, Read)

pitchToKey :: Pitch -> Key
pitchToKey = \case
  Octave36 k -> k
  Octave48 k -> k
  Octave60 k -> k
  Octave72 k -> k
  Octave84C  -> C

instance Enum Pitch where
  fromEnum (Octave36 k) = fromEnum k
  fromEnum (Octave48 k) = fromEnum k + 12
  fromEnum (Octave60 k) = fromEnum k + 24
  fromEnum (Octave72 k) = fromEnum k + 36
  fromEnum Octave84C    = 48
  toEnum i = case divMod i 12 of
    (0, j) -> Octave36 $ toEnum j
    (1, j) -> Octave48 $ toEnum j
    (2, j) -> Octave60 $ toEnum j
    (3, j) -> Octave72 $ toEnum j
    (4, 0) -> Octave84C
    _      -> error $ "No vocals Pitch for: fromEnum " ++ show i

instance Bounded Pitch where
  minBound = Octave36 minBound
  maxBound = Octave84C

data PercussionType
  = Tambourine
  | Cowbell
  | Clap
  deriving (Eq, Ord, Show, Read, Enum, Bounded)

instance Command (PercussionType, Bool) where
  fromCommand (typ, b) = [T.toLower (T.pack $ show typ) <> if b then "_start" else "_end"]
  toCommand = reverseLookup ((,) <$> each <*> each) fromCommand

instanceMIDIEvent [t| Event |]

  [ edge 0 $ applyB [p| RangeShift |]
  , blip 1 [p| LyricShift |]

  , edgeRange [36..47] $ \_i _b -> [p| Note $(boolP _b) (Octave36 $(keyP $ _i - 36)) |]
  , edgeRange [48..59] $ \_i _b -> [p| Note $(boolP _b) (Octave48 $(keyP $ _i - 48)) |]
  , edgeRange [60..71] $ \_i _b -> [p| Note $(boolP _b) (Octave60 $(keyP $ _i - 60)) |]
  , edgeRange [72..83] $ \_i _b -> [p| Note $(boolP _b) (Octave72 $(keyP $ _i - 72)) |]
  , edge      84       $ \   _b -> [p| Note $(boolP _b) Octave84C                    |]

  , blip 96 [p| Percussion |]
  , blip 97 [p| PercussionSound |]
  , edge 105 $ applyB [p| Phrase |]
  , edge 106 $ applyB [p| Phrase2 |]
  , edge 116 $ applyB [p| Overdrive |]

  , ( [e| mapParseOne Mood parseCommand |]
    , [e| \case Mood m -> unparseCommand m |]
    )
  , ( [e| mapParseOne (uncurry PercussionAnimation) parseCommand |]
    , [e| \case PercussionAnimation t b -> unparseCommand (t, b) |]
    )
  , ( [e| firstEventWhich $ \case
        E.MetaEvent (Meta.Lyric s) -> Just $ Lyric $ T.pack s
        E.MetaEvent (Meta.TextEvent s) -> Just $ Lyric $ T.pack s
        -- unrecognized text events are lyrics by default.
        -- but note that this must come after the mood and perc-anim parsers!
        _ -> Nothing
      |]
    , [e| \case Lyric s -> RTB.singleton NNC.zero $ E.MetaEvent $ Meta.Lyric $ T.unpack s |]
    )
  ]