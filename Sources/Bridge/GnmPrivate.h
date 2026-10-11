// Bridge-internal declarations.  This is the only header that may include
// engine headers, and it must never be imported from Sources/App or from the
// public include directory.
#import <GnmCocoa/GnmCocoa.h>

#include <gnumeric.h>
#include <libgnumeric.h>
#include <gnm-plugin.h>
#include <gnumeric-conf.h>
#include <gutils.h>
#include <application.h>
#include <workbook.h>
#include <workbook-view.h>
#include <workbook-control-priv.h>
#include <sheet.h>
#include <sheet-view.h>
#include <sheet-control-priv.h>
#include <sheet-style.h>
#include <sheet-merge.h>
#include <sheet-object.h>
#include <cell.h>
#include <cell-draw.h>
#include <cellspan.h>
#include <colrow.h>
#include <style-border.h>
#include <style-conditions.h>
#include <mstyle.h>
#include <style-color.h>
#include <pattern.h>
#include <position.h>
#include <ranges.h>
#include <selection.h>
#include <parse-util.h>
#include <commands.h>
#include <workbook-cmd-format.h>
#include <cmd-edit.h>
#include <clipboard.h>
#include <number-match.h>
#include <stf-parse.h>
#include <value.h>
#include <gnm-format.h>
#include <func.h>
#include <goffice/goffice.h>
#include <goffice/app/go-cmd-context-impl.h>
#include <gsf/gsf-impl-utils.h>
#include <cairo.h>
#include <cairo-quartz.h>

NS_ASSUME_NONNULL_BEGIN

/// The WorkbookControl subclass.  `owner` is the unretained GnmWorkbook that
/// created it; the wrapper clears it before the engine can outlive it.
typedef struct {
    WorkbookControl base;
    void *_Nullable owner;
} GnmCocoaWorkbookControl;

/// The SheetControl subclass.  `owner` is the unretained GnmSheet.
typedef struct {
    SheetControl base;
    void *_Nullable owner;
} GnmCocoaSheetControl;

GType gnm_cocoa_workbook_control_get_type (void);
GType gnm_cocoa_sheet_control_get_type (void);

@interface GnmEngine ()
@property (nonatomic, readonly) GOCmdContext *commandContext;
/// Route engine messages into an array until the matching end call, so a
/// bridge method can turn them into one NSError.
- (void)_beginCollectingMessages;
- (NSArray<NSError *> *)_endCollectingMessages;
/// Called by the command-context implementations.
- (void)_reportMessage:(NSString *)message details:(nullable NSString *)details;
- (void)_reportProgress:(double)fraction message:(nullable NSString *)message;
- (NSError *)_errorWithCode:(GnmErrorCode)code description:(NSString *)description
             collected:(NSArray<NSError *> *)collected;
/// Weak registry of live wrappers, so `shutdown` can refuse to tear the
/// engine down under them.
- (void)_registerWorkbook:(GnmWorkbook *)workbook;
- (void)_unregisterWorkbook:(GnmWorkbook *)workbook;
@property (nonatomic, readonly, getter=isRunning) BOOL running;
@end

@interface GnmWorkbook ()
/// Takes ownership of the view reference the engine's opener returned.
- (instancetype)initWithWorkbookView:(WorkbookView *)view engine:(GnmEngine *)engine NS_DESIGNATED_INITIALIZER;
@property (nonatomic, readonly) GnmEngine *engine;
@property (nonatomic, readonly) WorkbookView *workbookView;
@property (nonatomic, readonly) Workbook *engineWorkbook;
@property (nonatomic, readonly, nullable) WorkbookControl *control;
// WorkbookControl vtable entry points.
- (void)_controlDidAddSheetView:(SheetView *)sheetView;
- (void)_controlWillRemoveSheet:(Sheet *)sheet;
- (void)_controlWillRemoveAllSheets;
- (void)_controlDidFocusSheet:(nullable Sheet *)sheet;
- (void)_controlEditLineDidChange:(nullable const char *)text;
- (void)_controlSelectionDescriptionDidChange:(nullable const char *)text;
- (void)_controlUndoLabelDidChange:(nullable const char *)undo redoLabel:(nullable const char *)redo;
- (void)_controlMenuStateDidChange:(int)flags;
- (BOOL)_controlAskYesNo:(nullable const char *)question defaultAnswer:(BOOL)defaultAnswer;
- (BOOL)_controlClaimSelection;
- (void)_controlPasteFromSelection:(GnmPasteTarget const *)target;
/// Drop the engine's clipboard when another application has replaced the
/// system pasteboard since the control claimed it.
- (void)_dropStaleEngineClipboard;
/// Run an engine command that returns TRUE on failure, turning messages it
/// reported into `error`.
- (BOOL)_runCommand:(gboolean (NS_NOESCAPE ^)(WorkbookControl *wbc))command
        description:(NSString *)description error:(NSError **)error;
@end

@interface GnmSheet ()
- (instancetype)initWithSheetView:(SheetView *)sheetView workbook:(GnmWorkbook *)workbook NS_DESIGNATED_INITIALIZER;
@property (nonatomic, readonly) Sheet *engineSheet;
@property (nonatomic, readonly, nullable) SheetView *sheetView;
/// Detach and release the SheetControl; safe to call more than once.
- (void)_detachFromEngine;
- (void)_controlWasFinalized;
// SheetControl vtable entry points.
- (void)_controlNeedsDisplayIncludingHeaders:(BOOL)headers;
- (void)_controlNeedsDisplayInRange:(GnmRange const *)range;
- (void)_controlNeedsHeaderDisplayForColumns:(BOOL)columns rows:(BOOL)rows;
- (void)_controlGeometryDidChange;
- (void)_controlCursorDidMoveToRange:(nullable GnmRange const *)range;
- (void)_controlScrollToColumn:(int)column row:(int)row;
- (void)_controlMakeVisibleColumn:(int)column row:(int)row;
- (void)_controlMarchingAntsDidChange;
- (void)_controlFrozenPanesDidChange;
@end

/// Color conversions shared by the drawing and style code.
GdkRGBA gnm_cocoa_rgba_from_cgcolor (CGColorRef color);
CGColorRef gnm_cocoa_cgcolor_from_go (GOColor c) CF_RETURNS_RETAINED;
GOColor gnm_cocoa_go_from_cgcolor (CGColorRef color);
/// The common style of a range (nil properties differ), and the partial
/// style plus borders a GnmCellFormat describes, for cmd_selection_format.
GnmCellFormat *gnm_cocoa_format_from_selection (Sheet const *sheet, GnmRange const *range);
void gnm_cocoa_format_to_engine (GnmCellFormat *format, GnmStyle *_Nonnull *_Nonnull style_out,
                                 GnmBorder *_Nullable borders[_Nonnull GNM_STYLE_BORDER_EDGE_MAX]);

/// NSString from a UTF-8 C string, empty for NULL.
NS_INLINE NSString *GnmString(const char *_Nullable s) {
    return s ? [NSString stringWithUTF8String:s] ?: @"" : @"";
}

NS_ASSUME_NONNULL_END
