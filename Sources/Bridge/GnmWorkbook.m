// GnmWorkbook and the Cocoa WorkbookControl (docs/architecture.md §3).
#import "GnmPrivate.h"
#import <AppKit/NSPasteboard.h>
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
    NSAssert (NSThread.isMainThread, @"engine access off the main thread");
    [_engine _beginCollectingMessages];
    gboolean failed = command ((WorkbookControl *) _wbc);
    NSArray<NSError *> *messages = [_engine _endCollectingMessages];
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
    if (_wb->undo_commands)
        command_undo ((WorkbookControl *) _wbc);
}

- (void)redo
{
    if (_wb->redo_commands)
        command_redo ((WorkbookControl *) _wbc);
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
    GOFileSaver *fs = go_file_saver_for_file_name (url.lastPathComponent.UTF8String);
    if (fs == NULL) {
        if (error)
            *error = [_engine _errorWithCode:GnmErrorUnknownFormat
                                 description:[NSString stringWithFormat:@"No file saver handles “%@”.", url.lastPathComponent]
                                   collected:@[]];
        return NO;
    }
    return [self writeToURL:url saver:fs error:error];
}

- (BOOL)writeToURL:(NSURL *)url saverIdentifier:(NSString *)saverIdentifier error:(NSError **)error
{
    GOFileSaver *fs = go_file_saver_for_id (saverIdentifier.UTF8String);
    if (fs == NULL) {
        if (error)
            *error = [_engine _errorWithCode:GnmErrorUnknownFormat
                                 description:[NSString stringWithFormat:@"Unknown file saver “%@”.", saverIdentifier]
                                   collected:@[]];
        return NO;
    }
    return [self writeToURL:url saver:fs error:error];
}

- (BOOL)writeToURL:(NSURL *)url saver:(GOFileSaver *)fs error:(NSError **)error
{
    char *uri = url.isFileURL ? go_shell_arg_to_uri (url.path.fileSystemRepresentation)
                              : g_strdup (url.absoluteString.UTF8String);
    [_engine _beginCollectingMessages];
    /* workbook_view_save_as adopts the uri and saver and clears the dirty
     * flag; it reports through the command context and returns success. */
    gboolean ok = workbook_view_save_as (_wbv, fs, uri, _engine.commandContext);
    NSArray<NSError *> *messages = [_engine _endCollectingMessages];
    g_free (uri);
    if (!ok && error)
        *error = [_engine _errorWithCode:GnmErrorSaveFailed
                             description:[NSString stringWithFormat:@"Could not save “%@”.", url.lastPathComponent]
                               collected:messages];
    return ok;
}

#pragma mark - Control callbacks

- (void)_controlDidAddSheetView:(SheetView *)sheetView
{
    Sheet *sheet = sv_sheet (sheetView);
    GnmSheet *wrapper = [self wrapperForEngineSheet:sheet];
    if (wrapper == nil) {
        wrapper = [[GnmSheet alloc] initWithSheetView:sheetView workbook:self];
        [_sheetWrappers addObject:wrapper];
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

- (void)_controlPasteFromSelection:(GnmPasteTarget const *)target
{
    NSString *string = [NSPasteboard.generalPasteboard stringForType:NSPasteboardTypeString];
    if (string == nil)
        return;
    GnmCellRegion *cr = region_from_text (_wb, string);
    if (cr->cols > 0 && cr->rows > 0)
        cmd_paste_copy ((WorkbookControl *) _wbc, target, cr);
    cellregion_unref (cr);
}

- (BOOL)_controlAskYesNo:(const char *)question defaultAnswer:(BOOL)defaultAnswer
{
    if ([self.delegate respondsToSelector:@selector(workbook:askYesNo:defaultAnswer:)])
        return [self.delegate workbook:self askYesNo:GnmString (question) defaultAnswer:defaultAnswer];
    return defaultAnswer;
}

@end
