// Printing: a sheet's page setup (`print-info.h`, the GTK Page Setup
// dialog's pages) and its printed pages (print.c's pagination and page
// drawing, with the GTK print operation replaced by drawing into a
// Core Graphics context, one page at a time).
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <GnmCocoa/GnmGeometry.h>
#import <GnmCocoa/GnmSheet.h>

NS_ASSUME_NONNULL_BEGIN

/// `GtkPageOrientation`.
typedef NS_ENUM(NSInteger, GnmPageOrientation) {
    GnmPageOrientationPortrait = 0,
    GnmPageOrientationLandscape,
    GnmPageOrientationReversePortrait,
    GnmPageOrientationReverseLandscape,
} NS_SWIFT_NAME(PrintSettings.Orientation);

typedef NS_ENUM(NSInteger, GnmPrintScaling) {
    /// A percentage of the natural size.
    GnmPrintScalingPercentage = 0,
    /// Shrunk to fit a number of pages across and down (0: as many as needed).
    GnmPrintScalingFitPages,
} NS_SWIFT_NAME(PrintSettings.Scaling);

/// A sheet's `GnmPrintInformation`, as the Page Setup dialog's pages set
/// it (the paper, the margins, the scaling, the header and footer, what
/// to print); all lengths in points.
NS_SWIFT_UI_ACTOR NS_SWIFT_NAME(PrintSettings)
@interface GnmPrintSettings : NSObject <NSCopying>
/// The engine's defaults (the preferences' paper and margins).
- (instancetype)init;
/// A paper name ("na_letter", "iso_a4"); `paperDisplayNames` lists them.
@property (nonatomic, copy) NSString *paperName;
@property (nonatomic, readonly, copy) NSString *paperDisplayName;
@property (nonatomic) GnmPageOrientation orientation;
/// The paper as oriented.
@property (nonatomic, readonly) double paperWidth;
@property (nonatomic, readonly) double paperHeight;
/// The dialog's margins: from the paper's edge to the content (top and
/// bottom), to the header and footer, and to the content's sides.
@property (nonatomic) double topMargin;
@property (nonatomic) double bottomMargin;
@property (nonatomic) double headerMargin;
@property (nonatomic) double footerMargin;
@property (nonatomic) double leftMargin;
@property (nonatomic) double rightMargin;
@property (nonatomic) GnmPrintScaling scaling;
/// 100 at first.
@property (nonatomic) double scalePercentage;
@property (nonatomic) NSInteger fitColumns;
@property (nonatomic) NSInteger fitRows;
@property (nonatomic) BOOL centersHorizontally;
@property (nonatomic) BOOL centersVertically;
@property (nonatomic) BOOL printsGridLines;
/// The row and column headers.
@property (nonatomic) BOOL printsTitles;
@property (nonatomic) BOOL printsBlackAndWhite;
/// Pages go across first (off: down first).
@property (nonatomic) BOOL printsAcrossThenDown;
/// Rows and columns repeated on every page ("$1:$2", "$A:$A"); empty for none.
@property (nonatomic, copy) NSString *repeatTop;
@property (nonatomic, copy) NSString *repeatLeft;
/// The header and footer, left, middle, and right, with the engine's
/// codes (&[PAGE], &[PAGES], &[TAB], &[DATE], &[TIME], &[FILE], &[PATH]).
@property (nonatomic, copy) NSString *headerLeft;
@property (nonatomic, copy) NSString *headerMiddle;
@property (nonatomic, copy) NSString *headerRight;
@property (nonatomic, copy) NSString *footerLeft;
@property (nonatomic, copy) NSString *footerMiddle;
@property (nonatomic, copy) NSString *footerRight;
/// The papers GTK knows, name to display name.
@property (class, nonatomic, readonly) NSDictionary<NSString *, NSString *> *paperDisplayNames;
@end

/// A sheet paginated for its page setup, drawing one page at a time.
NS_SWIFT_UI_ACTOR NS_SWIFT_NAME(PrintJob)
@interface GnmPrintJob : NSObject
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@property (nonatomic, readonly) NSInteger pageCount;
/// The paper as oriented, in points.
@property (nonatomic, readonly) CGSize pageSize;
/// Draw a page (0-based) into a context whose origin is the paper's
/// top-left corner with y growing downward, in points (a flipped view).
- (void)drawPage:(NSInteger)page inContext:(CGContextRef)context NS_SWIFT_NAME(drawPage(_:in:));
/// The cells on a page ("A1:F40"), for the headless checks.
- (NSString *)rangeNameOfPage:(NSInteger)page NS_SWIFT_NAME(rangeName(ofPage:));
@end

@interface GnmSheet (Printing)
/// The sheet's page setup.
@property (nonatomic, readonly, copy) GnmPrintSettings *printSettings;
/// Give the sheet (or every sheet) a page setup ("Page Setup For
/// Sheet1", undoable; `cmd_print_setup`).
- (BOOL)setPrintSettings:(GnmPrintSettings *)settings forAllSheets:(BOOL)allSheets error:(NSError **)error NS_SWIFT_NAME(setPrintSettings(_:forAllSheets:));
/// The pages of the sheet's print area (or its used range), or of the
/// selection; nil when there is nothing to print.
- (nullable GnmPrintJob *)printJobForSelectionOnly:(BOOL)selectionOnly ignoringPrintArea:(BOOL)ignoringPrintArea NS_SWIFT_NAME(printJob(selectionOnly:ignoringPrintArea:));
/// The print area ("A1:F40"), or empty when the whole sheet prints.
@property (nonatomic, readonly, copy) NSString *printAreaName;
/// Set the print area to a range, or clear it with nil ("Set Print Area
/// to …", "Clear Print Area"; the `Print_Area` name).
- (BOOL)setPrintArea:(nullable NSString *)rangeName error:(NSError **)error NS_SWIFT_NAME(setPrintArea(_:));
/// The print area as a range (`sheet_get_nominal_printarea`); NO when
/// the whole sheet prints.
- (BOOL)getPrintArea:(GnmCellRange *)range NS_SWIFT_NAME(getPrintArea(_:));
/// The manual page breaks: the columns a page starts at (a break to the
/// left of each) and the rows (a break above each), ascending.
@property (nonatomic, readonly, copy) NSArray<NSNumber *> *columnPageBreaks;
@property (nonatomic, readonly, copy) NSArray<NSNumber *> *rowPageBreaks;
/// Whether any manual page break is set (`print_info_has_manual_breaks`).
@property (nonatomic, readonly) BOOL hasManualPageBreaks;
/// The GTK File → Print Area → Add/Remove Column (Row) Page Break
/// (`cmd_page_break_toggle`): a manual break to the left of the edit
/// column (above the edit row) is set when none is there and removed
/// when one is.  The engine names the command after the action that
/// reverses it ("Remove Column Page Break" when one was added), and the
/// undo label follows.
- (BOOL)togglePageBreakAtEditPositionForColumns:(BOOL)columns error:(NSError **)error NS_SWIFT_NAME(togglePageBreakAtEditPosition(forColumns:));
/// Clear All Page Breaks (`cmd_page_breaks_clear`, undoable).
- (BOOL)clearPageBreaksWithError:(NSError **)error NS_SWIFT_NAME(clearPageBreaks());
@end

NS_ASSUME_NONNULL_END
