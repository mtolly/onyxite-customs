module Main where

import Prelude
import Data.Maybe
import Data.Maybe.Unsafe
import Data.Traversable
import Control.Monad.Eff
import Graphics.Canvas
import DOM
import Data.DOM.Simple.Window
import Control.Monad.Eff.Console
import Data.Foreign
import Data.Foreign.Class
import Data.Foreign.NullOrUndefined
import Data.Either
import qualified Data.Map as Map
import Data.Tuple

foreign import onyxData :: Foreign

newtype Song = Song
  { end   :: Number
  , drums :: Maybe Drums
  }

newtype Drums = Drums
  { notes  :: Map.Map Number (Array Gem)
  , solo   :: Map.Map Number Boolean
  , energy :: Map.Map Number Boolean
  }

instance isForeignSong :: IsForeign Song where
  read f = do
    end <- readProp "end" f
    NullOrUndefined drums <- readProp "drums" f
    return $ Song { end: end, drums: drums }

readMap :: forall a b. (Ord a, IsForeign a, IsForeign b) => Foreign -> F (Map.Map a b)
readMap f = Map.fromFoldable <$> (readArray f >>= traverse readPair)

readPair :: forall a b. (IsForeign a, IsForeign b) => Foreign -> F (Tuple a b)
readPair pair = Tuple <$> readProp 0 pair <*> readProp 1 pair

instance isForeignDrums :: IsForeign Drums where
  read f = do
    notes  <- readProp "notes"  f >>= readMap
    solo   <- readProp "solo"   f >>= readMap
    energy <- readProp "energy" f >>= readMap
    return $ Drums { notes: notes, solo: solo, energy: energy }

data Gem = Kick | Red | YCym | YTom | BCym | BTom | GCym | GTom

instance isForeignGem :: IsForeign Gem where
  read f = read f >>= \s -> case s of
    "kick"  -> return Kick
    "red"   -> return Red
    "y-cym" -> return YCym
    "y-tom" -> return YTom
    "b-cym" -> return BCym
    "b-tom" -> return BTom
    "g-cym" -> return GCym
    "g-tom" -> return GTom
    _ -> Left $ TypeMismatch "drum gem name" $ show s

instance showGem :: Show Gem where
  show g = case g of
    Kick -> "Kick"
    Red  -> "Red"
    YCym -> "YCym"
    YTom -> "YTom"
    BCym -> "BCym"
    BTom -> "BTom"
    GCym -> "GCym"
    GTom -> "GTom"

main :: Eff (canvas :: Canvas, dom :: DOM, console :: CONSOLE) Unit
main = do
  c   <- fromJust <$> getCanvasElementById "the-canvas"
  ctx <- getContext2D c
  let draw = do
        w <- innerWidth globalWindow
        h <- innerHeight globalWindow
        setCanvasWidth  w c
        setCanvasHeight h c
        void $ setFillStyle "rgb(54,59,123)" ctx
        void $ fillRect ctx { x: 0.0, y: 0.0, w: w, h: h }
  draw
  case read onyxData of
    Right (Song s) -> case s.drums of
      Just (Drums d) -> log $ show d.notes
      Nothing -> return unit
    Left _ -> return unit
