module Draw.Protar (drawProtar, eachChordsWidth) where

import           Prelude

import           Data.Array              (cons, index, range, snoc, unsnoc, uncons, take)
import           Data.Foldable           (for_)
import           Data.Int                (ceil, round, toNumber)
import           Data.List               as L
import           Data.Maybe              (Maybe (..), fromMaybe, isNothing)
import           Data.Time.Duration      (Seconds, negateDuration)
import           Data.Traversable        (for, maximum, sum)
import           Data.Tuple              (Tuple (..), fst, snd)
import           Effect                  (Effect)
import           Effect.Exception.Unsafe (unsafeThrow)
import           Graphics.Canvas         as C

import           Draw.Common             (Draw, drawImage, drawLane, fillRect,
                                          secToNum, setFillStyle, drawBeats)
import           Images                  (ImageID (..), protarFrets)
import           OnyxMap                 as Map
import           Song                    (ChordLine (..), Flex (..),
                                          GuitarNoteType (..), Protar (..),
                                          ProtarNote (..), Song (..),
                                          Sustainable (..))
import           Style                   (customize)

getChordsWidth
  :: C.Context2D -> Protar -> Effect Protar
getChordsWidth ctx (Protar pg) = do
  widths <- for (Map.values pg.chords) $ \x -> let
    f xs = map sum $ for xs \(Tuple line str) -> do
      case line of
        Baseline    -> C.setFont ctx "19px sans-serif"
        Superscript -> C.setFont ctx "14px sans-serif"
      metrics <- C.measureText ctx str
      pure metrics.width
    in case x of
      SustainEnd -> pure 0.0
      Sustain ps -> f ps
      Note    ps -> f ps
  pure $ Protar pg { chordsWidth = ceil $ fromMaybe 0.0 $ maximum widths }

eachChordsWidth
  :: C.Context2D -> Song -> Effect Song
eachChordsWidth ctx (Song o) = do
  parts <- for o.parts \(Tuple s f@(Flex flex)) -> case flex.protar of
    Nothing -> pure $ Tuple s f
    Just pg -> do
      pg' <- for pg \(Tuple d pgd) -> do
        pgd' <- getChordsWidth ctx pgd
        pure $ Tuple d pgd'
      pure $ Tuple s $ Flex flex { protar = Just pg' }
  pure $ Song o { parts = parts }

drawProtar :: Protar -> Int -> Draw Int
drawProtar (Protar protar) startX stuff = do
  windowH <- map round $ C.getCanvasHeight stuff.canvas
  let targetX = if stuff.app.settings.leftyFlip
        then startX
        else startX + protar.chordsWidth
      pxToSecsVert px = stuff.pxToSecsVert (windowH - px) <> stuff.time
      secsToPxVert secs = windowH - stuff.secsToPxVert (secs <> negateDuration stuff.time)
      widthFret = customize.widthProtarFret
      widthHighway = widthFret * protar.strings + 2
      maxSecs = pxToSecsVert $ stuff.minY - 50
      minSecs = pxToSecsVert $ stuff.maxY + 50
      zoomDesc :: forall v m. (Monad m) => Map.Map Seconds v -> (Seconds -> v -> m Unit) -> m Unit
      zoomDesc = Map.zoomDescDo minSecs maxSecs
      zoomAsc :: forall v m. (Monad m) => Map.Map Seconds v -> (Seconds -> v -> m Unit) -> m Unit
      zoomAsc = Map.zoomAscDo minSecs maxSecs
      targetY = secsToPxVert stuff.time
      handedness n = if stuff.app.settings.leftyFlip then protar.strings - 1 - n else n
      drawH = stuff.maxY - stuff.minY
  -- Chord names
  let drawChord = drawChord' $ if stuff.app.settings.leftyFlip
        then toNumber $ startX + widthHighway + 5
        else toNumber $ targetX - 5
      removePiece name = if stuff.app.settings.leftyFlip
        then map (\o -> {piece: o.head, pieces: o.tail}) (uncons name)
        else map (\o -> {piece: o.last, pieces: o.init}) (unsnoc name)
      drawChord' x secs name = case removePiece name of
        Nothing -> pure unit
        Just o -> do
          let ctx = stuff.context
          y <- case fst o.piece of
            Baseline -> do
              C.setFont ctx customize.proChordNameFont
              C.setFillStyle ctx customize.proChordNameColor
              pure $ toNumber $ secsToPxVert secs + 5
            Superscript -> do
              C.setFont ctx customize.proChordNameFontSuperscript
              C.setFillStyle ctx customize.proChordNameColor
              pure $ toNumber $ secsToPxVert secs - 3
          void $ C.setTextAlign ctx $ if stuff.app.settings.leftyFlip
            then C.AlignLeft
            else C.AlignRight
          void $ C.fillText ctx (snd o.piece) x y
          metrics <- C.measureText ctx (snd o.piece)
          let x' = if stuff.app.settings.leftyFlip
                then x + metrics.width
                else x - metrics.width
          drawChord' x' secs o.pieces
  -- 1. draw chords that end before now
  Map.zoomDescDo minSecs stuff.time protar.chords \secs e -> case e of
    Sustain _ -> pure unit
    Note c -> drawChord secs c
    SustainEnd -> case Map.lookupLT secs protar.chords of
      -- TODO process beforehand to remove the lookup here
      Just { value: Sustain c } -> drawChord secs c
      _ -> pure unit -- shouldn't happen
  -- 2. draw chords sticking at now
  case Map.lookupLE stuff.time protar.chords of
    Just { value: Sustain c } -> drawChord stuff.time c
    _ -> pure unit
  -- 3. draw chords that start after now
  Map.zoomDescDo stuff.time maxSecs protar.chords \secs e -> case e of
    SustainEnd -> pure unit
    Sustain c  -> drawChord secs c
    Note    c  -> drawChord secs c
  -- Highway
  setFillStyle customize.highway stuff
  fillRect { x: toNumber targetX, y: toNumber stuff.minY, width: toNumber widthHighway, height: toNumber drawH } stuff
  -- Solo highway
  setFillStyle customize.highwaySolo stuff
  let startsAsSolo = case Map.lookupLE minSecs protar.solo of
        Nothing           -> false
        Just { value: v } -> v
      soloEdges
        = L.fromFoldable
        $ cons (Tuple minSecs startsAsSolo)
        $ flip snoc (Tuple maxSecs false)
        $ Map.doTupleArray (zoomAsc protar.solo)
      drawSolos L.Nil            = pure unit
      drawSolos (L.Cons _ L.Nil) = pure unit
      drawSolos (L.Cons (Tuple s1 b1) rest@(L.Cons (Tuple s2 _) _)) = do
        let y1 = secsToPxVert s1
            y2 = secsToPxVert s2
        when b1 $ for_ (map (\i -> i * widthFret + 2) $ range 0 (protar.strings - 1)) \offsetX -> do
          fillRect { x: toNumber $ targetX + offsetX, y: toNumber y2, width: toNumber $ widthFret - 2, height: toNumber $ y1 - y2 } stuff
        drawSolos rest
  drawSolos soloEdges
  -- Solo edges
  zoomDesc protar.solo \secs _ -> do
    let y = secsToPxVert secs
    setFillStyle customize.highwaySoloEdge stuff
    fillRect { x: toNumber targetX, y: toNumber y, width: toNumber widthHighway, height: 1.0 } stuff
  -- Beats
  drawBeats secsToPxVert
    { x: targetX
    , width: widthHighway
    , minSecs: minSecs
    , maxSecs: maxSecs
    } stuff
  -- Railings
  setFillStyle customize.highwayRailing stuff
  for_ (map (\i -> i * widthFret) $ range 0 protar.strings) \offsetX -> do
    fillRect { x: toNumber $ targetX + offsetX, y: toNumber stuff.minY, width: 1.0, height: toNumber drawH } stuff
  setFillStyle customize.highwayDivider stuff
  for_ (map (\i -> i * widthFret + 1) $ range 0 protar.strings) \offsetX -> do
    fillRect { x: toNumber $ targetX + offsetX, y: toNumber stuff.minY, width: 1.0, height: toNumber drawH } stuff
  -- Lanes
  let colors' =
        [ { c: _.s6, lane: _.s6, x: handedness 0 * widthFret + 1, strum: Image_gem_red_pro   , hopo: Image_gem_red_pro_hopo   , tap: Image_gem_red_pro_tap
          , shades: customize.sustainRed, target: Image_highway_protar_target_red
          }
        , { c: _.s5, lane: _.s5, x: handedness 1 * widthFret + 1, strum: Image_gem_green_pro , hopo: Image_gem_green_pro_hopo , tap: Image_gem_green_pro_tap
          , shades: customize.sustainGreen, target: Image_highway_protar_target_green
          }
        , { c: _.s4, lane: _.s4, x: handedness 2 * widthFret + 1, strum: Image_gem_orange_pro, hopo: Image_gem_orange_pro_hopo, tap: Image_gem_orange_pro_tap
          , shades: customize.sustainOrange, target: Image_highway_protar_target_orange
          }
        , { c: _.s3, lane: _.s3, x: handedness 3 * widthFret + 1, strum: Image_gem_blue_pro  , hopo: Image_gem_blue_pro_hopo  , tap: Image_gem_blue_pro_tap
          , shades: customize.sustainBlue, target: Image_highway_protar_target_blue
          }
        , { c: _.s2, lane: _.s2, x: handedness 4 * widthFret + 1, strum: Image_gem_yellow_pro, hopo: Image_gem_yellow_pro_hopo, tap: Image_gem_yellow_pro_tap
          , shades: customize.sustainYellow, target: Image_highway_protar_target_yellow
          }
        , { c: _.s1, lane: _.s1, x: handedness 5 * widthFret + 1, strum: Image_gem_purple_pro, hopo: Image_gem_purple_pro_hopo, tap: Image_gem_purple_pro_tap
          , shades: customize.sustainPurple, target: Image_highway_protar_target_purple
          }
        ]
      colors = take protar.strings colors'
  for_ colors \{x: offsetX, lane: gem} -> let
    thisLane = Map.union protar.bre $ gem protar.lanes
    startsAsLane = case Map.lookupLE minSecs thisLane of
      Nothing           -> false
      Just { value: v } -> v
    laneEdges
      = L.fromFoldable
      $ cons (Tuple minSecs startsAsLane)
      $ flip snoc (Tuple maxSecs false)
      $ Map.doTupleArray (zoomAsc thisLane)
    drawLanes L.Nil            = pure unit
    drawLanes (L.Cons _ L.Nil) = pure unit
    drawLanes (L.Cons (Tuple s1 b1) rest@(L.Cons (Tuple s2 _) _)) = do
      let y1 = secsToPxVert s1
          y2 = secsToPxVert s2
      when b1 $ drawLane
        { x: targetX + offsetX + 1
        , y: y2
        , width: widthFret - 2
        , height: y1 - y2
        } stuff
      drawLanes rest
    in drawLanes laneEdges
  -- Target
  for_ colors \{x: offsetX, target: targetImage} -> do
    drawImage targetImage (toNumber $ targetX + offsetX) (toNumber targetY - 5.0) stuff
  -- Sustains
  for_ colors \{ c: getColor, x: offsetX, shades: normalShades } -> do
    let thisColor = getColor protar.notes
        isEnergy secs = case Map.lookupLE secs protar.energy of
          Nothing           -> false
          Just { value: v } -> v
        hitAtY = if stuff.app.settings.autoplay then targetY else stuff.maxY + 50
        drawSustainBlock ystart yend energy mute = when (ystart < hitAtY || yend < hitAtY) do
          let ystart' = min ystart hitAtY
              yend'   = min yend   hitAtY
              sustaining = stuff.app.settings.autoplay && (targetY < ystart || targetY < yend)
              shades =
                if energy    then customize.sustainEnergy
                else if mute then customize.sustainProtarMute
                else              normalShades
              h = yend' - ystart' + 1
          setFillStyle customize.sustainBorder stuff
          fillRect { x: toNumber $ targetX + offsetX + 11, y: toNumber ystart', width: 1.0, height: toNumber h } stuff
          fillRect { x: toNumber $ targetX + offsetX + 19, y: toNumber ystart', width: 1.0, height: toNumber h } stuff
          setFillStyle shades.light stuff
          fillRect { x: toNumber $ targetX + offsetX + 12, y: toNumber ystart', width: 1.0, height: toNumber h } stuff
          setFillStyle shades.normal stuff
          fillRect { x: toNumber $ targetX + offsetX + 13, y: toNumber ystart', width: 5.0, height: toNumber h } stuff
          setFillStyle shades.dark stuff
          fillRect { x: toNumber $ targetX + offsetX + 18, y: toNumber ystart', width: 1.0, height: toNumber h } stuff
          when sustaining do
            setFillStyle shades.light stuff
            fillRect { x: toNumber $ targetX + offsetX + 1, y: toNumber $ targetY - 4, width: toNumber $ widthFret - 1, height: 8.0 } stuff
        go false (L.Cons (Tuple secsEnd SustainEnd) rest) = case Map.lookupLT secsEnd thisColor of
          Just { key: secsStart, value: Sustain (ProtarNote o) } -> do
            drawSustainBlock (secsToPxVert secsEnd) stuff.maxY (isEnergy secsStart) (isNothing o.fret)
            go false rest
          _ -> unsafeThrow "during protar drawing: found a sustain end not preceded by sustain start"
        go true (L.Cons (Tuple _ SustainEnd) rest) = go false rest
        go _ (L.Cons (Tuple _ (Note _)) rest) = go false rest
        go _ (L.Cons (Tuple secsStart (Sustain (ProtarNote o))) rest) = do
          let pxEnd = case rest of
                L.Nil                      -> stuff.minY
                L.Cons (Tuple secsEnd _) _ -> secsToPxVert secsEnd
          drawSustainBlock pxEnd (secsToPxVert secsStart) (isEnergy secsStart) (isNothing o.fret)
          go true rest
        go _ L.Nil = pure unit
    case L.fromFoldable $ Map.doTupleArray (zoomAsc thisColor) of
      L.Nil -> case Map.lookupLT (pxToSecsVert stuff.maxY) thisColor of
        -- handle the case where the entire screen is the middle of a sustain
        Just { key: secsStart, value: Sustain (ProtarNote o) } ->
          drawSustainBlock stuff.minY stuff.maxY (isEnergy secsStart) (isNothing o.fret)
        _ -> pure unit
      events -> go false events
  -- Sustain ends
  for_ colors \{ c: getColor, x: offsetX } -> do
    setFillStyle customize.sustainBorder stuff
    zoomDesc (getColor protar.notes) \secs evt -> case evt of
      SustainEnd -> do
        let futureSecs = secToNum $ secs <> negateDuration stuff.time
        if stuff.app.settings.autoplay && futureSecs <= 0.0
          then pure unit -- note is in the past or being hit now
          else fillRect
            { x: toNumber $ targetX + offsetX + 11
            , y: toNumber $ secsToPxVert secs
            , width: 9.0
            , height: 1.0
            } stuff
      _ -> pure unit
  -- Notes
  for_ colors \{ c: getColor, x: offsetX, strum: strumImage, hopo: hopoImage, tap: tapImage, shades: shades } -> do
    zoomDesc (getColor protar.notes) \secs evt -> let
      withNoteType obj = do
        let futureSecs = secToNum $ secs <> negateDuration stuff.time
        if stuff.app.settings.autoplay && futureSecs <= 0.0
          then do
            -- note is in the past or being hit now
            if (-0.1) < futureSecs
              then do
                setFillStyle (shades.hit $ (futureSecs + 0.1) / 0.05) stuff
                fillRect { x: toNumber $ targetX + offsetX + 1, y: toNumber $ targetY - 4, width: toNumber $ widthFret - 1, height: 8.0 } stuff
              else pure unit
          else do
            let y = secsToPxVert secs
                isEnergy = case Map.lookupLE secs protar.energy of
                  Just {value: bool} -> bool
                  Nothing            -> false
                fretImage i = case index protarFrets i of
                  Just x  -> x
                  Nothing -> Image_pro_fret_00 -- whatever
            case obj.fret of
              Just fret -> let
                gemImg = case obj.noteType of
                  Strum -> if isEnergy then Image_gem_energy_pro      else strumImage
                  HOPO  -> if isEnergy then Image_gem_energy_pro_hopo else hopoImage
                  Tap   -> if isEnergy then Image_gem_energy_pro_tap  else tapImage
                in do
                  drawImage gemImg           (toNumber $ targetX + offsetX) (toNumber $ y - 10) stuff
                  drawImage (fretImage fret) (toNumber $ targetX + offsetX) (toNumber $ y - 10) stuff
              Nothing -> let
                gemImg = case obj.noteType of
                  Strum -> if isEnergy then Image_gem_energy_mute      else Image_gem_mute
                  HOPO  -> if isEnergy then Image_gem_energy_mute_hopo else Image_gem_mute_hopo
                  Tap   -> if isEnergy then Image_gem_energy_mute_tap  else Image_gem_mute_tap
                in drawImage gemImg (toNumber $ targetX + offsetX) (toNumber $ y - 10) stuff
      in case evt of
        Note    (ProtarNote obj) -> withNoteType obj
        Sustain (ProtarNote obj) -> withNoteType obj
        SustainEnd               -> pure unit
  pure $ startX + protar.chordsWidth + widthHighway + customize.marginWidth
