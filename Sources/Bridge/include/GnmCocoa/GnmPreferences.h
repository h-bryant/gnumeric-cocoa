// The engine's preferences (`gnumeric-conf.h`), the ones the app or the
// engine honors, as properties.  Reads and writes go straight to the
// engine's configuration, which GSettings persists through NSUserDefaults
// under the bundle identifier when the engine runs with
// `persistsPreferences` (docs/decisions.md ADR-010); a write takes effect
// at once, as in the GTK Preferences dialog.
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Where Return moves the edit position (`GODirection`).
typedef NS_ENUM(NSInteger, GnmEnterDirection) {
    GnmEnterDirectionUp = 0,
    GnmEnterDirectionDown = 1,
    GnmEnterDirectionLeft = 2,
    GnmEnterDirectionRight = 3,
} NS_SWIFT_NAME(Preferences.Direction);

NS_SWIFT_UI_ACTOR NS_SWIFT_NAME(Preferences)
@interface GnmPreferences : NSObject
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

// Files.
/// `core/xml/compression-level`: 0 writes `.gnumeric` files as plain XML,
/// 9 the smallest gzip; the GTK default is 9.
@property (nonatomic) NSInteger xmlCompressionLevel;

// New workbooks (`core/workbook`, `core/gui/window/zoom`).
@property (nonatomic) NSInteger newWorkbookSheetCount;
/// Rows and columns are rounded to a valid sheet size (powers of two
/// within `GnmWorkbook`'s limits) when a sheet is made.
@property (nonatomic) NSInteger newWorkbookRowCount;
@property (nonatomic) NSInteger newWorkbookColumnCount;
/// 1.0 is 100%.
@property (nonatomic) double defaultZoom;
/// `core/workbook/autosave_time`: seconds between automatic saves of an
/// edited workbook, 0 for none (the GTK's Tools → Auto Save starts from
/// it; the setting is per window there and here).
@property (nonatomic) NSInteger autosaveTime;

// The default font of new workbooks (`core/defaultfont`).
@property (nonatomic, copy) NSString *defaultFontName;
@property (nonatomic) double defaultFontSize;
@property (nonatomic) BOOL defaultFontBold;
@property (nonatomic) BOOL defaultFontItalic;

// Editing (`core/gui/editing`, `autocorrect`).
@property (nonatomic) GnmEnterDirection enterMovesDirection;
@property (nonatomic) BOOL autocorrectsInitialCapitals;
@property (nonatomic) BOOL autocorrectsFirstLetter;
@property (nonatomic) BOOL autocorrectsNamesOfDays;
/// The replacement list (`autocorrect/replace`).
@property (nonatomic) BOOL autocorrectsReplacements;

// Undo (`undo`).
/// How many commands stay undoable.
@property (nonatomic) NSInteger undoMaximumSteps;
/// The total size the undo list may reach, in the engine's units (a
/// one-cell edit is 1).
@property (nonatomic) NSInteger undoMaximumSize;
/// Whether command descriptions name the sheet.
@property (nonatomic) BOOL undoShowsSheetName;
/// The longest a command description gets, in characters.
@property (nonatomic) NSInteger undoMaximumDescriptorWidth;

// Sorting (`core/sort`): what the Sort dialog starts with.
@property (nonatomic) BOOL sortRetainsFormats;
@property (nonatomic) BOOL sortIsCaseSensitive;
@property (nonatomic) BOOL sortAscending;
@property (nonatomic) NSInteger sortInitialClauseCount;
@end

NS_ASSUME_NONNULL_END
