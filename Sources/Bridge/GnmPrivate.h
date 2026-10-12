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
#include <validation.h>
#include <input-msg.h>
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
#include <sort.h>
#include <func.h>
#include <sheet-filter.h>
#include <sheet-filter-combo.h>
#include <sheet-object-impl.h>
#include <sheet-object-cell-comment.h>
#include <sheet-object-graph.h>
#include <sheet-object-image.h>
#include <graph.h>
#include <sheet-utils.h>
#include <tools/filter.h>
#include <tools/auto-correct.h>
#include <tools/dao.h>
#include <tools/fill-series.h>
#include <tools/analysis-tools.h>
#include <tools/analysis-regression.h>
#include <tools/goal-seek.h>
#include <tools/gnm-solver.h>
#include <goffice/goffice.h>
#include <goffice/app/go-cmd-context-impl.h>
#include <goffice/graph/gog-plot-engine.h>
#include <goffice/utils/go-rsm.h>
#include <gsf/gsf-impl-utils.h>
#include <gsf/gsf-output-memory.h>
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
- (GnmValidationStatus)_controlValidationMessage:(nullable const char *)message title:(nullable const char *)title style:(int)style
                                        fallback:(GnmValidationStatus)fallback;
- (BOOL)_controlClaimSelection;
- (void)_controlPasteFromSelection:(GnmPasteTarget const *)target;
/// Drop the engine's clipboard when another application has replaced the
/// system pasteboard since the control claimed it.
- (void)_dropStaleEngineClipboard;
/// The wrapper attached to an engine sheet, if any.
- (nullable GnmSheet *)wrapperForEngineSheet:(Sheet *)sheet;
/// The save behind the public writes, with the saver already found.
- (BOOL)writeToURL:(NSURL *)url saver:(GOFileSaver *)fs adoptingURL:(BOOL)adopt error:(NSError **)error;
/// Run an engine command that returns TRUE on failure, turning messages it
/// reported into `error`.
- (BOOL)_runCommand:(gboolean (NS_NOESCAPE ^)(WorkbookControl *wbc))command
        description:(NSString *)description error:(NSError **)error;
/// The same, telling the caller whether the engine reported anything: a
/// TRUE with no message is how some commands say "nothing to do".
- (BOOL)_runCommand:(gboolean (NS_NOESCAPE ^)(WorkbookControl *wbc))command
        description:(NSString *)description reported:(nullable BOOL *)reported error:(NSError **)error;
@end

@interface GnmSheet ()
- (instancetype)initWithSheetView:(SheetView *)sheetView workbook:(GnmWorkbook *)workbook NS_DESIGNATED_INITIALIZER;
/// The wrapper of an engine object, created on first sight and kept.
- (GnmSheetObject *)_wrapperForObject:(SheetObject *)object;
/// An object's bounds changed, or it left or joined the sheet.
- (void)_objectsDidChange;
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

@interface GnmSheetObject ()
- (instancetype)initWithObject:(SheetObject *)object sheet:(GnmSheet *)sheet NS_DESIGNATED_INITIALIZER;
@property (nonatomic, readonly, nullable) SheetObject *engineObject;
/// The sheet wrapper that made this object's wrapper.
@property (nonatomic, readonly, weak, nullable) GnmSheet *_ownerSheet;
- (void)_detachFromEngine;
- (void)_engineObjectDidChange;
@end

@interface GnmTextImportSession ()
- (instancetype)initWithText:(GString *)text name:(NSString *)name encoding:(NSString *)encoding url:(nullable NSURL *)url;
- (GnmStfParseOptions *)_parseOptions;
/// The chosen lines, NUL-terminated; the caller frees it.
- (char *)_copyOfRange;
@end

@interface GnmGoalSeekResult ()
- (instancetype)initWithFound:(BOOL)found solution:(double)solution current:(double)current target:(double)target NS_DESIGNATED_INITIALIZER;
@end

@interface GnmAnalysisOutput ()
- (instancetype)initPrivate NS_DESIGNATED_INITIALIZER;
/// The engine's output description for a run on a sheet; the command
/// that runs takes it over.  NULL with the dialogs' message.
- (nullable data_analysis_output_t *)_outputForSheet:(Sheet *)sheet engine:(GnmEngine *)engine error:(NSError **)error;
@end

@interface GnmAnalysis ()
- (instancetype)initWithTitle:(NSString *)title NS_DESIGNATED_INITIALIZER;
/// The engine's tool with the settings and the input read relative to
/// the sheet; the caller owns it.  NULL with the dialogs' message.
- (nullable GnmAnalysisTool *)_engineToolForSheet:(Sheet *)sheet engine:(GnmEngine *)engine error:(NSError **)error;
/// After a failed run, what the tool's error code means, or nil for none.
- (nullable NSString *)_failureDescriptionForEngineTool:(GnmAnalysisTool *)tool;
@end

@interface GnmGroupedAnalysis ()
- (GnmAnalysisTool *)_newEngineTool;
- (BOOL)_configureEngineTool:(GnmAnalysisTool *)tool engine:(GnmEngine *)engine error:(NSError **)error;
@end

@interface GnmTwoSampleAnalysis ()
- (instancetype)initWithTitle:(NSString *)title;
- (GnmAnalysisTool *)_newEngineTool;
- (BOOL)_configureEngineTool:(GnmAnalysisTool *)tool engine:(GnmEngine *)engine error:(NSError **)error;
@end

@interface GnmSolverAlgorithm ()
- (instancetype)initWithFactory:(GnmSolverFactory *)factory NS_DESIGNATED_INITIALIZER;
@end

@interface GnmSolverSettings ()
- (instancetype)initWithParameters:(GnmSolverParameters *)param sheet:(nullable Sheet *)sheet NS_DESIGNATED_INITIALIZER;
/// extract_settings: write the settings into a sheet's parameters.
- (void)_fillParameters:(GnmSolverParameters *)param sheet:(Sheet *)sheet;
@end

@interface GnmSolverOutcome ()
- (instancetype)initWithSolver:(GnmSolver *)solver NS_DESIGNATED_INITIALIZER;
@end

@interface GnmCellComment ()
- (instancetype)initWithComment:(GnmComment *)comment NS_DESIGNATED_INITIALIZER;
@end

@interface GnmPreferences ()
- (instancetype)initPrivate NS_DESIGNATED_INITIALIZER;
@end

@interface GnmImageFormat ()
- (instancetype)initWithFormat:(GOImageFormat)format NS_DESIGNATED_INITIALIZER;
@property (nonatomic, readonly) GOImageFormat format;
@end

@interface GnmChartProperty ()
- (instancetype)initWithName:(NSString *)name label:(NSString *)label kind:(GnmChartPropertyKind)kind value:(nullable id)value
                     choices:(NSArray<NSString *> *)choices choiceLabels:(NSArray<NSString *> *)choiceLabels
                     minimum:(double)minimum maximum:(double)maximum NS_DESIGNATED_INITIALIZER;
@end

@interface GnmChartDimension ()
- (instancetype)initWithIndex:(NSInteger)index label:(NSString *)label kind:(GnmChartDataKind)kind text:(NSString *)text
                        isSet:(BOOL)isSet NS_DESIGNATED_INITIALIZER;
@end

@interface GnmChartStyle ()
- (instancetype)initWithStyle:(GOStyle const *)style NS_DESIGNATED_INITIALIZER;
- (instancetype)initPrivate;
/// Write the fields into an engine style (a duplicate the caller owns).
- (void)writeToStyle:(GOStyle *)style;
@end

@interface GnmChartNode ()
/// Watches the object without keeping it alive (a weak reference); the
/// editor caches one node per object and forgets it when the object goes.
- (instancetype)initWithObject:(GogObject *)object editor:(GnmChartEditor *)editor NS_DESIGNATED_INITIALIZER;
/// NULL once the object is gone.
@property (nonatomic, readonly, nullable) GogObject *object;
- (void)_objectGone;
@end

@interface GnmChartEditor ()
/// The working copy.
@property (nonatomic, readonly) GogGraph *graph;
/// The sheet the chart is on, for expressions and their dependencies.
@property (nonatomic, readonly, nullable) Sheet *sheet;
- (GnmChartNode *)_nodeForObject:(GogObject *)object;
- (void)_forgetNodeForObject:(GogObject *)object;
- (void)_didChange;
@end

@interface GnmPlotType ()
- (instancetype)initWithEngineType:(GogPlotType const *)type NS_DESIGNATED_INITIALIZER;
@property (nonatomic, readonly) GogPlotType const *engineType;
/// A value from the type's property table ("guru-hints", "type", ...).
- (nullable NSString *)propertyNamed:(NSString *)name;
@end

@interface GnmFilterButton ()
/// Keeps a reference on the filter; `field` indexes `filter->fields`.
- (instancetype)initWithFilter:(GnmFilter *)filter field:(unsigned)field sheet:(Sheet *)sheet NS_DESIGNATED_INITIALIZER;
@property (nonatomic, readonly) GnmFilter *filter;
@property (nonatomic, readonly) unsigned field;
/// NO once the filter was removed from the sheet (undo, Remove Autofilter).
@property (nonatomic, readonly) BOOL isAttached;
@end

@interface GnmFilterCriterion ()
/// Value conditions: the engine value (owned).
- (instancetype)initWithValue:(GnmValue *)value index:(NSInteger)index text:(NSString *)text;
@property (nonatomic, readonly, nullable) GnmValue const *value;
/// The engine's condition of a field as a description; ShowAll for NULL.
+ (instancetype)conditionFromEngine:(nullable GnmFilterCondition const *)cond
                             values:(nullable GPtrArray *)values labels:(nullable NSArray<NSString *> *)labels;
/// A new engine condition (caller owns), or NULL for ShowAll.
- (nullable GnmFilterCondition *)newEngineConditionWithWorkbook:(Workbook *)wb;
@end

@interface GnmFilterChoices ()
- (instancetype)initWithValues:(GPtrArray *)values labels:(NSArray<NSString *> *)labels
                     hasBlanks:(BOOL)hasBlanks current:(GnmFilterCriterion *)current NS_DESIGNATED_INITIALIZER;
@end

/// A cairo context drawing into a CGContext (y downward, the CTM kept),
/// clipped to `rect`; the caller destroys the context, then flushes and
/// destroys the surface (GnmSheet.m).
cairo_t *gnm_cocoa_cairo_for_context (CGContextRef context, CGRect rect, cairo_surface_t *_Nonnull *_Nonnull surface_out);

/// The pixel rectangle of a sheet object (x0, y0, x1, y1), and the
/// column or row at a sheet pixel position with its edge (GnmSheet.m).
void gnm_cocoa_object_pixel_frame (Sheet const *sheet, SheetObject const *so, double *coords);
int gnm_cocoa_colrow_at (Sheet const *sheet, gboolean is_cols, gint64 pos, gint64 *_Nullable origin);

/// Color conversions shared by the drawing and style code.
GdkRGBA gnm_cocoa_rgba_from_cgcolor (CGColorRef color);
CGColorRef gnm_cocoa_cgcolor_from_go (GOColor c) CF_RETURNS_RETAINED;
GOColor gnm_cocoa_go_from_cgcolor (CGColorRef color);
/// The common style of a range (nil properties differ), and the partial
/// style plus borders a GnmCellFormat describes, for cmd_selection_format.
GnmCellFormat *gnm_cocoa_format_from_selection (Sheet const *sheet, GnmRange const *range);
GnmCellFormat *gnm_cocoa_format_from_style (GnmStyle const *style);
void gnm_cocoa_format_to_engine (GnmCellFormat *format, GnmStyle *_Nonnull *_Nonnull style_out,
                                 GnmBorder *_Nullable borders[_Nonnull GNM_STYLE_BORDER_EDGE_MAX]);

/// NSString from a UTF-8 C string, empty for NULL.
NS_INLINE NSString *GnmString(const char *_Nullable s) {
    return s ? [NSString stringWithUTF8String:s] ?: @"" : @"";
}

NS_ASSUME_NONNULL_END
