// Find and Replace over the engine's search (`search.h`): the options the
// GTK Search and Search & Replace dialogs collect, the matches the Search
// dialog lists, and the replace command (`cmd_search_replace`) with the
// questions it asks routed to a block.
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class GnmSheet;

typedef NS_ENUM(NSInteger, GnmSearchScope) {
    GnmSearchScopeWorkbook = 0,
    GnmSearchScopeSheet,
    /// The cells of `rangeText`, read in the sheet's syntax.
    GnmSearchScopeRange,
} NS_SWIFT_NAME(SearchOptions.Scope);

typedef NS_ENUM(NSInteger, GnmSearchTextKind) {
    GnmSearchTextPlain = 0,
    GnmSearchTextRegularExpression,
    /// A number, matched against numeric values to the text's precision
    /// (finding only; a replace takes it as plain text).
    GnmSearchTextNumber,
} NS_SWIFT_NAME(SearchOptions.TextKind);

/// What a replace does with a replacement that would not parse (a string
/// that starts like a formula in a cell that is not text-formatted).
typedef NS_ENUM(NSInteger, GnmSearchErrorBehavior) {
    /// Stop before changing anything, with an error naming the cell.
    GnmSearchErrorFail = 0,
    /// Leave that cell alone.
    GnmSearchErrorSkip,
    /// The engine's "query" choice, which this version treats as skip.
    GnmSearchErrorQuery,
    /// Store `=ERROR("…")` instead.
    GnmSearchErrorMakeError,
    /// Store it as a string.
    GnmSearchErrorMakeString,
} NS_SWIFT_NAME(SearchOptions.ErrorBehavior);

/// What the GTK dialogs collect, with their defaults (`gnumeric-conf`).
NS_SWIFT_UI_ACTOR NS_SWIFT_NAME(SearchOptions)
@interface GnmSearchOptions : NSObject <NSCopying>
@property (nonatomic, copy) NSString *searchText;
@property (nonatomic, copy) NSString *replaceText;
@property (nonatomic) GnmSearchScope scope;
/// For `GnmSearchScopeRange`: one or more ranges, sheet-qualified or
/// not, as the Range field holds them ("A1:B4", "Sheet2!C1:C9").
@property (nonatomic, copy) NSString *rangeText;
@property (nonatomic) GnmSearchTextKind textKind;
@property (nonatomic) BOOL ignoresCase;
@property (nonatomic) BOOL matchesWholeWords;
/// Replacing: keep the case of the replaced text (Emacs' case-replace).
@property (nonatomic) BOOL preservesCase;
// Which cells to look at.
@property (nonatomic) BOOL searchesStrings;
@property (nonatomic) BOOL searchesOtherValues;
@property (nonatomic) BOOL searchesExpressions;
/// The computed values of expressions (finding only; never replaced).
@property (nonatomic) BOOL searchesExpressionResults;
@property (nonatomic) BOOL searchesComments;
/// Row by row (A1, B1, …, A2) rather than column by column.
@property (nonatomic) BOOL byRow;
// Replacing.
/// Ask through the query handler before each change.
@property (nonatomic) BOOL asksBeforeEachChange;
/// A string stays a string even when the result looks like a number or
/// a formula.
@property (nonatomic) BOOL keepsStrings;
@property (nonatomic) GnmSearchErrorBehavior errorBehavior;
@end

typedef NS_ENUM(NSInteger, GnmSearchMatchLocus) {
    /// The cell's entered text (a string, a number, or a formula).
    GnmSearchMatchContents = 0,
    /// The computed value of a formula.
    GnmSearchMatchResult,
    GnmSearchMatchComment,
} NS_SWIFT_NAME(SearchMatch.Locus);

/// One hit of a find, as the GTK Search dialog's Matches page lists it.
NS_SWIFT_UI_ACTOR NS_SWIFT_NAME(SearchMatch)
@interface GnmSearchMatch : NSObject
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@property (nonatomic, readonly) GnmSheet *sheet;
@property (nonatomic, readonly) NSInteger column;
@property (nonatomic, readonly) NSInteger row;
@property (nonatomic, readonly) GnmSearchMatchLocus locus;
/// "C3".
@property (nonatomic, readonly, copy) NSString *cellName;
/// The cell with its sheet, quoted as the engine parses it
/// ("'Sheet 2'!C3"): a range text for `GnmSearchScopeRange`.
@property (nonatomic, readonly, copy) NSString *reference;
/// "String", "Number", "Expression", "Other value", "Result", "Comment".
@property (nonatomic, readonly, copy) NSString *kindDescription;
/// The entered text, the computed value, or the comment, at find time.
@property (nonatomic, readonly, copy) NSString *contents;
@end

/// A question the replace asks before one change.
NS_SWIFT_UI_ACTOR NS_SWIFT_NAME(SearchQuery)
@interface GnmSearchQuery : NSObject
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@property (nonatomic, readonly) GnmSheet *sheet;
@property (nonatomic, readonly) NSInteger column;
@property (nonatomic, readonly) NSInteger row;
@property (nonatomic, readonly) BOOL isComment;
/// "Sheet1!C3" or "Comment in cell Sheet1!C3", as the GTK query shows it.
@property (nonatomic, readonly, copy) NSString *location;
/// What the cell (or comment) holds and what it would hold.
@property (nonatomic, readonly, copy) NSString *currentText;
@property (nonatomic, readonly, copy) NSString *replacementText;
/// Clear it to make the remaining changes without asking (the query
/// dialog's "Ask before each change" box); read after Replace and Skip.
@property (nonatomic) BOOL asksAgain;
@end

typedef NS_ENUM(NSInteger, GnmSearchQueryAnswer) {
    GnmSearchQueryReplace = 0,
    GnmSearchQuerySkip,
    /// Stop here; the changes made so far stay, as one undoable command.
    GnmSearchQueryCancel,
} NS_SWIFT_NAME(SearchQuery.Answer);

typedef GnmSearchQueryAnswer (^GnmSearchQueryHandler)(GnmSearchQuery *query) NS_SWIFT_NAME(SearchQuery.Handler);

@class GnmWorkbook;
@interface GnmWorkbook (Search)
/// The cells matching `options`, in the order the search visits them
/// (`gnm_search_collect_cells`, `gnm_search_filter_matching`).  `sheet`
/// is the current sheet: the sheet scope, and the default sheet of the
/// range text.  Nil with an error for a bad pattern, a range that does
/// not parse, or no cell types to look at.
- (nullable NSArray<GnmSearchMatch *> *)findMatches:(GnmSearchOptions *)options inSheet:(GnmSheet *)sheet
                                              error:(NSError **)error NS_SWIFT_NAME(findMatches(_:in:));
/// Replace as the engine's "Search and Replace" command, undoable as a
/// whole.  With `asksBeforeEachChange` the handler answers for each
/// cell (and comment); without a handler every change is made.  NO with
/// an error for a bad pattern, no cell types, or, with
/// `GnmSearchErrorFail`, a replacement that would not parse (then
/// nothing changed).
- (BOOL)replaceMatches:(GnmSearchOptions *)options inSheet:(GnmSheet *)sheet
          queryHandler:(nullable GnmSearchQueryHandler)handler error:(NSError **)error NS_SWIFT_NAME(replaceMatches(_:in:queryHandler:));
@end

NS_ASSUME_NONNULL_END
