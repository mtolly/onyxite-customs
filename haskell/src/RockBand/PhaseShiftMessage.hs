{-# LANGUAGE DeriveDataTypeable #-}
{-# LANGUAGE DeriveFoldable     #-}
{-# LANGUAGE DeriveFunctor      #-}
{-# LANGUAGE DeriveTraversable  #-}
{-# LANGUAGE LambdaCase         #-}
module RockBand.PhaseShiftMessage where

import           Control.Applicative                   ((<|>))
import           Data.Data
import qualified Data.EventList.Relative.TimeBody      as RTB
import qualified Numeric.NonNegative.Class             as NNC
import           RockBand.Common                       (Difficulty (..))
import           RockBand.Parse
import qualified Sound.MIDI.File.Event                 as E
import qualified Sound.MIDI.File.Event.SystemExclusive as SysEx

data PSMessage = PSMessage
  { psDifficulty :: Maybe Difficulty
  , psPhraseID   :: PhraseID
  , psEdge       :: Bool -- ^ True for start, False for end
  } deriving (Eq, Ord, Show, Read, Typeable, Data)

data PhraseID
  = OpenStrum
  | ProSlideUp
  | ProSlideDown
  | TapNotes
  | HihatOpen
  | HihatPedal
  | SnareRimshot
  | HihatSizzle
  | PalmMuted
  | Vibrato
  | ProHarmonic
  | ProPinchHarmonic
  | ProBend
  | ProAccent
  | ProPop
  | ProSlap
  | YellowTomCymbal
  | BlueTomCymbal
  | GreenTomCymbal
  deriving (Eq, Ord, Show, Read, Enum, Bounded, Typeable, Data)

instance MIDIEvent PSMessage where
  parseOne = firstEventWhich $ \evt -> do
    E.SystemExclusive (SysEx.Regular [0x50, 0x53, 0, 0, bDiff, bPID, bEdge, 0xF7])
      <- return evt
    diff <- case bDiff of
      0   -> Just $ Just Easy
      1   -> Just $ Just Medium
      2   -> Just $ Just Hard
      3   -> Just $ Just Expert
      255 -> Just Nothing
      _   -> Nothing
    pid <- lookup (fromIntegral bPID)
      [ (fromEnum pid + 1, pid) | pid <- [minBound .. maxBound] ]
    pedge <- case bEdge of
      0 -> Just False
      1 -> Just True
      _ -> Nothing
    return $ PSMessage diff pid pedge
  unparseOne (PSMessage diff pid pedge) = RTB.singleton NNC.zero $ E.SystemExclusive $ SysEx.Regular
    [ 0x50
    , 0x53
    , 0
    , 0
    , fromIntegral $ maybe 255 fromEnum diff
    , fromIntegral $ fromEnum pid + 1
    , if pedge then 1 else 0
    , 0xF7
    ]

data PSWrap a
  = PS PSMessage
  | RB a
  deriving (Eq, Ord, Show, Read, Functor, Foldable, Traversable, Typeable, Data)

instance (MIDIEvent a) => MIDIEvent (PSWrap a) where
  parseOne rtb = mapParseOne PS parseOne rtb <|> mapParseOne RB parseOne rtb
  unparseOne = \case
    PS x -> unparseOne x
    RB x -> unparseOne x

discardPS :: (NNC.C t) => RTB.T t (PSWrap a) -> RTB.T t a
discardPS = RTB.mapMaybe $ \case
  PS _ -> Nothing
  RB x -> Just x

psMessages :: (NNC.C t) => RTB.T t (PSWrap a) -> RTB.T t PSMessage
psMessages = RTB.mapMaybe $ \case
  PS msg -> Just msg
  RB _   -> Nothing

withRB :: (NNC.C t, Ord a) => (RTB.T t a -> RTB.T t a) -> RTB.T t (PSWrap a) -> RTB.T t (PSWrap a)
withRB f rtb = let
  (rb, ps) = RTB.partitionMaybe (\case PS _ -> Nothing; RB x -> Just x) rtb
  in RTB.merge (fmap RB $ f rb) ps
