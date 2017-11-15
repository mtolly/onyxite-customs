module Song where

import Prelude
import Data.Time.Duration (Seconds(..))
import Data.Foreign
import Data.Foreign.Index (readProp, readIndex)
import OnyxMap as Map
import Data.Maybe (Maybe(..))
import Data.Traversable (sequence, traverse)
import Data.Tuple (Tuple(..))
import Data.Generic (class Generic, gShow, gEq, gCompare)
import Control.Monad.Except (throwError)

newtype Song = Song
  { end   :: Seconds
  , beats :: Beats
  , parts :: Array (Tuple String Flex)
  }

newtype Flex = Flex
  { five :: Maybe Five
  , six :: Maybe Six
  , drums :: Maybe Drums
  , prokeys :: Maybe ProKeys
  , protar :: Maybe Protar
  , vocal :: Maybe Vocal
  }

data FlexPart
  = FlexFive
  | FlexSix
  | FlexDrums
  | FlexProKeys
  | FlexProtar
  | FlexVocal

derive instance genFlexPart :: Generic FlexPart
instance showFlexPart :: Show FlexPart where
  show = gShow
instance eqFlexPart :: Eq FlexPart where
  eq = gEq
instance ordFlexPart :: Ord FlexPart where
  compare = gCompare

newtype Drums = Drums
  { notes  :: Map.Map Seconds (Array Gem)
  , solo   :: Map.Map Seconds Boolean
  , energy :: Map.Map Seconds Boolean
  }

data Sustainable a
  = SustainEnd
  | Note a
  | Sustain a

data GuitarNoteType = Strum | HOPO | Tap

newtype Five = Five
  { notes ::
    { open   :: Map.Map Seconds (Sustainable GuitarNoteType)
    , green  :: Map.Map Seconds (Sustainable GuitarNoteType)
    , red    :: Map.Map Seconds (Sustainable GuitarNoteType)
    , yellow :: Map.Map Seconds (Sustainable GuitarNoteType)
    , blue   :: Map.Map Seconds (Sustainable GuitarNoteType)
    , orange :: Map.Map Seconds (Sustainable GuitarNoteType)
    }
  , solo :: Map.Map Seconds Boolean
  , energy :: Map.Map Seconds Boolean
  }

newtype Six = Six
  { notes ::
    { open :: Map.Map Seconds (Sustainable GuitarNoteType)
    , b1   :: Map.Map Seconds (Sustainable GuitarNoteType)
    , b2   :: Map.Map Seconds (Sustainable GuitarNoteType)
    , b3   :: Map.Map Seconds (Sustainable GuitarNoteType)
    , w1   :: Map.Map Seconds (Sustainable GuitarNoteType)
    , w2   :: Map.Map Seconds (Sustainable GuitarNoteType)
    , w3   :: Map.Map Seconds (Sustainable GuitarNoteType)
    , bw1  :: Map.Map Seconds (Sustainable GuitarNoteType)
    , bw2  :: Map.Map Seconds (Sustainable GuitarNoteType)
    , bw3  :: Map.Map Seconds (Sustainable GuitarNoteType)
    }
  , solo :: Map.Map Seconds Boolean
  , energy :: Map.Map Seconds Boolean
  }

newtype ProtarNote = ProtarNote
  { noteType :: GuitarNoteType
  , fret     :: Maybe Int
  }

newtype Protar = Protar
  { notes ::
    { s1 :: Map.Map Seconds (Sustainable ProtarNote)
    , s2 :: Map.Map Seconds (Sustainable ProtarNote)
    , s3 :: Map.Map Seconds (Sustainable ProtarNote)
    , s4 :: Map.Map Seconds (Sustainable ProtarNote)
    , s5 :: Map.Map Seconds (Sustainable ProtarNote)
    , s6 :: Map.Map Seconds (Sustainable ProtarNote)
    }
  , solo :: Map.Map Seconds Boolean
  , energy :: Map.Map Seconds Boolean
  }

newtype ProKeys = ProKeys
  { notes  :: Map.Map Pitch (Map.Map Seconds (Sustainable Unit))
  , ranges :: Map.Map Seconds Range
  , solo   :: Map.Map Seconds Boolean
  , energy :: Map.Map Seconds Boolean
  }

data Range
  = RangeC
  | RangeD
  | RangeE
  | RangeF
  | RangeG
  | RangeA

isForeignRange :: Foreign -> F Range
isForeignRange f = readString f >>= \s -> case s of
  "c" -> pure RangeC
  "d" -> pure RangeD
  "e" -> pure RangeE
  "f" -> pure RangeF
  "g" -> pure RangeG
  "a" -> pure RangeA
  _ -> throwError $ pure $ TypeMismatch "pro keys range" $ show s

data Pitch
  = RedC
  | RedCs
  | RedD
  | RedDs
  | RedE
  | YellowF
  | YellowFs
  | YellowG
  | YellowGs
  | YellowA
  | YellowAs
  | YellowB
  | BlueC
  | BlueCs
  | BlueD
  | BlueDs
  | BlueE
  | GreenF
  | GreenFs
  | GreenG
  | GreenGs
  | GreenA
  | GreenAs
  | GreenB
  | OrangeC

derive instance genPitch :: Generic Pitch
instance showPitch :: Show Pitch where
  show = gShow
instance eqPitch :: Eq Pitch where
  eq = gEq
instance ordPitch :: Ord Pitch where
  compare = gCompare

isForeignFiveNote :: Foreign -> F (Sustainable GuitarNoteType)
isForeignFiveNote f = readString f >>= \s -> case s of
  "end"  -> pure SustainEnd
  "strum" -> pure $ Note Strum
  "hopo" -> pure $ Note HOPO
  "tap" -> pure $ Note Tap
  "strum-sust" -> pure $ Sustain Strum
  "hopo-sust" -> pure $ Sustain HOPO
  "tap-sust" -> pure $ Sustain Tap
  _ -> throwError $ pure $ TypeMismatch "grybo/ghl note event" $ show s

isForeignProtarNote :: Foreign -> F (Sustainable ProtarNote)
isForeignProtarNote f = readString f >>= \s -> case s of
  "end"  -> pure SustainEnd
  "strum-x" -> pure $ Note $ ProtarNote { noteType: Strum, fret: Nothing }
  "strum-0" -> pure $ Note $ ProtarNote { noteType: Strum, fret: Just 0 }
  "strum-1" -> pure $ Note $ ProtarNote { noteType: Strum, fret: Just 1 }
  "strum-2" -> pure $ Note $ ProtarNote { noteType: Strum, fret: Just 2 }
  "strum-3" -> pure $ Note $ ProtarNote { noteType: Strum, fret: Just 3 }
  "strum-4" -> pure $ Note $ ProtarNote { noteType: Strum, fret: Just 4 }
  "strum-5" -> pure $ Note $ ProtarNote { noteType: Strum, fret: Just 5 }
  "strum-6" -> pure $ Note $ ProtarNote { noteType: Strum, fret: Just 6 }
  "strum-7" -> pure $ Note $ ProtarNote { noteType: Strum, fret: Just 7 }
  "strum-8" -> pure $ Note $ ProtarNote { noteType: Strum, fret: Just 8 }
  "strum-9" -> pure $ Note $ ProtarNote { noteType: Strum, fret: Just 9 }
  "strum-10" -> pure $ Note $ ProtarNote { noteType: Strum, fret: Just 10 }
  "strum-11" -> pure $ Note $ ProtarNote { noteType: Strum, fret: Just 11 }
  "strum-12" -> pure $ Note $ ProtarNote { noteType: Strum, fret: Just 12 }
  "strum-13" -> pure $ Note $ ProtarNote { noteType: Strum, fret: Just 13 }
  "strum-14" -> pure $ Note $ ProtarNote { noteType: Strum, fret: Just 14 }
  "strum-15" -> pure $ Note $ ProtarNote { noteType: Strum, fret: Just 15 }
  "strum-16" -> pure $ Note $ ProtarNote { noteType: Strum, fret: Just 16 }
  "strum-17" -> pure $ Note $ ProtarNote { noteType: Strum, fret: Just 17 }
  "strum-18" -> pure $ Note $ ProtarNote { noteType: Strum, fret: Just 18 }
  "strum-19" -> pure $ Note $ ProtarNote { noteType: Strum, fret: Just 19 }
  "strum-20" -> pure $ Note $ ProtarNote { noteType: Strum, fret: Just 20 }
  "strum-21" -> pure $ Note $ ProtarNote { noteType: Strum, fret: Just 21 }
  "strum-22" -> pure $ Note $ ProtarNote { noteType: Strum, fret: Just 22 }
  "hopo-x" -> pure $ Note $ ProtarNote { noteType: HOPO, fret: Nothing }
  "hopo-0" -> pure $ Note $ ProtarNote { noteType: HOPO, fret: Just 0 }
  "hopo-1" -> pure $ Note $ ProtarNote { noteType: HOPO, fret: Just 1 }
  "hopo-2" -> pure $ Note $ ProtarNote { noteType: HOPO, fret: Just 2 }
  "hopo-3" -> pure $ Note $ ProtarNote { noteType: HOPO, fret: Just 3 }
  "hopo-4" -> pure $ Note $ ProtarNote { noteType: HOPO, fret: Just 4 }
  "hopo-5" -> pure $ Note $ ProtarNote { noteType: HOPO, fret: Just 5 }
  "hopo-6" -> pure $ Note $ ProtarNote { noteType: HOPO, fret: Just 6 }
  "hopo-7" -> pure $ Note $ ProtarNote { noteType: HOPO, fret: Just 7 }
  "hopo-8" -> pure $ Note $ ProtarNote { noteType: HOPO, fret: Just 8 }
  "hopo-9" -> pure $ Note $ ProtarNote { noteType: HOPO, fret: Just 9 }
  "hopo-10" -> pure $ Note $ ProtarNote { noteType: HOPO, fret: Just 10 }
  "hopo-11" -> pure $ Note $ ProtarNote { noteType: HOPO, fret: Just 11 }
  "hopo-12" -> pure $ Note $ ProtarNote { noteType: HOPO, fret: Just 12 }
  "hopo-13" -> pure $ Note $ ProtarNote { noteType: HOPO, fret: Just 13 }
  "hopo-14" -> pure $ Note $ ProtarNote { noteType: HOPO, fret: Just 14 }
  "hopo-15" -> pure $ Note $ ProtarNote { noteType: HOPO, fret: Just 15 }
  "hopo-16" -> pure $ Note $ ProtarNote { noteType: HOPO, fret: Just 16 }
  "hopo-17" -> pure $ Note $ ProtarNote { noteType: HOPO, fret: Just 17 }
  "hopo-18" -> pure $ Note $ ProtarNote { noteType: HOPO, fret: Just 18 }
  "hopo-19" -> pure $ Note $ ProtarNote { noteType: HOPO, fret: Just 19 }
  "hopo-20" -> pure $ Note $ ProtarNote { noteType: HOPO, fret: Just 20 }
  "hopo-21" -> pure $ Note $ ProtarNote { noteType: HOPO, fret: Just 21 }
  "hopo-22" -> pure $ Note $ ProtarNote { noteType: HOPO, fret: Just 22 }
  "strum-sust-x" -> pure $ Sustain $ ProtarNote { noteType: Strum, fret: Nothing }
  "strum-sust-0" -> pure $ Sustain $ ProtarNote { noteType: Strum, fret: Just 0 }
  "strum-sust-1" -> pure $ Sustain $ ProtarNote { noteType: Strum, fret: Just 1 }
  "strum-sust-2" -> pure $ Sustain $ ProtarNote { noteType: Strum, fret: Just 2 }
  "strum-sust-3" -> pure $ Sustain $ ProtarNote { noteType: Strum, fret: Just 3 }
  "strum-sust-4" -> pure $ Sustain $ ProtarNote { noteType: Strum, fret: Just 4 }
  "strum-sust-5" -> pure $ Sustain $ ProtarNote { noteType: Strum, fret: Just 5 }
  "strum-sust-6" -> pure $ Sustain $ ProtarNote { noteType: Strum, fret: Just 6 }
  "strum-sust-7" -> pure $ Sustain $ ProtarNote { noteType: Strum, fret: Just 7 }
  "strum-sust-8" -> pure $ Sustain $ ProtarNote { noteType: Strum, fret: Just 8 }
  "strum-sust-9" -> pure $ Sustain $ ProtarNote { noteType: Strum, fret: Just 9 }
  "strum-sust-10" -> pure $ Sustain $ ProtarNote { noteType: Strum, fret: Just 10 }
  "strum-sust-11" -> pure $ Sustain $ ProtarNote { noteType: Strum, fret: Just 11 }
  "strum-sust-12" -> pure $ Sustain $ ProtarNote { noteType: Strum, fret: Just 12 }
  "strum-sust-13" -> pure $ Sustain $ ProtarNote { noteType: Strum, fret: Just 13 }
  "strum-sust-14" -> pure $ Sustain $ ProtarNote { noteType: Strum, fret: Just 14 }
  "strum-sust-15" -> pure $ Sustain $ ProtarNote { noteType: Strum, fret: Just 15 }
  "strum-sust-16" -> pure $ Sustain $ ProtarNote { noteType: Strum, fret: Just 16 }
  "strum-sust-17" -> pure $ Sustain $ ProtarNote { noteType: Strum, fret: Just 17 }
  "strum-sust-18" -> pure $ Sustain $ ProtarNote { noteType: Strum, fret: Just 18 }
  "strum-sust-19" -> pure $ Sustain $ ProtarNote { noteType: Strum, fret: Just 19 }
  "strum-sust-20" -> pure $ Sustain $ ProtarNote { noteType: Strum, fret: Just 20 }
  "strum-sust-21" -> pure $ Sustain $ ProtarNote { noteType: Strum, fret: Just 21 }
  "strum-sust-22" -> pure $ Sustain $ ProtarNote { noteType: Strum, fret: Just 22 }
  "hopo-sust-x" -> pure $ Sustain $ ProtarNote { noteType: HOPO, fret: Nothing }
  "hopo-sust-0" -> pure $ Sustain $ ProtarNote { noteType: HOPO, fret: Just 0 }
  "hopo-sust-1" -> pure $ Sustain $ ProtarNote { noteType: HOPO, fret: Just 1 }
  "hopo-sust-2" -> pure $ Sustain $ ProtarNote { noteType: HOPO, fret: Just 2 }
  "hopo-sust-3" -> pure $ Sustain $ ProtarNote { noteType: HOPO, fret: Just 3 }
  "hopo-sust-4" -> pure $ Sustain $ ProtarNote { noteType: HOPO, fret: Just 4 }
  "hopo-sust-5" -> pure $ Sustain $ ProtarNote { noteType: HOPO, fret: Just 5 }
  "hopo-sust-6" -> pure $ Sustain $ ProtarNote { noteType: HOPO, fret: Just 6 }
  "hopo-sust-7" -> pure $ Sustain $ ProtarNote { noteType: HOPO, fret: Just 7 }
  "hopo-sust-8" -> pure $ Sustain $ ProtarNote { noteType: HOPO, fret: Just 8 }
  "hopo-sust-9" -> pure $ Sustain $ ProtarNote { noteType: HOPO, fret: Just 9 }
  "hopo-sust-10" -> pure $ Sustain $ ProtarNote { noteType: HOPO, fret: Just 10 }
  "hopo-sust-11" -> pure $ Sustain $ ProtarNote { noteType: HOPO, fret: Just 11 }
  "hopo-sust-12" -> pure $ Sustain $ ProtarNote { noteType: HOPO, fret: Just 12 }
  "hopo-sust-13" -> pure $ Sustain $ ProtarNote { noteType: HOPO, fret: Just 13 }
  "hopo-sust-14" -> pure $ Sustain $ ProtarNote { noteType: HOPO, fret: Just 14 }
  "hopo-sust-15" -> pure $ Sustain $ ProtarNote { noteType: HOPO, fret: Just 15 }
  "hopo-sust-16" -> pure $ Sustain $ ProtarNote { noteType: HOPO, fret: Just 16 }
  "hopo-sust-17" -> pure $ Sustain $ ProtarNote { noteType: HOPO, fret: Just 17 }
  "hopo-sust-18" -> pure $ Sustain $ ProtarNote { noteType: HOPO, fret: Just 18 }
  "hopo-sust-19" -> pure $ Sustain $ ProtarNote { noteType: HOPO, fret: Just 19 }
  "hopo-sust-20" -> pure $ Sustain $ ProtarNote { noteType: HOPO, fret: Just 20 }
  "hopo-sust-21" -> pure $ Sustain $ ProtarNote { noteType: HOPO, fret: Just 21 }
  "hopo-sust-22" -> pure $ Sustain $ ProtarNote { noteType: HOPO, fret: Just 22 }
  _ -> throwError $ pure $ TypeMismatch "protar note event" $ show s

isForeignPKNote :: Foreign -> F (Sustainable Unit)
isForeignPKNote f = readString f >>= \s -> case s of
  "end"  -> pure SustainEnd
  "note" -> pure $ Note unit
  "sust" -> pure $ Sustain unit
  _ -> throwError $ pure $ TypeMismatch "pro keys note event" $ show s

isForeignFive :: Foreign -> F Five
isForeignFive f = do
  notes  <- readProp "notes" f
  let readColor s = readProp s notes >>= readTimedMap isForeignFiveNote
  open   <- readColor "open"
  green  <- readColor "green"
  red    <- readColor "red"
  yellow <- readColor "yellow"
  blue   <- readColor "blue"
  orange <- readColor "orange"
  solo   <- readProp "solo" f >>= readTimedMap readBoolean
  energy <- readProp "energy" f >>= readTimedMap readBoolean
  pure $ Five
    { notes:
      { open: open
      , green: green
      , red: red
      , yellow: yellow
      , blue: blue
      , orange: orange
      }
    , solo: solo
    , energy: energy
    }

isForeignSix :: Foreign -> F Six
isForeignSix f = do
  notes  <- readProp "notes" f
  let readLane s = readProp s notes >>= readTimedMap isForeignFiveNote
  open <- readLane "open"
  b1   <- readLane "b1"
  b2   <- readLane "b2"
  b3   <- readLane "b3"
  w1   <- readLane "w1"
  w2   <- readLane "w2"
  w3   <- readLane "w3"
  bw1  <- readLane "bw1"
  bw2  <- readLane "bw2"
  bw3  <- readLane "bw3"
  solo   <- readProp "solo" f >>= readTimedMap readBoolean
  energy <- readProp "energy" f >>= readTimedMap readBoolean
  pure $ Six
    { notes:
      { open: open
      , b1: b1
      , b2: b2
      , b3: b3
      , w1: w1
      , w2: w2
      , w3: w3
      , bw1: bw1
      , bw2: bw2
      , bw3: bw3
      }
    , solo: solo
    , energy: energy
    }

isForeignProtar :: Foreign -> F Protar
isForeignProtar f = do
  notes <- readProp "notes" f
  let readString s = readProp s notes >>= readTimedMap isForeignProtarNote
  s1 <- readString "s1"
  s2 <- readString "s2"
  s3 <- readString "s3"
  s4 <- readString "s4"
  s5 <- readString "s5"
  s6 <- readString "s6"
  solo <- readProp "solo" f >>= readTimedMap readBoolean
  energy <- readProp "energy" f >>= readTimedMap readBoolean
  pure $ Protar
    { notes:
      { s1: s1
      , s2: s2
      , s3: s3
      , s4: s4
      , s5: s5
      , s6: s6
      }
    , solo: solo
    , energy: energy
    }

isForeignProKeys :: Foreign -> F ProKeys
isForeignProKeys f = do
  notes <- readProp "notes" f
  let readPitch p s = map (Tuple p) $ readProp s notes >>= readTimedMap isForeignPKNote
  pitches <- sequence
    [ readPitch RedC "ry-c"
    , readPitch RedCs "ry-cs"
    , readPitch RedD "ry-d"
    , readPitch RedDs "ry-ds"
    , readPitch RedE "ry-e"
    , readPitch YellowF "ry-f"
    , readPitch YellowFs "ry-fs"
    , readPitch YellowG "ry-g"
    , readPitch YellowGs "ry-gs"
    , readPitch YellowA "ry-a"
    , readPitch YellowAs "ry-as"
    , readPitch YellowB "ry-b"
    , readPitch BlueC "bg-c"
    , readPitch BlueCs "bg-cs"
    , readPitch BlueD "bg-d"
    , readPitch BlueDs "bg-ds"
    , readPitch BlueE "bg-e"
    , readPitch GreenF "bg-f"
    , readPitch GreenFs "bg-fs"
    , readPitch GreenG "bg-g"
    , readPitch GreenGs "bg-gs"
    , readPitch GreenA "bg-a"
    , readPitch GreenAs "bg-as"
    , readPitch GreenB "bg-b"
    , readPitch OrangeC "o-c"
    ]
  solo <- readProp "solo" f >>= readTimedMap readBoolean
  energy <- readProp "energy" f >>= readTimedMap readBoolean
  ranges <- readProp "ranges" f >>= readTimedMap isForeignRange
  pure $ ProKeys
    { notes: Map.fromFoldable pitches
    , solo: solo
    , energy: energy
    , ranges: ranges
    }

isForeignFlex :: Foreign -> F Flex
isForeignFlex f = do
  five <- readProp "five" f >>= readNullOrUndefined >>= traverse isForeignFive
  six <- readProp "six" f >>= readNullOrUndefined >>= traverse isForeignSix
  drums <- readProp "drums" f >>= readNullOrUndefined >>= traverse isForeignDrums
  prokeys <- readProp "prokeys" f >>= readNullOrUndefined >>= traverse isForeignProKeys
  protar <- readProp "protar" f >>= readNullOrUndefined >>= traverse isForeignProtar
  vocal <- readProp "vocal" f >>= readNullOrUndefined >>= traverse isForeignVocal
  pure $ Flex
    { five: five
    , six: six
    , drums: drums
    , prokeys: prokeys
    , protar: protar
    , vocal: vocal
    }

isForeignSong :: Foreign -> F Song
isForeignSong f = do
  end <- readProp "end" f >>= readNumber
  beats <- readProp "beats" f >>= isForeignBeats
  parts <- readProp "parts" f >>= readArray >>= traverse \pair ->
    Tuple <$> (readIndex 0 pair >>= readString) <*> (readIndex 1 pair >>= isForeignFlex)
  pure $ Song
    { end: Seconds end
    , beats: beats
    , parts: parts
    }

readTimedSet :: Foreign -> F (Map.Map Seconds Unit)
readTimedSet f = map (map $ \(_ :: Foreign) -> unit) $ readTimedMap pure f

readTimedMap :: forall a. (Foreign -> F a) -> Foreign -> F (Map.Map Seconds a)
readTimedMap g f = Map.fromFoldable <$> (readArray f >>= traverse (readTimedPair g))

readTimedPair :: forall a. (Foreign -> F a) -> Foreign -> F (Tuple Seconds a)
readTimedPair g pair = Tuple <$> (Seconds <$> (readIndex 0 pair >>= readNumber)) <*> (readIndex 1 pair >>= g)

isForeignDrums :: Foreign -> F Drums
isForeignDrums f = do
  notes  <- readProp "notes"  f >>= readTimedMap (\frn -> readArray frn >>= traverse isForeignGem)
  solo   <- readProp "solo"   f >>= readTimedMap readBoolean
  energy <- readProp "energy" f >>= readTimedMap readBoolean
  pure $ Drums { notes: notes, solo: solo, energy: energy }

data Gem = Kick | Red | YCym | YTom | BCym | BTom | GCym | GTom

isForeignGem :: Foreign -> F Gem
isForeignGem f = readString f >>= \s -> case s of
  "kick"  -> pure Kick
  "red"   -> pure Red
  "y-cym" -> pure YCym
  "y-tom" -> pure YTom
  "b-cym" -> pure BCym
  "b-tom" -> pure BTom
  "g-cym" -> pure GCym
  "g-tom" -> pure GTom
  _ -> throwError $ pure $ TypeMismatch "drum gem name" $ show s

derive instance genGem :: Generic Gem
instance showGem :: Show Gem where
  show = gShow
instance eqGem :: Eq Gem where
  eq = gEq
instance ordGem :: Ord Gem where
  compare = gCompare

newtype Beats = Beats
  { lines :: Map.Map Seconds Beat
  }

isForeignBeats :: Foreign -> F Beats
isForeignBeats f = do
  lines <- readProp "lines"  f >>= readTimedMap isForeignBeat
  pure $ Beats { lines: lines }

data Beat
  = Bar
  | Beat
  | HalfBeat

isForeignBeat :: Foreign -> F Beat
isForeignBeat f = readString f >>= \s -> case s of
  "bar"      -> pure Bar
  "beat"     -> pure Beat
  "halfbeat" -> pure HalfBeat
  _          -> throwError $ pure $ TypeMismatch "bar/beat/halfbeat" $ show s

instance showBeat :: Show Beat where
  show g = case g of
    Bar      -> "Bar"
    Beat     -> "Beat"
    HalfBeat -> "HalfBeat"

data Vocal = Vocal
  { harm1 :: Map.Map Seconds VocalNote
  , harm2 :: Map.Map Seconds VocalNote
  , harm3 :: Map.Map Seconds VocalNote
  , percussion :: Map.Map Seconds Unit
  , phrases :: Map.Map Seconds Unit
  , ranges :: Map.Map Seconds VocalRange
  , energy :: Map.Map Seconds Boolean
  , tonic :: Maybe Int
  }

isForeignVocal :: Foreign -> F Vocal
isForeignVocal f = do
  harm1 <- readProp "harm1"  f >>= readTimedMap isForeignVocalNote
  harm2 <- readProp "harm2"  f >>= readTimedMap isForeignVocalNote
  harm3 <- readProp "harm3"  f >>= readTimedMap isForeignVocalNote
  energy <- readProp "energy" f >>= readTimedMap readBoolean
  ranges <- readProp "ranges" f >>= readTimedMap isForeignVocalRange
  tonic <- readProp "tonic" f >>= readNullOrUndefined >>= traverse readInt
  percussion <- readProp "percussion" f >>= readTimedSet
  phrases <- readProp "phrases" f >>= readTimedSet
  pure $ Vocal { harm1: harm1, harm2: harm2, harm3: harm3, energy: energy, ranges: ranges, tonic: tonic, percussion: percussion, phrases: phrases }

data VocalRange
  = VocalRangeShift    -- ^ Start of a range shift
  | VocalRange Int Int -- ^ The starting range, or the end of a range shift

isForeignVocalRange :: Foreign -> F VocalRange
isForeignVocalRange f = if isNull f
  then pure VocalRangeShift
  else VocalRange <$> (readIndex 0 f >>= readInt) <*> (readIndex 1 f >>= readInt)

data VocalNote
  = VocalStart String (Maybe Int)
  | VocalEnd

isForeignVocalNote :: Foreign -> F VocalNote
isForeignVocalNote f = if isNull f
  then pure VocalEnd
  else do
    lyric <- readIndex 0 f >>= readString
    pitch <- readIndex 1 f >>= readNullOrUndefined >>= traverse readInt
    pure $ VocalStart lyric pitch
