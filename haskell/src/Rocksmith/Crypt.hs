module Rocksmith.Crypt where

import           Codec.Compression.Zlib (decompress)
import           Control.Monad.Fail     (MonadFail)
import           Crypto.Cipher.AES
import           Crypto.Cipher.Types
import           Crypto.Error
import           Data.Binary.Get
import qualified Data.ByteString        as B
import qualified Data.ByteString.Lazy   as BL

data GamePlatform
  = PC
  | Mac
  | Xbox360
  | PS3
  deriving (Eq, Ord, Show, Enum, Bounded)

unpackSNG :: GamePlatform -> FilePath -> IO BL.ByteString
unpackSNG plat fp = do
  bs <- B.readFile fp
  bs' <- case plat of
    PC  -> decryptSNGData bs sngKeyPC
    Mac -> decryptSNGData bs sngKeyMac
    _   -> return $ B.drop 8 bs
  return $ decompress $ BL.fromStrict $ B.drop 4 bs'

sngKeyMac, sngKeyPC :: B.ByteString
sngKeyMac = B.pack
  [ 0x98, 0x21, 0x33, 0x0E, 0x34, 0xB9, 0x1F, 0x70
  , 0xD0, 0xA4, 0x8C, 0xBD, 0x62, 0x59, 0x93, 0x12
  , 0x69, 0x70, 0xCE, 0xA0, 0x91, 0x92, 0xC0, 0xE6
  , 0xCD, 0xA6, 0x76, 0xCC, 0x98, 0x38, 0x28, 0x9D
  ]
sngKeyPC = B.pack
  [ 0xCB, 0x64, 0x8D, 0xF3, 0xD1, 0x2A, 0x16, 0xBF
  , 0x71, 0x70, 0x14, 0x14, 0xE6, 0x96, 0x19, 0xEC
  , 0x17, 0x1C, 0xCA, 0x5D, 0x2A, 0x14, 0x2E, 0x3E
  , 0x59, 0xDE, 0x7A, 0xDD, 0xA1, 0x8A, 0x3A, 0x30
  ]

decryptSNGData :: (MonadFail m) => B.ByteString -> B.ByteString -> m B.ByteString
decryptSNGData input key = do
  Just iv <- flip runGet (BL.fromStrict input) $ do
    0x4A <- getWord32be
    _platform <- getWord32be
    iv <- getByteString 16
    return $ return $ makeIV iv
  CryptoPassed cipher <- return $ cipherInit key
  return $ cfbDecrypt (cipher :: AES256) iv $ B.drop 24 input
