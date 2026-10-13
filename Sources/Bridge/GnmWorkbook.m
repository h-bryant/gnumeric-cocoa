// GnmWorkbook and the Cocoa WorkbookControl (docs/architecture.md §3).
#import "GnmPrivate.h"
#import <AppKit/NSPasteboard.h>
#import <AppKit/NSBitmapImageRep.h>
#include <workbook-priv.h>

/* ------------------------------------------------------------------------
 * WorkbookControl subclass.  Every vtable slot forwards to the owning
 * GnmWorkbook; slots the viewer does not need stay NULL, which the base
 * class tolerates (workbook-control.c WBC_VIRTUAL).
 */
typedef struct {
    WorkbookControlClass base;
} GnmCocoaWorkbookControlClass;

static GnmWorkbook *
wbc_owner (WorkbookControl *wbc)
{
    GnmCocoaWorkbookControl *c = (GnmCocoaWorkbookControl *) wbc;
    return c->owner ? (__bridge GnmWorkbook *) c->owner : nil;
}

static void
cwbc_sheet_add (WorkbookControl *wbc, SheetView *sv)
{
    [wbc_owner (wbc) _controlDidAddSheetView:sv];
}

static void
cwbc_sheet_remove (WorkbookControl *wbc, Sheet *sheet)
{
    [wbc_owner (wbc) _controlWillRemoveSheet:sheet];
}

static void
cwbc_sheet_focus (WorkbookControl *wbc, Sheet *sheet)
{
    [wbc_owner (wbc) _controlDidFocusSheet:sheet];
}

static void
cwbc_sheet_remove_all (WorkbookControl *wbc)
{
    [wbc_owner (wbc) _controlWillRemoveAllSheets];
}

static void
cwbc_edit_line_set (WorkbookControl *wbc, char const *text)
{
    [wbc_owner (wbc) _controlEditLineDidChange:text];
}

static void
cwbc_selection_descr_set (WorkbookControl *wbc, char const *text)
{
    [wbc_owner (wbc) _controlSelectionDescriptionDidChange:text];
}

static void
cwbc_undo_redo_labels (WorkbookControl *wbc, char const *undo, char const *redo)
{
    [wbc_owner (wbc) _controlUndoLabelDidChange:undo redoLabel:redo];
}

static void
cwbc_menu_state_update (WorkbookControl *wbc, int flags)
{
    [wbc_owner (wbc) _controlMenuStateDidChange:flags];
}

/* The system pasteboard half of the engine's clipboard (gui-clipboard.c for
 * GTK): claim_selection mirrors the engine's region as text so other
 * applications can paste it; paste_from_selection imports text from other
 * applications when the engine's own clipboard is empty. */
static gboolean
cwbc_claim_selection (WorkbookControl *wbc)
{
    GnmWorkbook *owner = wbc_owner (wbc);
    return owner ? [owner _controlClaimSelection] : TRUE;
}

static void
cwbc_paste_from_selection (WorkbookControl *wbc, GnmPasteTarget const *pt)
{
    [wbc_owner (wbc) _controlPasteFromSelection:pt];
}

/* patches/0001: commands ask through the control instead of a GTK dialog. */
static gboolean
cwbc_query_yes_no (WorkbookControl *wbc, gboolean default_answer, char const *question)
{
    GnmWorkbook *owner = wbc_owner (wbc);
    return owner ? [owner _controlAskYesNo:question defaultAnswer:default_answer] : default_answer;
}

static int
cwbc_validation_msg (WorkbookControl *wbc, ValidationStyle v, char const *title, char const *msg)
{
    GnmWorkbook *owner = wbc_owner (wbc);
    GnmValidationStatus fallback = v == GNM_VALIDATION_STYLE_STOP || v == GNM_VALIDATION_STYLE_WARNING
        ? GnmValidationStatusDiscard : GnmValidationStatusValid;   /* wbcg_validation_msg's default response */
    return owner ? [owner _controlValidationMessage:msg title:title style:v fallback:fallback] : fallback;
}

/* Commands report errors through the control's GOCmdContext interface
 * (go_cmd_context_error_invalid (GO_CMD_CONTEXT (wbc), ...) in commands.c),
 * so the subclass must provide the interface methods the base leaves NULL. */
static GnmEngine *
wbc_engine (GOCmdContext *cc)
{
    return wbc_owner (GNM_WBC (cc)).engine;
}

static void
cwbc_error (GOCmdContext *cc, GError *error)
{
    [wbc_engine (cc) _reportMessage:GnmString (error ? error->message : NULL) details:nil];
}

static void
cwbc_error_info (GOCmdContext *cc, GOErrorInfo *error)
{
    if (error)
        [wbc_engine (cc) _reportMessage:GnmString (go_error_info_peek_message (error)) details:nil];
}

static void
cwbc_error_info_list (GOCmdContext *cc, GSList *errors)
{
    for (; errors; errors = errors->next)
        cwbc_error_info (cc, errors->data);
}

static char *
cwbc_get_password (G_GNUC_UNUSED GOCmdContext *cc, G_GNUC_UNUSED char const *filename)
{
    return NULL;
}

static void
cwbc_set_sensitive (G_GNUC_UNUSED GOCmdContext *cc, G_GNUC_UNUSED gboolean sensitive)
{
}

static void
cwbc_progress_set (GOCmdContext *cc, double val)
{
    [wbc_engine (cc) _reportProgress:val message:nil];
}

static void
cwbc_progress_message_set (GOCmdContext *cc, gchar const *msg)
{
    [wbc_engine (cc) _reportProgress:-1 message:msg ? GnmString (msg) : nil];
}

static void
cwbc_cmd_context_init (GOCmdContextClass *iface)
{
    iface->get_password = cwbc_get_password;
    iface->set_sensitive = cwbc_set_sensitive;
    iface->error.error = cwbc_error;
    iface->error.error_info = cwbc_error_info;
    iface->error.error_info_list = cwbc_error_info_list;
    iface->progress_set = cwbc_progress_set;
    iface->progress_message_set = cwbc_progress_message_set;
}

static void
cwbc_class_init (GObjectClass *object_class)
{
    WorkbookControlClass *wbc_class = (WorkbookControlClass *) object_class;
    wbc_class->edit_line_set = cwbc_edit_line_set;
    wbc_class->selection_descr_set = cwbc_selection_descr_set;
    wbc_class->sheet.add = cwbc_sheet_add;
    wbc_class->sheet.remove = cwbc_sheet_remove;
    wbc_class->sheet.focus = cwbc_sheet_focus;
    wbc_class->sheet.remove_all = cwbc_sheet_remove_all;
    wbc_class->undo_redo.labels = cwbc_undo_redo_labels;
    wbc_class->menu_state.update = cwbc_menu_state_update;
    wbc_class->query_yes_no = cwbc_query_yes_no;
    wbc_class->validation_msg = cwbc_validation_msg;
    wbc_class->claim_selection = cwbc_claim_selection;
    wbc_class->paste_from_selection = cwbc_paste_from_selection;
}

static void
cb_dirty_changed (GObject *doc, GParamSpec *pspec, gpointer owner)
{
    GnmWorkbook *wb = (__bridge GnmWorkbook *) owner;
    if ([wb.delegate respondsToSelector:@selector(workbookModifiedStateDidChange:)])
        [wb.delegate workbookModifiedStateDidChange:wb];
}

static void
cb_sheet_changed (GObject *sheet, GParamSpec *pspec, gpointer owner)
{
    GnmWorkbook *wb = (__bridge GnmWorkbook *) owner;
    GnmSheet *wrapper = [wb wrapperForEngineSheet:(Sheet *) sheet];
    if (wrapper && [wb.delegate respondsToSelector:@selector(workbook:sheetDidChange:)])
        [wb.delegate workbook:wb sheetDidChange:wrapper];
}

/* The Format → Sheet toggles: the grid lays out and redraws, as the
 * GTK's sheet control does on these notifications. */
static void
cb_sheet_display_changed (GObject *sheet, GParamSpec *pspec, gpointer owner)
{
    GnmWorkbook *wb = (__bridge GnmWorkbook *) owner;
    GnmSheet *wrapper = [wb wrapperForEngineSheet:(Sheet *) sheet];
    if (wrapper && [wrapper.delegate respondsToSelector:@selector(sheetGeometryDidChange:)])
        [wrapper.delegate sheetGeometryDidChange:wrapper];
}

static void
cb_auto_expr_value_changed (GObject *view, GParamSpec *pspec, gpointer owner)
{
    GnmWorkbook *wb = (__bridge GnmWorkbook *) owner;
    if ([wb.delegate respondsToSelector:@selector(workbook:autoExpressionDidChange:)])
        [wb.delegate workbook:wb autoExpressionDidChange:wb.autoExpressionText];
}

GSF_CLASS_FULL (GnmCocoaWorkbookControl, gnm_cocoa_workbook_control,
                NULL, NULL, cwbc_class_init, NULL, NULL, GNM_WBC_TYPE, 0,
                GSF_INTERFACE (cwbc_cmd_context_init, GO_TYPE_CMD_CONTEXT))

/* ------------------------------------------------------------------------ */

@implementation GnmWorkbook {
    WorkbookView *_wbv;
    Workbook *_wb;
    GnmCocoaWorkbookControl *_wbc;
    NSMutableArray<GnmSheet *> *_sheetWrappers;   /* one per attached SheetView */
    gulong _dirtyHandler;
    gulong _autoExprHandler;
    NSString *_undoLabel, *_redoLabel;
    NSInteger _claimedPasteboardChangeCount;   /* -1: the pasteboard is not ours */
}

- (instancetype)initWithWorkbookView:(WorkbookView *)view engine:(GnmEngine *)engine
{
    if (!(self = [super init]))
        return nil;
    _engine = engine;
    _wbv = view;
    _wb = wb_view_get_workbook (view);
    _sheetWrappers = [NSMutableArray array];
    _claimedPasteboardChangeCount = -1;

    /* The wbc_gtk_new sequence minus the widgets. */
    _wbc = g_object_new (gnm_cocoa_workbook_control_get_type (), NULL);
    _wbc->owner = (__bridge void *) self;
    WorkbookControl *wbc = (WorkbookControl *) _wbc;
    wb_control_set_view (wbc, _wbv, NULL);   /* the view now owns the control */
    if (_wbv->current_sheet != NULL) {
        wb_control_menu_state_update (wbc, MS_ALL);
        wb_control_update_action_sensitivity (wbc);
        wb_control_style_feedback (wbc, NULL);
    }
    wb_control_init_state (wbc);   /* sheet.add for every existing SheetView */
    _dirtyHandler = g_signal_connect (G_OBJECT (_wb), "notify::dirty",
                                      G_CALLBACK (cb_dirty_changed), (__bridge void *) self);
    _autoExprHandler = g_signal_connect (G_OBJECT (_wbv), "notify::auto-expr-value",
                                         G_CALLBACK (cb_auto_expr_value_changed), (__bridge void *) self);
    [engine _registerWorkbook:self];
    return self;
}

- (void)dealloc
{
    [_engine _unregisterWorkbook:self];
    if (!_engine.isRunning) {
        /* The engine is gone (see GnmEngine.shutdown); leaking beats
         * touching freed state. */
        return;
    }
    if (_dirtyHandler)
        g_signal_handler_disconnect (G_OBJECT (_wb), _dirtyHandler);
    if (_autoExprHandler)
        g_signal_handler_disconnect (G_OBJECT (_wbv), _autoExprHandler);
    for (GnmSheet *sheet in _sheetWrappers)
        [sheet _detachFromEngine];
    [_sheetWrappers removeAllObjects];
    if (_wbc)
        _wbc->owner = NULL;
    /* Upstream convention: unreferencing the Workbook disposes it, which
     * detaches and releases its views, and the views release their controls
     * (workbook.c workbook_dispose, workbook-view.c wb_view_dispose). */
    if (_wb)
        g_object_unref (_wb);
}

- (WorkbookView *)workbookView { return _wbv; }
- (Workbook *)engineWorkbook { return _wb; }
- (WorkbookControl *)control { return (WorkbookControl *) _wbc; }

#pragma mark - Document facts

/* A new workbook already carries a placeholder uri ("Book1.gnumeric") and
 * the level GO_FILE_FL_NEW; only a workbook that was loaded from or saved to
 * a file has a real location (workbook.c workbook_set_saveinfo). */
- (BOOL)hasFileLocation
{
    return go_doc_get_uri (GO_DOC (_wb)) != NULL && _wb->file_format_level > GO_FILE_FL_NEW;
}

- (NSURL *)fileURL
{
    if (![self hasFileLocation])
        return nil;
    return [NSURL URLWithString:GnmString (go_doc_get_uri (GO_DOC (_wb)))];
}

- (NSString *)displayName
{
    char const *uri = go_doc_get_uri (GO_DOC (_wb));
    if (uri == NULL || ![self hasFileLocation])
        return @"Untitled";
    char *base = go_basename_from_uri (uri);
    NSString *name = GnmString (base);
    g_free (base);
    return name;
}

- (BOOL)isModified
{
    return go_doc_is_dirty (GO_DOC (_wb));
}

#pragma mark - Sheets

- (GnmSheet *)wrapperForEngineSheet:(Sheet *)sheet
{
    for (GnmSheet *s in _sheetWrappers)
        if (s.engineSheet == sheet)
            return s;
    return nil;
}

- (NSArray<GnmSheet *> *)sheets
{
    /* Workbook order, not attachment order. */
    NSMutableArray *ordered = [NSMutableArray arrayWithCapacity:_sheetWrappers.count];
    int n = workbook_sheet_count (_wb);
    for (int i = 0; i < n; i++) {
        GnmSheet *s = [self wrapperForEngineSheet:workbook_sheet_by_index (_wb, i)];
        if (s)
            [ordered addObject:s];
    }
    return ordered;
}

- (GnmSheet *)currentSheet
{
    Sheet *cur = wb_view_cur_sheet (_wbv);
    return cur ? [self wrapperForEngineSheet:cur] : nil;
}

- (void)selectSheet:(GnmSheet *)sheet
{
    wb_view_sheet_focus (_wbv, sheet.engineSheet);
}

#pragma mark - Sheet management

/* Run a sheet reorganisation as the GTK front end does: snapshot the
 * order, change it, then cmd_reorganize_sheets records the difference as
 * one undoable command (it owns the snapshot and refocuses `focus` on
 * undo). */
- (BOOL)_reorganizeSheetsWith:(void (NS_NOESCAPE ^)(void))change undoFocus:(Sheet *)focus error:(NSError **)error
{
    return [self _runCommand:^gboolean (WorkbookControl *wbc) {
        WorkbookSheetState *old_state = workbook_sheet_state_new (_wb);
        change ();
        return cmd_reorganize_sheets (wbc, old_state, focus);
    } description:@"Could not change the sheets." error:error];
}

- (GnmSheet *)insertSheetBefore:(GnmSheet *)sheet error:(NSError **)error
{
    Sheet *cur = wb_view_cur_sheet (_wbv);
    Sheet *model = sheet ? sheet.engineSheet : cur;
    if (model == NULL)
        return nil;
    __block Sheet *added = NULL;
    int pos = sheet ? sheet.engineSheet->index_in_wb : -1;
    BOOL ok = [self _reorganizeSheetsWith:^{
        added = workbook_sheet_add (_wb, pos, gnm_sheet_get_max_cols (model), gnm_sheet_get_max_rows (model));
    } undoFocus:cur error:error];
    return ok && added ? [self wrapperForEngineSheet:added] : nil;
}

- (GnmSheet *)duplicateSheet:(GnmSheet *)sheet error:(NSError **)error
{
    Sheet *source = sheet.engineSheet;
    if (source == NULL)
        return nil;
    __block Sheet *copy = NULL;
    BOOL ok = [self _reorganizeSheetsWith:^{
        copy = sheet_dup (source);
        workbook_sheet_attach_at_pos (_wb, copy, source->index_in_wb + 1);
        g_signal_emit_by_name (G_OBJECT (_wb), "sheet_added", 0);   /* as workbook_sheet_add does */
    } undoFocus:source error:error];
    GnmSheet *wrapper = ok && copy ? [self wrapperForEngineSheet:copy] : nil;
    if (copy)
        g_object_unref (copy);   /* the workbook holds its own reference */
    return wrapper;
}

- (BOOL)canRemoveSheets
{
    return workbook_sheet_count (_wb) > 1;
}

- (BOOL)removeSheet:(GnmSheet *)sheet error:(NSError **)error
{
    Sheet *doomed = sheet.engineSheet;
    if (doomed == NULL)
        return NO;
    if (!self.canRemoveSheets) {
        if (error)
            *error = [_engine _errorWithCode:GnmErrorCommandFailed
                                 description:@"The last sheet of a workbook cannot be removed." collected:@[]];
        return NO;
    }
    return [self _reorganizeSheetsWith:^{
        workbook_sheet_delete (doomed);
    } undoFocus:doomed error:error];
}

- (BOOL)renameSheet:(GnmSheet *)sheet to:(NSString *)name error:(NSError **)error
{
    Sheet *target = sheet.engineSheet;
    if (target == NULL)
        return NO;
    return [self _runCommand:^gboolean (WorkbookControl *wbc) {
        return cmd_rename_sheet (wbc, target, name.UTF8String);
    } description:@"Could not rename the sheet." error:error];
}

- (BOOL)moveSheet:(GnmSheet *)sheet toIndex:(NSInteger)index error:(NSError **)error
{
    Sheet *target = sheet.engineSheet;
    int count = workbook_sheet_count (_wb);
    if (target == NULL || index < 0 || index >= count)
        return NO;
    int delta = (int) index - target->index_in_wb;
    if (delta == 0)
        return YES;
    return [self _reorganizeSheetsWith:^{
        workbook_sheet_move (target, delta);
    } undoFocus:target error:error];
}

- (BOOL)resizeSheets:(NSArray<GnmSheet *> *)sheets toColumns:(NSInteger)columns rows:(NSInteger)rows error:(NSError **)error
{
    if (![self.class isValidSheetSizeWithColumns:columns rows:rows]) {
        if (error)
            *error = [_engine _errorWithCode:GnmErrorCommandFailed
                                 description:@"Sheet sizes must be powers of two within the engine's limits." collected:@[]];
        return NO;
    }
    GSList *list = NULL;
    for (GnmSheet *sheet in sheets.reverseObjectEnumerator)
        if (sheet.engineSheet)
            list = g_slist_prepend (list, sheet.engineSheet);
    if (list == NULL)
        return YES;
    return [self _runCommand:^gboolean (WorkbookControl *wbc) {
        return cmd_resize_sheets (wbc, list, (int) columns, (int) rows);   /* takes the list */
    } description:@"Could not resize the sheets." error:error];
}

+ (BOOL)isValidSheetSizeWithColumns:(NSInteger)columns rows:(NSInteger)rows
{
    return columns > 0 && rows > 0 && columns <= INT_MAX && rows <= INT_MAX
        && gnm_sheet_valid_size ((int) columns, (int) rows);
}

+ (NSInteger)minimumSheetColumns { return GNM_MIN_COLS; }
+ (NSInteger)maximumSheetColumns { return GNM_MAX_COLS; }
+ (NSInteger)minimumSheetRows { return GNM_MIN_ROWS; }
+ (NSInteger)maximumSheetRows { return GNM_MAX_ROWS; }

- (BOOL)setTabColor:(CGColorRef)background textColor:(CGColorRef)text ofSheet:(GnmSheet *)sheet error:(NSError **)error
{
    Sheet *target = sheet.engineSheet;
    if (target == NULL)
        return NO;
    /* dialogs/dialog-sheet-order.c cb_color_changed_back: the property
     * change between a sheet-state snapshot and cmd_reorganize_sheets. */
    GnmColor *bg = background ? gnm_color_new_go (gnm_cocoa_go_from_cgcolor (background)) : NULL;
    GnmColor *fg = text ? gnm_color_new_go (gnm_cocoa_go_from_cgcolor (text)) : NULL;
    BOOL ok = [self _reorganizeSheetsWith:^{
        g_object_set (target, "tab-background", bg, "tab-foreground", fg, NULL);
    } undoFocus:NULL error:error];
    style_color_unref (bg);
    style_color_unref (fg);
    return ok;
}

- (BOOL)canPaste
{
    NSPasteboard *pasteboard = NSPasteboard.generalPasteboard;
    if (!gnm_app_clipboard_is_empty () && _claimedPasteboardChangeCount == pasteboard.changeCount)
        return YES;
    return [pasteboard stringForType:NSPasteboardTypeString] != nil
        || [pasteboard dataForType:NSPasteboardTypePNG] != nil
        || [pasteboard dataForType:NSPasteboardTypeTIFF] != nil;
}

- (BOOL)jumpToReference:(NSString *)text error:(NSError **)error
{
    NSAssert (NSThread.isMainThread, @"engine access off the main thread");
    [_engine _beginCollectingMessages];
    /* TRUE when it jumped; FALSE with a message for a bad address, FALSE
     * without one when it defined a name instead. */
    gboolean jumped = wb_control_parse_and_jump ((WorkbookControl *) _wbc, text.UTF8String);
    NSArray<NSError *> *messages = [_engine _endCollectingMessages];
    if (!jumped && messages.count) {
        if (error)
            *error = [_engine _errorWithCode:GnmErrorCommandFailed
                                 description:[NSString stringWithFormat:@"“%@” is not a cell, range, or name.", text]
                                   collected:messages];
        return NO;
    }
    return YES;
}

- (void)recalculate
{
    workbook_recalc (_wb);
}

- (void)recalculateAll
{
    workbook_recalc_all (_wb);
}

#pragma mark - Auto-expression

- (NSString *)autoExpressionText
{
    GnmValue const *v = _wbv->auto_expr.value;
    if (v == NULL)
        return @"";
    NSMutableString *text = [NSMutableString string];
    if (_wbv->auto_expr.descr)
        [text appendFormat:@"%s = ", _wbv->auto_expr.descr];
    GOFormat const *format = VALUE_FMT (v);
    char *formatted = format ? format_value (format, v, -1, workbook_date_conv (_wb)) : value_get_as_string (v);
    [text appendString:formatted ? @(formatted) : @""];
    g_free (formatted);
    return text;
}

- (void)setAutoExpressionFunction:(NSString *)name label:(NSString *)label
{
    GnmFunc *func = gnm_func_lookup (name.UTF8String, _wb);
    if (func == NULL)
        return;
    g_object_set (_wbv, "auto-expr-func", func, "auto-expr-descr", label.UTF8String, NULL);
}

- (void)recomputeAutoExpression
{
    wb_view_auto_expr_recalc (_wbv);
}

- (NSString *)autoExpressionFunction
{
    GnmFunc *func = _wbv->auto_expr.func;
    return func ? @(gnm_func_get_name (func, FALSE)) : @"";
}

#pragma mark - Commands, undo, redo

- (BOOL)_runCommand:(gboolean (NS_NOESCAPE ^)(WorkbookControl *wbc))command
        description:(NSString *)description error:(NSError **)error
{
    return [self _runCommand:command description:description reported:NULL error:error];
}

- (BOOL)_runCommand:(gboolean (NS_NOESCAPE ^)(WorkbookControl *wbc))command
        description:(NSString *)description reported:(BOOL *)reported error:(NSError **)error
{
    NSAssert (NSThread.isMainThread, @"engine access off the main thread");
    [_engine _beginCollectingMessages];
    gboolean failed = command ((WorkbookControl *) _wbc);
    NSArray<NSError *> *messages = [_engine _endCollectingMessages];
    if (reported)
        *reported = messages.count > 0;
    if (failed) {
        if (error)
            *error = [_engine _errorWithCode:GnmErrorCommandFailed description:description collected:messages];
        return NO;
    }
    /* A command that succeeded may still have reported (for example a
     * warning); pass those on rather than lose them. */
    for (NSError *message in messages)
        if (_engine.messageHandler)
            _engine.messageHandler (message);
    return YES;
}

- (BOOL)canUndo { return _wb->undo_commands != NULL; }
- (BOOL)canRedo { return _wb->redo_commands != NULL; }
- (NSString *)undoLabel { return _undoLabel; }
- (NSString *)redoLabel { return _redoLabel; }

- (void)undo
{
    if (_wb->undo_commands) {
        command_undo ((WorkbookControl *) _wbc);
        [self _objectsMayHaveChanged];
    }
}

- (void)redo
{
    if (_wb->redo_commands) {
        command_redo ((WorkbookControl *) _wbc);
        [self _objectsMayHaveChanged];
    }
}

/* Reconfigure Graph swaps a chart's graph without any signal the grid
 * could hear (the GTK canvas item listens to the renderer instead), so
 * every undo and redo tells the current sheet its objects may differ. */
- (void)_objectsMayHaveChanged
{
    [self.currentSheet _objectsDidChange];
}

- (void)resendDelegateState
{
    if ([self.delegate respondsToSelector:@selector(workbook:autoExpressionDidChange:)])
        [self.delegate workbook:self autoExpressionDidChange:self.autoExpressionText];
    if (_wbv->current_sheet_view == NULL)
        return;
    wb_view_selection_desc (_wbv, TRUE, (WorkbookControl *) _wbc);
    wb_view_edit_line_set (_wbv, (WorkbookControl *) _wbc);
}

#pragma mark - Saving

- (BOOL)writeToURL:(NSURL *)url error:(NSError **)error
{
    return [self writeToURL:url adoptingURL:YES error:error];
}

- (BOOL)writeToURL:(NSURL *)url saverIdentifier:(NSString *)saverIdentifier error:(NSError **)error
{
    return [self writeToURL:url saverIdentifier:saverIdentifier adoptingURL:YES error:error];
}

- (BOOL)writeToURL:(NSURL *)url adoptingURL:(BOOL)adopt error:(NSError **)error
{
    GOFileSaver *fs = go_file_saver_for_file_name (url.lastPathComponent.UTF8String);
    if (fs == NULL) {
        if (error)
            *error = [_engine _errorWithCode:GnmErrorUnknownFormat
                                 description:[NSString stringWithFormat:@"No file saver handles “%@”.", url.lastPathComponent]
                                   collected:@[]];
        return NO;
    }
    return [self writeToURL:url saver:fs adoptingURL:adopt error:error];
}

- (BOOL)writeToURL:(NSURL *)url saverIdentifier:(NSString *)saverIdentifier adoptingURL:(BOOL)adopt error:(NSError **)error
{
    GOFileSaver *fs = go_file_saver_for_id (saverIdentifier.UTF8String);
    if (fs == NULL) {
        if (error)
            *error = [_engine _errorWithCode:GnmErrorUnknownFormat
                                 description:[NSString stringWithFormat:@"Unknown file saver “%@”.", saverIdentifier]
                                   collected:@[]];
        return NO;
    }
    return [self writeToURL:url saver:fs adoptingURL:adopt error:error];
}

static char *
uri_for_url (NSURL *url)
{
    return url.isFileURL ? go_shell_arg_to_uri (url.path.fileSystemRepresentation) : g_strdup (url.absoluteString.UTF8String);
}

- (BOOL)writeToURL:(NSURL *)url saver:(GOFileSaver *)fs adoptingURL:(BOOL)adopt error:(NSError **)error
{
    char *uri = uri_for_url (url);
    [_engine _beginCollectingMessages];
    gboolean ok;
    if (adopt) {
        /* workbook_view_save_as adopts the uri and saver and clears the
         * dirty flag; it reports through the command context. */
        ok = workbook_view_save_as (_wbv, fs, uri, _engine.commandContext);
    } else {
        /* The same steps without go_doc_set_uri (workbook-view.c
         * workbook_view_save_as): the file goes where asked, the saver and
         * clean state are recorded, the location stays. */
        GOCmdContext *cc = _engine.commandContext;
        GOIOContext *io_context = go_io_context_new (cc);
        go_cmd_context_set_sensitive (cc, FALSE);
        workbook_view_save_to_uri (_wbv, fs, uri, io_context);
        go_cmd_context_set_sensitive (cc, TRUE);
        gboolean has_error = go_io_error_occurred (io_context);
        gboolean has_warning = go_io_warning_occurred (io_context);
        if (!has_error && workbook_set_saveinfo (_wb, go_file_saver_get_format_level (fs), fs)) {
            go_doc_set_saved_state (GO_DOC (_wb), go_doc_get_state (GO_DOC (_wb)));
            go_doc_set_dirty (GO_DOC (_wb), FALSE);
            go_doc_set_pristine (GO_DOC (_wb), FALSE);
            workbook_set_read_only (_wb, FALSE);
        }
        if (has_error || has_warning)
            go_io_error_display (io_context);
        g_object_unref (io_context);
        ok = !has_error;
    }
    NSArray<NSError *> *messages = [_engine _endCollectingMessages];
    g_free (uri);
    if (!ok && error)
        *error = [_engine _errorWithCode:GnmErrorSaveFailed
                             description:[NSString stringWithFormat:@"Could not save “%@”.", url.lastPathComponent]
                               collected:messages];
    return ok;
}

- (void)adoptFileURL:(NSURL *)url
{
    char *uri = uri_for_url (url);
    go_doc_set_uri (GO_DOC (_wb), uri);
    g_free (uri);
}

#pragma mark - Control callbacks

- (void)_controlDidAddSheetView:(SheetView *)sheetView
{
    Sheet *sheet = sv_sheet (sheetView);
    GnmSheet *wrapper = [self wrapperForEngineSheet:sheet];
    if (wrapper == nil) {
        wrapper = [[GnmSheet alloc] initWithSheetView:sheetView workbook:self];
        [_sheetWrappers addObject:wrapper];
        g_signal_connect (G_OBJECT (sheet), "notify::name", G_CALLBACK (cb_sheet_changed), (__bridge void *) self);
        g_signal_connect (G_OBJECT (sheet), "notify::visibility", G_CALLBACK (cb_sheet_changed), (__bridge void *) self);
        g_signal_connect (G_OBJECT (sheet), "notify::tab-background", G_CALLBACK (cb_sheet_changed), (__bridge void *) self);
        g_signal_connect (G_OBJECT (sheet), "notify::tab-foreground", G_CALLBACK (cb_sheet_changed), (__bridge void *) self);
        for (const char *signal_name : (const char *[]) { "notify::display-formulas", "notify::display-zeros", "notify::display-grid",
                                                           "notify::display-column-header", "notify::display-row-header",
                                                           "notify::use-r1c1", "notify::text-is-rtl" })
            g_signal_connect (G_OBJECT (sheet), signal_name, G_CALLBACK (cb_sheet_display_changed), (__bridge void *) self);
    }
    if ([self.delegate respondsToSelector:@selector(workbook:didAddSheet:)])
        [self.delegate workbook:self didAddSheet:wrapper];
}

- (void)_controlWillRemoveSheet:(Sheet *)sheet
{
    GnmSheet *wrapper = [self wrapperForEngineSheet:sheet];
    if (wrapper == nil)
        return;
    if ([self.delegate respondsToSelector:@selector(workbook:willRemoveSheet:)])
        [self.delegate workbook:self willRemoveSheet:wrapper];
    [wrapper _detachFromEngine];
    g_signal_handlers_disconnect_by_data (G_OBJECT (sheet), (__bridge void *) self);
    [_sheetWrappers removeObject:wrapper];
}

- (void)_controlWillRemoveAllSheets
{
    if ([self.delegate respondsToSelector:@selector(workbookWillRemoveAllSheets:)])
        [self.delegate workbookWillRemoveAllSheets:self];
    for (GnmSheet *sheet in _sheetWrappers)
        [sheet _detachFromEngine];
    [_sheetWrappers removeAllObjects];
}

- (void)_controlDidFocusSheet:(Sheet *)sheet
{
    if ([self.delegate respondsToSelector:@selector(workbook:didFocusSheet:)])
        [self.delegate workbook:self didFocusSheet:sheet ? [self wrapperForEngineSheet:sheet] : nil];
}

- (void)_controlEditLineDidChange:(const char *)text
{
    if ([self.delegate respondsToSelector:@selector(workbook:editLineDidChange:)])
        [self.delegate workbook:self editLineDidChange:GnmString (text)];
}

- (void)_controlSelectionDescriptionDidChange:(const char *)text
{
    if ([self.delegate respondsToSelector:@selector(workbook:selectionDescriptionDidChange:)])
        [self.delegate workbook:self selectionDescriptionDidChange:GnmString (text)];
}

- (void)_controlUndoLabelDidChange:(const char *)undo redoLabel:(const char *)redo
{
    _undoLabel = undo ? GnmString (undo) : nil;
    _redoLabel = redo ? GnmString (redo) : nil;
    if ([self.delegate respondsToSelector:@selector(workbook:undoLabelDidChange:redoLabel:)])
        [self.delegate workbook:self undoLabelDidChange:undo ? GnmString (undo) : nil
                      redoLabel:redo ? GnmString (redo) : nil];
}

- (void)_controlMenuStateDidChange:(int)flags
{
    if ([self.delegate respondsToSelector:@selector(workbookMenuStateDidChange:)])
        [self.delegate workbookMenuStateDidChange:self];
}

#pragma mark - Clipboard

- (BOOL)_controlClaimSelection
{
    GnmCellRegion *content = gnm_app_clipboard_contents_get ();
    NSPasteboard *pasteboard = NSPasteboard.generalPasteboard;
    [pasteboard clearContents];
    if (content != NULL && content->cols > 0 && content->rows > 0) {
        GString *text = cellregion_to_string (content, TRUE, workbook_date_conv (_wb));
        if (text) {
            [pasteboard setString:GnmString (text->str) forType:NSPasteboardTypeString];
            g_string_free (text, TRUE);
        }
    } else if (content != NULL && content->objects != NULL) {
        /* Copied objects: a PNG of the first for other applications. */
        SheetObject *so = content->objects->data;
        if (GNM_IS_SO_IMAGEABLE (so)) {
            GsfOutput *output = gsf_output_memory_new ();
            GError *err = NULL;
            sheet_object_write_image (so, "png", -1, output, &err);
            gsf_output_close (output);
            if (err == NULL && gsf_output_size (output) > 0)
                [pasteboard setData:[NSData dataWithBytes:gsf_output_memory_get_bytes (GSF_OUTPUT_MEMORY (output))
                                                   length:(NSUInteger) gsf_output_size (output)]
                            forType:NSPasteboardTypePNG];
            g_clear_error (&err);
            g_object_unref (output);
        }
    }
    _claimedPasteboardChangeCount = pasteboard.changeCount;
    return TRUE;
}

- (void)_dropStaleEngineClipboard
{
    if (gnm_app_clipboard_is_empty ())
        return;
    if (_claimedPasteboardChangeCount < 0 || NSPasteboard.generalPasteboard.changeCount != _claimedPasteboardChangeCount) {
        gnm_app_clipboard_clear (TRUE);
        _claimedPasteboardChangeCount = -1;
    }
}

/* text_to_cell_region (gui-clipboard.c) without the import dialog: one
 * value is matched like typed input, anything else goes through the text
 * importer with guessed options. */
static GnmCellRegion *
region_from_text (Workbook *wb, NSString *string)
{
    const char *data = string.UTF8String;
    GnmCellRegion *cr;
    if (strchr (data, '\n') == NULL && strchr (data, '\t') == NULL && strchr (data, '\r') == NULL) {
        GnmCellCopy *cc = gnm_cell_copy_new ((cr = gnm_cell_region_new (NULL)), 0, 0);
        char *tmp = g_strdup (data);
        cc->val = format_match (tmp, NULL, workbook_date_conv (wb));
        if (cc->val)
            g_free (tmp);
        else
            cc->val = value_new_string_nocopy (tmp);
        cc->texpr = NULL;
        cr->cols = cr->rows = 1;
    } else {
        GnmStfParseOptions *options = stf_parse_options_guess (data);
        cr = stf_parse_region (options, data, NULL, wb);
        g_object_unref (options);   /* a GObject since 1.12.61 */
        if (cr == NULL)
            cr = gnm_cell_region_new (NULL);
    }
    return cr;
}

/* An image from another application lands as an image object at the
 * target's first cell, at its own size (scg_paste_image). */
- (void)_pasteImageData:(NSData *)png into:(GnmPasteTarget const *)target
{
    GnmSheet *sheet = [self wrapperForEngineSheet:target->sheet];
    if (sheet == nil)
        return;
    CGSize size = [sheet naturalSizeOfImageData:png];
    if (CGSizeEqualToSize (size, CGSizeZero))
        return;
    CGRect frame = CGRectMake ([sheet leftEdgeOfColumn:target->range.start.col],
                               [sheet topEdgeOfRow:target->range.start.row], size.width, size.height);
    [sheet insertImageData:png frame:frame error:NULL];
}

- (void)_controlPasteFromSelection:(GnmPasteTarget const *)target
{
    NSPasteboard *pasteboard = NSPasteboard.generalPasteboard;
    NSString *string = [pasteboard stringForType:NSPasteboardTypeString];
    if (string == nil) {
        NSData *png = [pasteboard dataForType:NSPasteboardTypePNG];
        if (png == nil) {
            NSData *tiff = [pasteboard dataForType:NSPasteboardTypeTIFF];
            if (tiff)
                png = [[NSBitmapImageRep imageRepWithData:tiff] representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
        }
        if (png)
            [self _pasteImageData:png into:target];
        return;
    }
    GnmCellRegion *cr = region_from_text (_wb, string);
    if (cr->cols > 0 && cr->rows > 0)
        cmd_paste_copy ((WorkbookControl *) _wbc, target, cr);
    cellregion_unref (cr);
}

- (GnmValidationStatus)_controlValidationMessage:(const char *)message title:(const char *)title style:(int)style
                                        fallback:(GnmValidationStatus)fallback
{
    if ([self.delegate respondsToSelector:@selector(workbook:presentValidationMessage:title:action:)])
        return [self.delegate workbook:self presentValidationMessage:GnmString (message) title:title ? GnmString (title) : nil
                                action:(GnmValidationAction) style];
    return fallback;
}

- (BOOL)_controlAskYesNo:(const char *)question defaultAnswer:(BOOL)defaultAnswer
{
    if ([self.delegate respondsToSelector:@selector(workbook:askYesNo:defaultAnswer:)])
        return [self.delegate workbook:self askYesNo:GnmString (question) defaultAnswer:defaultAnswer];
    return defaultAnswer;
}

@end
