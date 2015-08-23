{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE LambdaCase        #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards   #-}
{-# LANGUAGE DeriveFunctor     #-}
{-# LANGUAGE DeriveFoldable    #-}
{-# LANGUAGE DeriveTraversable #-}
module Config where

import           Control.Applicative        ((<|>))
import           Control.Monad.Trans.Class  (lift)
import           Control.Monad.Trans.Reader
import qualified Data.Aeson                 as A
import qualified Data.ByteString.Lazy.Char8 as BL8
import           Data.Char                  (isDigit)
import           Data.Conduit.Audio         (Duration (..))
import qualified Data.HashMap.Strict        as Map
import           Data.List                  ((\\))
import           Data.Maybe                 (fromMaybe)
import           Data.Scientific            (Scientific, toBoundedInteger,
                                             toRealFloat)
import qualified Data.Text                  as T
import           Data.Traversable
import qualified Data.Vector                as V
import qualified Sound.Jammit.Base          as J
import           StackTrace                 hiding (optional)
import           Text.Read                  (readMaybe)

type Parser context = StackTraceT (Reader context)

crash :: String -> Parser A.Value a
crash msg = lift ask >>= \v -> fatal $ msg ++ ": " ++ BL8.unpack (A.encode v)

class TraceJSON a where
  traceJSON :: Parser A.Value a

instance TraceJSON A.Value where
  traceJSON = lift ask

instance TraceJSON T.Text where
  traceJSON = lift ask >>= \case
    A.String s -> return s
    _          -> crash "Expected a string, but found"

instance TraceJSON String where
  traceJSON = fmap T.unpack traceJSON

instance TraceJSON Scientific where
  traceJSON = lift ask >>= \case
    A.Number n -> return n
    _          -> crash "Expected a number, but found"

instance TraceJSON Integer where
  traceJSON = fmap (round :: Scientific -> Integer) traceJSON

instance TraceJSON Double where
  traceJSON = fmap toRealFloat traceJSON

instance TraceJSON Int where
  traceJSON = traceJSON >>= \n -> case toBoundedInteger n of
    Nothing -> crash "Number doesn't fit into Int range"
    Just i  -> return i

parseFrom :: v -> Parser v a -> Parser v' a
parseFrom = mapStackTraceT . withReaderT . const

object :: Parser (Map.HashMap T.Text A.Value) a -> Parser A.Value a
object p = lift ask >>= \case
  A.Object o -> parseFrom o p
  _          -> crash "Expected an object, but found"

required :: T.Text -> Parser A.Value a -> Parser (Map.HashMap T.Text A.Value) a
required k p = lift ask >>= \hm -> case Map.lookup k hm of
  Nothing -> parseFrom (A.Object hm) $
    crash $ "Couldn't find required key " ++ show k ++ " in object"
  Just v  -> inside ("required key " ++ T.unpack k) $ parseFrom v p

optional :: T.Text -> Parser A.Value a -> Parser (Map.HashMap T.Text A.Value) (Maybe a)
optional k p = lift ask >>= \hm -> case Map.lookup k hm of
  Nothing -> return Nothing
  Just v  -> fmap Just $ inside ("optional key " ++ T.unpack k) $ parseFrom v p

theKey :: T.Text -> Parser A.Value a -> Parser (Map.HashMap T.Text A.Value) a
theKey k p = lift ask >>= \hm -> case Map.toList hm of
  [(k', v)] | k == k' -> inside ("only key " ++ T.unpack k) $ parseFrom v p
  _ -> parseFrom (A.Object hm) $
    crash $ "Expected an object with only key " ++ show k ++ ", but found"

expectedKeys :: [T.Text] -> Parser (Map.HashMap T.Text A.Value) ()
expectedKeys keys = do
  hm <- lift ask
  case Map.keys hm \\ keys of
    []    -> return ()
    unrec -> warn $ "Unrecognized object keys: " ++ show unrec

data Instrument = Guitar | Bass | Drums | Keys | Vocal
  deriving (Eq, Ord, Show, Read, Enum, Bounded)

jammitInstrument :: Instrument -> J.Instrument
jammitInstrument = \case
  Guitar -> J.Guitar
  Bass   -> J.Bass
  Drums  -> J.Drums
  Keys   -> J.Keyboard
  Vocal  -> J.Vocal

instance TraceJSON Instrument where
  traceJSON = (traceJSON :: Parser A.Value String) >>= \case
    "guitar" -> return Guitar
    "bass"   -> return Bass
    "drums"  -> return Drums
    "keys"   -> return Keys
    "vocal"  -> return Vocal
    _        -> crash "Invalid instrument string"

data SongYaml = SongYaml
  { _metadata :: Metadata
  , _audio    :: Map.HashMap T.Text AudioFile
  , _jammit   :: Map.HashMap T.Text JammitTrack
  , _plans    :: Map.HashMap T.Text Plan
  } deriving (Eq, Show, Read)

mapping :: Parser A.Value a -> Parser A.Value (Map.HashMap T.Text a)
mapping p = lift ask >>= \case
  A.Object o -> mapM (\x -> parseFrom x p) o
  _          -> crash "Expected object, but found"

list :: Parser A.Value a -> Parser A.Value [a]
list p = lift ask >>= \case
  A.Array v -> forM (zip [0..] $ V.toList v) $ \(i, x) ->
    inside ("element " ++ show (i :: Int)) $ parseFrom x p
  _         -> crash "Expected array, but found"

instance TraceJSON SongYaml where
  traceJSON = object $ do
    let defaultEmptyMap = fmap $ fromMaybe Map.empty
    _metadata <- required "metadata" traceJSON
    _audio    <- defaultEmptyMap $ optional "audio"  $ mapping traceJSON
    _jammit   <- defaultEmptyMap $ optional "jammit" $ mapping traceJSON
    _plans    <- defaultEmptyMap $ optional "plans"  $ mapping traceJSON
    expectedKeys ["metadata", "audio", "jammit", "plans"]
    return SongYaml{..}

data Metadata = Metadata
  { _title        :: T.Text
  , _artist       :: T.Text
  , _album        :: T.Text
  , _genre        :: T.Text
  , _subgenre     :: T.Text
  , _year         :: Int
  , _fileAlbumArt :: FilePath
  , _trackNumber  :: Int
  } deriving (Eq, Ord, Show, Read)

instance TraceJSON Metadata where
  traceJSON = object $ do
    _title        <- required "title"          traceJSON
    _artist       <- required "artist"         traceJSON
    _album        <- required "album"          traceJSON
    _genre        <- required "genre"          traceJSON
    _subgenre     <- required "subgenre"       traceJSON
    _year         <- required "year"           traceJSON
    _fileAlbumArt <- required "file-album-art" traceJSON
    _trackNumber  <- required "track-number"   traceJSON
    expectedKeys ["title", "artist", "album", "genre", "subgenre", "year", "file-album-art", "track-number"]
    return Metadata{..}

data AudioFile = AudioFile
  { _md5    :: Maybe T.Text
  , _frames :: Maybe Integer
  , _name   :: Maybe FilePath
  , _rate   :: Maybe Int
  } deriving (Eq, Ord, Show, Read)

instance TraceJSON AudioFile where
  traceJSON = object $ do
    _md5    <- optional "md5"    traceJSON
    _frames <- optional "frames" traceJSON
    _name   <- optional "name"   traceJSON
    _rate   <- optional "rate"   traceJSON
    expectedKeys ["md5", "frames", "name", "rate"]
    return AudioFile{..}

data JammitTrack = JammitTrack
  { _jammitTitle  :: Maybe T.Text
  , _jammitArtist :: Maybe T.Text
  } deriving (Eq, Ord, Show, Read)

instance TraceJSON JammitTrack where
  traceJSON = object $ do
    _jammitTitle  <- optional "title"  traceJSON
    _jammitArtist <- optional "artist" traceJSON
    expectedKeys ["title", "artist"]
    return JammitTrack{..}

data Plan
  = Plan
    { _song   :: Audio Duration AudioInput
    , _guitar :: Audio Duration AudioInput
    , _bass   :: Audio Duration AudioInput
    , _keys   :: Audio Duration AudioInput
    , _drums  :: Audio Duration AudioInput
    , _vocal  :: Audio Duration AudioInput
    }
  | EachPlan
    { _each :: Audio Duration T.Text
    }
  deriving (Eq, Ord, Show, Read)

instance TraceJSON Plan where
  traceJSON = object
    $   do
      _each <- required "each" traceJSON
      expectedKeys ["each"]
      return EachPlan{..}
    <|> do
      let defaultSilence = fromMaybe $ Silence 1 $ Seconds 1
      _song   <- defaultSilence <$> optional "song"   traceJSON
      _guitar <- defaultSilence <$> optional "guitar" traceJSON
      _bass   <- defaultSilence <$> optional "bass"   traceJSON
      _keys   <- defaultSilence <$> optional "keys"   traceJSON
      _drums  <- defaultSilence <$> optional "drums"  traceJSON
      _vocal  <- defaultSilence <$> optional "vocal"  traceJSON
      expectedKeys ["song", "guitar", "bass", "keys", "drums", "vocal"]
      return Plan{..}

data AudioInput
  = Named T.Text
  | JammitSelect J.AudioPart T.Text
  deriving (Eq, Ord, Show, Read)

instance TraceJSON AudioInput where
  traceJSON
    =   do
      Named <$> traceJSON
    <|> do
      algebraic2 "only"
        (\part str -> JammitSelect (J.Only part) str)
        (traceJSON >>= \title -> case J.titleToPart title of
          Just part -> return part
          Nothing   -> crash "Unrecognized Jammit part name"
          )
        traceJSON
    <|> do
      algebraic2 "without"
        (\inst str -> JammitSelect (J.Without $ jammitInstrument inst) str)
        traceJSON
        traceJSON

data Audio t a
  = Silence Int t
  | Input a
  | Mix            [Audio t a]
  | Merge          [Audio t a]
  | Concatenate    [Audio t a]
  | Gain Double    (Audio t a)
  | Take Edge t    (Audio t a)
  | Drop Edge t    (Audio t a)
  | Fade Edge t    (Audio t a)
  | Pad  Edge t    (Audio t a)
  | Resample       (Audio t a)
  | Channels [Int] (Audio t a)
  deriving (Eq, Ord, Show, Read, Functor, Foldable, Traversable)

data Edge = Start | End
  deriving (Eq, Ord, Show, Read, Enum, Bounded)

instance TraceJSON Edge where
  traceJSON = (traceJSON :: Parser A.Value String) >>= \case
    "start" -> return Start
    "begin" -> return Start
    "end"   -> return End
    _       -> crash "Invalid audio edge"

mapTime :: (t -> u) -> Audio t a -> Audio u a
mapTime f aud = case aud of
  Silence c t     -> Silence c $ f t
  Input   x       -> Input x
  Mix         xs  -> Mix         $ map (mapTime f) xs
  Merge       xs  -> Merge       $ map (mapTime f) xs
  Concatenate xs  -> Concatenate $ map (mapTime f) xs
  Gain g x        -> Gain g $ mapTime f x
  Take e t x      -> Take e (f t) $ mapTime f x
  Drop e t x      -> Drop e (f t) $ mapTime f x
  Fade e t x      -> Fade e (f t) $ mapTime f x
  Pad  e t x      -> Pad  e (f t) $ mapTime f x
  Resample x      -> Resample     $ mapTime f x
  Channels cs x   -> Channels cs  $ mapTime f x

algebraic1 :: T.Text -> (a -> b) -> Parser A.Value a -> Parser A.Value b
algebraic1 k f p1 = object $ theKey k $ lift ask >>= \case
  A.Array v -> case V.toList v of
    [x] -> fmap f $ inside "ADT field 1 of 1" $ parseFrom x p1
    _ -> crash "Expected array of 1 ADT field, but found"
  _ -> crash "Expected array of 1 ADT field, but found"

algebraic2 :: T.Text -> (a -> b -> c) ->
  Parser A.Value a -> Parser A.Value b -> Parser A.Value c
algebraic2 k f p1 p2 = object $ theKey k $ lift ask >>= \case
  A.Array v -> case V.toList v of
    [x, y] -> f
      <$> do inside "ADT field 1 of 2" $ parseFrom x p1
      <*> do inside "ADT field 2 of 2" $ parseFrom y p2
    _ -> crash "Expected array of 2 ADT fields, but found"
  _ -> crash "Expected array of 2 ADT fields, but found"

algebraic3 :: T.Text -> (a -> b -> c -> d) ->
  Parser A.Value a -> Parser A.Value b -> Parser A.Value c -> Parser A.Value d
algebraic3 k f p1 p2 p3 = object $ theKey k $ lift ask >>= \case
  A.Array v -> case V.toList v of
    [x, y, z] -> f
      <$> do inside "ADT field 1 of 3" $ parseFrom x p1
      <*> do inside "ADT field 2 of 3" $ parseFrom y p2
      <*> do inside "ADT field 3 of 3" $ parseFrom z p3
    _ -> crash "Expected array of 3 ADT fields, but found"
  _ -> crash "Expected array of 3 ADT fields, but found"

instance (TraceJSON t, TraceJSON a) => TraceJSON (Audio t a) where
  traceJSON
    =   do algebraic2 "silence" Silence traceJSON traceJSON
    <|> do object $ theKey "mix"         $ Mix         <$> list traceJSON
    <|> do object $ theKey "merge"       $ Merge       <$> list traceJSON
    <|> do object $ theKey "concatenate" $ Concatenate <$> list traceJSON
    <|> do algebraic2 "gain" Gain traceJSON traceJSON
    <|> do supplyEdge "take" Take
    <|> do supplyEdge "drop" Drop
    <|> do supplyEdge "fade" Fade
    <|> do supplyEdge "pad"  Pad
    <|> do algebraic1 "resample" Resample traceJSON
    <|> do algebraic2 "channels" Channels (list traceJSON) traceJSON
    <|> do Input <$> traceJSON
    where supplyEdge s f
            =   do algebraic2 s (f Start   ) traceJSON traceJSON
            <|> do algebraic3 s  f traceJSON traceJSON traceJSON

instance TraceJSON Duration where
  traceJSON
    =   do
      object $ theKey "frames" $ Frames <$> traceJSON
    <|> do
      object $ theKey "seconds" $ Seconds <$> parseMinutes
    <|> do
      Seconds <$> parseMinutes
    where parseMinutes = do
            v <- lift ask
            case v of
              A.String minstr
                | (minutes@(_:_), ':' : secstr) <- span isDigit $ T.unpack minstr
                , Just seconds <- readMaybe secstr
                -> return $ read minutes * 60 + seconds
              A.String secstr
                | Just seconds <- readMaybe $ T.unpack secstr
                -> return seconds
              _ -> traceJSON -- will succeed if JSON number
