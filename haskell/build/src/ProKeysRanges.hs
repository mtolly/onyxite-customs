{-# LANGUAGE DeriveFunctor #-}
module ProKeysRanges (completeFile, completeRanges, closeShifts, closeShiftsFile) where

import           Control.Monad.Trans.StackTrace   (printStackTraceIO)
import qualified RockBand.File as RBFile
import RockBand.ProKeys
import RockBand.Common
import qualified Data.EventList.Absolute.TimeBody as ATB
import qualified Data.EventList.Relative.TimeBody as RTB
import qualified Numeric.NonNegative.Class as NNC
import qualified Data.Set as Set
import Data.List (sortOn)
import Data.Maybe (listToMaybe, mapMaybe)
import qualified Sound.MIDI.File as F
import qualified Sound.MIDI.File.Load as Load
import qualified Sound.MIDI.File.Save as Save
import qualified Sound.MIDI.Util as U
import Data.Fixed (Milli)
import OnyxiteDisplay.Process (showTimestamp)

completeFile :: FilePath -> FilePath -> IO ()
completeFile fin fout = do
  mid@(F.Cons typ dvn trks) <- Load.fromFile fin
  res <- case dvn of
    F.Ticks res -> return res
    _           -> error "unsupported smpte time"
  song <- printStackTraceIO $ RBFile.readMIDIFile mid
  let mid' = F.Cons typ dvn trks'
      trks' = filter notProKeys trks ++ map (ticks . RBFile.showTrack) proKeys
      ticks :: RTB.T U.Beats a -> RTB.T F.ElapsedTime a
      ticks = RTB.discretize . RTB.mapTime (* fromIntegral res)
      notProKeys trk = case U.trackName trk of
        Just "PART REAL_KEYS_X" -> False
        Just "PART REAL_KEYS_H" -> False
        Just "PART REAL_KEYS_M" -> False
        Just "PART REAL_KEYS_E" -> False
        _                       -> True
      proKeys = RBFile.s_tracks song >>= \case
        RBFile.PartRealKeys diff trk -> [RBFile.PartRealKeys diff $ completeRanges trk]
        _                            -> []
  Save.toFile fout mid'

-- | Adds ranges if there are none.
completeRanges :: RTB.T U.Beats Event -> RTB.T U.Beats Event
completeRanges rtb = let
  (ranges, notRanges) = flip RTB.partitionMaybe rtb $ \case
    LaneShift r -> Just r
    _           -> Nothing
  held = heldNotes $ U.trackJoin $ flip fmap notRanges $ \case
    Note (Blip () p) -> RTB.fromPairList
      [ (0  , (True, p))
      , (1/4, (True, p)) -- give all blips a 16th note of room
      ]
    Note (NoteOn () p) -> RTB.singleton 0 (True, p)
    Note (NoteOff   p) -> RTB.singleton 0 (False, p)
    _                  -> RTB.empty
  in if RTB.null ranges
    then RTB.merge rtb $ fmap LaneShift $ pullBackRanges held $ createRanges held
    else rtb

heldNotes :: (NNC.C t) => RTB.T t (Bool, Pitch) -> RTB.T t (Set.Set Pitch)
heldNotes = go Set.empty . RTB.collectCoincident where
  go held rtb = case RTB.viewL rtb of
    Nothing -> RTB.empty
    Just ((dt, ends), rtb') -> let
      ons  = Set.fromList [p | (True , p) <- ends]
      offs = Set.fromList [p | (False, p) <- ends]
      held' = Set.difference held offs `Set.union` ons
      in RTB.cons dt held' $ go held' rtb'

-- | Chooses valid ranges to accommodate the given notes.
createRanges :: (NNC.C t) => RTB.T t (Set.Set Pitch) -> RTB.T t LaneRange
createRanges = go Nothing where
  go currentRange rtb = case RTB.viewL rtb of
    Nothing -> RTB.empty
    Just ((dt, held), rtb') -> if maybe False (\r -> all (keyInRange r) held) currentRange
      then RTB.delay dt $ go currentRange rtb'
      else case bestRange currentRange held rtb' of
        Nothing -> error $ "Couldn't make a Pro Keys range, because all of these notes are held simultaneously: " ++ show held
        Just newRange -> RTB.cons dt newRange $ go (Just newRange) rtb'

pullBackRanges :: (NNC.C t) => RTB.T t (Set.Set Pitch) -> RTB.T t LaneRange -> RTB.T t LaneRange
pullBackRanges rtb rngs = case RTB.viewL rngs of
  Nothing -> RTB.empty
  Just ((trng, rng), rngs') -> case RTB.viewL rtb of
    Nothing -> RTB.empty
    Just ((theld, held), rtb') -> case NNC.split theld trng of
      (_, (theldLEQtrng, tdiff)) -> if theldLEQtrng
        then if all (all $ keyInRange rng) $ U.trackTake trng rtb
          then RTB.cons theld rng $ pullBackRanges rtb' $ RTB.delay tdiff rngs'
          else RTB.delay theld $ pullBackRanges rtb' $ RTB.cons tdiff rng rngs'
        else RTB.cons trng rng $ pullBackRanges (RTB.cons tdiff held rtb') rngs'

data Lifetime t
  = Mortal t
  | Immortal
  deriving (Eq, Ord, Show, Read, Functor)

bestRange :: (NNC.C t) => Maybe LaneRange -> Set.Set Pitch -> RTB.T t (Set.Set Pitch) -> Maybe LaneRange
bestRange currentRange held rtb = let
  ranges = filter (\rng -> all (keyInRange rng) held) [minBound .. maxBound]
  isLegible rng = rng `notElem` [RangeD, RangeE]
  distance rng = case currentRange of
    Nothing -> 0
    Just cr -> abs $ fromEnum cr - fromEnum rng
  -- higher of each score value is better
  score rng = (rangeLifetime rng rtb, isLegible rng, negate $ distance rng)
  -- First, we want to pick the longest-lasting range.
  -- Second, I personally think D and E ranges are harder to read.
  -- Third, we want to pick a range that is closest to the last one.
  in listToMaybe $ reverse $ sortOn score ranges

rangeLifetime :: (NNC.C t) => LaneRange -> RTB.T t (Set.Set Pitch) -> Lifetime t
rangeLifetime rng rtb = case RTB.viewL rtb of
  Nothing -> Immortal -- range lasts till end of song
  Just ((dt, held), rtb') -> if all (keyInRange rng) held
    then NNC.add dt <$> rangeLifetime rng rtb'
    else Mortal dt

keyInRange :: LaneRange -> Pitch -> Bool
keyInRange RangeC p = RedYellow C <= p && p <= BlueGreen E
keyInRange RangeD p = RedYellow D <= p && p <= BlueGreen F
keyInRange RangeE p = RedYellow E <= p && p <= BlueGreen G
keyInRange RangeF p = RedYellow F <= p && p <= BlueGreen A
keyInRange RangeG p = RedYellow G <= p && p <= BlueGreen B
keyInRange RangeA p = RedYellow A <= p && p <= OrangeC

keyInPreRange :: LaneRange -> Pitch -> Bool
keyInPreRange RangeC p = RedYellow C  <= p && p <= BlueGreen E
keyInPreRange RangeD p = RedYellow Cs <= p && p <= BlueGreen Fs
keyInPreRange RangeE p = RedYellow Ds <= p && p <= BlueGreen Gs
keyInPreRange RangeF p = RedYellow F  <= p && p <= BlueGreen As
keyInPreRange RangeG p = RedYellow Fs <= p && p <= BlueGreen B
keyInPreRange RangeA p = RedYellow Gs <= p && p <= OrangeC

closeShiftsFile :: RBFile.Song U.Beats -> String
closeShiftsFile song = let
  xpk = foldr RTB.merge RTB.empty [ trk | RBFile.PartRealKeys Expert trk <- RBFile.s_tracks song ]
  close = U.unapplyTempoTrack (RBFile.s_tempos song) $ closeShifts 1 $ U.applyTempoTrack (RBFile.s_tempos song) xpk
  showSeconds secs = show (realToFrac secs :: Milli) ++ "s"
  showClose (t, (rng1, rng2, dt, p)) = unwords
    [ showTimestamp (U.applyTempoMap (RBFile.s_tempos song) t) ++ ":"
    , "expert pro keys shift to"
    , show rng2
    , "is"
    , showSeconds dt
    , "before"
    , show p ++ ","
    , "which is outside previous range"
    , show rng1
    ]
  in unlines $ map showClose $ ATB.toPairList $ RTB.toAbsoluteEventList 0 close

closeShifts :: U.Seconds -> RTB.T U.Seconds Event -> RTB.T U.Seconds (LaneRange, LaneRange, U.Seconds, Pitch)
closeShifts threshold rtb = let
  lanes = ATB.toPairList $ RTB.toAbsoluteEventList 0 $ flip RTB.mapMaybe rtb $ \case LaneShift rng -> Just rng; _ -> Nothing
  shifts = zip lanes $ drop 1 lanes
  notes = flip RTB.mapMaybe rtb $ \case
    Note (NoteOn () p) -> Just p
    Note (Blip   () p) -> Just p
    _                  -> Nothing
  closeNotes ((_, rng1), (t, rng2)) = do
    ((dt, p), _) <- RTB.viewL $ RTB.filter (not . keyInPreRange rng1) $ U.trackTake threshold $ U.trackDrop t notes
    return (t, (rng1, rng2, dt, p))
  in RTB.fromAbsoluteEventList $ ATB.fromPairList $ mapMaybe closeNotes shifts
