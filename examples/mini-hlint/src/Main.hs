-- Copyright (c) 2019 - 2021, Digital Asset (Switzerland) GmbH and/or
-- its affiliates. All rights reserved. SPDX-License-Identifier:
-- (Apache-2.0 OR BSD-3-Clause)

{-# LANGUAGE CPP #-}
{-# LANGUAGE PackageImports #-}
{-# OPTIONS_GHC -Wno-missing-fields #-}

module Main (main) where

-- We use 0.x for HEAD
#if !MIN_VERSION_ghc_lib_parser(1,0,0)
#  define GHC_MASTER
#elif MIN_VERSION_ghc_lib_parser(9,4,0)
#  define GHC_941
#elif MIN_VERSION_ghc_lib_parser(9,2,0)
#  define GHC_921
#elif MIN_VERSION_ghc_lib_parser(9,0,0)
#  define GHC_901
#elif MIN_VERSION_ghc_lib_parser(8,10,0)
#  define GHC_8101
#endif

#if defined (GHC_MASTER) || defined (GHC_941)
import "ghc-lib-parser" GHC.Driver.Config.Diagnostic
import "ghc-lib-parser" GHC.Utils.Logger
import "ghc-lib-parser" GHC.Driver.Errors
import "ghc-lib-parser" GHC.Driver.Errors.Types
import "ghc-lib-parser" GHC.Types.Error
#endif
#if defined (GHC_MASTER) || defined (GHC_941)
import "ghc-lib-parser" GHC.Driver.Config.Parser
#endif
#if defined (GHC_MASTER) || defined (GHC_941) || defined (GHC_921)
import "ghc-lib-parser" GHC.Driver.Ppr
import "ghc-lib-parser" GHC.Driver.Config
#endif
#if defined (GHC_MASTER) || defined (GHC_941) || defined (GHC_921) || defined (GHC_901) || defined (GHC_8101)
import "ghc-lib-parser" GHC.Hs
#else
import "ghc-lib-parser" HsSyn
#endif
#if defined (GHC_MASTER) || defined (GHC_941) || defined (GHC_921) || defined (GHC_901)
import "ghc-lib-parser" GHC.Settings.Config
import "ghc-lib-parser" GHC.Driver.Session
import "ghc-lib-parser" GHC.Data.StringBuffer
import "ghc-lib-parser" GHC.Utils.Fingerprint
import "ghc-lib-parser" GHC.Parser.Lexer
import "ghc-lib-parser" GHC.Types.Name.Reader
import "ghc-lib-parser" GHC.Utils.Error
import qualified "ghc-lib-parser" GHC.Parser
import "ghc-lib-parser" GHC.Data.FastString
import "ghc-lib-parser" GHC.Utils.Outputable
#  if !defined (GHC_901)
import "ghc-lib-parser" GHC.Parser.Errors.Ppr
#  endif
import "ghc-lib-parser" GHC.Types.SrcLoc
import "ghc-lib-parser" GHC.Utils.Panic
#  if defined (GHC_MASTER) || defined (GHC_941) || defined (GHC_921)
import "ghc-lib-parser" GHC.Types.SourceError
#  else
import "ghc-lib-parser" GHC.Driver.Types
#  endif
import "ghc-lib-parser" GHC.Parser.Header
import "ghc-lib-parser" GHC.Parser.Annotation
#else
import "ghc-lib-parser" Config
import "ghc-lib-parser" DynFlags
import "ghc-lib-parser" StringBuffer
import "ghc-lib-parser" Fingerprint
import "ghc-lib-parser" Lexer
import "ghc-lib-parser" RdrName
import "ghc-lib-parser" ErrUtils
import qualified "ghc-lib-parser" Parser
import "ghc-lib-parser" FastString
import "ghc-lib-parser" Outputable
import "ghc-lib-parser" SrcLoc
import "ghc-lib-parser" Panic
import "ghc-lib-parser" HscTypes
import "ghc-lib-parser" HeaderInfo
import "ghc-lib-parser" ApiAnnotation
#endif
#if defined (GHC_MASTER) || defined (GHC_941) || defined (GHC_921) || defined (GHC_901)
import "ghc-lib-parser" GHC.Settings
#elif defined (GHC_8101)
import "ghc-lib-parser" ToolSettings
#endif
#if defined (GHC_MASTER) || defined (GHC_941) || defined (GHC_921) || defined (GHC_901) || defined (GHC_8101)
import "ghc-lib-parser" GHC.Platform
#else
import "ghc-lib-parser" Bag
import "ghc-lib-parser" Platform
#endif

import Control.Monad.Extra
import System.Environment
import System.IO.Extra
import qualified Data.Map as Map
import Data.Generics.Uniplate.Operations
import Data.Generics.Uniplate.Data

fakeSettings :: Settings
fakeSettings = Settings
#if defined (GHC_MASTER) || defined (GHC_941) || defined (GHC_921) || defined (GHC_901) || defined (GHC_8101)
  { sGhcNameVersion=ghcNameVersion
  , sFileSettings=fileSettings
  , sTargetPlatform=platform
  , sPlatformMisc=platformMisc
#if !defined (GHC_MASTER) && !defined (GHC_941) && !defined (GHC_921)
  , sPlatformConstants=platformConstants
#endif
  , sToolSettings=toolSettings
  }
#else
  { sTargetPlatform=platform
  , sPlatformConstants=platformConstants
  , sProjectVersion=cProjectVersion
  , sProgramName="ghc"
  , sOpt_P_fingerprint=fingerprint0
  }
#endif
  where
#if defined (GHC_MASTER) || defined (GHC_941) || defined (GHC_921) || defined (GHC_901) || defined (GHC_8101)
    toolSettings = ToolSettings {
      toolSettings_opt_P_fingerprint=fingerprint0
      }
    fileSettings = FileSettings {}
    platformMisc = PlatformMisc {}
    ghcNameVersion =
      GhcNameVersion{ghcNameVersion_programName="ghc"
                    ,ghcNameVersion_projectVersion=cProjectVersion
                    }
#endif

    platform =
#if defined (GHC_MASTER) || defined (GHC_941) || defined (GHC_921)
      genericPlatform
#else
      Platform{
#if defined (GHC_901)
    -- It doesn't matter what values we write here as these fields are
    -- not referenced for our purposes. However the fields are strict
    -- so we must say something.
        platformByteOrder=LittleEndian
      , platformHasGnuNonexecStack=True
      , platformHasIdentDirective=False
      , platformHasSubsectionsViaSymbols=False
      , platformIsCrossCompiling=False
      , platformLeadingUnderscore=False
      , platformTablesNextToCode=False
      ,
#endif
#if defined (GHC_8101) || defined (GHC_901)
        platformWordSize=PW8
      , platformMini=PlatformMini {platformMini_arch=ArchUnknown, platformMini_os=OSUnknown}
#else
        platformWordSize=8
      , platformOS=OSUnknown
#endif
      , platformUnregisterised=True
      }
#endif
#if !defined(GHC_MASTER) && !defined(GHC_941) && !defined(GHC_921)
    platformConstants = PlatformConstants{ pc_DYNAMIC_BY_DEFAULT=False, pc_WORD_SIZE=8 }
#endif

#if defined (GHC_MASTER)
-- Intentionally empty
#elif defined (GHC_941) || defined (GHC_921) || defined (GHC_901) || defined (GHC_8101)
fakeLlvmConfig :: LlvmConfig
fakeLlvmConfig = LlvmConfig [] []
#else
fakeLlvmConfig :: (LlvmTargets, LlvmPasses)
fakeLlvmConfig = ([], [])
#endif

#if defined (GHC_MASTER) || defined (GHC_941) || defined (GHC_921) || defined (GHC_901)
parse :: String -> DynFlags -> String -> ParseResult (Located HsModule)
#else
parse :: String -> DynFlags -> String -> ParseResult (Located (HsModule GhcPs))
#endif
parse filename flags str =
#if defined (GHC_MASTER) || defined (GHC_941) || defined (GHC_921) || defined (GHC_901)
  unP GHC.Parser.parseModule parseState
#else
  unP Parser.parseModule parseState
#endif
  where
    location = mkRealSrcLoc (mkFastString filename) 1 1
    buffer = stringToStringBuffer str
    parseState =
#if defined (GHC_MASTER) || defined (GHC_941) || defined (GHC_921)
      initParserState (initParserOpts flags) buffer location
#else
      mkPState flags buffer location
#endif

parsePragmasIntoDynFlags :: DynFlags -> FilePath -> String -> IO (Maybe DynFlags)
parsePragmasIntoDynFlags flags filepath str =
  catchErrors $ do
#if defined (GHC_MASTER) || defined (GHC_941)
    let (_, opts) = getOptions (initParserOpts flags)
                      (stringToStringBuffer str) filepath
#else
    let opts = getOptions flags
                      (stringToStringBuffer str) filepath
#endif
    (flags, _, _) <- parseDynamicFilePragma flags opts
    return $ Just flags
  where
    catchErrors :: IO (Maybe DynFlags) -> IO (Maybe DynFlags)
    catchErrors act = handleGhcException reportGhcException
                        (handleSourceError reportSourceErr act)

    reportGhcException e = do
      print e; return Nothing

    reportSourceErr msgs = do
      putStrLn $ head
             [ showSDoc flags msg
             | msg <-
#if defined (GHC_MASTER) || defined (GHC_941)
                      pprMsgEnvelopeBagWithLoc . getMessages
#elif defined (GHC_921)
                      pprMsgEnvelopeBagWithLoc
#else
                      pprErrMsgBagWithLoc
#endif
                      $ srcErrorMessages msgs
             ]
      return Nothing

idNot :: RdrName
idNot = mkVarUnqual (fsLit "not")

isNegated :: HsExpr GhcPs -> Bool
isNegated (HsApp _ (L _ (HsVar _ (L _ id))) _) = id == idNot
#if defined (GHC_MASTER) || defined (GHC_941)
isNegated (HsPar _ _ (L _ e) _) = isNegated e
#else
isNegated (HsPar _ (L _ e)) = isNegated e
#endif
isNegated _ = False

#if defined (GHC_MASTER) || defined (GHC_941) || defined (GHC_921)
analyzeExpr :: DynFlags -> LocatedA (HsExpr GhcPs) -> IO ()
#else
analyzeExpr :: DynFlags -> Located (HsExpr GhcPs) -> IO ()
#endif
analyzeExpr flags (L loc expr) = do
  case expr of
    HsApp _ (L _ (HsVar _ (L _ id))) (L _ e)
        | id == idNot, isNegated e ->
#if defined (GHC_MASTER) || defined (GHC_941) || defined (GHC_921)
            putStrLn (showSDoc flags (ppr (locA loc))
#else
            putStrLn (showSDoc flags (ppr loc)
#endif
                      ++ " : lint : double negation "
                      ++ "`" ++ showSDoc flags (ppr expr) ++ "'")
    _ -> return ()

#if defined (GHC_MASTER) || defined (GHC_941) || defined (GHC_921)
analyzeModule :: DynFlags -> Located HsModule -> IO ()
#elif defined (GHC_901)
analyzeModule :: DynFlags -> Located HsModule -> ApiAnns -> IO ()
#else
analyzeModule :: DynFlags -> Located (HsModule GhcPs) -> ApiAnns -> IO ()
#endif
analyzeModule flags (L _ modu)
#if !(defined (GHC_MASTER) || defined(GHC_941) || defined (GHC_921))
                                _ -- ApiAnns
#endif
 = sequence_ [analyzeExpr flags e | e <- universeBi modu]

main :: IO ()
main = do
  args <- getArgs
  case args of
    [file] -> do
      s <- readFile' file
      flags <-
        parsePragmasIntoDynFlags
#if defined(GHC_MASTER)
          (defaultDynFlags fakeSettings) file s
#else
          (defaultDynFlags fakeSettings fakeLlvmConfig) file s
#endif
      whenJust flags $ \flags ->
         case parse file (flags `gopt_set` Opt_KeepRawTokenStream)s of
#if defined (GHC_MASTER) || defined (GHC_941)
            PFailed s -> report flags $ GhcPsMessage <$> snd (getPsMessages s)
#elif defined (GHC_921)
            PFailed s -> report flags $ fmap pprError (snd (getMessages s))
#elif defined (GHC_901) || defined (GHC_8101)
            PFailed s -> report flags $ snd (getMessages s flags)
#else
            PFailed _ loc err -> report flags $ unitBag $ mkPlainErrMsg flags loc err
#endif
            POk s m -> do
#if defined (GHC_MASTER) || defined (GHC_941)
              let (wrns, errs) = getPsMessages s
              report flags $ GhcPsMessage <$> wrns
              report flags $ GhcPsMessage <$> errs
#elif defined (GHC_921)
              let (wrns, errs) = getMessages s
              report flags (fmap pprWarning wrns)
              report flags (fmap pprError errs)
#else
              let (wrns, errs) = getMessages s flags
              report flags wrns
              report flags errs
#endif
              when (null errs) $
                analyzeModule flags m
#if !(defined (GHC_MASTER) || defined(GHC_941) || defined (GHC_921))
                                      (harvestAnns s)
#endif
    _ -> fail "Exactly one file argument required"
  where

#if defined (GHC_MASTER) || defined (GHC_941)
    -- Nowdays, to print hints along with errors you need 'printMessages'.
    -- See
    -- https://gitlab.haskell.org/ghc/ghc/-/merge_requests/6087#note_365215
    -- for details.
    report flags msgs = do
      logger <- initLogger
      let opts = initDiagOpts flags
      printMessages logger opts msgs
#else
    report flags msgs =
      sequence_
        [ putStrLn $ showSDoc flags msg
        | msg <-
#  if defined (GHC_921)
                  pprMsgEnvelopeBagWithLoc msgs
#  else
                  pprErrMsgBagWithLoc msgs
#  endif
        ]
#endif
#if !(defined(GHC_MASTER) || defined(GHC_941) || defined (GHC_921))
    harvestAnns pst =
#  if defined (GHC_901)
        ApiAnns {
              apiAnnItems = Map.fromListWith (++) $ annotations pst
            , apiAnnEofPos = Nothing
            , apiAnnComments = Map.fromListWith (++) $ annotations_comments pst
            , apiAnnRogueComments = comment_q pst
            }
#  else
      ( Map.fromListWith (++) $ annotations pst
      , Map.fromList ((noSrcSpan, comment_q pst) : annotations_comments pst)
      )
#  endif
#endif
