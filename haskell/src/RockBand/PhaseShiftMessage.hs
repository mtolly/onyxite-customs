{-# LANGUAGE LambdaCase        #-}
{-# LANGUAGE OverloadedStrings #-}
module RockBand.PhaseShiftMessage where

import qualified Data.Text                             as T
import           RockBand.Common                       (Command (..),
                                                        Difficulty (..))
import qualified Sound.MIDI.File.Event                 as E
import qualified Sound.MIDI.File.Event.SystemExclusive as SysEx
import           Text.Read                             (readMaybe)

data PSMessage = PSMessage
  { psDifficulty :: Maybe Difficulty
  , psPhraseID   :: PhraseID
  , psEdge       :: Bool -- ^ True for start, False for end
  } deriving (Eq, Ord, Show, Read)

data PhraseID
  = OpenStrum
  -- ^ Note: in PS this (I think) only makes green notes into open notes.
  -- However in Clone Hero it makes all notes into open notes.
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
  deriving (Eq, Ord, Show, Read, Enum, Bounded)

instance Command PSMessage where
  fromCommand = error "PSMessage to command not implemented"
  toCommand = \case
    ["onyx", "ps", d, pid, e] -> do
      diff <- case d of
        "easy"   -> return $ Just Easy
        "medium" -> return $ Just Medium
        "hard"   -> return $ Just Hard
        "expert" -> return $ Just Expert
        "all"    -> return Nothing
        _        -> Nothing
      phraseID <- readMaybe $ T.unpack pid
      onoff <- case e of
        "on"  -> Just True
        "off" -> Just False
        _     -> Nothing
      return $ PSMessage diff phraseID onoff
    _ -> Nothing

parsePSSysEx :: E.T -> Maybe PSMessage
parsePSSysEx evt = do
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

unparsePSSysEx :: PSMessage -> E.T
unparsePSSysEx (PSMessage diff pid pedge) = E.SystemExclusive $ SysEx.Regular
  [ 0x50
  , 0x53
  , 0
  , 0
  , fromIntegral $ maybe 255 fromEnum diff
  , fromIntegral $ fromEnum pid + 1
  , if pedge then 1 else 0
  , 0xF7
  ]
