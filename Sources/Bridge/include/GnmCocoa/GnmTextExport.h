// Text export with options: what the GTK "Export as Text" dialog
// (dialog-stf-export.c) collects, applied to the engine's per-workbook
// export object (`GnmStfExport`, `gnm_stf_get_stfe`) and written through
// the "Text (configurable)" saver.
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class GnmSheet;

typedef NS_ENUM(NSInteger, GnmTextLineEnding) {
    /// "\n"
    GnmTextLineEndingUnix = 0,
    /// "\r"
    GnmTextLineEndingMacintosh,
    /// "\r\n"
    GnmTextLineEndingWindows,
} NS_SWIFT_NAME(TextExportOptions.LineEnding);

typedef NS_ENUM(NSInteger, GnmTextQuoting) {
    /// Quotes where a field holds a separator, a quote, a space, or a line end.
    GnmTextQuotingAutomatic = 0,
    GnmTextQuotingAlways,
    GnmTextQuotingNever,
} NS_SWIFT_NAME(TextExportOptions.Quoting);

/// What becomes of characters the encoding lacks.
typedef NS_ENUM(NSInteger, GnmTextUnknownCharacters) {
    /// The nearest the encoding has (iconv's //TRANSLIT), when supported.
    GnmTextUnknownCharactersTransliterate = 0,
    /// An escape sequence.
    GnmTextUnknownCharactersEscape,
} NS_SWIFT_NAME(TextExportOptions.UnknownCharacters);

typedef NS_ENUM(NSInteger, GnmTextFormatMode) {
    /// Numbers as displayed, except that dates and such keep a form that reads back.
    GnmTextFormatAutomatic = 0,
    /// Values unformatted.
    GnmTextFormatRaw,
    /// Everything exactly as displayed.
    GnmTextFormatPreserve,
} NS_SWIFT_NAME(TextExportOptions.FormatMode);

NS_SWIFT_UI_ACTOR NS_SWIFT_NAME(TextExportOptions)
@interface GnmTextExportOptions : NSObject <NSCopying>
/// The sheets to write, in this order; empty means every sheet in the
/// workbook's order.
@property (nonatomic, copy) NSArray<GnmSheet *> *sheets;
@property (nonatomic) GnmTextLineEnding lineEnding;
/// Between fields: "," by default; any string.
@property (nonatomic, copy) NSString *separator;
@property (nonatomic) GnmTextQuoting quoting;
/// "\"" by default.
@property (nonatomic, copy) NSString *quoteCharacter;
/// An iconv name ("UTF-8", "ISO-8859-1", "WINDOWS-1252"); nil is UTF-8.
@property (nonatomic, copy, nullable) NSString *characterEncoding;
/// The locale that formats numbers ("C" for a period decimal point
/// whatever the system says); nil is the current one.
@property (nonatomic, copy, nullable) NSString *locale;
@property (nonatomic) GnmTextUnknownCharacters unknownCharacters;
@property (nonatomic) GnmTextFormatMode format;
/// Formulas rather than their values.
@property (nonatomic) BOOL exportsFormulas;
/// Whether this iconv can transliterate (else Escape is the only choice).
@property (class, nonatomic, readonly) BOOL canTransliterate;
@end

@class GnmWorkbook;
@interface GnmWorkbook (TextExport)
/// What an export of this workbook starts from: the preferences'
/// defaults, or the choices of its last text export.
@property (nonatomic, readonly) GnmTextExportOptions *textExportOptions;
/// Write the workbook as text with `options` (the "Text (configurable)"
/// saver, `Gnumeric_stf:stf_assistant`).  `remember` makes the choices
/// the preferences' defaults (the GTK "Save as default formatting").
/// `adopt` as in `writeToURL:saverIdentifier:adoptingURL:error:`.
- (BOOL)writeToURL:(NSURL *)url textExportOptions:(GnmTextExportOptions *)options rememberAsDefault:(BOOL)remember
       adoptingURL:(BOOL)adopt error:(NSError **)error NS_SWIFT_NAME(write(to:textExportOptions:rememberAsDefault:adoptingURL:));
@end

NS_ASSUME_NONNULL_END
