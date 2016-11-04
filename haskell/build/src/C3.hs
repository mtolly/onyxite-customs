-- | Defines a type for the @.c3@ file used by C3's Magma.
{-# LANGUAGE NoMonomorphismRestriction #-}
{-# LANGUAGE OverloadedStrings         #-}
module C3 where

import           Control.Monad              (forM_)
import           Control.Monad.Trans.Writer
import           Data.Monoid                ((<>))
import qualified Data.Text                  as T
import           RockBand.Common            (Key (..))

-- .c3 files are always encoded in UTF8, regardless of encodeANSI and encodeUTF8

data C3 = C3
  { song               :: T.Text
  , artist             :: T.Text
  , album              :: T.Text
  , customID           :: T.Text
  , version            :: Int
  , isMaster           :: Bool
  , encodingQuality    :: Int
  , crowdAudio         :: Maybe T.Text -- optional
  , crowdVol           :: Maybe Double -- optional
  , is2xBass           :: Bool -- 2xBass in file
  , rhythmKeys         :: Bool
  , rhythmBass         :: Bool
  , karaoke            :: Bool
  , multitrack         :: Bool
  , convert            :: Bool
  , expertOnly         :: Bool
  -- note: CAT EMH and Encrypt Audio are not settings in the .c3 file.
  -- CAT EMH is not remembered at all for some reason.
  -- Encrypt Audio is a setting remembered by the program, not an individual song.
  -- next 4 fields are optional
  , proBassDiff        :: Maybe Int
  , proBassTuning      :: Maybe T.Text -- like "(real_bass_tuning (0 0 0 0))"
  , proGuitarDiff      :: Maybe Int
  , proGuitarTuning    :: Maybe T.Text -- like "(real_guitar_tuning (0 0 0 0 0 0))"
  , disableProKeys     :: Bool
  , tonicNote          :: Maybe Key -- optional
  , tuningCents        :: Int
  , songRating         :: Int
  -- ^ 1,2,3,4 are Family Friendly, Supervision Recommended, Mature, Unrated
  , drumKitSFX         :: Int
  -- ^ index into [Hard Rock Kit (default), Arena Kit, Vintage Kit, Trashy Kit, Electronic Kit]
  , hopoThresholdIndex :: Int -- HopoTresholdIndex in file (misspelled)
  -- ^ index into [90, 130, 170 (default), 250]
  , muteVol            :: Int
  , vocalMuteVol       :: Int
  , soloDrums          :: Bool
  , soloGuitar         :: Bool
  , soloBass           :: Bool
  , soloKeys           :: Bool
  , soloVocals         :: Bool
  , songPreview        :: Int
  , checkTempoMap      :: Bool
  , wiiMode            :: Bool
  , doDrumMixEvents    :: Bool
  , packageDisplay     :: T.Text
  , packageDescription :: T.Text
  , songAlbumArt       :: FilePath
  , packageThumb       :: FilePath
  , encodeANSI         :: Bool
  , encodeUTF8         :: Bool
  , useNumericID       :: Bool
  , uniqueNumericID    :: T.Text
  , uniqueNumericID2X  :: T.Text
  , toDoList           :: [(T.Text, Bool, Bool)] -- ^ to do item, is required, is completed
  } deriving (Eq, Ord, Show, Read)

showC3 :: C3 -> T.Text
showC3 c3 = T.unlines $ execWriter $ do
  line "//Created by Onyxite's Build Tool"
  line "//Feel free to edit manually if you know what you're doing!"
  pair "Song" song
  pair "Artist" artist
  pair "CustomID" customID
  showPair "Version" version
  showPair "IsMaster" isMaster
  showPair "EncodingQuality" encodingQuality
  maybePair "CrowdAudio" crowdAudio
  maybeShowPair "CrowdVol" crowdVol
  showPair "2xBass" is2xBass
  showPair "RhythmKeys" rhythmKeys
  showPair "RhythmBass" rhythmBass
  showPair "Karaoke" karaoke
  showPair "Multitrack" multitrack
  showPair "Convert" convert
  showPair "ExpertOnly" expertOnly
  maybeShowPair "ProBassDiff" proBassDiff
  maybePair "ProBassTuning" proBassTuning
  maybeShowPair "ProGuitarDiff" proGuitarDiff
  maybePair "ProGuitarTuning" proGuitarTuning
  showPair "DisableProKeys" disableProKeys
  maybeShowPair "TonicNote" $ fmap fromEnum . tonicNote
  showPair "TuningCents" tuningCents
  showPair "SongRating" songRating
  showPair "DrumKitSFX" drumKitSFX
  showPair "HopoTresholdIndex" hopoThresholdIndex
  showPair "MuteVol" muteVol
  showPair "VocalMuteVol" vocalMuteVol
  showPair "SoloDrums" soloDrums
  showPair "SoloGuitar" soloGuitar
  showPair "SoloBass" soloBass
  showPair "SoloKeys" soloKeys
  showPair "SoloVocals" soloVocals
  showPair "SongPreview" songPreview
  showPair "CheckTempoMap" checkTempoMap
  showPair "WiiMode" wiiMode
  showPair "DoDrumMixEvents" doDrumMixEvents
  pair "PackageDisplay" packageDisplay
  pair "PackageDescription" packageDescription
  pair "SongAlbumArt" $ T.pack . songAlbumArt
  pair "PackageThumb" $ T.pack . packageThumb
  showPair "EncodeANSI" encodeANSI
  showPair "EncodeUTF8" encodeUTF8
  showPair "UseNumericID" useNumericID
  pair "UniqueNumericID" uniqueNumericID
  pair "UniqueNumericID2X" uniqueNumericID2X
  line ""
  line "TO DO List Begin"
  forM_ (zip [1..] $ toDoList c3) $ \(i, (todo, required, completed)) ->
    line $ "ToDo" <> showT (i :: Int) <> "=" <>
      todo <> "," <> showT required <> "," <> showT completed
  line "TO DO List End"
  line ""
  where line s = tell [s]
        pair key f = maybePair key $ Just . f
        showPair key f = pair key $ showT . f
        maybePair key f = case f c3 of
          Nothing -> return ()
          Just v  -> line $ key <> "=" <> v
        maybeShowPair key f = maybePair key $ fmap showT . f
        showT = T.pack . show

defaultToDo :: [(T.Text, Bool, Bool)]
defaultToDo = map (\s -> (s, False, False))
  [ "Verify the accuracy of all metadata"
  , "Grab official *.png_xbox art file if applicable"
  , "Chart reductions in all instruments"
  , "Add drum fills"
  , "Add overdrive for all instruments"
  , "Add overdrive for vocals"
  , "Create practice sessions [EVENTS]"
  , "Draw sing-along notes in VENUE"
  , "Record dry vocals for lipsync"
  , "Render audio with RB limiter and count-in"
  , "Click to add new item..."
  , "Click to add new item..."
  , "Click to add new item..."
  , "Click to add new item..."
  ]
