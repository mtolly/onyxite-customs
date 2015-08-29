{-# LANGUAGE TemplateHaskell #-}
module Magma (runMagmaMIDI, runMagma, oggToMogg) where

import           Control.Monad                (forM_)
import           Control.Monad.Trans.Resource (ResourceT, runResourceT)
import           Data.Bits                    (shiftL)
import qualified Data.ByteString              as B
import           Data.Conduit.Audio           (AudioSource, Duration (..),
                                               silent)
import           Data.Conduit.Audio.Sndfile   (sinkSnd)
import           Data.FileEmbed               (embedDir)
import           Data.Int                     (Int16)
import           Data.Word                    (Word32)
import qualified Sound.File.Sndfile           as Snd
import qualified System.Directory             as Dir
import           System.FilePath              ((</>))
import           System.Info                  (os)
import qualified System.IO                    as IO
import           System.IO.Temp               (withSystemTempDirectory)
import           System.Process               (CreateProcess (..), proc,
                                               readCreateProcess)

magmaFiles :: [(FilePath, B.ByteString)]
magmaFiles = $(embedDir "vendors/magma/")

withExe :: (FilePath -> [String] -> IO a) -> FilePath -> [String] -> IO a
withExe f exe args = if os == "mingw32"
  then f exe args
  else f "wine" $ exe : args

runMagmaMIDI :: FilePath -> FilePath -> IO ()
runMagmaMIDI proj mid = withSystemTempDirectory "magma" $ \tmp -> do
  wd <- Dir.getCurrentDirectory
  let proj' = wd </> proj
      mid'  = wd </> mid
  Dir.createDirectory $ tmp </> "gen"
  forM_ magmaFiles $ \(path, bs) -> B.writeFile (tmp </> path) bs
  withExe
    (\exe args -> readCreateProcess (proc exe args){ cwd = Just tmp } "" >>= putStr)
    "MagmaCompilerC3.exe" ["-export_midi", proj', mid']

runMagma :: FilePath -> FilePath -> IO ()
runMagma proj rba = withSystemTempDirectory "magma" $ \tmp -> do
  wd <- Dir.getCurrentDirectory
  let proj' = wd </> proj
      rba'  = wd </> rba
  Dir.createDirectory $ tmp </> "gen"
  forM_ magmaFiles $ \(path, bs) -> B.writeFile (tmp </> path) bs
  withExe
    (\exe args -> readCreateProcess (proc exe args){ cwd = Just tmp } "" >>= putStr)
    "MagmaCompilerC3.exe" [proj', rba']

oggToMogg :: FilePath -> FilePath -> IO ()
oggToMogg ogg mogg = withSystemTempDirectory "ogg2mogg" $ \tmp -> do
  wd <- Dir.getCurrentDirectory
  let ogg'  = wd </> ogg
      mogg' = wd </> mogg
  Dir.createDirectory $ tmp </> "gen"
  forM_ magmaFiles $ \(path, bs) -> B.writeFile (tmp </> path) bs
  Dir.renameFile (tmp </> "oggenc-redirect.exe") (tmp </> "oggenc.exe")
  Dir.copyFile ogg' $ tmp </> "audio.ogg"
  let proj = "hellskitchen.rbproj"
      rba = "out.rba"
  runResourceT
    $ sinkSnd (tmp </> "silence.wav")
    (Snd.Format Snd.HeaderFormatWav Snd.SampleFormatPcm16 Snd.EndianFile)
    (silent (Seconds 31) 44100 2 :: AudioSource (ResourceT IO) Int16)
  _ <- withExe
    (\exe args -> readCreateProcess (proc exe args){ cwd = Just tmp } "" >>= putStr)
   "MagmaCompilerC3.exe"
   [proj, rba]
  IO.withBinaryFile (tmp </> rba) IO.ReadMode $ \hrba -> do
    IO.hSeek hrba IO.AbsoluteSeek $ 4 + (4 * 3)
    moggOffset <- hReadWord32le hrba
    IO.hSeek hrba IO.AbsoluteSeek $ 4 + (4 * 10)
    moggLength <- hReadWord32le hrba
    IO.hSeek hrba IO.AbsoluteSeek $ fromIntegral moggOffset
    moggData <- B.hGet hrba $ fromIntegral moggLength
    B.writeFile mogg' moggData

hReadWord32le :: IO.Handle -> IO Word32
hReadWord32le h = do
  [a, b, c, d] <- fmap (map fromIntegral . B.unpack) $ B.hGet h 4
  return $ a + (b `shiftL` 8) + (c `shiftL` 16) + (d `shiftL` 24)
