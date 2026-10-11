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
- (void)workbook:(GnmWorkbook *)workbook didAddSheet:(GnmSheet *)sheet NS_SWIFT_NAME(workbook(_:didAdd:));
- (void)workbook:(GnmWorkbook *)workbook willRemoveSheet:(GnmSheet *)sheet NS_SWIFT_NAME(workbook(_:willRemove:));
- (void)workbookWillRemoveAllSheets:(GnmWorkbook *)workbook NS_SWIFT_NAME(workbookWillRemoveAllSheets(_:));
- (void)workbook:(GnmWorkbook *)workbook didFocusSheet:(nullable GnmSheet *)sheet NS_SWIFT_NAME(workbook(_:didFocus:));
/// A sheet's name or visibility changed (the GTK tab listens to the same
/// signals); the order of `sheets` may have changed with it.
- (void)workbook:(GnmWorkbook *)workbook sheetDidChange:(GnmSheet *)sheet NS_SWIFT_NAME(workbook(_:sheetDidChange:));
- (void)workbook:(GnmWorkbook *)workbook editLineDidChange:(NSString *)text NS_SWIFT_NAME(workbook(_:editLineDidChange:));
- (void)workbook:(GnmWorkbook *)workbook selectionDescriptionDidChange:(NSString *)text NS_SWIFT_NAME(workbook(_:selectionDescriptionDidChange:));
- (void)workbook:(GnmWorkbook *)workbook undoLabelDidChange:(nullable NSString *)undoLabel
       redoLabel:(nullable NSString *)redoLabel NS_SWIFT_NAME(workbook(_:undoLabelDidChange:redoLabel:));
- (void)workbookMenuStateDidChange:(GnmWorkbook *)workbook NS_SWIFT_NAME(workbookMenuStateDidChange(_:));
/// The document's dirty flag changed (`go_doc_set_dirty`).
- (void)workbookModifiedStateDidChange:(GnmWorkbook *)workbook NS_SWIFT_NAME(workbookModifiedStateDidChange(_:));
/// The auto-expression over the selection (for example "Sum = 42") was
/// recomputed; `text` is empty when there is nothing to show.
- (void)workbook:(GnmWorkbook *)workbook autoExpressionDidChange:(NSString *)text NS_SWIFT_NAME(workbook(_:autoExpressionDidChange:));
/// A command needs a yes/no answer (for example hiding every row, or
/// pasting more than ten thousand copies).  Return the answer; when the
/// delegate does not implement this, the command gets `defaultAnswer`.
- (BOOL)workbook:(GnmWorkbook *)workbook askYesNo:(NSString *)question defaultAnswer:(BOOL)defaultAnswer NS_SWIFT_NAME(workbook(_:askYesNo:defaultAnswer:));
@end

NS_SWIFT_UI_ACTOR NS_SWIFT_NAME(Workbook)
@interface GnmWorkbook : NSObject

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

@property (nonatomic, weak, nullable) id<GnmWorkbookDelegate> delegate;

/// Deliver the current selection description and edit line to the delegate
/// again; the engine only sends them on change, and the first ones go out
/// before a delegate can be attached.
- (void)resendDelegateState;

/// The document URI as the engine knows it (`go_doc_get_uri`), or nil for a
/// workbook that has never been saved.
@property (nonatomic, readonly, copy, nullable) NSURL *fileURL;
@property (nonatomic, readonly, copy) NSString *displayName;
@property (nonatomic, readonly, getter=isModified) BOOL modified;

/// Sheets in workbook order, including hidden ones.  Wrappers are stable for
/// the life of the engine sheet.
@property (nonatomic, readonly, copy) NSArray<GnmSheet *> *sheets;
@property (nonatomic, readonly, nullable) GnmSheet *currentSheet;
- (void)selectSheet:(GnmSheet *)sheet NS_SWIFT_NAME(select(_:));

// Sheet management, each one undoable command (`cmd_reorganize_sheets`,
// `cmd_rename_sheet`), as the GTK tab menu does it.  New sheets take the
// current sheet's size and the engine's next free name; the wrapper for a
// new sheet is in `sheets` when the call returns.
/// Insert an empty sheet before `sheet`, or at the end for nil.
- (nullable GnmSheet *)insertSheetBefore:(nullable GnmSheet *)sheet error:(NSError **)error NS_SWIFT_NAME(insertSheet(before:));
/// A copy of `sheet` right after it (`sheet_dup`).
- (nullable GnmSheet *)duplicateSheet:(GnmSheet *)sheet error:(NSError **)error NS_SWIFT_NAME(duplicate(_:));
/// Remove `sheet`; the last sheet cannot be removed (`canRemoveSheets`).
- (BOOL)removeSheet:(GnmSheet *)sheet error:(NSError **)error NS_SWIFT_NAME(remove(_:));
@property (nonatomic, readonly) BOOL canRemoveSheets;
/// Rename; the engine refuses an empty or duplicate name.
- (BOOL)renameSheet:(GnmSheet *)sheet to:(NSString *)name error:(NSError **)error NS_SWIFT_NAME(rename(_:to:));
/// Move `sheet` to position `index` in the workbook order.
- (BOOL)moveSheet:(GnmSheet *)sheet toIndex:(NSInteger)index error:(NSError **)error NS_SWIFT_NAME(move(_:toIndex:));

/// The status bar's auto-expression: the function's label, " = ", and the
/// value over the current selection, formatted as the engine suggests
/// (the GTK status bar); empty when there is no value.
@property (nonatomic, readonly, copy) NSString *autoExpressionText;
/// The engine function the auto-expression applies to the selection
/// ("sum" by default; "min", "max", "average", "count" are the GTK
/// choices) and the label shown for it.  An unknown name is ignored.
- (void)setAutoExpressionFunction:(NSString *)name label:(NSString *)label NS_SWIFT_NAME(setAutoExpression(function:label:));
@property (nonatomic, readonly, copy) NSString *autoExpressionFunction;
/// Recompute the auto-expression now; the engine otherwise does it a
/// recalc lag (a GLib timeout) after the selection changes.
- (void)recomputeAutoExpression;

/// Recalculate cells that need it (`workbook_recalc`).
- (void)recalculate;
/// Recalculate every cell (`workbook_recalc_all`, the GTK Recalculate).
- (void)recalculateAll;

// Undo and redo come from the engine's command stack, which is the only
// source of truth (never mirror it in NSUndoManager).  Labels are the
// command descriptions the engine reports, for the Edit menu.
@property (nonatomic, readonly) BOOL canUndo;
@property (nonatomic, readonly) BOOL canRedo;
@property (nonatomic, readonly, copy, nullable) NSString *undoLabel;
@property (nonatomic, readonly, copy, nullable) NSString *redoLabel;
- (void)undo;
- (void)redo;

/// Save with the saver goffice picks from the file name (for example
/// `.gnumeric` or `.xlsx`).  On success the workbook adopts the URL.
- (BOOL)writeToURL:(NSURL *)url error:(NSError **)error NS_SWIFT_NAME(write(to:));

/// Save with an explicit saver such as `Gnumeric_XmlIO:sax` (uncompressed
/// Gnumeric XML when the file name ends in `.xml`) or `Gnumeric_Excel:xlsx2`.
- (BOOL)writeToURL:(NSURL *)url saverIdentifier:(NSString *)saverIdentifier error:(NSError **)error NS_SWIFT_NAME(write(to:saverIdentifier:));

@end

NS_ASSUME_NONNULL_END
