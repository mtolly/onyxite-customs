{- | Datatypes and functions used across multiple MIDI parsers. -}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE LambdaCase        #-}
{-# LANGUAGE PatternSynonyms   #-}
{-# LANGUAGE TemplateHaskell   #-}
{-# LANGUAGE TupleSections     #-}
{-# LANGUAGE ViewPatterns      #-}
{-# LANGUAGE DeriveFunctor     #-}
{-# LANGUAGE DeriveFoldable    #-}
{-# LANGUAGE DeriveTraversable #-}
module RockBand.Common where

import           Control.Monad                    (guard)
import           Data.Char                        (isSpace)
import qualified Data.EventList.Relative.TimeBody as RTB
import           Data.List                        (stripPrefix)
import           Language.Haskell.TH
import qualified Numeric.NonNegative.Class        as NNC
import qualified Sound.MIDI.File.Event            as E
import qualified Sound.MIDI.File.Event.Meta       as Meta
import           Text.Read                        (readMaybe)
import qualified Sound.MIDI.Util as U
import Data.Bifunctor (Bifunctor(..))

-- | Class for events which are stored as a @\"[x y z]\"@ text event.
class Command a where
  toCommand :: [String] -> Maybe a
  fromCommand :: a -> [String]

reverseLookup :: (Eq b) => [a] -> (a -> b) -> b -> Maybe a
reverseLookup xs f y = let
  pairs = [ (f x, x) | x <- xs ]
  in lookup y pairs

each :: (Enum a, Bounded a) => [a]
each = [minBound .. maxBound]

data Mood
  = Mood_idle_realtime
  | Mood_idle
  | Mood_idle_intense
  | Mood_play
  | Mood_mellow
  | Mood_intense
  | Mood_play_solo
  deriving (Eq, Ord, Show, Read, Enum, Bounded)

instance Command Mood where
  fromCommand x = [drop (length "Mood_") $ show x]
  toCommand = \case
    ["play", "solo"] -> Just Mood_play_solo
    cmd -> reverseLookup each fromCommand cmd

instance Command [String] where
  toCommand   = Just
  fromCommand = id

data Difficulty = Easy | Medium | Hard | Expert
  deriving (Eq, Ord, Show, Read, Enum, Bounded)

readCommand' :: (Command a) => E.T -> Maybe a
readCommand' (E.MetaEvent (Meta.TextEvent s)) = readCommand s
readCommand' (E.MetaEvent (Meta.Lyric s)) = readCommand s
readCommand' _ = Nothing

-- | Turns a string like @\"[foo bar baz]\"@ into some parsed type.
readCommand :: (Command a) => String -> Maybe a
readCommand s =  case dropWhile isSpace s of
  '[' : s'    -> case dropWhile isSpace $ reverse s' of
    ']' : s'' -> toCommand $ words $ reverse s''
    _         -> Nothing
  _           -> Nothing

showCommand' :: (Command a) => a -> E.T
showCommand' = E.MetaEvent . Meta.TextEvent . showCommand

-- | Opposite of 'readCommand'.
showCommand :: (Command a) => a -> String
showCommand ws = "[" ++ unwords (fromCommand ws) ++ "]"

data Trainer
  = TrainerBegin Int
  | TrainerNorm Int
  | TrainerEnd Int
  deriving (Eq, Ord, Show, Read)

instance Command (Trainer, String) where
  fromCommand (t, s) = case t of
    TrainerBegin i -> ["begin_" ++ s, "song_trainer_" ++ s ++ "_" ++ show i]
    TrainerNorm  i -> [ s ++ "_norm", "song_trainer_" ++ s ++ "_" ++ show i]
    TrainerEnd   i -> [  "end_" ++ s, "song_trainer_" ++ s ++ "_" ++ show i]
  toCommand [x, stripPrefix "song_trainer_" -> Just y] = case x of
    (stripPrefix "begin_" -> Just s) -> f s TrainerBegin
    (stripSuffix "_norm"  -> Just s) -> f s TrainerNorm
    (stripPrefix "end_"   -> Just s) -> f s TrainerEnd
    _ -> Nothing
    where f s con = case stripPrefix s y of
            Just ('_' : (readMaybe -> Just i)) -> Just (con i, s)
            Just (readMaybe -> Just i) -> Just (con i, s)
            _ -> Nothing
          stripSuffix sfx s = fmap reverse $ stripPrefix (reverse sfx) (reverse s)
  toCommand _ = Nothing

data Key = C | Cs | D | Ds | E | F | Fs | G | Gs | A | As | B
  deriving (Eq, Ord, Show, Read, Enum, Bounded)

keyP :: Int -> Q Pat
keyP = \case
  0  -> [p| C  |]
  1  -> [p| Cs |]
  2  -> [p| D  |]
  3  -> [p| Ds |]
  4  -> [p| E  |]
  5  -> [p| F  |]
  6  -> [p| Fs |]
  7  -> [p| G  |]
  8  -> [p| Gs |]
  9  -> [p| A  |]
  10 -> [p| As |]
  11 -> [p| B  |]
  i  -> error $ "keyP: can't make Key pattern from " ++ show i

baseCopyExpert
  :: (NNC.C t, Ord a)
  => (Difficulty -> d -> a)
  -> (a -> Maybe (Difficulty, d))
  -> RTB.T t a
  -> RTB.T t a
baseCopyExpert differ undiffer rtb = let
  (diffEvents, rtb') = RTB.partitionMaybe undiffer rtb
  [e, m, h, x] = flip map [Easy, Medium, Hard, Expert] $ \diff ->
    flip RTB.mapMaybe diffEvents $ \(diff', evt) -> guard (diff == diff') >> return evt
  e' = fmap (differ Easy  ) $ if RTB.null e then x else e
  m' = fmap (differ Medium) $ if RTB.null m then x else m
  h' = fmap (differ Hard  ) $ if RTB.null h then x else h
  x' = fmap (differ Expert) x
  in foldr RTB.merge rtb' [e', m', h', x']

data LongNote s a
  = NoteOff     a
  | Blip      s a
  | NoteOn    s a
  deriving (Eq, Ord, Show, Read, Functor, Foldable, Traversable)

instance Bifunctor LongNote where
  first f = \case
    NoteOff  x -> NoteOff      x
    Blip   s x -> Blip   (f s) x
    NoteOn s x -> NoteOn (f s) x
  second = fmap

joinEdges :: (NNC.C t, Eq a) => RTB.T t (LongNote s a) -> RTB.T t (s, a, Maybe t)
joinEdges rtb = case RTB.viewL rtb of
  Nothing -> RTB.empty
  Just ((dt, x), rtb') -> case x of
    Blip s a -> RTB.cons dt (s, a, Nothing) $ joinEdges rtb'
    NoteOn s a -> let
      isNoteOff (NoteOff a') = guard (a == a') >> Just ()
      isNoteOff _            = Nothing
      in case U.extractFirst isNoteOff rtb' of
        Nothing -> RTB.delay dt $ joinEdges rtb' -- unmatched note on
        Just ((len, ()), rtb'') -> RTB.cons dt (s, a, Just len) $ joinEdges rtb''
    NoteOff _ -> RTB.delay dt $ joinEdges rtb' -- unmatched note off

splitEdges :: (NNC.C t, Ord s, Ord a) => RTB.T t (s, a, Maybe t) -> RTB.T t (LongNote s a)
splitEdges = U.trackJoin . fmap f where
  f (s, a, len) = case len of
    Nothing -> RTB.singleton NNC.zero $ Blip s a
    Just t  -> RTB.fromPairList
      [ (NNC.zero, NoteOn s a)
      , (t       , NoteOff  a)
      ]
