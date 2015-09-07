module Magma (runMagmaMIDI, runMagma, oggToMogg, withSystemTempDirectory) where

import qualified Control.Exception            as Exception
import           Control.Monad                (forM_)
import           Control.Monad.Trans.Resource (ResourceT, runResourceT)
import           Data.Bits                    (shiftL)
import qualified Data.ByteString              as B
import           Data.Conduit.Audio           (AudioSource, Duration (..),
                                               silent)
import           Data.Conduit.Audio.Sndfile   (sinkSnd)
import           Data.Int                     (Int16)
import           Data.Word                    (Word32)
import           Development.Shake
import           Resources                    (magmaFiles)
import qualified Sound.File.Sndfile           as Snd
import qualified System.Directory             as Dir
import           System.FilePath              ((</>))
import           System.Info                  (os)
import qualified System.IO                    as IO
import           System.IO.Temp               (createTempDirectory)

withExe :: (FilePath -> [String] -> a) -> FilePath -> [String] -> a
withExe f exe args = if os == "mingw32"
  then f exe args
  else f "wine" $ exe : args

callProcessIn :: FilePath -> FilePath -> [String] -> Action ()
callProcessIn dir = command_
  [ Cwd dir
  , Stdin ""
  , WithStdout True
  , WithStderr True
  , EchoStdout False
  , EchoStderr False
  ]

runMagmaMIDI :: FilePath -> FilePath -> Action ()
runMagmaMIDI proj mid = withSystemTempDirectory "magma" $ \tmp -> do
  wd <- liftIO Dir.getCurrentDirectory
  let proj' = wd </> proj
      mid'  = wd </> mid
  liftIO $ Dir.createDirectory $ tmp </> "gen"
  liftIO $ forM_ magmaFiles $ \(path, bs) -> B.writeFile (tmp </> path) bs
  withExe (callProcessIn tmp) (tmp </> "MagmaCompilerC3.exe") ["-export_midi", proj', mid']

runMagma :: FilePath -> FilePath -> Action ()
runMagma proj rba = withSystemTempDirectory "magma" $ \tmp -> do
  wd <- liftIO Dir.getCurrentDirectory
  let proj' = wd </> proj
      rba'  = wd </> rba
  liftIO $ Dir.createDirectory $ tmp </> "gen"
  liftIO $ forM_ magmaFiles $ \(path, bs) -> B.writeFile (tmp </> path) bs
  withExe (callProcessIn tmp) (tmp </> "MagmaCompilerC3.exe") [proj', rba']

-- | Like the one from 'System.IO.Temp', but in the 'Action' monad.
withSystemTempDirectory :: String -> (FilePath -> Action a) -> Action a
withSystemTempDirectory template f = do
  parent <- liftIO $ Dir.getTemporaryDirectory
  dir <- liftIO $ createTempDirectory parent template
  actionFinally (f dir) $ ignoringIOErrors $ Dir.removeDirectoryRecursive dir
  where ignoringIOErrors ioe =
          ioe `Exception.catch` (\e -> const (return ()) (e :: IOError))

oggToMogg :: FilePath -> FilePath -> Action ()
oggToMogg ogg mogg = withSystemTempDirectory "ogg2mogg" $ \tmp -> do
  wd <- liftIO Dir.getCurrentDirectory
  let ogg'  = wd </> ogg
      mogg' = wd </> mogg
  liftIO $ Dir.createDirectory $ tmp </> "gen"
  liftIO $ forM_ magmaFiles $ \(path, bs) -> B.writeFile (tmp </> path) bs
  liftIO $ Dir.renameFile (tmp </> "oggenc-redirect.exe") (tmp </> "oggenc.exe")
  liftIO $ Dir.copyFile ogg' $ tmp </> "audio.ogg"
  let proj = "hellskitchen.rbproj"
      rba = "out.rba"
  liftIO $ runResourceT
    $ sinkSnd (tmp </> "silence.wav")
    (Snd.Format Snd.HeaderFormatWav Snd.SampleFormatPcm16 Snd.EndianFile)
    (silent (Seconds 31) 44100 2 :: AudioSource (ResourceT IO) Int16)
  _ <- withExe (callProcessIn tmp) (tmp </> "MagmaCompilerC3.exe") [proj, rba]
  liftIO $ IO.withBinaryFile (tmp </> rba) IO.ReadMode $ \hrba -> do
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
