{-# LANGUAGE LambdaCase        #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards   #-}
{-# LANGUAGE TupleSections     #-}
module RockBand.Milo.Lipsync where

import           Control.Arrow                    (first)
import           Control.Monad                    (forM, forM_, guard,
                                                   replicateM, void)
import           Control.Monad.Codec
import           Control.Monad.Trans.StackTrace   (logStdout, stackIO)
import           Data.Binary.Get
import           Data.Binary.Put
import qualified Data.ByteString                  as B
import qualified Data.ByteString.Char8            as B8
import qualified Data.ByteString.Lazy             as BL
import qualified Data.EventList.Absolute.TimeBody as ATB
import qualified Data.EventList.Relative.TimeBody as RTB
import qualified Data.HashMap.Strict              as HM
import           Data.Int
import           Data.List.Extra                  (foldl', nubOrd, sort, zip3)
import qualified Data.Map                         as Map
import           Data.Maybe                       (fromMaybe, isJust, isNothing,
                                                   listToMaybe)
import qualified Data.Set                         as Set
import qualified Data.Text                        as T
import qualified Data.Text.Encoding               as TE
import           Data.Word
import           DryVox                           (vocalTubes)
import           Resources                        (CMUPhoneme (..), cmuDict)
import           RockBand.Codec                   (mapTrack)
import qualified RockBand.Codec.File              as RBFile
import           RockBand.Codec.Lipsync           (BeatlesViseme (..),
                                                   GH2Viseme (..),
                                                   LipsyncTrack (..),
                                                   MagmaViseme (..),
                                                   VisemeEvent (..))
import           RockBand.Codec.Vocal
import           RockBand.Common                  (noRedundantStatus)
import           RockBand.Milo.Compression
import           RockBand.Milo.Dir
import           Rocksmith.Sng2014                (Bin (..))
import qualified Sound.MIDI.File.Load             as Load
import qualified Sound.MIDI.File.Save             as Save
import qualified Sound.MIDI.Util                  as U
import           System.FilePath                  (takeExtension)

data MagmaLipsync
  = MagmaLipsync1 Lipsync
  | MagmaLipsync2 Lipsync Lipsync
  | MagmaLipsync3 Lipsync Lipsync Lipsync
  deriving (Eq, Show)

magmaMiloDir :: MagmaLipsync -> MiloDir
magmaMiloDir ml = MiloDir
  { miloVersion = 28
  , miloType = "ObjectDir"
  , miloName = "lipsync"
  , miloU1 = case ml of
    MagmaLipsync1{} -> 4
    MagmaLipsync2{} -> 6
    MagmaLipsync3{} -> 8
  , miloU2 = case ml of
    MagmaLipsync1{} -> 0x15
    MagmaLipsync2{} -> 0x23
    MagmaLipsync3{} -> 0x31
  , miloEntryNames = concat
    [ case ml of
      MagmaLipsync1{} -> []
      _               -> [("CharLipSync", "part2.lipsync")]
    , case ml of
      MagmaLipsync3{} -> [("CharLipSync", "part3.lipsync")]
      _               -> []
    , [("CharLipSync", "song.lipsync")]
    ]
  , miloU3 = 0x1B
  , miloU4 = Just 2
  , miloSubname = Just ""
  , miloU5 = Just 0
  , miloU6 = Just 0
  , miloMatrices = let
    float a b c d = runGet getFloatbe $ BL.pack [a, b, c, d]
    in
      [ [ float 0x3F 0x35 0x04 0xF3, float 0xBF 0x35 0x04 0xF3, float 0x00 0x00 0x00 0x00
        , float 0x3F 0x13 0xCD 0x3A, float 0x3F 0x13 0xCD 0x3A, float 0xBF 0x13 0xCD 0x3A
        , float 0x3E 0xD1 0x05 0xEB, float 0x3E 0xD1 0x05 0xEB, float 0x3F 0x51 0x05 0xEB
        , float 0xC3 0xDD 0xB3 0xD7, float 0xC3 0xDD 0xB3 0xD7, float 0x43 0xDD 0xB3 0xD7
        ]
      , [ float 0x00 0x00 0x00 0x00, float 0xBF 0x80 0x00 0x00, float 0x00 0x00 0x00 0x00
        , float 0x3F 0x80 0x00 0x00, float 0x00 0x00 0x00 0x00, float 0x00 0x00 0x00 0x00
        , float 0x00 0x00 0x00 0x00, float 0x00 0x00 0x00 0x00, float 0x3F 0x80 0x00 0x00
        , float 0xC4 0x40 0x00 0x00, float 0x00 0x00 0x00 0x00, float 0x00 0x00 0x00 0x00
        ]
      , [ float 0x00 0x00 0x00 0x00, float 0x3F 0x80 0x00 0x00, float 0x00 0x00 0x00 0x00
        , float 0xBF 0x80 0x00 0x00, float 0x00 0x00 0x00 0x00, float 0x00 0x00 0x00 0x00
        , float 0x00 0x00 0x00 0x00, float 0x00 0x00 0x00 0x00, float 0x3F 0x80 0x00 0x00
        , float 0x44 0x40 0x00 0x00, float 0x00 0x00 0x00 0x00, float 0x00 0x00 0x00 0x00
        ]
      , [ float 0x3F 0x80 0x00 0x00, float 0x00 0x00 0x00 0x00, float 0x00 0x00 0x00 0x00
        , float 0x00 0x00 0x00 0x00, float 0x00 0x00 0x00 0x00, float 0xBF 0x80 0x00 0x00
        , float 0x00 0x00 0x00 0x00, float 0x3F 0x80 0x00 0x00, float 0x00 0x00 0x00 0x00
        , float 0x00 0x00 0x00 0x00, float 0x00 0x00 0x00 0x00, float 0x44 0x40 0x00 0x00
        ]
      , [ float 0x3F 0x80 0x00 0x00, float 0x00 0x00 0x00 0x00, float 0x00 0x00 0x00 0x00
        , float 0x00 0x00 0x00 0x00, float 0x00 0x00 0x00 0x00, float 0x3F 0x80 0x00 0x00
        , float 0x00 0x00 0x00 0x00, float 0xBF 0x80 0x00 0x00, float 0x00 0x00 0x00 0x00
        , float 0x00 0x00 0x00 0x00, float 0x00 0x00 0x00 0x00, float 0xC4 0x40 0x00 0x00
        ]
      , [ float 0x3F 0x80 0x00 0x00, float 0x00 0x00 0x00 0x00, float 0x00 0x00 0x00 0x00
        , float 0x00 0x00 0x00 0x00, float 0x3F 0x80 0x00 0x00, float 0x00 0x00 0x00 0x00
        , float 0x00 0x00 0x00 0x00, float 0x00 0x00 0x00 0x00, float 0x3F 0x80 0x00 0x00
        , float 0x00 0x00 0x00 0x00, float 0xC4 0x40 0x00 0x00, float 0x00 0x00 0x00 0x00
        ]
      , [ float 0xBF 0x80 0x00 0x00, float 0x00 0x00 0x00 0x00, float 0x00 0x00 0x00 0x00
        , float 0x00 0x00 0x00 0x00, float 0xBF 0x80 0x00 0x00, float 0x00 0x00 0x00 0x00
        , float 0x00 0x00 0x00 0x00, float 0x00 0x00 0x00 0x00, float 0x3F 0x80 0x00 0x00
        , float 0x00 0x00 0x00 0x00, float 0x44 0x40 0x00 0x00, float 0x00 0x00 0x00 0x00
        ]
      ]
  , miloU7 = 0
  , miloU8 = 1
  , miloU9 = 0
  , miloParents = []
  , miloU10 = 0
  , miloChildren = []
  , miloU11 = Nothing
  , miloSubdirs = []
  , miloUnknownBytes = BL.replicate 13 0
  , miloFiles = map (runPut . putLipsync) $ case ml of
    MagmaLipsync1 h1       -> [h1]
    MagmaLipsync2 h1 h2    -> [h2, h1]
    MagmaLipsync3 h1 h2 h3 -> [h2, h3, h1]
  }

magmaMilo :: MagmaLipsync -> BL.ByteString
magmaMilo = addMiloHeader . runPut . void . codecOut bin . magmaMiloDir

data Lipsync = Lipsync
  { lipsyncVersion    :: Word32 -- 1 from magma v2
  , lipsyncSubversion :: Word32 -- 2 from magma v2
  , lipsyncDTAImport  :: B.ByteString -- empty string from magma v2
  , lipsyncVisemes    :: [B.ByteString]
  , lipsyncKeyframes  :: [Keyframe]
  } deriving (Eq, Show)

newtype Keyframe = Keyframe
  { keyframeEvents :: [VisemeEvent Int]
  } deriving (Eq, Show)

parseLipsync :: Get Lipsync
parseLipsync = do
  lipsyncVersion <- getWord32be
  lipsyncSubversion <- getWord32be
  lipsyncDTAImport <- getStringBE
  dtb <- getWord8
  case dtb of
    0 -> return ()
    _ -> fail "Parsing of Lipsync files with embedded DTB is not currently supported"
  skip 4 -- skips zeroes
  visemeCount <- getWord32be
  lipsyncVisemes <- replicateM (fromIntegral visemeCount) getStringBE
  keyframeCount <- getWord32be
  _followingSize <- getWord32be
  lipsyncKeyframes <- replicateM (fromIntegral keyframeCount) $ do
    eventCount <- getWord8
    keyframeEvents <- replicateM (fromIntegral eventCount) $ do
      visemeKey <- fromIntegral <$> getWord8
      visemeWeight <- getWord8
      return VisemeEvent{..}
    return Keyframe{..}
  return Lipsync{..}

putLipsync :: Lipsync -> Put
putLipsync lip = do
  putWord32be $ lipsyncVersion lip
  putWord32be $ lipsyncSubversion lip
  putStringBE $ lipsyncDTAImport lip
  putWord8 0
  putWord32be 0
  putWord32be $ fromIntegral $ length $ lipsyncVisemes lip
  mapM_ putStringBE $ lipsyncVisemes lip
  putWord32be $ fromIntegral $ length $ lipsyncKeyframes lip
  let keyframeBS = runPut $ forM_ (lipsyncKeyframes lip) $ \key -> do
        putWord8 $ fromIntegral $ length $ keyframeEvents key
        forM_ (keyframeEvents key) $ \evt -> do
          putWord8 $ fromIntegral $ visemeKey evt
          putWord8 $ visemeWeight evt
  putWord32be $ fromIntegral $ BL.length keyframeBS
  putLazyByteString keyframeBS
  putWord32be 0

lipsyncToMIDITrack :: Lipsync -> LipsyncTrack U.Seconds
lipsyncToMIDITrack lip
  = LipsyncTrack
  $ RTB.flatten
  $ RTB.fromPairList
  $ do
    (dt, key) <- zip (0 : repeat (1/30 :: U.Seconds)) $ lipsyncKeyframes lip
    let lookupViseme i = TE.decodeLatin1 $ lipsyncVisemes lip !! i
    return (dt, map (fmap lookupViseme) $ keyframeEvents key)

cmuToVisemes :: CMUPhoneme -> [MagmaViseme]
cmuToVisemes = \case
  -- ipa and examples from https://en.wikipedia.org/wiki/ARPABET

  CMU_AA -> [Viseme_Ox_hi, Viseme_Ox_lo] -- ɑ : balm bot
  CMU_AH -> [Viseme_If_hi, Viseme_If_lo] -- ʌ : butt
  CMU_AY -> [Viseme_Ox_hi, Viseme_Ox_lo] -- aɪ : bite
  -- probably should be a diphthong
  CMU_EH -> [Viseme_Cage_hi, Viseme_Cage_lo] -- ɛ : bet
  CMU_ER -> [Viseme_Church_hi, Viseme_Church_lo] -- ɝ : bird
  CMU_EY -> [Viseme_Cage_hi, Viseme_Cage_lo] -- eɪ : bait
  CMU_IH -> [Viseme_If_hi, Viseme_If_lo] -- ɪ : bit
  CMU_IY -> [Viseme_Eat_hi, Viseme_Eat_lo] -- i : beat
  CMU_OW -> [Viseme_Earth_hi, Viseme_Earth_lo] -- oʊ : boat
  CMU_UW -> [Viseme_Wet_hi, Viseme_Wet_lo] -- u : boot
  CMU_AE -> [Viseme_Cage_hi, Viseme_Cage_lo] -- æ : bat
  CMU_AO -> [Viseme_Earth_hi, Viseme_Earth_lo] -- ɔ : story
  CMU_AW -> [Viseme_If_hi, Viseme_If_lo] -- aʊ : bout
  -- probably should be a diphthong
  CMU_OY -> [Viseme_Oat_hi, Viseme_Oat_lo] -- ɔɪ : boy
  -- probably should be a diphthong
  CMU_UH -> [Viseme_Though_hi, Viseme_Though_lo] -- ʊ : book

  _      -> [] -- probably shouldn't happen

cmuToGH2Viseme :: CMUPhoneme -> Maybe GH2Viseme
cmuToGH2Viseme = \case
  CMU_AA -> Just GH2_Ox -- ɑ : balm bot
  CMU_AH -> Just GH2_If -- ʌ : butt
  CMU_AY -> Just GH2_Ox -- aɪ : bite
  CMU_EH -> Just GH2_Cage -- ɛ : bet
  CMU_ER -> Just GH2_Church -- ɝ : bird
  CMU_EY -> Just GH2_Cage -- eɪ : bait
  CMU_IH -> Just GH2_If -- ɪ : bit
  CMU_IY -> Just GH2_Eat -- i : beat
  CMU_OW -> Just GH2_Earth -- oʊ : boat
  CMU_UW -> Just GH2_Wet -- u : boot
  CMU_AE -> Just GH2_Cage -- æ : bat
  CMU_AO -> Just GH2_Earth -- ɔ : story
  CMU_AW -> Just GH2_If -- aʊ : bout
  CMU_OY -> Just GH2_Oat -- ɔɪ : boy
  CMU_UH -> Just GH2_Though -- ʊ : book
  _      -> Nothing -- probably shouldn't happen

cmuToBeatles :: CMUPhoneme -> [(BeatlesViseme, Word8)]
cmuToBeatles = \case

  CMU_AA -> aa -- ɑ : balm bot
  CMU_AH -> ah -- ʌ : butt
  CMU_AY -> aa -- aɪ : bite, should be diphthong
  CMU_EH -> eh -- ɛ : bet
  CMU_ER -> er -- ɝ : bird
  CMU_EY -> ey -- eɪ : bait
  CMU_IH -> ih -- ɪ : bit
  CMU_IY -> iy -- i : beat
  CMU_OW -> ow -- oʊ : boat
  CMU_UW -> uw -- u : boot
  CMU_AE -> ae -- æ : bat
  CMU_AO -> aa -- ɔ : story (closer to ɑ in british pronunciation)
  CMU_AW -> aa -- aʊ : bout, should be diphthong
  CMU_OY -> ow -- ɔɪ : boy, should be diphthong
  CMU_UH -> uh -- ʊ : book
  _      -> [] -- probably shouldn't happen

  where
    -- samples collected from a hard day's night
    ah = -- it's been *a* hard day's night
      [ (Viseme_l_uplip_up, 10), (Viseme_r_uplip_up, 10)
      , (Viseme_l_smile_open, 19), (Viseme_r_smile_open, 19)
      , (Viseme_l_smile_closed, 72), (Viseme_r_smile_closed, 72)
      , (Viseme_l_lolip_up, 40), (Viseme_r_lolip_up, 40)
      , (Viseme_jaw_open, 100)
      ]
    aa = -- it's been a *hard* day's night
      [ (Viseme_jaw_open, 239)
      , (Viseme_l_smile_closed, 28), (Viseme_r_smile_closed, 28)
      , (Viseme_l_uplip_up, 44), (Viseme_r_uplip_up, 44)
      , (Viseme_l_lolip_up, 94), (Viseme_r_lolip_up, 94)
      ]
    ih = -- it's *been* a hard day's night
      [ (Viseme_jaw_open, 50)
      , (Viseme_tongue_up, 200)
      , (Viseme_l_uplip_up, 35), (Viseme_r_uplip_up, 35)
      , (Viseme_l_smile_open, 26), (Viseme_r_smile_open, 26)
      , (Viseme_l_lolip_up, 50), (Viseme_r_lolip_up, 50)
      , (Viseme_jaw_fwd, 13)
      , (Viseme_l_mouth_pucker, 15), (Viseme_r_mouth_pucker, 15)
      ]
    ae = -- *and* i've been working
      [ (Viseme_tongue_up, 200)
      , (Viseme_l_smile_closed, 120), (Viseme_r_smile_closed, 120)
      , (Viseme_l_uplip_up, 30), (Viseme_r_uplip_up, 30)
      , (Viseme_l_mouth_pucker, 40), (Viseme_r_mouth_pucker, 40)
      , (Viseme_l_lolip_dn, 40), (Viseme_r_lolip_dn, 40)
      , (Viseme_jaw_open, 100)
      ]
    eh = -- when i *get* home to you
      [ (Viseme_l_uplip_up, 40), (Viseme_r_uplip_up, 40)
      , (Viseme_l_smile_open, 16), (Viseme_r_smile_open, 16)
      , (Viseme_l_smile_closed, 80), (Viseme_r_smile_closed, 80)
      , (Viseme_l_mouth_pucker, 40), (Viseme_r_mouth_pucker, 40)
      , (Viseme_l_lolip_up, 40), (Viseme_r_lolip_up, 40)
      , (Viseme_l_lolip_dn, 20), (Viseme_r_lolip_dn, 20)
      , (Viseme_jaw_open, 120)
      , (Viseme_jaw_fwd, 15)
      ]
    uw = -- when i get home to *you*
      [ (Viseme_l_uplip_up, 49), (Viseme_r_uplip_up, 49)
      , (Viseme_l_smile_closed, 40), (Viseme_r_smile_closed, 40)
      , (Viseme_l_mouth_pucker, 160), (Viseme_r_mouth_pucker, 160)
      , (Viseme_l_lolip_up, 40), (Viseme_r_lolip_up, 40)
      , (Viseme_jaw_open, 80)
      , (Viseme_jaw_fwd, 8)
      ]
    iy = -- will make me *be* here
      [ (Viseme_l_uplip_up, 60), (Viseme_r_uplip_up, 60)
      , (Viseme_l_smile_open, 19), (Viseme_r_smile_open, 19)
      , (Viseme_l_smile_closed, 130), (Viseme_r_smile_closed, 130)
      , (Viseme_l_lolip_up, 10), (Viseme_r_lolip_up, 10)
      , (Viseme_l_lolip_roll, 30), (Viseme_r_lolip_roll, 30)
      , (Viseme_l_lolip_dn, 37), (Viseme_r_lolip_dn, 37)
      , (Viseme_l_lip_pull, 19), (Viseme_r_lip_pull, 19)
      , (Viseme_jaw_open, 100)
      ]
    ey = -- it's been a hard *day's* night
      [ (Viseme_l_uplip_up, 50), (Viseme_r_uplip_up, 50)
      , (Viseme_l_smile_open, 20), (Viseme_r_smile_open, 20)
      , (Viseme_l_smile_closed, 125), (Viseme_r_smile_closed, 125)
      , (Viseme_l_mouth_pucker, 10), (Viseme_r_mouth_pucker, 10)
      , (Viseme_l_lip_pull, 20), (Viseme_r_lip_pull, 20)
      , (Viseme_jaw_open, 166)
      ]
    er = -- and i've been *work*ing
      [ (Viseme_tongue_up, 50)
      , (Viseme_l_uplip_up, 46), (Viseme_r_uplip_up, 46)
      , (Viseme_l_smile_closed, 31), (Viseme_r_smile_closed, 31)
      , (Viseme_l_mouth_pucker, 15), (Viseme_r_mouth_pucker, 15)
      , (Viseme_l_lolip_up, 91), (Viseme_r_lolip_up, 91)
      , (Viseme_jaw_open, 200)
      ]
    uh = -- *to* get you money
      [ (Viseme_tongue_up, 200)
      , (Viseme_l_uplip_up, 40), (Viseme_r_uplip_up, 40)
      , (Viseme_l_smile_open, 23), (Viseme_r_smile_open, 23)
      , (Viseme_l_smile_closed, 80), (Viseme_r_smile_closed, 80)
      , (Viseme_l_mouth_pucker, 23), (Viseme_r_mouth_pucker, 23)
      , (Viseme_l_lolip_up, 50), (Viseme_r_lolip_up, 50)
      , (Viseme_jaw_open, 70)
      , (Viseme_jaw_fwd, 14)
      ]
    ow = -- when i'm *home*
      [ (Viseme_l_open_pucker, 150), (Viseme_r_open_pucker, 150)
      , (Viseme_l_smile_open, 23), (Viseme_r_smile_open, 23)
      , (Viseme_l_mouth_pucker, 80), (Viseme_r_mouth_pucker, 80)
      , (Viseme_jaw_open, 180)
      ]

englishVowels :: RTB.T t (Maybe T.Text) -> RTB.T t (Maybe CMUPhoneme)
englishVowels = let
  splitFirstWord evts = let
    (x, y) = flip span evts $ \case
      (_, Nothing   ) -> True
      (_, Just lyric) -> elem
        (T.takeEnd 1 $ T.dropWhileEnd (`elem` ['$', '#', '^']) lyric)
        ["-", "="]
    in (x <> take 1 y, drop 1 y)
  go [] = []
  go evts = case splitFirstWord evts of
    (wordEvents, rest) -> let
      numSyllables = length [ () | (_, Just _) <- wordEvents ]
      isVowel phone = elem phone
        [ CMU_AA, CMU_AE, CMU_AH, CMU_AO, CMU_AW
        , CMU_AY, CMU_EH, CMU_ER, CMU_EY, CMU_IH
        , CMU_IY, CMU_OW, CMU_OY, CMU_UH, CMU_UW
        ]
      filterLyric = maybe ""
        $ T.map (\case '=' -> '-'; c -> c)
        . T.filter (`notElem` ("-#^$!?" :: String))
      word = B8.pack $ T.unpack $ T.toUpper $ T.concat $ map (filterLyric . snd) wordEvents
      phones = case filter ((== numSyllables) . length) $ map (filter isVowel) $ fromMaybe [] $ HM.lookup word cmuDict of
        match : _ -> applyPhonemes match wordEvents
        []        -> guessPhonemes wordEvents
      in phones ++ go rest
  applyPhonemes phones           ((t, Nothing) : events) = (t, Nothing    ) : applyPhonemes phones events
  applyPhonemes (phone : phones) ((t, Just _ ) : events) = (t, Just phone ) : applyPhonemes phones events
  applyPhonemes _                []                      = []
  applyPhonemes []               ((t, Just _ ) : events) = (t, Just CMU_AH) : applyPhonemes []     events -- shouldn't happen
  guessPhonemes = map $ \case
    (t, Nothing) -> (t, Nothing)
    (t, Just _lyric) -> let
      phone = CMU_AH -- TODO
      in (t, Just phone)
  in RTB.fromPairList . go . RTB.toPairList

-- for some reason you sometimes need an extra zero for a viseme to be totally shut off.
-- official lipsync files usually have this as well
redundantZero :: (Eq a) => [[(a, Word8)]] -> [[(a, Word8)]]
redundantZero []               = []
redundantZero [x]              = [x, x]
redundantZero (x : xs@(y : _)) = x : case [ vis | (vis, 0) <- x, isNothing $ lookup vis y ] of
  []      -> redundantZero xs
  visemes -> case redundantZero xs of
    []      -> [] -- shouldn't happen
    y' : ys -> (map (, 0) visemes ++ y') : ys

-- each list in the event list is an absolute set of visemes, not just changes
visemesToLipsync :: U.Seconds -> RTB.T U.Seconds [(T.Text, Word8)] -> Lipsync
visemesToLipsync transition rtb = let
  halfTransition = transition / 2
  transitionSteps = ceiling $ transition * 30 :: Int
  pairs = ATB.toPairList $ RTB.toAbsoluteEventList 0 rtb
  triples = zip3
    ((0, []) : pairs) -- previous time and viseme
    pairs
    (map Just (drop 1 $ map fst pairs) ++ [Nothing]) -- time of next viseme
  withTransitions = flip concatMap triples $ \((prevTime, prevVisemes), (thisTime, thisVisemes), mNextTime) -> let
    dt = thisTime - prevTime
    transitionBefore = min halfTransition (dt / 2)
    transitionAfter = case mNextTime of
      Nothing       -> halfTransition
      Just nextTime -> min halfTransition ((nextTime - thisTime) / 2)
    transitionStart = thisTime - transitionBefore
    transitionLength = transitionBefore + transitionAfter
    transitionVisemes = do
      vis <- nubOrd $ map fst $ prevVisemes ++ thisVisemes
      let startValue = maybe 0 fromIntegral $ lookup vis prevVisemes
          endValue = maybe 0 fromIntegral $ lookup vis thisVisemes
          change = endValue - startValue
      return (vis, startValue :: Rational, change :: Rational)
    in flip map [0 .. transitionSteps] $ \i -> let
      frac = fromIntegral i / fromIntegral transitionSteps
      newTime = transitionStart + transitionLength * fromRational frac
      newVisemes = do
        (vis, startValue, change) <- transitionVisemes
        let thisValue = round $ startValue + change * frac
        return $ VisemeEvent vis thisValue
      in (newTime, newVisemes)
  in lipsyncFromMIDITrack
    $ LipsyncTrack
    $ RTB.flatten
    $ RTB.fromAbsoluteEventList
    $ ATB.fromPairList withTransitions

autoLipsync :: VocalTrack U.Seconds -> Lipsync
autoLipsync
  = visemesToLipsync 0.12
  . fmap (maybe [] $ map (\v -> (T.pack $ drop 7 $ show v, 140)) . cmuToVisemes)
  . englishVowels
  . vocalTubes

autoLipsyncAh :: VocalTrack U.Seconds -> Lipsync
autoLipsyncAh
  = visemesToLipsync 0.12
  . fmap (\x -> guard (isJust x) >> [("Ox_hi", 100), ("Ox_lo", 100)])
  . vocalTubes

beatlesLipsync :: VocalTrack U.Seconds -> Lipsync
beatlesLipsync
  = (\lip -> lip
    { lipsyncVersion = 0
    , lipsyncSubversion = 2
    , lipsyncDTAImport = "proj9"
    })
  . visemesToLipsync 0.12
  . fmap (maybe [] $ map (first $ T.pack . drop 7 . show) . cmuToBeatles)
  . englishVowels
  . vocalTubes

gh2Lipsync :: VocalTrack U.Seconds -> VocFile
gh2Lipsync
  = visemesToVoc
  . fmap (\mcmu -> case mcmu >>= cmuToGH2Viseme of
    Nothing  -> []
    Just vis -> [(T.replace "_" " " $ T.pack $ drop 4 $ show vis, 1)]
    )
  . englishVowels
  . vocalTubes

lipsyncFromMIDITrack :: LipsyncTrack U.Seconds -> Lipsync
lipsyncFromMIDITrack lip = let
  makeKeyframes cur rest = let
    (frame, after) = U.trackSplit (1/30 :: U.Seconds) rest
    next = Map.filter (/= 0) $ foldl' (\m (VisemeEvent k w) -> Map.insert k w m) cur frame
    keyframe = do
      vis <- Set.toList $ Map.keysSet cur <> Map.keysSet next
      return (vis, fromMaybe 0 $ Map.lookup vis next)
    in keyframe : if RTB.null after
      then []
      else makeKeyframes next after
  visemeSet = Set.fromList $ map visemeKey $ RTB.getBodies $ lipEvents lip
  in Lipsync
    { lipsyncVersion    = 1
    , lipsyncSubversion = 2
    , lipsyncDTAImport  = B.empty
    , lipsyncVisemes    = map TE.encodeUtf8 $ Set.toList visemeSet
    , lipsyncKeyframes
      = map (Keyframe . sort . map ((\(vis, n) -> VisemeEvent (Set.findIndex vis visemeSet) n)))
      $ redundantZero
      $ makeKeyframes Map.empty
      $ RTB.delay (1/60 :: U.Seconds) -- this is so we can process the first 1/30 and end up in the center of the first frame
      $ lipEvents lip
    }

testConvertLipsync :: FilePath -> [FilePath] -> FilePath -> IO ()
testConvertLipsync fmid fvocs fout = do
  res <- logStdout $ stackIO (Load.fromFile fmid) >>= RBFile.readMIDIFile'
  mid <- case res of
    Left err  -> error $ show err
    Right mid -> return mid
  trks <- forM fvocs $ \fvoc -> do
    trk <- BL.readFile fvoc >>= return . case takeExtension fvoc of
      ".voc" -> vocToMIDITrack     . runGet parseVocFile
      _      -> lipsyncToMIDITrack . runGet parseLipsync
    return $ mapTrack (U.unapplyTempoTrack $ RBFile.s_tempos mid) trk
  Save.toFile fout $ RBFile.showMIDIFile' mid
    { RBFile.s_tracks = (RBFile.s_tracks mid)
      { RBFile.onyxParts = let
        orig = RBFile.onyxParts $ RBFile.s_tracks mid
        fn vox = Just (fromMaybe mempty vox)
          { RBFile.onyxLipsync1 = fromMaybe mempty $ listToMaybe trks
          , RBFile.onyxLipsync2 = fromMaybe mempty $ listToMaybe $ drop 1 trks
          , RBFile.onyxLipsync3 = fromMaybe mempty $ listToMaybe $ drop 2 trks
          }
        in Map.alter fn RBFile.FlexVocal orig
      }
    }

data VocFile = VocFile
  { vocMystery1  :: Word32 -- RB: 1500, GH2: 1200
  , vocMystery2  :: Word16 -- RB: 1, GH2: 0
  , vocCompany   :: B.ByteString -- "Harmonix"
  , vocMystery3  :: Word16 -- 1
  , vocComment   :: B.ByteString
    -- RB: "5 projects developed before 5/7/2007"
    -- GH2: "Karaoke Revolution Vol 4"
  -- boundaries between next few are uncertain
  , vocMystery4  :: Word32 -- 1000
  , vocMystery5  :: Word32 -- 0
  , vocMystery6  :: Word16 -- 0
  , vocMystery7  :: Word16 -- RB: 1, GH2: 0
  , vocName      :: B.ByteString -- "alright_dryvox"
  , vocMystery8  :: Word16 -- 3
  , vocFileSize  :: Word32 -- total size of the file. 123525 (0x1E285)
  , vocMystery9  :: Word16 -- 0
  , vocVisemes   :: [VocViseme]
  -- again, boundaries uncertain
  , vocMystery10 :: Word32 -- 0
  , vocMystery11 :: Word16 -- 0
  -- pretty sure these are floats. could be weight transition times
  , vocMystery12 :: Float -- 0.16
  , vocMystery13 :: Float -- 0.22
  -- GH2 file ends here. RB file continues
  , vocMystery14 :: Maybe Word32 -- 0
  , vocMystery15 :: Maybe Word16 -- 0
  , vocMystery16 :: Maybe Word32 -- 1
  , vocMystery17 :: Maybe Word16 -- 0
  , vocMystery18 :: Maybe Word32 -- 1
  , vocMystery19 :: Maybe Word16 -- 0
  , vocMystery20 :: Maybe Int32 -- -1
  } deriving (Show)

data VocViseme = VocViseme
  { vvMystery1 :: Word32 -- 0
  , vvMystery2 :: Word16 -- 0
  , vvMystery3 :: Word16 -- RB: 1, GH2: 0
  , vvName     :: B.ByteString -- "Eat", "If", etc.
  , vvMystery4 :: Word32 -- 0
  , vvMystery5 :: Word32 -- 0
  , vvEvents   :: [VocEvent] -- each is 18 bytes
  , vvMystery6 :: Word16 -- 0
  } deriving (Show)

data VocEvent = VocEvent
  { veMystery1 :: Word32 -- 0
  , veTime     :: Float -- timestamp in seconds
  , veWeight   :: Float -- range appears to vary per property. 0 to 1 is typical but some are negative or higher than 1
  , veMystery2 :: Word32 -- 0
  , veMystery3 :: Word16 -- 0
  } deriving (Show)

parseVocFile :: Get VocFile
parseVocFile = do
  "FACE" <- getByteString 4
  vocMystery1 <- getWord32le
  vocMystery2 <- getWord16le
  vocCompany <- getStringLE
  vocMystery3 <- getWord16le
  vocComment <- getStringLE
  vocMystery4 <- getWord32le
  vocMystery5 <- getWord32le
  vocMystery6 <- getWord16le
  vocMystery7 <- getWord16le
  vocName <- getStringLE
  vocMystery8 <- getWord16le
  vocFileSize <- getWord32le
  vocMystery9 <- getWord16le
  visemeCount <- getWord32le
  vocVisemes <- replicateM (fromIntegral visemeCount) $ do
    vvMystery1 <- getWord32le
    vvMystery2 <- getWord16le
    vvMystery3 <- getWord16le
    vvName <- getStringLE
    vvMystery4 <- getWord32le
    vvMystery5 <- getWord32le
    eventCount <- getWord16le
    vvEvents <- replicateM (fromIntegral eventCount) $ do
      veMystery1 <- getWord32le
      veTime <- getFloatle
      veWeight <- getFloatle
      veMystery2 <- getWord32le
      veMystery3 <- getWord16le
      return VocEvent{..}
    vvMystery6 <- getWord16le
    return VocViseme{..}
  vocMystery10 <- getWord32le
  vocMystery11 <- getWord16le
  vocMystery12 <- getFloatle
  vocMystery13 <- getFloatle
  isGH <- isEmpty
  vocMystery14 <- if isGH then return Nothing else Just <$> getWord32le
  vocMystery15 <- if isGH then return Nothing else Just <$> getWord16le
  vocMystery16 <- if isGH then return Nothing else Just <$> getWord32le
  vocMystery17 <- if isGH then return Nothing else Just <$> getWord16le
  vocMystery18 <- if isGH then return Nothing else Just <$> getWord32le
  vocMystery19 <- if isGH then return Nothing else Just <$> getWord16le
  vocMystery20 <- if isGH then return Nothing else Just <$> getInt32le
  return VocFile{..}

putVocFileRaw :: VocFile -> Put
putVocFileRaw VocFile{..} = do
  putByteString "FACE"
  putWord32le vocMystery1
  putWord16le vocMystery2
  putStringLE vocCompany
  putWord16le vocMystery3
  putStringLE vocComment
  putWord32le vocMystery4
  putWord32le vocMystery5
  putWord16le vocMystery6
  putWord16le vocMystery7
  putStringLE vocName
  putWord16le vocMystery8
  putWord32le vocFileSize
  putWord16le vocMystery9
  putWord32le $ fromIntegral $ length vocVisemes
  forM_ vocVisemes $ \VocViseme{..} -> do
    putWord32le vvMystery1
    putWord16le vvMystery2
    putWord16le vvMystery3
    putStringLE vvName
    putWord32le vvMystery4
    putWord32le vvMystery5
    putWord16le $ fromIntegral $ length vvEvents
    forM_ vvEvents $ \VocEvent{..} -> do
      putWord32le veMystery1
      putFloatle veTime
      putFloatle veWeight
      putWord32le veMystery2
      putWord16le veMystery3
    putWord16le vvMystery6
  putWord32le vocMystery10
  putWord16le vocMystery11
  putFloatle vocMystery12
  putFloatle vocMystery13
  mapM_ putWord32le vocMystery14
  mapM_ putWord16le vocMystery15
  mapM_ putWord32le vocMystery16
  mapM_ putWord16le vocMystery17
  mapM_ putWord32le vocMystery18
  mapM_ putWord16le vocMystery19
  mapM_ putInt32le vocMystery20

putVocFile :: VocFile -> Put
putVocFile voc = let
  len = fromIntegral $ BL.length $ runPut $ putVocFileRaw voc
  in putVocFileRaw voc { vocFileSize = len }

getStringLE :: Get B.ByteString
getStringLE = do
  len <- getWord32le
  getByteString $ fromIntegral len

putStringLE :: B.ByteString -> Put
putStringLE bs = do
  putWord32le $ fromIntegral $ B.length bs
  putByteString bs

vocToMIDITrack :: VocFile -> LipsyncTrack U.Seconds
vocToMIDITrack voc
  = LipsyncTrack
  $ foldr RTB.merge RTB.empty
  $ flip map (vocVisemes voc)
  $ \vis -> let
    name = TE.decodeLatin1 $ vvName vis
    in RTB.fromAbsoluteEventList
      $ ATB.fromPairList
      $ flip map (vvEvents vis) $ \evt -> let
        -- arterialblack.voc has a veTime of -2.3666643e-2 so we clamp to 0
        time = realToFrac $ if veTime evt < 0 then 0 else veTime evt
        -- TODO extend lipsync track to support the full range
        weight
          | veWeight evt < 0 = 0
          | veWeight evt > 1 = 255
          | otherwise        = round $ veWeight evt * 255
        in (time, VisemeEvent name weight)

visemesToVoc :: RTB.T U.Seconds [(T.Text, Float)] -> VocFile
visemesToVoc visemes = VocFile
  { vocMystery1 = 1200
  , vocMystery2 = 0
  , vocCompany = "Harmonix"
  , vocMystery3 = 0
  , vocComment = "Karaoke Revolution Vol 4"
  , vocMystery4 = 1000
  , vocMystery5 = 0
  , vocMystery6 = 0
  , vocMystery7 = 0
  , vocName = "onyx_toolkit_lipsync"
  , vocMystery8 = 0
  , vocFileSize = 0xDEADBEEF -- calculated later
  , vocMystery9 = 0
  , vocVisemes = flip map (nubOrd $ map fst $ concat $ RTB.getBodies visemes) $ \vis -> VocViseme
    { vvMystery1 = 0
    , vvMystery2 = 0
    , vvMystery3 = 0
    , vvName = TE.encodeUtf8 vis
    , vvMystery4 = 0
    , vvMystery5 = 0
    , vvEvents
      = map (\(t, weight) -> VocEvent
        { veMystery1 = 0
        , veTime = realToFrac t
        , veWeight = weight
        , veMystery2 = 0
        , veMystery3 = 0
        })
      $ ATB.toPairList
      $ RTB.toAbsoluteEventList 0
      $ noRedundantStatus
      $ fmap (\set -> fromMaybe 0 $ lookup vis set) visemes
    , vvMystery6 = 0
    }
  , vocMystery10 = 0
  , vocMystery11 = 0
  , vocMystery12 = 0.16
  , vocMystery13 = 0.22
  , vocMystery14 = Nothing
  , vocMystery15 = Nothing
  , vocMystery16 = Nothing
  , vocMystery17 = Nothing
  , vocMystery18 = Nothing
  , vocMystery19 = Nothing
  , vocMystery20 = Nothing
  }
