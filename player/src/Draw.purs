module Draw (Settings(), App(..), DrawStuff(), draw, _M, _B, getWindowDims) where

import Prelude
import qualified Graphics.Canvas as C
import Data.Time
import Images
import Control.Monad.Reader.Trans
import Control.Monad.Eff
import Data.Int (toNumber, round)
import DOM
import qualified OnyxMap as Map
import Data.Maybe
import Data.Array (uncons, cons, snoc, take, zip, (..), length, concat)
import qualified Data.List as L
import Data.Tuple
import Control.Monad (when)
import Control.Monad.Eff.Exception.Unsafe (unsafeThrow)
import Data.Ord (min, max)
import Data.Foldable (elem, sum, for_)
import Control.Apply ((*>))
import Control.MonadPlus (guard)
import qualified Data.String.Regex as R
import Math (pi)

import Song

foreign import getWindowDims :: forall e. Eff (dom :: DOM | e) {w :: Number, h :: Number}

type Settings =
  { seeGuitar  :: Boolean
  , seeBass    :: Boolean
  , seeKeys    :: Boolean
  , seeProKeys :: Boolean
  , seeDrums   :: Boolean
  , seeVocal   :: Boolean
  }

data App
  = Paused
    { pausedSongTime :: Seconds
    , settings :: Settings
    }
  | Playing
    { startedPageTime :: Seconds
    , startedSongTime :: Seconds
    , settings :: Settings
    }

type DrawStuff =
  { time :: Seconds
  , app :: App
  , song :: Song
  , getImage :: ImageID -> C.CanvasImageSource
  , canvas :: C.CanvasElement
  , context :: C.Context2D
  , pxToSecsVert :: Int -> Seconds -- pixels from bottom -> now-offset in seconds
  , secsToPxVert :: Seconds -> Int -- now-offset in seconds -> pixels from bottom
  , pxToSecsHoriz :: Int -> Seconds -- pixels from left -> now-offset in seconds
  , secsToPxHoriz :: Seconds -> Int -- now-offset in seconds -> pixels from left
  }

type Draw e = ReaderT DrawStuff (Eff (canvas :: C.Canvas | e))

askStuff :: forall e. Draw e DrawStuff
askStuff = ask

setFillStyle :: forall e. String -> Draw e Unit
setFillStyle s = onContext $ C.setFillStyle s

fillRect :: forall e. C.Rectangle -> Draw e Unit
fillRect rect = onContext $ \ctx -> C.fillRect ctx rect

fillCircle :: forall e. { x :: Number, y :: Number, r :: Number } -> Draw e Unit
fillCircle o = do
  ctx <- map _.context ask
  lift $ void do
    C.beginPath ctx
    C.arc ctx { x: o.x, y: o.y, r: o.r, start: 0.0, end: 2.0 * pi }
    C.fill ctx
    C.closePath ctx

drawImage :: forall e. ImageID -> Number -> Number -> Draw e Unit
drawImage iid x y = do
  img <- map _.getImage ask
  onContext $ \ctx -> C.drawImage ctx (img iid) x y

onContext :: forall e. (C.Context2D -> Eff (canvas :: C.Canvas | e) C.Context2D) -> Draw e Unit
onContext act = map _.context ask >>= act >>> void >>> lift

measureText :: forall e. String -> Draw e C.TextMetrics
measureText str = map _.context ask >>= \ctx -> lift $ C.measureText ctx str

draw :: forall e. Draw (dom :: DOM | e) Unit
draw = do
  stuff <- ask
  {w: windowW, h: windowH} <- lift getWindowDims
  lift $ C.setCanvasWidth  windowW stuff.canvas
  lift $ C.setCanvasHeight windowH stuff.canvas
  setFillStyle "rgb(54,59,123)"
  fillRect { x: 0.0, y: 0.0, w: windowW, h: windowH }
  -- Draw the visible instrument tracks in sequence
  let drawTracks targetX trks = case uncons trks of
        Nothing -> return unit
        Just {head: trk, tail: trkt} -> do
          drawResult <- trk targetX
          case drawResult of
            Just targetX' -> drawTracks targetX' trkt
            Nothing       -> drawTracks targetX  trkt
  drawTracks (_M + _B + _M + _B + _M)
    [ drawPart (\(Song o) -> o.guitar ) _.seeGuitar  drawFive
    , drawPart (\(Song o) -> o.bass   ) _.seeBass    drawFive
    , drawPart (\(Song o) -> o.drums  ) _.seeDrums   drawDrums
    , drawPart (\(Song o) -> o.keys   ) _.seeKeys    drawFive
    , drawPart (\(Song o) -> o.prokeys) _.seeProKeys drawProKeys
    ]
  void $ drawPart (\(Song o) -> o.vocal) _.seeVocal drawVocal 0
  let drawButtons _ L.Nil             = return unit
      drawButtons y (L.Cons iid iids) = do
        drawImage iid (toNumber $ _M + _B + _M) (toNumber y)
        drawButtons (y - _M - _B) iids
      song = case stuff.song of Song s -> s
      settings = case stuff.app of
        Paused  o -> o.settings
        Playing o -> o.settings
  drawButtons (round windowH - _M - _B) $ L.fromFoldable $ concat
    [ guard (isJust song.prokeys) *> [ if settings.seeProKeys then Image_button_prokeys else Image_button_prokeys_off ]
    , guard (isJust song.keys   ) *> [ if settings.seeKeys    then Image_button_keys    else Image_button_keys_off    ]
    , guard (isJust song.vocal  ) *> [ if settings.seeVocal   then Image_button_vocal   else Image_button_vocal_off   ]
    , guard (isJust song.drums  ) *> [ if settings.seeDrums   then Image_button_drums   else Image_button_drums_off   ]
    , guard (isJust song.bass   ) *> [ if settings.seeBass    then Image_button_bass    else Image_button_bass_off    ]
    , guard (isJust song.guitar ) *> [ if settings.seeGuitar  then Image_button_guitar  else Image_button_guitar_off  ]
    ]
  let playPause = case stuff.app of
        Paused  _ -> Image_button_play
        Playing _ -> Image_button_pause
  drawImage playPause (toNumber _M) (windowH - toNumber _M - toNumber _B)
  let timelineH = windowH - 3.0 * toNumber _M - toNumber _B - 2.0
      filled = case stuff.time / (case stuff.song of Song o -> o.end) of
        Seconds n -> n
  setFillStyle "black"
  fillRect { x: toNumber _M, y: toNumber _M, w: toNumber _B, h: timelineH + 2.0 }
  setFillStyle "white"
  fillRect { x: toNumber _M + 1.0, y: toNumber _M + 1.0, w: toNumber _B - 2.0, h: timelineH }
  setFillStyle "rgb(100,130,255)"
  fillRect
    { x: toNumber _M + 1.0
    , y: toNumber _M + 1.0 + timelineH * (1.0 - filled)
    , w: toNumber _B - 2.0
    , h: timelineH * filled
    }

-- | Height/width of margins
_M :: Int
_M = 20

-- | Height/width of buttons
_B :: Int
_B = 41

drawPart
  :: forall e a r
  .  (Song -> Maybe a)
  -> (Settings -> Boolean)
  -> (a -> Int -> Draw e r)
  -> Int
  -> Draw e (Maybe r)
drawPart getPart see drawIt targetX = do
  stuff <- askStuff
  let settings = case stuff.app of
        Paused  o -> o.settings
        Playing o -> o.settings
  case getPart stuff.song of
    Just part | see settings -> map Just $ drawIt part targetX
    _                        -> return Nothing

drawFive :: forall e. Five -> Int -> Draw e Int
drawFive (Five five) targetX = do
  stuff <- askStuff
  windowH <- map round $ lift $ C.getCanvasHeight stuff.canvas
  let pxToSecsVert px = stuff.pxToSecsVert (windowH - px) + stuff.time
      secsToPxVert secs = windowH - stuff.secsToPxVert (secs - stuff.time)
      maxSecs = pxToSecsVert (-100)
      minSecs = pxToSecsVert $ windowH + 100
      zoomDesc :: forall v m. (Monad m) => Map.Map Seconds v -> (Seconds -> v -> m Unit) -> m Unit
      zoomDesc = Map.zoomDescDo minSecs maxSecs
      zoomAsc :: forall v m. (Monad m) => Map.Map Seconds v -> (Seconds -> v -> m Unit) -> m Unit
      zoomAsc = Map.zoomAscDo minSecs maxSecs
      targetY = secsToPxVert stuff.time
  -- Highway
  setFillStyle "rgb(126,126,150)"
  fillRect { x: toNumber targetX, y: 0.0, w: 182.0, h: toNumber windowH }
  setFillStyle "rgb(184,185,204)"
  for_ [0, 36, 72, 108, 144, 180] $ \offsetX -> do
    fillRect { x: toNumber $ targetX + offsetX, y: 0.0, w: 1.0, h: toNumber windowH }
  setFillStyle "black"
  for_ [1, 37, 73, 109, 145, 181] $ \offsetX -> do
    fillRect { x: toNumber $ targetX + offsetX, y: 0.0, w: 1.0, h: toNumber windowH }
  -- Solo highway
  setFillStyle "rgb(91,137,185)"
  let startsAsSolo = case Map.lookupLE minSecs five.solo of
        Nothing           -> false
        Just { value: v } -> v
      soloEdges
        = L.fromFoldable
        $ cons (Tuple minSecs startsAsSolo)
        $ flip snoc (Tuple maxSecs false)
        $ Map.doTupleArray (zoomAsc five.solo)
      drawSolos L.Nil            = return unit
      drawSolos (L.Cons _ L.Nil) = return unit
      drawSolos (L.Cons (Tuple s1 b1) rest@(L.Cons (Tuple s2 _) _)) = do
        let y1 = secsToPxVert s1
            y2 = secsToPxVert s2
        when b1 $ for_ [2, 38, 74, 110, 146] $ \offsetX -> do
          fillRect { x: toNumber $ targetX + offsetX, y: toNumber y2, w: 34.0, h: toNumber $ y1 - y2 }
        drawSolos rest
  drawSolos soloEdges
  -- Solo edges
  zoomDesc five.solo $ \secs _ -> do
    drawImage Image_highway_grybo_solo_edge (toNumber targetX) (toNumber $ secsToPxVert secs)
  -- Beats
  zoomDesc (case stuff.song of Song o -> case o.beats of Beats o' -> o'.lines) $ \secs evt -> do
    let y = secsToPxVert secs
    case evt of
      Bar      -> drawImage Image_highway_grybo_bar      (toNumber targetX) (toNumber y - 1.0)
      Beat     -> drawImage Image_highway_grybo_beat     (toNumber targetX) (toNumber y - 1.0)
      HalfBeat -> drawImage Image_highway_grybo_halfbeat (toNumber targetX) (toNumber y)
  -- Target
  drawImage Image_highway_grybo_target (toNumber targetX) (toNumber targetY - 5.0)
  -- Sustains
  let colors =
        [ { c: _.green , x: 1  , strum: Image_gem_green , hopo: Image_gem_green_hopo 
          , shades: { light: "rgb(135,247,126)", normal: "rgb( 21,218,  2)", dark: "rgb( 13,140,  2)" }
          , hit: \o -> "rgba(190,255,192," <> show o <> ")"
          }
        , { c: _.red   , x: 37 , strum: Image_gem_red   , hopo: Image_gem_red_hopo   
          , shades: { light: "rgb(247,127,158)", normal: "rgb(218,  2, 62)", dark: "rgb(140,  2, 40)" }
          , hit: \o -> "rgba(255,188,188," <> show o <> ")"
          }
        , { c: _.yellow, x: 73 , strum: Image_gem_yellow, hopo: Image_gem_yellow_hopo
          , shades: { light: "rgb(247,228,127)", normal: "rgb(218,180,  2)", dark: "rgb(140,115,  3)" }
          , hit: \o -> "rgba(255,244,151," <> show o <> ")"
          }
        , { c: _.blue  , x: 109, strum: Image_gem_blue  , hopo: Image_gem_blue_hopo  
          , shades: { light: "rgb(119,189,255)", normal: "rgb(  2,117,218)", dark: "rgb(  3, 76,140)" }
          , hit: \o -> "rgba(190,198,255," <> show o <> ")"
          }
        , { c: _.orange, x: 145, strum: Image_gem_orange, hopo: Image_gem_orange_hopo
          , shades: { light: "rgb(255,183,119)", normal: "rgb(218, 97,  4)", dark: "rgb(140, 63,  3)" }
          , hit: \o -> "rgba(231,196,112," <> show o <> ")"
          }
        ]
  for_ colors $ \{ c: getColor, x: offsetX, shades: normalShades } -> do
    let thisColor = getColor five.notes
        isEnergy secs = case Map.lookupLE secs five.energy of
          Nothing           -> false
          Just { value: v } -> v
        drawSustainBlock ystart yend energy = when (ystart < targetY || yend < targetY) do
          let ystart' = min ystart targetY
              yend'   = min yend   targetY
              sustaining = targetY < ystart || targetY < yend
              shades = if energy
                then { light: "rgb(137,235,204)", normal: "rgb(138,192,175)", dark: "rgb(124,158,149)" }
                else normalShades
              h = yend' - ystart' + 1
          setFillStyle "black"
          fillRect { x: toNumber $ targetX + offsetX + 14, y: toNumber ystart', w: 1.0, h: toNumber h }
          fillRect { x: toNumber $ targetX + offsetX + 22, y: toNumber ystart', w: 1.0, h: toNumber h }
          setFillStyle shades.light
          fillRect { x: toNumber $ targetX + offsetX + 15, y: toNumber ystart', w: 1.0, h: toNumber h }
          setFillStyle shades.normal
          fillRect { x: toNumber $ targetX + offsetX + 16, y: toNumber ystart', w: 5.0, h: toNumber h }
          setFillStyle shades.dark
          fillRect { x: toNumber $ targetX + offsetX + 21, y: toNumber ystart', w: 1.0, h: toNumber h }
          when sustaining do
            setFillStyle shades.light
            fillRect { x: toNumber $ targetX + offsetX + 1, y: toNumber $ targetY - 4, w: 35.0, h: 8.0 }
        go false (L.Cons (Tuple secsEnd SustainEnd) rest) = case Map.lookupLT secsEnd thisColor of
          Just { key: secsStart, value: Sustain _ } -> do
            drawSustainBlock (secsToPxVert secsEnd) windowH $ isEnergy secsStart
            go false rest
          _ -> unsafeThrow "during grybo drawing: found a sustain end not preceded by sustain start"
        go true (L.Cons (Tuple _ SustainEnd) rest) = go false rest
        go _ (L.Cons (Tuple _ (Note _)) rest) = go false rest
        go _ (L.Cons (Tuple secsStart (Sustain _)) rest) = do
          let pxEnd = case rest of
                L.Nil                      -> 0
                L.Cons (Tuple secsEnd _) _ -> secsToPxVert secsEnd
          drawSustainBlock pxEnd (secsToPxVert secsStart) $ isEnergy secsStart
          go true rest
        go _ L.Nil = return unit
    case L.fromFoldable $ Map.doTupleArray (zoomAsc thisColor) of
      L.Nil -> case Map.lookupLT (pxToSecsVert windowH) thisColor of
        -- handle the case where the entire screen is the middle of a sustain
        Just { key: secsStart, value: Sustain _ } ->
          drawSustainBlock 0 windowH $ isEnergy secsStart
        _ -> return unit
      events -> go false events
  -- Notes
  for_ colors $ \{ c: getColor, x: offsetX, strum: strumImage, hopo: hopoImage, hit: shadeHit } -> do
    zoomDesc (getColor five.notes) $ \secs evt -> do
      let futureSecs = secToNum $ secs - stuff.time
      if futureSecs <= 0.0
        then do
          -- note is in the past or being hit now
          if (-0.1) < futureSecs
            then case evt of
              SustainEnd -> return unit
              _ -> do
                setFillStyle $ shadeHit $ (futureSecs + 0.1) / 0.05
                fillRect { x: toNumber $ targetX + offsetX + 1, y: toNumber $ targetY - 4, w: 35.0, h: 8.0 }
            else return unit
        else do
          let y = secsToPxVert secs
              isEnergy = case Map.lookupLE secs five.energy of
                Just {value: bool} -> bool
                Nothing            -> false
          case evt of
            SustainEnd    -> drawImage Image_sustain_end                                        (toNumber $ targetX + offsetX) (toNumber   y     )
            Note    Strum -> drawImage (if isEnergy then Image_gem_energy      else strumImage) (toNumber $ targetX + offsetX) (toNumber $ y - 5 )
            Sustain Strum -> drawImage (if isEnergy then Image_gem_energy      else strumImage) (toNumber $ targetX + offsetX) (toNumber $ y - 5 )
            Note    HOPO  -> drawImage (if isEnergy then Image_gem_energy_hopo else hopoImage ) (toNumber $ targetX + offsetX) (toNumber $ y - 5 )
            Sustain HOPO  -> drawImage (if isEnergy then Image_gem_energy_hopo else hopoImage ) (toNumber $ targetX + offsetX) (toNumber $ y - 5 )
  return $ targetX + 182 + _M

drawDrums :: forall e. Drums -> Int -> Draw e Int
drawDrums (Drums drums) targetX = do
  stuff <- askStuff
  windowH <- map round $ lift $ C.getCanvasHeight stuff.canvas
  let pxToSecsVert px = stuff.pxToSecsVert (windowH - px) + stuff.time
      secsToPxVert secs = windowH - stuff.secsToPxVert (secs - stuff.time)
      maxSecs = pxToSecsVert (-100)
      minSecs = pxToSecsVert $ windowH + 100
      zoomDesc :: forall v m. (Monad m) => Map.Map Seconds v -> (Seconds -> v -> m Unit) -> m Unit
      zoomDesc = Map.zoomDescDo minSecs maxSecs
      zoomAsc :: forall v m. (Monad m) => Map.Map Seconds v -> (Seconds -> v -> m Unit) -> m Unit
      zoomAsc = Map.zoomAscDo minSecs maxSecs
      targetY = secsToPxVert stuff.time
  -- Highway
  setFillStyle "rgb(126,126,150)"
  fillRect { x: toNumber targetX, y: 0.0, w: 146.0, h: toNumber windowH }
  setFillStyle "rgb(184,185,204)"
  for_ [0, 36, 72, 108, 144] $ \offsetX -> do
    fillRect { x: toNumber $ targetX + offsetX, y: 0.0, w: 1.0, h: toNumber windowH }
  setFillStyle "black"
  for_ [1, 37, 73, 109, 145] $ \offsetX -> do
    fillRect { x: toNumber $ targetX + offsetX, y: 0.0, w: 1.0, h: toNumber windowH }
  -- Solo highway
  setFillStyle "rgb(91,137,185)"
  let startsAsSolo = case Map.lookupLE minSecs drums.solo of
        Nothing           -> false
        Just { value: v } -> v
      soloEdges
        = L.fromFoldable
        $ cons (Tuple minSecs startsAsSolo)
        $ flip snoc (Tuple maxSecs false)
        $ Map.doTupleArray (zoomAsc drums.solo)
      drawSolos L.Nil            = return unit
      drawSolos (L.Cons _ L.Nil) = return unit
      drawSolos (L.Cons (Tuple s1 b1) rest@(L.Cons (Tuple s2 _) _)) = do
        let y1 = secsToPxVert s1
            y2 = secsToPxVert s2
        when b1 $ for_ [2, 38, 74, 110] $ \offsetX -> do
          fillRect { x: toNumber $ targetX + offsetX, y: toNumber y2, w: 34.0, h: toNumber $ y1 - y2 }
        drawSolos rest
  drawSolos soloEdges
  -- Solo edges
  zoomDesc drums.solo $ \secs _ -> do
    drawImage Image_highway_drums_solo_edge (toNumber targetX) (toNumber $ secsToPxVert secs)
  -- Beats
  zoomDesc (case stuff.song of Song o -> case o.beats of Beats o' -> o'.lines) $ \secs evt -> do
    let y = secsToPxVert secs
    case evt of
      Bar      -> drawImage Image_highway_drums_bar      (toNumber targetX) (toNumber y - 1.0)
      Beat     -> drawImage Image_highway_drums_beat     (toNumber targetX) (toNumber y - 1.0)
      HalfBeat -> drawImage Image_highway_drums_halfbeat (toNumber targetX) (toNumber y)
  -- Target
  drawImage Image_highway_drums_target (toNumber targetX) (toNumber targetY - 5.0)
  -- Notes
  zoomDesc drums.notes $ \secs evts -> do
    let futureSecs = secToNum $ secs - stuff.time
    if futureSecs <= 0.0
      then do
        -- note is in the past or being hit now
        if (-0.1) < futureSecs
          then do
            let opacity = (futureSecs + 0.1) / 0.05
                kick = do
                  setFillStyle $ "rgba(231, 196, 112, " <> show opacity <> ")"
                  fillRect { x: toNumber $ targetX + 2, y: toNumber $ targetY - 5, w: 143.0, h: 1.0 }
                  fillRect { x: toNumber $ targetX + 2, y: toNumber $ targetY + 4, w: 143.0, h: 1.0 }
                red = do
                  setFillStyle $ "rgba(255, 188, 188, " <> show opacity <> ")"
                  fillRect { x: toNumber $ targetX + 2, y: toNumber $ targetY - 4, w: 35.0, h: 8.0 }
                yellow = do
                  setFillStyle $ "rgba(255, 244, 151, " <> show opacity <> ")"
                  fillRect { x: toNumber $ targetX + 38, y: toNumber $ targetY - 4, w: 35.0, h: 8.0 }
                blue = do
                  setFillStyle $ "rgba(190, 198, 255, " <> show opacity <> ")"
                  fillRect { x: toNumber $ targetX + 74, y: toNumber $ targetY - 4, w: 35.0, h: 8.0 }
                green = do
                  setFillStyle $ "rgba(190, 255, 192, " <> show opacity <> ")"
                  fillRect { x: toNumber $ targetX + 110, y: toNumber $ targetY - 4, w: 35.0, h: 8.0 }
            for_ evts $ \e -> case e of
              Kick -> kick
              Red  -> red
              YCym -> yellow
              YTom -> yellow
              BCym -> blue
              BTom -> blue
              GCym -> green
              GTom -> green
          else return unit
      else do
        -- note is in the future
        let y = secsToPxVert secs
            isEnergy = case Map.lookupLE secs drums.energy of
              Just {value: bool} -> bool
              Nothing            -> false
        for_ evts $ \e -> case e of
          Kick -> drawImage (if isEnergy then Image_gem_kick_energy   else Image_gem_kick         ) (toNumber $ targetX + 1  ) (toNumber $ y - 3)
          Red  -> drawImage (if isEnergy then Image_gem_energy        else Image_gem_red          ) (toNumber $ targetX + 1  ) (toNumber $ y - 5)
          YTom -> drawImage (if isEnergy then Image_gem_energy        else Image_gem_yellow       ) (toNumber $ targetX + 37 ) (toNumber $ y - 5)
          YCym -> drawImage (if isEnergy then Image_gem_energy_cymbal else Image_gem_yellow_cymbal) (toNumber $ targetX + 37 ) (toNumber $ y - 8)
          BTom -> drawImage (if isEnergy then Image_gem_energy        else Image_gem_blue         ) (toNumber $ targetX + 73 ) (toNumber $ y - 5)
          BCym -> drawImage (if isEnergy then Image_gem_energy_cymbal else Image_gem_blue_cymbal  ) (toNumber $ targetX + 73 ) (toNumber $ y - 8)
          GTom -> drawImage (if isEnergy then Image_gem_energy        else Image_gem_green        ) (toNumber $ targetX + 109) (toNumber $ y - 5)
          GCym -> drawImage (if isEnergy then Image_gem_energy_cymbal else Image_gem_green_cymbal ) (toNumber $ targetX + 109) (toNumber $ y - 8)
  -- TODO: draw all kicks before starting hand gems
  -- Return targetX of next track
  return $ targetX + 146 + _M

data PKHighway
  = RailingLight
  | RailingDark
  | WhiteKey
  | WhiteKeyShort
  | BlackKey

pkHighway :: L.List PKHighway
pkHighway = L.fromFoldable
  [ RailingLight, RailingDark, WhiteKey, BlackKey, WhiteKey, BlackKey, WhiteKeyShort
  , RailingLight, RailingDark, WhiteKey, BlackKey, WhiteKey, BlackKey, WhiteKey, BlackKey, WhiteKeyShort
  , RailingLight, RailingDark, WhiteKey, BlackKey, WhiteKey, BlackKey, WhiteKeyShort
  , RailingLight, RailingDark, WhiteKey, BlackKey, WhiteKey, BlackKey, WhiteKey, BlackKey, WhiteKeyShort
  , RailingLight, RailingDark, WhiteKeyShort
  , RailingLight, RailingDark
  ]

inits :: forall a. Array a -> Array (Array a)
inits ary = map (\n -> take n ary) (0 .. length ary)

pitchList :: Array { pitch :: Pitch, offsetX :: Int, isBlack :: Boolean }
pitchList = do
  let allPitches = [RedC,RedCs,RedD,RedDs,RedE,YellowF,YellowFs,YellowG,YellowGs,YellowA,YellowAs,YellowB,BlueC,BlueCs,BlueD,BlueDs,BlueE,GreenF,GreenFs,GreenG,GreenGs,GreenA,GreenAs,GreenB,OrangeC]
      isBlack p = elem p [RedCs,RedDs,YellowFs,YellowGs,YellowAs,BlueCs,BlueDs,GreenFs,GreenGs,GreenAs]
  Tuple pitch lowerPitches <- zip allPitches $ inits allPitches
  return
    { pitch: pitch
    , offsetX: 1 + sum (map (\p -> if isBlack p then 10 else 12) lowerPitches)
    , isBlack: isBlack pitch
    }

data HackBool = False | True

drawProKeys :: forall e. ProKeys -> Int -> Draw e Int
drawProKeys (ProKeys pk) targetX = do
  stuff <- askStuff
  windowH <- map round $ lift $ C.getCanvasHeight stuff.canvas
  let pxToSecsVert px = stuff.pxToSecsVert (windowH - px) + stuff.time
      secsToPxVert secs = windowH - stuff.secsToPxVert (secs - stuff.time)
      maxSecs = pxToSecsVert (-100)
      minSecs = pxToSecsVert $ windowH + 100
      zoomDesc :: forall v m. (Monad m) => Map.Map Seconds v -> (Seconds -> v -> m Unit) -> m Unit
      zoomDesc = Map.zoomDescDo minSecs maxSecs
      zoomAsc :: forall v m. (Monad m) => Map.Map Seconds v -> (Seconds -> v -> m Unit) -> m Unit
      zoomAsc = Map.zoomAscDo minSecs maxSecs
      targetY = secsToPxVert stuff.time
  -- Highway
  let drawHighway _    L.Nil                 = return unit
      drawHighway xpos (L.Cons chunk chunks) = do
        let params = case chunk of
              RailingLight  -> { color: "rgb(184,185,205)", width: 1 }
              RailingDark   -> { color: "black"           , width: 1 }
              WhiteKey      -> { color: "rgb(126,126,150)", width: 11 }
              WhiteKeyShort -> { color: "rgb(126,126,150)", width: 10 }
              BlackKey      -> { color: "rgb(105,105,129)", width: 11 }
        setFillStyle params.color
        fillRect { x: toNumber xpos, y: 0.0, w: toNumber params.width, h: toNumber windowH }
        drawHighway (xpos + params.width) chunks
  drawHighway targetX pkHighway
  -- Solo highway
  let startsAsSolo = case Map.lookupLE minSecs pk.solo of
        Nothing           -> false
        Just { value: v } -> v
      soloEdges
        = L.fromFoldable
        $ cons (Tuple minSecs startsAsSolo)
        $ flip snoc (Tuple maxSecs false)
        $ Map.doTupleArray (zoomAsc pk.solo)
      drawSoloHighway _    _  _  L.Nil                 = return unit
      drawSoloHighway xpos y1 y2 (L.Cons chunk chunks) = do
        let params = case chunk of
              RailingLight  -> { color: Nothing                , width: 1  }
              RailingDark   -> { color: Nothing                , width: 1  }
              WhiteKey      -> { color: Just "rgb( 91,137,185)", width: 11 }
              WhiteKeyShort -> { color: Just "rgb( 91,137,185)", width: 10 }
              BlackKey      -> { color: Just "rgb( 73,111,149)", width: 11 }
        case params.color of
          Nothing -> return unit
          Just c  -> do
            setFillStyle c
            fillRect { x: toNumber xpos, y: toNumber y1, w: toNumber params.width, h: toNumber $ y2 - y1 }
        drawSoloHighway (xpos + params.width) y1 y2 chunks
      drawSolos L.Nil            = return unit
      drawSolos (L.Cons _ L.Nil) = return unit
      drawSolos (L.Cons (Tuple s1 b1) rest@(L.Cons (Tuple s2 _) _)) = do
        when b1 $ drawSoloHighway targetX (secsToPxVert s1) (secsToPxVert s2) pkHighway
        drawSolos rest
  drawSolos soloEdges
  -- Solo edges
  zoomDesc pk.solo $ \secs _ -> do
    drawImage Image_highway_prokeys_solo_edge (toNumber targetX) (toNumber $ secsToPxVert secs)
  -- Beats
  zoomDesc (case stuff.song of Song o -> case o.beats of Beats o' -> o'.lines) $ \secs evt -> do
    let y = secsToPxVert secs
    case evt of
      Bar      -> drawImage Image_highway_prokeys_bar      (toNumber targetX) (toNumber y - 1.0)
      Beat     -> drawImage Image_highway_prokeys_beat     (toNumber targetX) (toNumber y - 1.0)
      HalfBeat -> drawImage Image_highway_prokeys_halfbeat (toNumber targetX) (toNumber y)
  -- Target
  drawImage Image_highway_prokeys_target (toNumber targetX) (toNumber targetY - 5.0)
  -- Ranges
  setFillStyle "rgba(0,0,0,0.3)"
  let rangeEdges
        = L.fromFoldable
        $ cons (Tuple minSecs $ map _.value $ Map.lookupLE minSecs pk.ranges)
        $ flip snoc (Tuple maxSecs Nothing)
        $ map (map Just) $ Map.doTupleArray (zoomAsc pk.ranges)
      drawRanges L.Nil = return unit
      drawRanges (L.Cons _ L.Nil) = return unit
      drawRanges (L.Cons (Tuple s1 rng) rest@(L.Cons (Tuple s2 _) _)) = do
        case rng of
          Nothing -> return unit
          Just r -> let
            y = toNumber (secsToPxVert s1)
            h = toNumber (secsToPxVert s2) - y
            rects = case r of
              RangeC -> [{x: toNumber $ targetX + 192, y: y, w: 90.0, h: h}]
              RangeD -> [{x: toNumber $ targetX + 2, y: y, w: 22.0, h: h}, {x: toNumber $ targetX + 203, y: y, w: 79.0, h: h}]
              RangeE -> [{x: toNumber $ targetX + 2, y: y, w: 44.0, h: h}, {x: toNumber $ targetX + 225, y: y, w: 57.0, h: h}]
              RangeF -> [{x: toNumber $ targetX + 2, y: y, w: 56.0, h: h}, {x: toNumber $ targetX + 247, y: y, w: 35.0, h: h}]
              RangeG -> [{x: toNumber $ targetX + 2, y: y, w: 78.0, h: h}, {x: toNumber $ targetX + 270, y: y, w: 12.0, h: h}]
              RangeA -> [{x: toNumber $ targetX + 2, y: y, w: 100.0, h: h}]
            in for_ rects fillRect
        drawRanges rest
  drawRanges rangeEdges
  -- Sustains
  for_ pitchList $ \{ pitch: pitch, offsetX: offsetX, isBlack: isBlack } -> do
    let thisPitch = fromMaybe Map.empty $ Map.lookup pitch pk.notes
        isEnergy secs = case Map.lookupLE secs pk.energy of
          Just {value: bool} -> bool
          Nothing            -> false
        drawSustainBlock ystart yend energy = when (ystart < targetY || yend < targetY) do
          let ystart' = min ystart targetY
              yend'   = min yend   targetY
              sustaining = targetY < ystart || targetY < yend
              shades = if energy
                then if isBlack
                  then { light: "rgb( 52,148,117)", normal: "rgb( 71,107, 95)", dark: "rgb( 69, 83, 79)" }
                  else { light: "rgb(137,235,204)", normal: "rgb(138,192,175)", dark: "rgb(124,158,149)" }
                else if isBlack
                  then { light: "rgb(175, 83,201)", normal: "rgb(147, 49,175)", dark: "rgb(123, 42,150)" }
                  else { light: "rgb(199,134,218)", normal: "rgb(184,102,208)", dark: "rgb(178, 86,204)" }
              h = yend' - ystart' + 1
              offsetX' = offsetX + if isBlack then 0 else 0
          setFillStyle "black"
          fillRect { x: toNumber $ targetX + offsetX' + 2, y: toNumber ystart', w: 1.0, h: toNumber h }
          fillRect { x: toNumber $ targetX + offsetX' + 8, y: toNumber ystart', w: 1.0, h: toNumber h }
          setFillStyle shades.light
          fillRect { x: toNumber $ targetX + offsetX' + 3, y: toNumber ystart', w: 1.0, h: toNumber h }
          setFillStyle shades.normal
          fillRect { x: toNumber $ targetX + offsetX' + 4, y: toNumber ystart', w: 3.0, h: toNumber h }
          setFillStyle shades.dark
          fillRect { x: toNumber $ targetX + offsetX' + 7, y: toNumber ystart', w: 1.0, h: toNumber h }
          when sustaining do
            setFillStyle shades.light
            fillRect { x: toNumber $ targetX + offsetX' + 1, y: toNumber $ targetY - 4, w: if isBlack then 9.0 else 11.0, h: 8.0 }
        go False (L.Cons (Tuple secsEnd SustainEnd) rest) = case Map.lookupLT secsEnd thisPitch of
          Just { key: secsStart, value: Sustain _ } -> do
            drawSustainBlock (secsToPxVert secsEnd) windowH $ isEnergy secsStart
            go False rest
          _ -> unsafeThrow "during prokeys drawing: found a sustain end not preceded by sustain start"
        go True (L.Cons (Tuple _ SustainEnd) rest) = go False rest
        go _ (L.Cons (Tuple _ (Note (_ :: Unit))) rest) = go False rest
        go _ (L.Cons (Tuple secsStart (Sustain (_ :: Unit))) rest) = do
          let pxEnd = case rest of
                L.Nil                      -> 0
                L.Cons (Tuple secsEnd _) _ -> secsToPxVert secsEnd
          drawSustainBlock pxEnd (secsToPxVert secsStart) $ isEnergy secsStart
          go True rest
        go _ L.Nil = return unit
    case L.fromFoldable $ Map.doTupleArray (zoomAsc thisPitch) of
      L.Nil -> case Map.lookupLT (pxToSecsVert windowH) thisPitch of
        -- handle the case where the entire screen is the middle of a sustain
        Just { key: secsStart, value: Sustain (_ :: Unit) } ->
          drawSustainBlock 0 windowH $ isEnergy secsStart
        _ -> return unit
      events -> go False events
  -- Notes
  for_ pitchList $ \{ pitch: pitch, offsetX: offsetX, isBlack: isBlack } -> do
    zoomDesc (fromMaybe Map.empty $ Map.lookup pitch pk.notes) $ \secs evt -> do
      let futureSecs = secToNum $ secs - stuff.time
      if futureSecs <= 0.0
        then do
          -- note is in the past or being hit now
          if (-0.1) < futureSecs
            then case evt of
              SustainEnd -> return unit
              _ -> do
                setFillStyle $ "rgba(227,193,238," <> show ((futureSecs + 0.1) / 0.05) <> ")"
                fillRect { x: toNumber $ targetX + offsetX + 1, y: toNumber $ targetY - 4, w: if isBlack then 9.0 else 11.0, h: 8.0 }
            else return unit
        else do
          let y = secsToPxVert secs
              isEnergy = case Map.lookupLE secs pk.energy of
                Just {value: bool} -> bool
                Nothing            -> false
              img = if isEnergy
                then if isBlack then Image_gem_blackkey_energy else Image_gem_whitekey_energy
                else if isBlack then Image_gem_blackkey        else Image_gem_whitekey
          case evt of
            SustainEnd   -> drawImage Image_sustain_key_end (toNumber $ targetX + offsetX - if isBlack then 1 else 0) (toNumber   y    )
            Note    (_ :: Unit) -> drawImage img                   (toNumber $ targetX + offsetX                           ) (toNumber $ y - 5)
            Sustain (_ :: Unit) -> drawImage img                   (toNumber $ targetX + offsetX                           ) (toNumber $ y - 5)
  return $ targetX + 282 + _M

zoomAscDoPadding :: forall k a m. (Ord k, Monad m) => k -> k -> Map.Map k a -> (k -> a -> m Unit) -> m Unit
zoomAscDoPadding k1 k2 m act = do
  case Map.lookupLE k1 m of
    Nothing -> return unit
    Just { key: k, value: v } -> act k v
  Map.zoomAscDo k1 k2 m act
  case Map.lookupGE k2 m of
    Nothing -> return unit
    Just { key: k, value: v } -> act k v

zoomDescDoPadding :: forall k a m. (Ord k, Monad m) => k -> k -> Map.Map k a -> (k -> a -> m Unit) -> m Unit
zoomDescDoPadding k1 k2 m act = do
  case Map.lookupGE k2 m of
    Nothing -> return unit
    Just { key: k, value: v } -> act k v
  Map.zoomDescDo k1 k2 m act
  case Map.lookupLE k1 m of
    Nothing -> return unit
    Just { key: k, value: v } -> act k v

slide :: Number -> Number -> Number -> Number -> Number -> Number
slide t1 t2 tx v1 v2 = v1 + (v2 - v1) * ((tx - t1) / (t2 - t1))

secToNum :: Seconds -> Number
secToNum (Seconds n) = n

drawVocal :: forall e. Vocal -> Int -> Draw e Int
drawVocal (Vocal v) targetY = do
  stuff <- askStuff
  windowW <- map round $ lift $ C.getCanvasWidth stuff.canvas
  let pxToSecsHoriz px = stuff.pxToSecsHoriz px + stuff.time
      secsToPxHoriz secs = stuff.secsToPxHoriz $ secs - stuff.time
      minSecs = pxToSecsHoriz (-100)
      maxSecs = pxToSecsHoriz $ windowW + 100
      zoomDesc :: forall v m. (Monad m) => Map.Map Seconds v -> (Seconds -> v -> m Unit) -> m Unit
      zoomDesc = zoomDescDoPadding minSecs maxSecs
      zoomAsc :: forall v m. (Monad m) => Map.Map Seconds v -> (Seconds -> v -> m Unit) -> m Unit
      zoomAsc = zoomAscDoPadding minSecs maxSecs
      targetX = secsToPxHoriz stuff.time
  setFillStyle "rgba(0,0,0,0.6)"
  fillRect { x: 0.0, y: toNumber targetY + 25.0, w: toNumber windowW, h: 130.0 }
  setFillStyle "rgba(0,27,89,0.85)"
  fillRect { x: 0.0, y: toNumber targetY + 155.0, w: toNumber windowW, h: 25.0 }
  setFillStyle "rgba(87,55,0,0.85)"
  fillRect { x: 0.0, y: toNumber targetY, w: toNumber windowW, h: 25.0 }
  -- Draw note pitches
  -- TODO: draw all pitch lines before talkies
  -- TODO: draw harmony unisons better
  let thisRange = case Map.lookupLE stuff.time v.ranges of
        Nothing -> { min: 36.0, max: 84.0 }
        Just { value: VocalRange rmin rmax } -> { min: toNumber rmin, max: toNumber rmax }
        Just { key: t1, value: VocalRangeShift } -> case Map.lookupGT stuff.time v.ranges of
          Just { key: t2, value: VocalRange bmin bmax } -> case Map.lookupLT t1 v.ranges of
            Just { value: VocalRange amin amax } ->
              { min: slide (secToNum t1) (secToNum t2) (secToNum stuff.time) (toNumber amin) (toNumber bmin)
              , max: slide (secToNum t1) (secToNum t2) (secToNum stuff.time) (toNumber amax) (toNumber bmax)
              }
            _ -> unsafeThrow "not a valid range shift"
          _ -> unsafeThrow "not a valid range shift"
      pitchToY p = toNumber targetY + slide thisRange.min thisRange.max (toNumber p) 143.0 37.0
      drawLines :: Maybe (Tuple Seconds Int) -> L.List (Tuple Seconds VocalNote) -> Draw e Unit
      drawLines (Just (Tuple t1 p1)) evts@(L.Cons (Tuple t2 (VocalStart lyric (Just p2))) _) | lyric == "+" || lyric == "+$" = do
        -- draw line from (t1,p1) to (t2,p2)
        onContext $ \ctx -> C.moveTo ctx (toNumber $ secsToPxHoriz t1) (pitchToY p1)
        onContext $ \ctx -> C.lineTo ctx (toNumber $ secsToPxHoriz t2) (pitchToY p2)
        drawLines Nothing evts
      drawLines (Just _) evts = drawLines Nothing evts -- ignore last note-off because no slide
      drawLines Nothing (L.Cons (Tuple t1 (VocalStart _ (Just p))) (L.Cons (Tuple t2 VocalEnd) rest)) = do
        -- draw line from (t1,p) to (t2,p)
        onContext $ \ctx -> C.moveTo ctx (toNumber $ secsToPxHoriz t1) (pitchToY p)
        onContext $ \ctx -> C.lineTo ctx (toNumber $ secsToPxHoriz t2) (pitchToY p)
        drawLines (Just (Tuple t2 p)) rest
      drawLines Nothing (L.Cons (Tuple t1 (VocalStart _ (Just p))) rest@(L.Cons (Tuple t2 (VocalStart _ _)) _)) = do
        -- draw line from (t1,p) to (t2,p)
        -- this case only happens in sloppy vox charts with no gap between notes
        onContext $ \ctx -> C.moveTo ctx (toNumber $ secsToPxHoriz t1) (pitchToY p)
        onContext $ \ctx -> C.lineTo ctx (toNumber $ secsToPxHoriz t2) (pitchToY p)
        drawLines (Just (Tuple t2 p)) rest
      drawLines Nothing (L.Cons (Tuple t1 (VocalStart _ Nothing)) (L.Cons (Tuple t2 VocalEnd) rest)) = do
        -- draw talky from t1 to t2
        fillRect { x: toNumber $ secsToPxHoriz t1, y: toNumber targetY + 25.0, w: toNumber $ secsToPxHoriz t2 - secsToPxHoriz t1, h: 130.0 }
        drawLines Nothing rest
      drawLines Nothing (L.Cons (Tuple t1 (VocalStart _ Nothing)) rest@(L.Cons (Tuple t2 (VocalStart _ _)) _)) = do
        -- draw talky from t1 to t2
        -- this case only happens in sloppy vox charts with no gap between notes
        fillRect { x: toNumber $ secsToPxHoriz t1, y: toNumber targetY + 25.0, w: toNumber $ secsToPxHoriz t2 - secsToPxHoriz t1, h: 130.0 }
        drawLines Nothing rest
      drawLines Nothing (L.Cons (Tuple _ (VocalStart _ _)) L.Nil) = return unit -- off-screen
      drawLines _ L.Nil = return unit
      drawLines Nothing (L.Cons (Tuple _ VocalEnd) rest) = drawLines Nothing rest
      lineParts =
        [ { part: v.harm2, line: "rgb(189,67,0)"  , talky: "rgba(189,67,0,0.6)"  , width: 6.0 }
        , { part: v.harm3, line: "rgb(225,148,22)", talky: "rgba(225,148,22,0.6)", width: 5.0 }
        , { part: v.harm1, line: "rgb(46,229,223)", talky: "rgba(46,229,223,0.6)", width: 4.0 }
        ]
  onContext $ C.setLineCap C.Round
  for_ lineParts $ \o -> do
    onContext C.beginPath
    onContext $ C.setStrokeStyle o.line
    onContext $ C.setLineWidth o.width
    onContext $ C.setFillStyle o.talky
    drawLines Nothing $ L.fromFoldable $ Map.doTupleArray (zoomAsc o.part)
    onContext $ C.stroke
    onContext $ C.closePath
  -- Draw text
  let lyricParts =
        [ { part: v.harm1, y: targetY + 174, isHarm3: false }
        , { part: v.harm2, y: targetY + 20, isHarm3: false }
        , { part: v.harm3, y: targetY + 20, isHarm3: true }
        ]
      harm2Lyric t = case Map.lookup t v.harm2 of
        Nothing -> Nothing
        Just VocalEnd -> Nothing
        Just (VocalStart lyric _) -> Just lyric
      getLyrics
        :: Boolean
        -> L.List (Tuple Seconds VocalNote)
        -> L.List {time :: Seconds, lyric :: String, isTalky :: Boolean}
      getLyrics isHarm3 = L.mapMaybe $ \(Tuple t vn) -> case vn of
        VocalEnd -> Nothing
        VocalStart lyric pitch
          | lyric == "+" -> Nothing
          | R.test (R.regex "\\$$" R.noFlags) lyric -> Nothing
          | isHarm3 && harm2Lyric t == Just lyric -> Nothing
          | otherwise -> Just
            { time: t
            , lyric: R.replace (R.regex "=$" R.noFlags) "-" lyric
            , isTalky: isNothing pitch
            }
          -- TODO: support §
      drawLyrics
        :: Number
        -> Number
        -> L.List {time :: Seconds, lyric :: String, isTalky :: Boolean}
        -> Draw e Unit
      drawLyrics _    _     L.Nil           = return unit
      drawLyrics minX textY (L.Cons o rest) = do
        let textX = max minX $ toNumber $ secsToPxHoriz o.time
        onContext $ C.setFont $ if o.isTalky
          then "bold italic 17px sans-serif"
          else "bold 17px sans-serif"
        setFillStyle $ case Map.lookupLE o.time v.energy of
          Nothing -> "white"
          Just { value: v } -> if v then "yellow" else "white"
        metric <- measureText o.lyric
        onContext $ \ctx -> C.fillText ctx o.lyric textX textY
        drawLyrics (textX + metric.width + 5.0) textY rest
      mergeTime
        :: forall a t. (Ord t)
        => L.List {time :: t | a}
        -> L.List {time :: t | a}
        -> L.List {time :: t | a}
      mergeTime L.Nil ly = ly
      mergeTime lx L.Nil = lx
      mergeTime lx@(L.Cons x tx) ly@(L.Cons y ty) = if x.time <= y.time
        then L.Cons x $ mergeTime tx ly
        else L.Cons y $ mergeTime lx ty
  drawLyrics (-999.0) (toNumber targetY + 174.0) $
    getLyrics false $ L.fromFoldable $ Map.doTupleArray (zoomAsc v.harm1)
  drawLyrics (-999.0) (toNumber targetY + 20.0) $ mergeTime
    (getLyrics false $ L.fromFoldable $ Map.doTupleArray (zoomAsc v.harm2))
    (getLyrics true  $ L.fromFoldable $ Map.doTupleArray (zoomAsc v.harm3))
  -- Draw percussion notes
  zoomDesc v.percussion $ \t (_ :: Unit) -> if t > stuff.time
    then do
      setFillStyle "#d9d9d9"
      fillCircle { x: toNumber $ secsToPxHoriz t, y: toNumber targetY + 90.0, r: 11.0 }
      setFillStyle "#00b9c9"
      fillCircle { x: toNumber $ secsToPxHoriz t, y: toNumber targetY + 90.0, r: 9.0 }
    else do
      let opacity = (secToNum (t - stuff.time) + 0.1) / 0.05
      when (opacity > 0.0) $ do
        setFillStyle $ "rgba(255, 255, 255, " <> show opacity <> ")"
        fillCircle { x: toNumber $ secsToPxHoriz stuff.time, y: toNumber targetY + 90.0, r: 11.0 }
  -- Draw phrase ends
  setFillStyle "#bbb"
  zoomDesc v.phrases $ \t (_ :: Unit) -> do
    fillRect { x: toNumber (secsToPxHoriz t) - 1.0, y: toNumber targetY + 25.0, w: 3.0, h: 130.0 }
  -- Draw target line
  setFillStyle "#ddd"
  fillRect { x: toNumber targetX - 1.0, y: toNumber targetY + 25.0, w: 3.0, h: 130.0 }
  return $ targetY + 180 + _M
