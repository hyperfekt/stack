{-# LANGUAGE NoImplicitPrelude #-}
{-# OPTIONS_GHC -fno-warn-orphans #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE OverloadedStrings #-}

module Stack.PrettyPrint
    (
      -- * Pretty printing functions
      displayPlain, displayWithColor
      -- * Logging based on pretty-print typeclass
    , prettyDebug, prettyInfo, prettyWarn, prettyError
    , prettyDebugL, prettyInfoL, prettyWarnL, prettyErrorL
    , prettyDebugS, prettyInfoS, prettyWarnS, prettyErrorS
      -- * Semantic styling functions
      -- | These are preferred to styling or colors directly, so that we can
      -- encourage consistency.
    , styleWarning, styleError, styleGood
    , styleShell, styleFile, styleDir
    , styleCurrent, styleTarget
    , displayMilliseconds
      -- * Formatting utils
    , bulletedList
    , debugBracket
      -- * Re-exports from "Text.PrettyPrint.Leijen.Extended"
    , Display(..), AnsiDoc, AnsiAnn(..), HasAnsiAnn(..), Doc
    , nest, line, linebreak, group, softline, softbreak
    , align, hang, indent, encloseSep
    , (<+>)
    , hsep, vsep, fillSep, sep, hcat, vcat, fillCat, cat, punctuate
    , fill, fillBreak
    , enclose, squotes, dquotes, parens, angles, braces, brackets
    , indentAfterLabel, wordDocs, flow
    ) where

import           Stack.Prelude
import           Data.List (intersperse)
import qualified Data.Text as T
import           Language.Haskell.TH
import           Stack.Types.Config
import           Stack.Types.Package
import           Stack.Types.PackageIdentifier
import           Stack.Types.PackageName
import           Stack.Types.Runner
import           Stack.Types.Version
import qualified System.Clock as Clock
import           Text.PrettyPrint.Leijen.Extended

displayWithColor
    :: (HasRunner env, MonadReader env m, Display a, HasAnsiAnn (Ann a))
    => a -> m T.Text
displayWithColor x = do
    useAnsi <- liftM logUseColor $ view logOptionsL
    return $ if useAnsi then displayAnsi x else displayPlain x

-- TODO: switch to using implicit callstacks once 7.8 support is dropped

prettyWith :: LogLevel -> ExpQ -> Q Exp
prettyWith level f = do
    loc <- location
    [e| monadLoggerLog loc "" level <=< displayWithColor . $f |]

-- Note: I think keeping this section aligned helps spot errors, might be
-- worth keeping the alignment in place.
prettyDebugWith, prettyInfoWith, prettyWarnWith, prettyErrorWith :: ExpQ -> Q Exp
prettyDebugWith   = prettyWith LevelDebug
prettyInfoWith    = prettyWith LevelInfo
prettyWarnWith  f = prettyWith LevelWarn
                        [| (line <>) . (styleWarning "Warning:" <+>) .
                           indentAfterLabel . $f |]
prettyErrorWith f = prettyWith LevelError
                        [| (line <>) . (styleError   "Error:" <+>) .
                           indentAfterLabel . $f |]

prettyDebug, prettyInfo, prettyWarn, prettyError :: Q Exp
prettyDebug  = prettyDebugWith [| id |]
prettyInfo   = prettyInfoWith  [| id |]
prettyWarn   = prettyWarnWith  [| id |]
prettyError  = prettyErrorWith [| id |]

prettyDebugL, prettyInfoL, prettyWarnL, prettyErrorL :: Q Exp
prettyDebugL = prettyDebugWith [| fillSep |]
prettyInfoL  = prettyInfoWith  [| fillSep |]
prettyWarnL  = prettyWarnWith  [| fillSep |]
prettyErrorL = prettyErrorWith [| fillSep |]

prettyDebugS, prettyInfoS, prettyWarnS, prettyErrorS :: Q Exp
prettyDebugS = prettyDebugWith [| flow |]
prettyInfoS  = prettyInfoWith  [| flow |]
prettyWarnS  = prettyWarnWith  [| flow |]
prettyErrorS = prettyErrorWith [| flow |]
-- End of aligned section

-- | Use after a label and before the rest of what's being labelled for
--   consistent spacing/indenting/etc.
--
--   For example this is used after "Warning:" in warning messages.
indentAfterLabel :: Doc a -> Doc a
indentAfterLabel = align

-- | Make a 'Doc' from each word in a 'String'
wordDocs :: String -> [Doc a]
wordDocs = map fromString . words

-- | Wordwrap a 'String'
flow :: String -> Doc a
flow = fillSep . wordDocs

debugBracket :: Q Exp
debugBracket = do
    loc <- location
    [e| \msg f -> do
            let output = monadLoggerLog loc "" LevelDebug <=< displayWithColor
            output $ "Start: " <> msg
            start <- liftIO $ Clock.getTime Clock.Monotonic
            x <- f `catch` \ex -> do
                end <- liftIO $ Clock.getTime Clock.Monotonic
                let diff = Clock.diffTimeSpec start end
                output $ "Finished with exception in" <+> displayMilliseconds diff <> ":" <+>
                    msg <> line <>
                    "Exception thrown: " <> fromString (show ex)
                throwIO (ex :: SomeException)
            end <- liftIO $ Clock.getTime Clock.Monotonic
            let diff = Clock.diffTimeSpec start end
            output $ "Finished in" <+> displayMilliseconds diff <> ":" <+> msg
            return x
      |]

-- | Style an 'AnsiDoc' as an error. Should be used sparingly, not to style
--   entire long messages. For example, it's used to style the "Error:"
--   label for an error message, not the entire message.
styleError :: AnsiDoc -> AnsiDoc
styleError = dullred

-- | Style an 'AnsiDoc' as a warning. Should be used sparingly, not to style
--   entire long messages. For example, it's used to style the "Warning:"
--   label for an error message, not the entire message.
styleWarning :: AnsiDoc -> AnsiDoc
styleWarning = yellow

-- | Style an 'AnsiDoc' in a way to emphasize that it is a particularly good
--   thing.
styleGood :: AnsiDoc -> AnsiDoc
styleGood = green

-- | Style an 'AnsiDoc' as a shell command, i.e. when suggesting something
--   to the user that should be typed in directly as written.
styleShell :: AnsiDoc -> AnsiDoc
styleShell = magenta

-- | Style an 'AnsiDoc' as a filename. See 'styleDir' for directories.
styleFile :: AnsiDoc -> AnsiDoc
styleFile = bold . white

-- | Style an 'AnsiDoc' as a directory name. See 'styleFile' for files.
styleDir :: AnsiDoc -> AnsiDoc
styleDir = bold . blue

-- | Style an 'AnsiDoc' in a way that emphasizes that it is related to
--   a current thing. For example, could be used when talking about the
--   current package we're processing when outputting the name of it.
styleCurrent :: AnsiDoc -> AnsiDoc
styleCurrent = yellow

-- TODO: figure out how to describe this
styleTarget :: AnsiDoc -> AnsiDoc
styleTarget = cyan

instance Display PackageName where
    display = fromString . packageNameString

instance Display PackageIdentifier where
    display = fromString . packageIdentifierString

instance Display Version where
    display = fromString . versionString

instance Display (Path b File) where
    display = styleFile . fromString . toFilePath

instance Display (Path b Dir) where
    display = styleDir . fromString . toFilePath

instance Display (PackageName, NamedComponent) where
    display = cyan . fromString . T.unpack . renderPkgComponent

-- Display milliseconds.
displayMilliseconds :: Clock.TimeSpec -> AnsiDoc
displayMilliseconds t = green $
    (fromString . show . (`div` 10^(6 :: Int)) . Clock.toNanoSecs) t <> "ms"

-- | Display a list of 'AnsiDoc', one per line, with bullets before each
bulletedList :: [AnsiDoc] -> AnsiDoc
bulletedList = mconcat . intersperse line . map ("*" <+>)
