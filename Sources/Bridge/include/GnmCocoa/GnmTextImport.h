// Text import with the assistant's choices: a session over the engine's
// parse options (`GnmStfParseOptions`, `stf-parse.h`) holding the decoded
// text, the options the GTK assistant's pages set (dialog-stf.c and its
// main, separators, fixed-width, and format pages), previews of the
// parse, and the parse itself into a new workbook (what `stf_read_workbook`
// does after its dialog).
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class GnmEngine, GnmWorkbook;

typedef NS_ENUM(NSInteger, GnmTextImportKind) {
    /// Fields between separator characters.
    GnmTextImportSeparated = 0,
    /// Columns at fixed character positions.
    GnmTextImportFixedWidth,
} NS_SWIFT_NAME(TextImportSession.Kind);

typedef NS_OPTIONS(NSUInteger, GnmTextLineBreaks) {
    GnmTextLineBreaksUnix = 1 << 0,
    GnmTextLineBreaksWindows = 1 << 1,
    GnmTextLineBreaksMacintosh = 1 << 2,
} NS_SWIFT_NAME(TextImportSession.LineBreaks);

typedef NS_ENUM(NSInteger, GnmTextTrimming) {
    GnmTextTrimmingNone = 0,
    GnmTextTrimmingBoth,
    GnmTextTrimmingLeft,
    GnmTextTrimmingRight,
} NS_SWIFT_NAME(TextImportSession.Trimming);

NS_SWIFT_UI_ACTOR NS_SWIFT_NAME(TextImportSession)
@interface GnmTextImportSession : NSObject
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

/// Read a file, decode it (`go_guess_encoding`: `encoding` when given,
/// else a guess), and guess the options from its text (CSV rules for a
/// `.csv` name, as the engine's opener does).  Nil with an error when
/// the file cannot be read or is not in the encoding.
+ (nullable instancetype)sessionWithContentsOfURL:(NSURL *)url encoding:(nullable NSString *)encoding
                                            error:(NSError **)error NS_SWIFT_NAME(init(contentsOf:encoding:));
/// A session over text already decoded (tests, Text to Columns).
+ (instancetype)sessionWithText:(NSString *)text name:(NSString *)name NS_SWIFT_NAME(init(text:name:));

/// The source's name (the sheet's name after the import).
@property (nonatomic, readonly, copy) NSString *name;
/// The encoding the text came in, as iconv names it.
@property (nonatomic, readonly, copy) NSString *encoding;
/// The file's own location, when read from one.
@property (nonatomic, readonly, copy, nullable) NSURL *url;
/// Lines in the whole text, with the current line breaks.
@property (nonatomic, readonly) NSInteger lineCount;

// The main page.
@property (nonatomic) GnmTextImportKind kind;
@property (nonatomic) GnmTextLineBreaks lineBreaks;
/// The lines to import, 1-based and inclusive; the whole text at first.
@property (nonatomic) NSInteger startLine;
@property (nonatomic) NSInteger stopLine;

// The separators page.
/// Each character is a separator ("\t,;"); empty for none.
@property (nonatomic, copy) NSString *separatorCharacters;
/// Longer separators, each taken whole.
@property (nonatomic, copy) NSArray<NSString *> *customSeparators;
/// Two separators in a row count as one.
@property (nonatomic) BOOL mergesAdjacentSeparators;
/// Separators at the start of a line are ignored.
@property (nonatomic) BOOL ignoresLeadingSeparators;
/// One character, or empty for no quoting.
@property (nonatomic, copy) NSString *quoteCharacter;
/// Two quotes inside a quoted field are one literal quote.
@property (nonatomic) BOOL doubledQuoteIsLiteral;

// The fixed-width page.
/// Character positions where columns split, ascending.
@property (nonatomic, copy) NSArray<NSNumber *> *splitPositions;
/// The engine's guess at the split positions from the text.
- (void)discoverSplitPositions;

// The format page.
@property (nonatomic) GnmTextTrimming trimming;
/// The locale that reads numbers and dates ("C", "de_DE"); nil is the
/// current one.
@property (nonatomic, copy, nullable) NSString *locale;
/// Columns the current options produce over the chosen lines.
@property (nonatomic, readonly) NSInteger columnCount;
/// A format per column in the engine's syntax ("General", "@" for text,
/// "d/m/yyyy"), as guessed from the text until set; shorter arrays leave
/// the rest general.
@property (nonatomic, copy) NSArray<NSString *> *columnFormats;
/// Guess the formats again from the text with the current options.
- (void)guessColumnFormats;
/// Which columns to import (a BOOL per column); shorter arrays import
/// the rest.
@property (nonatomic, copy) NSArray<NSNumber *> *importedColumns;

/// The first lines of the chosen range parsed with the current options:
/// each line its fields.
- (NSArray<NSArray<NSString *> *> *)previewLines:(NSInteger)maxLines NS_SWIFT_NAME(previewLines(_:));
@end

@interface GnmEngine (TextImport)
/// Parse the session's chosen lines into a new workbook with one sheet
/// named after the source (`stf_parse_sheet`, then the columns fitted
/// and the text saver recorded, as the engine's opener does); the
/// workbook knows the file as its location when the session has one.
- (nullable GnmWorkbook *)importTextSession:(GnmTextImportSession *)session error:(NSError **)error NS_SWIFT_NAME(importText(_:));
@end

NS_ASSUME_NONNULL_END
