{-# OPTIONS_GHC -Wall #-}
-----------------------------------------------------------------------------
-- |
-- Module      :  lpconvert
-- Copyright   :  (c) Masahiro Sakai 2012-2014
-- License     :  BSD-style
-- 
-- Maintainer  :  masahiro.sakai@gmail.com
-- Stability   :  experimental
-- Portability :  portable
--
-----------------------------------------------------------------------------

module Main where

import Data.Char
import qualified Data.Version as V
import System.Environment
import System.IO
import System.Exit
import System.FilePath
import System.Console.GetOpt
import qualified Language.CNF.Parse.ParseDIMACS as DIMACS

import qualified Data.MIP as MIP
import qualified Text.LPFile as LPFile
import qualified Text.MaxSAT as MaxSAT
import qualified Text.MPSFile as MPSFile
import qualified Text.PBFile as PBFile
import Converter.ObjType
import qualified Converter.MIP2SMT as MIP2SMT
import qualified Converter.MaxSAT2IP as MaxSAT2IP
import qualified Converter.MaxSAT2NLPB as MaxSAT2NLPB
import qualified Converter.PB2IP as PB2IP
import qualified Converter.PBSetObj as PBSetObj
import qualified Converter.SAT2PB as SAT2PB
import ToySolver.Version

data Flag
  = Help
  | Version
  | Output String
  | AsMaxSAT
  | ObjType ObjType
  | IndicatorConstraint
  | Optimize
  | NoCheck
  | NoProduceModel
  | MaxSATNonLinear
  deriving Eq

options :: [OptDescr Flag]
options =
    [ Option ['h'] ["help"] (NoArg Help) "show help"
    , Option ['v'] ["version"] (NoArg Version)         "show version number"
    , Option ['o'] [] (ReqArg Output "FILE") "output filename"
    , Option []    ["maxsat"]  (NoArg AsMaxSAT)  "treat *.cnf file as MAX-SAT problem"
    , Option []    ["obj"] (ReqArg (ObjType . parseObjType) "STRING") "objective function for SAT/PBS: none (default), max-one, max-zero"
    , Option []    ["indicator"] (NoArg IndicatorConstraint) "use indicator constraints in output LP file"
    , Option []    ["smt-optimize"] (NoArg Optimize)   "output optimiality condition which uses quantifiers"
    , Option []    ["smt-no-check"] (NoArg NoCheck)    "do not output \"(check)\""
    , Option []    ["smt-no-produce-model"] (NoArg NoProduceModel) "do not output \"(set-option :produce-models true)\""    
    , Option []    ["maxsat-nonlinear"] (NoArg MaxSATNonLinear) "use non-linear formulation of Max-SAT"
    ]
  where
    parseObjType s =
      case map toLower s of
        "none"     -> ObjNone
        "max-one"  -> ObjMaxOne
        "max-zero" -> ObjMaxZero
        _          -> error ("unknown obj: " ++ s)

header :: String
header = unlines
  [ "Usage:"
  , "    lpconvert -o <outputfile> <inputfile>"
  , ""
  , "Supported formats:"
  , "    input: .lp .mps .cnf .wcnf .opb .wbo"
  , "    output: .lp .smt2 .ys"
  , ""
  , "Options:"
  ]

readLP :: [Flag] -> String -> IO MIP.Problem
readLP o fname = do
  case map toLower (takeExtension fname) of
    ".cnf"
      | AsMaxSAT `elem` o -> readWCNF
      | otherwise -> do
          ret <- DIMACS.parseFile fname
          case ret of
            Left err -> hPrint stderr err >> exitFailure
            Right cnf -> do
              let pb = transformPBFile o $ SAT2PB.convert cnf
              let (mip, _) = PB2IP.convert pb
              return mip
    ".wcnf" -> readWCNF
    ".opb"  -> do
      ret <- PBFile.parseOPBFile fname
      case ret of
        Left err -> hPrint stderr err >> exitFailure
        Right formula -> do
          let pb = transformPBFile o formula
          let (mip, _) = PB2IP.convert pb
          return mip
    ".wbo"  -> do
      ret <- PBFile.parseWBOFile fname
      case ret of
        Left err -> hPrint stderr err >> exitFailure
        Right formula -> do
          let (mip, _) = PB2IP.convertWBO (IndicatorConstraint `elem` o) formula
          return mip
    ".lp"   -> do
      ret <- LPFile.parseFile fname
      case ret of
        Left err -> hPrint stderr err >> exitFailure
        Right mip -> return mip
    ".mps"  -> do
      ret <- MPSFile.parseFile fname
      case ret of
        Left err -> hPrint stderr err >> exitFailure
        Right mip -> return mip
    ext ->
      error $ "unknown file extension: " ++ show ext
  where
    readWCNF = do
      ret <- MaxSAT.parseWCNFFile fname
      case ret of
        Left err -> hPutStrLn stderr err >> exitFailure
        Right wcnf
          | MaxSATNonLinear `elem` o -> do
              let pb = transformPBFile o $ MaxSAT2NLPB.convert wcnf
                  (mip, _) = PB2IP.convert pb
              return mip
          | otherwise -> do
              let (mip, _) = MaxSAT2IP.convert (IndicatorConstraint `elem` o) wcnf
              return mip

transformPBFile :: [Flag] -> PBFile.Formula -> PBFile.Formula
transformPBFile o opb@(Nothing,_) = PBSetObj.setObj objType opb
  where
    objType = last (ObjNone : [t | ObjType t <- o])
transformPBFile _ opb = opb

writeLP :: [Flag] -> MIP.Problem -> IO ()
writeLP o mip = do
  let mip2smtOpt =
        MIP2SMT.defaultOptions
        { MIP2SMT.optCheckSAT     = not (NoCheck `elem` o)
        , MIP2SMT.optProduceModel = not (NoProduceModel `elem` o)
        , MIP2SMT.optOptimize     = Optimize `elem` o
        }

  case head ([Just fname | Output fname <- o] ++ [Nothing]) of
    Nothing -> do
      case LPFile.render mip of
        Nothing -> hPutStrLn stderr "conversion failure" >> exitFailure
        Just s -> putStr s
    Just fname -> do
      case map toLower (takeExtension fname) of
        ".lp" -> do
          case LPFile.render mip of
            Nothing -> hPutStrLn stderr "conversion failure" >> exitFailure
            Just s -> writeFile fname s
        ".smt2" -> do
          writeFile fname (MIP2SMT.convert mip2smtOpt mip "")
        ".ys" -> do
          writeFile fname (MIP2SMT.convert mip2smtOpt{ MIP2SMT.optLanguage = MIP2SMT.YICES } mip "")
        ext -> do
          error $ "unknown file extension: " ++ show ext
          
main :: IO ()
main = do
  args <- getArgs
  case getOpt Permute options args of
    (o,_,[])
      | Help `elem` o    -> putStrLn (usageInfo header options)
      | Version `elem` o -> putStrLn (V.showVersion version)
    (o,[fname],[]) -> do
      mip <- readLP o fname
      writeLP o mip
    (_,_,errs) -> do
      hPutStrLn stderr $ concat errs ++ usageInfo header options
      exitFailure
