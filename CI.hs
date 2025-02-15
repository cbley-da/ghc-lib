-- Copyright (c) 2019-2020, Digital Asset (Switzerland) GmbH and/or
-- its affiliates. All rights reserved.  SPDX-License-Identifier:
-- (Apache-2.0 OR BSD-3-Clause)

-- CI script, compatible with all of Travis, Appveyor and Azure.
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE CPP #-}
import Control.Monad.Extra
import System.Directory
import System.FilePath
import System.IO.Extra
import System.Info.Extra
import System.Process.Extra
import System.Time.Extra
import System.Info (os, arch)
import Data.Maybe
import Data.List.Extra
import Data.Time.Clock
import Data.Time.Calendar
import qualified Options.Applicative as Opts

main :: IO ()
main = do
    let opts =
          Opts.info (parseOptions Opts.<**> Opts.helper)
          ( Opts.fullDesc
            <> Opts.progDesc "Build ghc-lib and ghc-lib-parser tarballs."
            <> Opts.header "CI - CI script for ghc-lib"
          )
    Options { ghcFlavor, noGhcCheckout, stackOptions, versionSuffix } <- Opts.execParser opts
    version <- buildDists ghcFlavor noGhcCheckout stackOptions versionSuffix
    putStrLn version

data Options = Options
    { ghcFlavor :: GhcFlavor
    , noGhcCheckout :: Bool
    , stackOptions :: StackOptions
    , versionSuffix :: Maybe String
    } deriving (Show)

data StackOptions = StackOptions
    { stackYaml :: Maybe String -- Optional config file
    , resolver :: Maybe String  -- If 'Just _', override stack.yaml.
    , verbosity :: Maybe String -- If provided, pass '--verbosity=xxx' to 'stack build'. Valid values are "silent",  "error", "warn", "info" or "debug".
    , cabalVerbose :: Bool -- If enabled, pass '--cabal-verbose' to 'stack build'.
    , ghcOptions :: Maybe String -- If 'Just _', pass '--ghc-options="xxx"' to 'stack build' (for ghc verbose, try 'v3').
    } deriving (Show)

data GhcFlavor = Ghc941
               | Ghc922
               | Ghc921
               | Ghc901
               | Ghc902
               | Ghc8101
               | Ghc8102
               | Ghc8103
               | Ghc8104
               | Ghc8105
               | Ghc8106
               | Ghc8107
               | Ghc881
               | Ghc882
               | Ghc883
               | Ghc884
               | Da { mergeBaseSha :: String, patches :: [String], flavor :: String, upstream :: String }
               | GhcMaster String
  deriving (Eq, Show)

-- Last tested gitlab.haskell.org/ghc/ghc.git at
current :: String
current = "ffbe28e56aa382164525300fbc32d78eefd95e7d" -- 2022-05-23

-- Command line argument generators.

stackYamlOpt :: Maybe String -> String
stackYamlOpt = \case
  Just stackYaml -> "--stack-yaml " ++ stackYaml
  Nothing -> ""

stackResolverOpt :: Maybe String -> String
stackResolverOpt = \case
  Just resolver -> "--resolver " ++ resolver
  Nothing -> ""

ghcFlavorOpt :: GhcFlavor -> String
ghcFlavorOpt = \case
    Ghc941 -> "--ghc-flavor ghc-9.4.1"
    Ghc922 -> "--ghc-flavor ghc-9.2.2"
    Ghc921 -> "--ghc-flavor ghc-9.2.1"
    Ghc901 -> "--ghc-flavor ghc-9.0.1"
    Ghc902 -> "--ghc-flavor ghc-9.0.2"
    Ghc8101 -> "--ghc-flavor ghc-8.10.1"
    Ghc8102 -> "--ghc-flavor ghc-8.10.2"
    Ghc8103 -> "--ghc-flavor ghc-8.10.3"
    Ghc8104 -> "--ghc-flavor ghc-8.10.4"
    Ghc8105 -> "--ghc-flavor ghc-8.10.5"
    Ghc8106 -> "--ghc-flavor ghc-8.10.6"
    Ghc8107 -> "--ghc-flavor ghc-8.10.7"
    Ghc881 -> "--ghc-flavor ghc-8.8.1"
    Ghc882 -> "--ghc-flavor ghc-8.8.2"
    Ghc883 -> "--ghc-flavor ghc-8.8.3"
    Ghc884 -> "--ghc-flavor ghc-8.8.4"
    Da { flavor } -> "--ghc-flavor " <> flavor
    GhcMaster _hash -> "--ghc-flavor ghc-master"
      -- The git SHA1 hash is not passed to ghc-lib-gen at this time.

stackVerbosityOpt :: Maybe String -> String
stackVerbosityOpt = \case
  Just verbosity -> "--verbosity=" ++ verbosity
  Nothing -> ""

cabalVerboseOpt :: Bool -> String
cabalVerboseOpt True = "--cabal-verbose"; cabalVerboseOpt False = ""

ghcOptionsOpt :: Maybe String -> String
ghcOptionsOpt = \case
  Just options -> "--ghc-options=\"" ++ options ++ "\""
  Nothing -> ""

genDateSuffix :: IO String
genDateSuffix = do
  UTCTime day _ <- getCurrentTime
  pure $ replace "-" "" (showGregorian day)

-- Calculate a version string based on a ghc flavor and a suffix.
genVersionStr :: GhcFlavor -> String -> String
genVersionStr flavor suffix =
  base <> case suffix of
    "" -> ""
    _ -> "." <> suffix
  where
    base = case flavor of
      Da {}       -> "8.8.1"
      GhcMaster _ -> "0"
      Ghc941      -> "9.4.1"
      Ghc922      -> "9.2.2"
      Ghc921      -> "9.2.1"
      Ghc901      -> "9.0.1"
      Ghc902      -> "9.0.2"
      Ghc8101     -> "8.10.1"
      Ghc8102     -> "8.10.2"
      Ghc8103     -> "8.10.3"
      Ghc8104     -> "8.10.4"
      Ghc8105     -> "8.10.5"
      Ghc8106     -> "8.10.6"
      Ghc8107     -> "8.10.7"
      Ghc881      -> "8.8.1"
      Ghc882      -> "8.8.2"
      Ghc883      -> "8.8.3"
      Ghc884      -> "8.8.4"

parseOptions :: Opts.Parser Options
parseOptions = Options
    <$> (parseDaOptions
         Opts.<|>
         Opts.option readFlavor
          ( Opts.long "ghc-flavor"
         <> Opts.help "The ghc-flavor to test against"
          )
        )
    <*> Opts.switch
          ( Opts.long "no-checkout"
          <> Opts.help "If enabled, don't perform a GHC checkout"
          )
    <*> parseStackOptions
    <*> Opts.optional
          ( Opts.strOption
            ( Opts.long "version-suffix"
            <> Opts.help "If specified, append to version string for generated ghc-lib. Otherwise use current date."
            )
          )
 where
   readFlavor :: Opts.ReadM GhcFlavor
   readFlavor = Opts.eitherReader $ \case
       "ghc-9.4.1" -> Right Ghc941
       "ghc-9.2.2" -> Right Ghc922
       "ghc-9.2.1" -> Right Ghc921
       "ghc-9.0.1" -> Right Ghc901
       "ghc-9.0.2" -> Right Ghc902
       "ghc-8.10.1" -> Right Ghc8101
       "ghc-8.10.2" -> Right Ghc8102
       "ghc-8.10.3" -> Right Ghc8103
       "ghc-8.10.4" -> Right Ghc8104
       "ghc-8.10.5" -> Right Ghc8105
       "ghc-8.10.6" -> Right Ghc8106
       "ghc-8.10.7" -> Right Ghc8107
       "ghc-8.8.1" -> Right Ghc881
       "ghc-8.8.2" -> Right Ghc882
       "ghc-8.8.3" -> Right Ghc883
       "ghc-8.8.4" -> Right Ghc884
       "ghc-master" -> Right (GhcMaster current)
       hash -> Right (GhcMaster hash)
   parseDaOptions :: Opts.Parser GhcFlavor
   parseDaOptions =
       Opts.flag' Da ( Opts.long "da" <> Opts.help "Enables DA custom build." )
       <*> Opts.strOption
           ( Opts.long "merge-base-sha"
          <> Opts.help "DA flavour only. Base commit to use from the GHC repo."
          <> Opts.showDefault
          <> Opts.value "ghc-8.8.1-release"
           )
       <*> (Opts.some
             (Opts.strOption
              ( Opts.long "patch"
             <> Opts.help "DA flavour only. Commits to merge in from the DA GHC fork, referenced as 'upstream'. Can be specified multiple times. If no patch is specified, default will be equivalent to `--patch upstream/da-master-8.8.1 --patch upstream/da-unit-ids-8.8.1`. Specifying any patch will overwrite the default (i.e. replace, not add)."
              ))
            Opts.<|>
            pure ["upstream/da-master-8.8.1", "upstream/da-unit-ids-8.8.1"])
       <*> Opts.strOption
           ( Opts.long "gen-flavor"
          <> Opts.help "DA flavor only. Flavor to pass on to ghc-lib-gen."
          <> Opts.showDefault
          <> Opts.value "da-ghc-8.8.1")
       <*> Opts.strOption
           ( Opts.long "upstream"
          <> Opts.help "DA flavor only. URL for the git remote add command."
          <> Opts.showDefault
          <> Opts.value "https://github.com/digital-asset/ghc.git")

parseStackOptions :: Opts.Parser StackOptions
parseStackOptions = StackOptions
    <$> Opts.optional ( Opts.strOption
        ( Opts.long "stack-yaml"
       <> Opts.help "If specified, pass '--stack-yaml=xxx' to stack"
        ))
    <*> Opts.optional ( Opts.strOption
        ( Opts.long "resolver"
       <> Opts.help "If specified, pass '--resolver=xxx' to stack"
        ))
    <*> Opts.optional ( Opts.strOption
        ( Opts.long "verbosity"
       <> Opts.help "If specified, pass '--verbosity=xxx' to stack"
        ))
    <*> Opts.switch
        ( Opts.long "cabal-verbose"
       <> Opts.help "If specified, pass '--cabal-verbose' to stack"
        )
    <*> Opts.optional ( Opts.strOption
        ( Opts.long "ghc-options"
       <> Opts.help "If specified, pass '--ghc-options=\"xxx\"' to stack"
        ))

buildDists :: GhcFlavor -> Bool -> StackOptions -> Maybe String -> IO String
buildDists
  ghcFlavor
  noGhcCheckout
  StackOptions {stackYaml, resolver, verbosity, cabalVerbose, ghcOptions}
  versionSuffix
  =
  do
    let stackConfig = fromMaybe "stack.yaml" stackYaml

    -- Clear up any detritus left over from previous runs.
    filesInDot <- getDirectoryContents "."
    let lockFiles = filter (isExtensionOf ".lock") filesInDot
        tarBalls  = filter (isExtensionOf ".tar.gz") filesInDot
        ghcDirs   = ["ghc" | not noGhcCheckout] ++ [ "ghc-lib", "ghc-lib-parser" ]
        toDelete  = ghcDirs ++ tarBalls ++ lockFiles
    forM_ toDelete removePath
    cmd $ "git checkout " ++ stackConfig

    -- Get packages missing on Windows needed by hadrian.
    when isWindows $
        stack "exec -- pacman -S autoconf automake-wrapper make patch python tar mintty --noconfirm"
    -- Building of hadrian dependencies that result from the
    -- invocations of ghc-lib-gen can require some versions of these
    -- have been installed.
    stack "build alex happy"

    -- If '--no-checkout' is given, it's on the caller to get the GHC
    -- clone with e.g.
    --  git clone https://gitlab.haskell.org/ghc/ghc.git && \
    --      git fetch --tags && git submodule update --init --recursive
    -- and it won't be deleted between runs.
    if noGhcCheckout then
      cmd "cd ghc && git clean -xdf && git submodule foreach git clean -xdf && git submodule foreach git checkout . && git checkout ."
    else do
      cmd "git clone https://gitlab.haskell.org/ghc/ghc.git"
      cmd "cd ghc && git fetch --tags"
    case ghcFlavor of
        Ghc941 -> cmd "cd ghc && git checkout ghc-9.4"
        Ghc922 -> cmd "cd ghc && git checkout ghc-9.2.2-release"
        Ghc921 -> cmd "cd ghc && git checkout ghc-9.2.1-release"
        Ghc901 -> cmd "cd ghc && git checkout ghc-9.0.1-release"
        Ghc902 -> cmd "cd ghc && git checkout ghc-9.0.2-release"
        Ghc8101 -> cmd "cd ghc && git checkout ghc-8.10.1-release"
        Ghc8102 -> cmd "cd ghc && git checkout ghc-8.10.2-release"
        Ghc8103 -> cmd "cd ghc && git checkout ghc-8.10.3-release"
        Ghc8104 -> cmd "cd ghc && git checkout ghc-8.10.4-release"
        Ghc8105 -> cmd "cd ghc && git checkout ghc-8.10.5-release"
        Ghc8106 -> cmd "cd ghc && git checkout ghc-8.10.6-release"
        Ghc8107 -> cmd "cd ghc && git checkout ghc-8.10.7-release"
        Ghc881 -> cmd "cd ghc && git checkout ghc-8.8.1-release"
        Ghc882 -> cmd "cd ghc && git checkout ghc-8.8.2-release"
        Ghc883 -> cmd "cd ghc && git checkout ghc-8.8.3-release"
        Ghc884 -> cmd "cd ghc && git checkout ghc-8.8.4-release"
        Da { mergeBaseSha, patches, upstream } -> do
            cmd $ "cd ghc && git checkout " <> mergeBaseSha
            -- Apply Digital Asset extensions.
            cmd $ "cd ghc && git remote add upstream " <> upstream
            cmd "cd ghc && git fetch upstream"
            cmd $ "cd ghc && git -c user.name=\"Cookie Monster\" -c user.email=cookie.monster@seasame-street.com merge --no-edit " <> unwords patches
        GhcMaster hash -> cmd $ "cd ghc && git checkout " ++ hash
    cmd "cd ghc && git submodule update --init --recursive"

    -- Feedback on the compiler used for ghc-lib-gen.
    stack "exec -- ghc --version"
    -- Build ghc-lib-gen. Do this here rather than in the Azure script
    -- so that it's not forgotten when testing this program locally.
    stack "build --no-terminal --ghc-options \"-Wall -Wno-name-shadowing -Werror\""

    -- Any invocations of GHC in the sdist steps that follow use the
    -- hadrian/stack.yaml resolver (which can and we should expect
    -- to be, different to our resolver).

    -- Calculate version and package names.
    version <- tag
    let pkg_ghclib = "ghc-lib-" ++ version
        pkg_ghclib_parser = "ghc-lib-parser-" ++ version

    -- Make and extract an sdist of ghc-lib-parser.
    cmd "cd ghc && git checkout ."

    stack $ "exec -- ghc-lib-gen ghc --ghc-lib-parser " ++ ghcFlavorOpt ghcFlavor
    patchVersion version "ghc/ghc-lib-parser.cabal"
    mkTarball pkg_ghclib_parser
    renameDirectory pkg_ghclib_parser "ghc-lib-parser"
    removeFile "ghc/ghc-lib-parser.cabal"
    cmd "git checkout stack.yaml"

    -- Make and extract an sdist of ghc-lib.
    cmd "cd ghc && git checkout ."
    stack $ "exec -- ghc-lib-gen ghc --ghc-lib " ++ ghcFlavorOpt ghcFlavor
    patchVersion version "ghc/ghc-lib.cabal"
    patchConstraint version "ghc/ghc-lib.cabal"
    mkTarball pkg_ghclib
    renameDirectory pkg_ghclib "ghc-lib"
    removeFile "ghc/ghc-lib.cabal"
    cmd "git checkout stack.yaml"

    -- Append the libraries and examples to the prevailing stack
    -- configuration file.
    stackYaml <- readFile' stackConfig
    writeFile stackConfig $
      stackYaml ++
      unlines [ "- ghc-lib-parser"
              , "- ghc-lib"
              , "- examples/test-utils"
              , "- examples/mini-hlint"
              , "- examples/mini-compile"
              ] ++
      case ghcFlavor of
#if __GLASGOW_HASKELL__ == 804 && __GLASGOW_HASKELL_PATCHLEVEL1__ == 4
        GhcMaster _ ->
          -- Resolver 'lts-12.26' serves 'transformers-0.5.5.0' which
          -- lacks 'Control.Monad.Trans.RWS.CPS'. The need for that
          -- module came in around around 09/20/2019. Putting this
          -- here keeps the CI ghc-8.4.4 builds going (for 8.8.*
          -- ghc-libs, there is no support for bootstrapping ghc-8.10
          -- builds with ghc-8.4.4; see azure-pipelines.yml for an
          -- explanation)
          unlines ["extra-deps: [transformers-0.5.6.2]"]
#endif
        Da {} ->
          unlines ["flags: {mini-compile: {daml-unit-ids: true}}"]
        _ -> ""

    -- All invocations of GHC from here on are using our resolver.

    -- Feedback on what compiler has been selected for building
    -- ghc-lib packages and tests.
    stack "exec -- ghc --version"

    -- Separate the two library build commands so they are
    -- independently timed. Note that optimizations in these builds
    -- are disabled in stack.yaml via `ghc-options: -O0`.
    -- `-haddock` makes the parser stricter about Haddock comments (see
    -- https://gitlab.haskell.org/ghc/ghc/-/commit/c35c545d3f32f092c52052349f741739a844ec0f).
    -- TODO: https://github.com/digital-asset/ghc/issues/97
    let ghcOpts = case ghcFlavor of Da {} -> ghcOptionsOpt ghcOptions;  _ -> ghcOptionsWithHaddock ghcOptions
    stack $ "--no-terminal --interleaved-output build " ++ ghcOpts ++ " ghc-lib-parser"
    stack $ "--no-terminal --interleaved-output build " ++ ghcOptionsOpt ghcOptions ++ " ghc-lib"
    stack $ "--no-terminal --interleaved-output build " ++ ghcOptionsOpt ghcOptions ++ " mini-hlint mini-compile"

    -- Run tests.
    let testArguments = "--test-arguments \"" ++ stackYamlOpt (Just $ "../.." </> stackConfig) ++ " " ++ stackResolverOpt resolver ++ " " ++ ghcFlavorOpt ghcFlavor ++ "\""
    stack $ "test mini-hlint --no-terminal " ++ testArguments
    stack "--no-terminal exec -- mini-compile examples/mini-compile/test/MiniCompileTest.hs | tail -10"

#if __GLASGOW_HASKELL__ == 808 && \
    (__GLASGOW_HASKELL_PATCHLEVEL1__ == 1 || __GLASGOW_HASKELL_PATCHLEVEL1__ == 2) && \
    defined (mingw32_HOST_OS)
    -- Skip these tests on ghc-8.8.1 and ghc-8.8.2. See
    -- https://gitlab.haskell.org/ghc/ghc/issues/17599.
#else
    -- Test everything loads in GHCi, see
    -- https://github.com/digital-asset/ghc-lib/issues/27
    stack "--no-terminal exec -- ghc -ignore-dot-ghci -package=ghc-lib-parser -e \"print 1\""
    stack "--no-terminal exec -- ghc -ignore-dot-ghci -package=ghc-lib -e \"print 1\""
#endif

    -- Something like, "8.8.1.20190828".
    tag -- The return value of type 'IO string'.

    where
      ghcOptionsWithHaddock :: Maybe String -> String
      -- Enabling strict haddock mode with -haddock (and for some
      -- build compilers -Winvalid-haddock) has become too tedious.
      -- See 20935, 20924 and now 21269. The good news is that MR#
      -- 7762 means this shouldn't be an issue anymore going forward.
      ghcOptionsWithHaddock = ghcOptionsOpt

      -- Mitigate macOS w/[ghc-9.0 <= 9.2.2] build failures for lack of
      -- this c-include path (including e.g. ghc-lib-parser on
      -- ghc-9.2.2). See
      -- https://gitlab.haskell.org/ghc/ghc/-/issues/20592#note_391266.
      prelude :: (String, String) -> String
      prelude ("darwin", _) = "C_INCLUDE_PATH=`xcrun --show-sdk-path`/usr/include/ffi"
      prelude _ = ""

      stack :: String -> IO ()
      stack action = cmd $ prelude (os, arch) ++ " stack " ++
        concatMap (<> " ")
                 [ stackYamlOpt stackYaml
                 , stackResolverOpt resolver
                 , stackVerbosityOpt verbosity
                 , cabalVerboseOpt cabalVerbose
                 ] ++
        action

      cmd :: String -> IO ()
      cmd x = do
        putStrLn $ "\n\n# Running: " ++ x
        hFlush stdout
        (t, _) <- duration $ system_ x
        putStrLn $ "# Completed in " ++ showDuration t ++ ": " ++ x ++ "\n"
        hFlush stdout

      mkTarball :: String -> IO ()
      mkTarball target = do
        writeFile "stack.yaml" . (++ "- ghc\n") =<< readFile' "stack.yaml"
        stack "sdist ghc --tar-dir=."
        cmd $ "tar -xvf " ++ target ++ ".tar.gz"

      tag :: IO String
      tag = do
        suffix <- maybe genDateSuffix pure versionSuffix
        return $ genVersionStr ghcFlavor suffix

      patchVersion :: String -> FilePath -> IO ()
      patchVersion version file =
        writeFile file .
          replace "version: 0.1.0" ("version: " ++ version)
          =<< readFile' file

      patchConstraint :: String -> FilePath -> IO ()
      patchConstraint version file =
        writeFile file .
          replace "ghc-lib-parser" ("ghc-lib-parser == " ++ version)
          =<< readFile' file

      removePath :: FilePath -> IO ()
      removePath p =
        whenM (doesPathExist p) $ do
          putStrLn $ "# Removing " ++ p
          removePathForcibly p
