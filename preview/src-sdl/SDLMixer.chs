module SDLMixer where

import Foreign
import Foreign.C
import Control.Exception (bracket_)

import SDLUtil

#include <SDL_mixer.h>

mixDefaultFormat :: Word16
mixDefaultFormat = {#const MIX_DEFAULT_FORMAT#}

{#enum MIX_InitFlags as MixInitFlag {}
  deriving (Eq, Ord, Show, Read, Bounded) #}

{#fun Mix_Init as ^ { `CInt' } -> `CInt' #}
{#fun Mix_Quit as ^ {} -> `()' #}
{#fun Mix_OpenAudio as ^ { `CInt', `Word16', `CInt', `CInt' } -> `CInt' #}
{#fun Mix_CloseAudio as ^ {} -> `()' #}

{#pointer *Mix_Music as MixMusic #}
{#fun Mix_LoadMUS as ^ { `CString' } -> `MixMusic' #}
{#fun Mix_FreeMusic as ^ { `MixMusic' } -> `()' #}
{#fun Mix_PlayMusic as ^ { `MixMusic', `CInt' } -> `CInt' #}

withMixer :: [MixInitFlag] -> IO a -> IO a
withMixer flags = let
  val = fromIntegral $ foldr (.|.) 0 $ map fromEnum flags
  in bracket_ (sdlCode (== val) $ mixInit val) mixQuit

withMixerAudio :: CInt -> Word16 -> CInt -> CInt -> IO a -> IO a
withMixerAudio a b c d = bracket_ (zero $ mixOpenAudio a b c d) mixCloseAudio
