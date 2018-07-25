{-# LANGUAGE DeriveDataTypeable #-}
{-# LANGUAGE DeriveGeneric      #-}
{-# LANGUAGE OverloadedStrings  #-}

module Main where

import qualified Codec.Archive.Tar             as Tar
import qualified Codec.Compression.GZip        as GZ
import           Data.Aeson
import qualified Data.ByteString.Lazy          as B
import           Data.List
import qualified Data.List.NonEmpty            as NE
import           Data.Monoid
import qualified Data.Text                     as T
import           Data.Version                  (showVersion)
import           GHC.Generics
import           Network.HTTP.Conduit
import           Network.HTTP.Simple
import           Paths_curl_runnings           (version)
import           System.Console.CmdArgs
import           System.Directory
import           System.Environment
import           System.Exit
import           System.Info
import           Testing.CurlRunnings
import           Testing.CurlRunnings.Internal
import           Testing.CurlRunnings.Types

-- | Command line flags
data CurlRunnings = CurlRunnings
  { file    :: FilePath
  , grep    :: Maybe T.Text
  , upgrade :: Bool
  } deriving (Show, Data, Typeable, Eq)

-- | cmdargs object
argParser :: CurlRunnings
argParser =
  CurlRunnings
  { file = def &= typFile &= help "File to run"
  , grep = def &= help "Regex to filter test cases by name"
  , upgrade = def &= help "Pull the latest version of curl runnings"
  } &=
  summary ("curl-runnings " ++ showVersion version) &=
  program "curl-runnings" &=
  verbosity &=
  help "Use the --file or -f flag to specify an intput file spec to run"

-- | A single release asset in a github release. Eg curl-runnings-${version}.tar.gz
data GithubReleaseAsset = GithubReleaseAsset
  { name                 :: String
  , browser_download_url :: String -- snake case because that's what we get back from github
  } deriving (Show, Generic)

instance FromJSON GithubReleaseAsset

-- | The json response we expect from github when we check for the latest release
data GithubReleaseResponse = GithubReleaseResponse
  { assets   :: NE.NonEmpty GithubReleaseAsset
  , tag_name :: String -- snake case because that's what we get back from github
  } deriving (Show, Generic)

instance FromJSON GithubReleaseResponse

setGithubReqHeaders :: Request -> Request
setGithubReqHeaders = setRequestHeaders [("User-Agent", "aviaviavi")]

runFile :: FilePath -> Verbosity -> Maybe T.Text -> IO ()
runFile "" _ _ =
  putStrLn
    "Please specify an input file with the --file (-f) flag or use --help for more information"
runFile path verbosityLevel regexp = do
  home <- getEnv "HOME"
  suite <- decodeFile . T.unpack $ T.replace "~" (T.pack home) (T.pack path)
  case suite of
    Right s -> do
      results <-
        runSuite (s {suiteCaseFilter = regexp}) $ toLogLevel verbosityLevel
      if any isFailing results
        then putStrLn (T.unpack $ makeRed "Some tests failed") >>
             exitWith (ExitFailure 1)
        else putStrLn . T.unpack $ makeGreen "All tests passed!"
    Left message ->
      (putStrLn . T.unpack . makeRed . T.pack $
       "Couldn't read input json or yaml file: " <> message) >>
      exitWith (ExitFailure 1)

-- | If we're on mac, we want a *-mac tarball from the releases page. If we're on linux we
-- do not
filterAsset :: NE.NonEmpty GithubReleaseAsset -> Maybe GithubReleaseAsset
filterAsset assetList = find filterFn $ NE.toList assetList
  where
    filterFn' a = "mac" `isInfixOf` Main.name a
    filterFn =
      if os == "darwin"
        then filterFn'
        else not . filterFn'

-- | We'll upgrade any time the latest version is different from what we have
shouldUpgrade :: GithubReleaseResponse -> Bool
shouldUpgrade response = showVersion version /= tag_name response

-- | If conditions are met, download the appropriate tarball from the latest
-- github release, extract and copy to /usr/local/bin
upgradeCurlRunnings :: IO ()
upgradeCurlRunnings =
  let tmpArchive = "/tmp/curl-runnings-latest.tar.gz"
      tmpArchiveExtracedFolder = "/tmp/curl-runnings-latest"
      tmpExtractedBin = tmpArchiveExtracedFolder ++ "curl-runnings"
      installPath = "/usr/local/bin/curl-runnings"
  in do req <-
          parseRequest
            "https://api.github.com/repos/aviaviavi/curl-runnings/releases/latest"
        req' <- return $ setGithubReqHeaders req
        resp <- httpBS req'
        decoded <- return $ eitherDecode' . B.fromStrict $ getResponseBody resp
        case decoded of
          Right r ->
            if shouldUpgrade r
              then let asset = filterAsset $ assets r
                   in case asset of
                        (Just a) -> do
                          let downloadUrl = browser_download_url a
                          putStrLn
                            "Getting the latest version of curl-runnings..."
                          downloadResp <-
                            httpBS . setGithubReqHeaders =<<
                            parseRequest downloadUrl
                          _ <-
                            B.writeFile
                              tmpArchive
                              (B.fromStrict $ getResponseBody downloadResp)
                          putStrLn "Extracting..."
                          Tar.unpack tmpArchiveExtracedFolder .
                            Tar.read . GZ.decompress =<<
                            B.readFile tmpArchive
                          putStrLn "Copying..."
                          permissions <- getPermissions tmpExtractedBin
                          setPermissions
                            tmpExtractedBin
                            (setOwnerExecutable True permissions)
                          copyFile tmpExtractedBin installPath
                          putStrLn $
                            "The latest version curl-runnings has been installed to /usr/local/bin. " ++
                            "If you are using curl-runnings from a different location," ++
                            " please update your environment accordingly."
                        -- We got a good response from github, but no asset for our platform was there
                        Nothing -> do
                          putStrLn . T.unpack $
                            makeRed "Error upgrading curl-runnings"
                          putStrLn $
                            "No asset found from github. It's possible the binary for your " ++
                            "platform hasn't yet been uploaded to the latest release. Please wait and try again. " ++
                            "If the issue persists, please open an issue at https://github.com/aviaviavi/curl-runnings/issues."
                          exitWith (ExitFailure 1)
              -- No upgrade required
              else putStrLn $
                   "curl-runnings is already at the newest version: " ++
                   showVersion version ++ ". Nothing to upgrade."
          -- Coudn't decode github response
          Left err -> do
            putStrLn . T.unpack $ makeRed "Error upgrading curl-runnings"
            putStrLn err
            exitWith (ExitFailure 1)

toLogLevel :: Verbosity -> LogLevel
toLogLevel v = toEnum $ fromEnum v

main :: IO ()
main = do
  userArgs <- cmdArgs argParser
  verbosityLevel <- getVerbosity
  if upgrade userArgs
    then upgradeCurlRunnings
    else runFile (file userArgs) verbosityLevel (grep userArgs)
