// A Workbook plus its WorkbookView and one Cocoa WorkbookControl.
//
// Ownership (docs/architecture.md §3 and upstream convention): the wrapper
// holds the view reference returned by the engine's opener; the view owns the
// control; releasing the wrapper calls g_object_unref on the Workbook, whose
// dispose detaches and releases views and controls, exactly as ssconvert and
// the GTK front end shut a workbook down.
#import <Foundation/Foundation.h>
#import <GnmCocoa/GnmGeometry.h>

NS_ASSUME_NONNULL_BEGIN

@class GnmWorkbook, GnmSheet;

/// Notifications the engine sends through the WorkbookControl vtable.  All
/// methods are optional and arrive on the main thread.
NS_SWIFT_UI_ACTOR NS_SWIFT_NAME(WorkbookDelegate)
@protocol GnmWorkbookDelegate <NSObject>
@optional
- (void)workbook:(GnmWorkbook *)workbook didAddSheet:(GnmSheet *)sheet;
- (void)workbook:(GnmWorkbook *)workbook willRemoveSheet:(GnmSheet *)sheet;
- (void)workbookWillRemoveAllSheets:(GnmWorkbook *)workbook;
- (void)workbook:(GnmWorkbook *)workbook didFocusSheet:(nullable GnmSheet *)sheet;
- (void)workbook:(GnmWorkbook *)workbook editLineDidChange:(NSString *)text;
- (void)workbook:(GnmWorkbook *)workbook selectionDescriptionDidChange:(NSString *)text;
- (void)workbook:(GnmWorkbook *)workbook undoLabelDidChange:(nullable NSString *)undoLabel
       redoLabel:(nullable NSString *)redoLabel;
- (void)workbookMenuStateDidChange:(GnmWorkbook *)workbook;
@end

NS_SWIFT_UI_ACTOR NS_SWIFT_NAME(Workbook)
@interface GnmWorkbook : NSObject

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

@property (nonatomic, weak, nullable) id<GnmWorkbookDelegate> delegate;

/// The document URI as the engine knows it (`go_doc_get_uri`), or nil for a
/// workbook that has never been saved.
@property (nonatomic, readonly, copy, nullable) NSURL *fileURL;
@property (nonatomic, readonly, copy) NSString *displayName;
@property (nonatomic, readonly, getter=isModified) BOOL modified;

/// Sheets in workbook order, including hidden ones.  Wrappers are stable for
/// the life of the engine sheet.
@property (nonatomic, readonly, copy) NSArray<GnmSheet *> *sheets;
@property (nonatomic, readonly, nullable) GnmSheet *currentSheet;
- (void)selectSheet:(GnmSheet *)sheet;

/// Recalculate cells that need it (`workbook_recalc`).
- (void)recalculate;

/// Save with the saver goffice picks from the file name (for example
/// `.gnumeric` or `.xlsx`).  On success the workbook adopts the URL.
- (BOOL)writeToURL:(NSURL *)url error:(NSError **)error;

/// Save with an explicit saver such as `Gnumeric_XmlIO:sax` (uncompressed
/// Gnumeric XML when the file name ends in `.xml`) or `Gnumeric_Excel:xlsx2`.
- (BOOL)writeToURL:(NSURL *)url saverIdentifier:(NSString *)saverIdentifier error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
