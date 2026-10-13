// Engine lifecycle and the bridge's GOCmdContext (docs/architecture.md §2).
#import "GnmPrivate.h"
#include <libintl.h>
#include <locale.h>
#import <GnmCocoa/GnmRunLoopBridge.h>
#include <stdlib.h>
#include <pango/pangocairo.h>

/* ------------------------------------------------------------------------
 * GOCmdContext implementation: a GObject whose interface methods forward to
 * the owning GnmEngine.  This replaces gnm_cmd_context_stderr_new().
 */
typedef struct {
    GObject base;
    void *engine;   /* unretained GnmEngine */
} GnmCocoaCmdContext;
typedef GObjectClass GnmCocoaCmdContextClass;

static GnmEngine *
ccc_engine (GOCmdContext *cc)
{
    GnmCocoaCmdContext *ccc = (GnmCocoaCmdContext *) cc;
    return ccc->engine ? (__bridge GnmEngine *) ccc->engine : nil;
}

static void
ccc_error (GOCmdContext *cc, GError *error)
{
    [ccc_engine (cc) _reportMessage:GnmString (error ? error->message : NULL) details:nil];
}

static void
error_info_details (GOErrorInfo *ei, NSMutableArray<NSString *> *lines, int depth)
{
    for (GSList *l = go_error_info_peek_details (ei); l; l = l->next) {
        GOErrorInfo *d = l->data;
        NSString *indent = [@"" stringByPaddingToLength:(NSUInteger) depth * 2 withString:@" " startingAtIndex:0];
        [lines addObject:[indent stringByAppendingString:GnmString (go_error_info_peek_message (d))]];
        error_info_details (d, lines, depth + 1);
    }
}

static void
ccc_error_info (GOCmdContext *cc, GOErrorInfo *error)
{
    if (error == NULL)
        return;
    NSMutableArray<NSString *> *lines = [NSMutableArray array];
    error_info_details (error, lines, 0);
    [ccc_engine (cc) _reportMessage:GnmString (go_error_info_peek_message (error))
                            details:lines.count ? [lines componentsJoinedByString:@"\n"] : nil];
}

static void
ccc_error_info_list (GOCmdContext *cc, GSList *errors)
{
    for (; errors; errors = errors->next)
        ccc_error_info (cc, errors->data);
}

static char *
ccc_get_password (G_GNUC_UNUSED GOCmdContext *cc, G_GNUC_UNUSED char const *filename)
{
    return NULL;   /* password prompts are a dialog for a later phase */
}

static void
ccc_set_sensitive (G_GNUC_UNUSED GOCmdContext *cc, G_GNUC_UNUSED gboolean sensitive)
{
}

static void
ccc_progress_set (GOCmdContext *cc, double val)
{
    [ccc_engine (cc) _reportProgress:val message:nil];
}

static void
ccc_progress_message_set (GOCmdContext *cc, gchar const *msg)
{
    [ccc_engine (cc) _reportProgress:-1 message:msg ? GnmString (msg) : nil];
}

static void
ccc_cmd_context_init (GOCmdContextClass *cc_class)
{
    cc_class->get_password = ccc_get_password;
    cc_class->set_sensitive = ccc_set_sensitive;
    cc_class->progress_set = ccc_progress_set;
    cc_class->progress_message_set = ccc_progress_message_set;
    cc_class->error.error = ccc_error;
    cc_class->error.error_info = ccc_error_info;
    cc_class->error.error_info_list = ccc_error_info_list;
}

static GType gnm_cocoa_cmd_context_get_type (void);
GSF_CLASS_FULL (GnmCocoaCmdContext, gnm_cocoa_cmd_context,
                NULL, NULL, NULL, NULL, NULL, G_TYPE_OBJECT, 0,
                GSF_INTERFACE (ccc_cmd_context_init, GO_TYPE_CMD_CONTEXT))

/* ------------------------------------------------------------------------ */

@implementation GnmEngineConfiguration

- (instancetype)init
{
    if ((self = [super init])) {
        _programName = @"gnumeric-cocoa";
        _persistsPreferences = NO;
        _extraPluginDirectories = @[];
        _integratesMainRunLoop = YES;
    }
    return self;
}

- (id)copyWithZone:(NSZone *)zone
{
    GnmEngineConfiguration *c = [[GnmEngineConfiguration allocWithZone:zone] init];
    c.programName = self.programName;
    c.persistsPreferences = self.persistsPreferences;
    c.settingsSchemaDirectory = self.settingsSchemaDirectory;
    c.extraPluginDirectories = self.extraPluginDirectories;
    c.libraryDirectory = self.libraryDirectory;
    c.dataDirectory = self.dataDirectory;
    c.localeDirectory = self.localeDirectory;
    c.integratesMainRunLoop = self.integratesMainRunLoop;
    c.xmlCompressionLevel = self.xmlCompressionLevel;
    return c;
}

@end

static GnmEngine *sharedEngine;
static BOOL engineWasStarted;   /* gnm_init cannot be repeated in one process */

@implementation GnmEngine {
    GOCmdContext *_cc;
    NSMutableArray<NSError *> *_collected;   /* nil when not collecting */
    NSUInteger _collectionDepth;             /* commands nest: a paste that inserts an image */
    NSHashTable<GnmWorkbook *> *_workbooks;
    char *_argv0;
    GnmPreferences *_preferences;
}

- (GnmPreferences *)preferences
{
    if (!_preferences)
        _preferences = [[GnmPreferences alloc] initPrivate];
    return _preferences;
}

+ (GnmEngine *)shared
{
    return sharedEngine;
}

+ (GnmEngine *)startWithConfiguration:(GnmEngineConfiguration *)configuration error:(NSError **)error
{
    NSAssert (NSThread.isMainThread, @"GnmEngine must be started on the main thread");
    if (sharedEngine != nil || engineWasStarted) {
        if (error)
            *error = [NSError errorWithDomain:GnmErrorDomain code:GnmErrorEngineAlreadyRunning
                                     userInfo:@{ NSLocalizedDescriptionKey:
                                                     @"The Gnumeric engine can only be started once per process." }];
        return nil;
    }
    GnmEngine *engine = [[GnmEngine alloc] initWithConfiguration:configuration];
    engineWasStarted = YES;
    sharedEngine = engine;
    return engine;
}

- (instancetype)initWithConfiguration:(GnmEngineConfiguration *)configuration
{
    if (!(self = [super init]))
        return nil;
    _configuration = [configuration copy];
    _workbooks = [NSHashTable weakObjectsHashTable];

    if (_configuration.settingsSchemaDirectory.length)
        setenv ("GSETTINGS_SCHEMA_DIR", _configuration.settingsSchemaDirectory.fileSystemRepresentation, 1);
    if (_configuration.libraryDirectory.length)
        setenv ("GNUMERIC_LIBDIR", _configuration.libraryDirectory.fileSystemRepresentation, 1);
    if (_configuration.dataDirectory.length)
        setenv ("GNUMERIC_DATADIR", _configuration.dataDirectory.fileSystemRepresentation, 1);
    if (_configuration.localeDirectory.length)
        setenv ("GNUMERIC_LOCALEDIR", _configuration.localeDirectory.fileSystemRepresentation, 1);
    if (_configuration.extraPluginDirectories.count)
        setenv ("GNUMERIC_PLUGIN_PATH",
                [_configuration.extraPluginDirectories componentsJoinedByString:@":"].UTF8String, 1);

    /* The ssconvert sequence (docs/architecture.md §2).  argv must outlive
     * gnm_pre_parse_init, which keeps argv[0]. */
    _argv0 = strdup (_configuration.programName.UTF8String);
    char const *argv[] = { _argv0, NULL };
    gnm_pre_parse_init (1, argv);
    /* goffice binds its catalogs to its build-time directory; a bundle
     * carries them beside the engine's (scripts/bundle.sh), so rebind. */
    if (_configuration.localeDirectory.length)
        bindtextdomain ("goffice-" GOFFICE_VERSION, _configuration.localeDirectory.fileSystemRepresentation);
    gnm_conf_set_persistence (_configuration.persistsPreferences);
    gnm_init ();
    if (_configuration.xmlCompressionLevel != nil)
        gnm_conf_set_core_xml_compression_level (_configuration.xmlCompressionLevel.intValue);

    _cc = g_object_new (gnm_cocoa_cmd_context_get_type (), NULL);
    ((GnmCocoaCmdContext *) _cc)->engine = (__bridge void *) self;
    gnm_plugins_init (_cc);
    go_component_set_default_command_context (_cc);

    if (_configuration.integratesMainRunLoop)
        [GnmRunLoopBridge attachToMainRunLoop];
    return self;
}

- (void)shutdown
{
    if (sharedEngine != self)
        return;
    /* A workbook released after gnm_shutdown would touch freed engine
     * state, and the engine's own shutdown reports its cells as leaks. */
    NSAssert (_workbooks.count == 0,
              @"GnmEngine shutdown with %lu workbook(s) still alive; release them (and drain "
              @"autorelease pools) first", (unsigned long) _workbooks.count);
    if (_configuration.persistsPreferences) {
        /* What main-application.c's store_plugin_state does; without it the
         * next launch has file states but no active list and loads nothing. */
        GSList *active = go_plugins_get_active_plugins ();
        gnm_conf_set_plugins_active (active);
        g_slist_free (active);
    }
    go_component_set_default_command_context (NULL);
    ((GnmCocoaCmdContext *) _cc)->engine = NULL;
    g_object_unref (_cc);
    _cc = NULL;
    gnm_shutdown ();
    gnm_pre_parse_shutdown ();
    sharedEngine = nil;
}

- (GOCmdContext *)commandContext
{
    return _cc;
}

- (BOOL)isRunning
{
    return _cc != NULL;
}

- (void)_registerWorkbook:(GnmWorkbook *)workbook
{
    [_workbooks addObject:workbook];
}

- (void)_unregisterWorkbook:(GnmWorkbook *)workbook
{
    [_workbooks removeObject:workbook];
}

#pragma mark - Facts

- (NSString *)version
{
    return @GNM_VERSION_FULL;
}

- (NSUInteger)availablePluginCount
{
    return g_slist_length (go_plugins_get_available_plugins ());
}

- (NSString *)resolvedFontFamilyForName:(NSString *)name
{
    NSAssert (NSThread.isMainThread, @"engine access off the main thread");
    PangoFontMap *fm = pango_cairo_font_map_get_default ();
    PangoContext *ctx = pango_font_map_create_context (fm);
    PangoFontDescription *desc = pango_font_description_new ();
    pango_font_description_set_family (desc, name.UTF8String);
    pango_font_description_set_size (desc, 10 * PANGO_SCALE);
    PangoFont *font = pango_font_map_load_font (fm, ctx, desc);
    NSString *result = name;
    if (font) {
        PangoFontDescription *actual = pango_font_describe (font);
        const char *family = actual ? pango_font_description_get_family (actual) : NULL;
        if (family && *family)
            result = GnmString (family);
        if (actual)
            pango_font_description_free (actual);
        g_object_unref (font);
    }
    pango_font_description_free (desc);
    g_object_unref (ctx);
    return result;
}

- (NSUInteger)activePluginCount
{
    return g_slist_length (go_plugins_get_active_plugins ());
}

- (NSString *)libraryDirectory { return GnmString (gnm_sys_lib_dir ()); }
- (NSString *)dataDirectory { return GnmString (gnm_sys_data_dir ()); }
- (NSString *)localeDirectory { return GnmString (gnm_locale_dir ()); }
- (NSString *)messagesLocale { return GnmString (setlocale (LC_MESSAGES, NULL)); }
- (NSString *)localizedString:(NSString *)message
{
    return GnmString (dgettext ("gnumeric-" GNM_VERSION_FULL, message.UTF8String));
}

#pragma mark - Messages

/* Collections nest: a command run from inside another (the paste of an
 * image from the pasteboard inserts an object while the paste command is
 * running) reports into the outer collection and gets none of its own. */
- (void)_beginCollectingMessages
{
    if (_collectionDepth++ == 0)
        _collected = [NSMutableArray array];
}

- (NSArray<NSError *> *)_endCollectingMessages
{
    if (_collectionDepth == 0)
        return @[];
    if (--_collectionDepth > 0)
        return @[];
    NSArray *result = _collected ?: @[];
    _collected = nil;
    return result;
}

- (void)_reportMessage:(NSString *)message details:(NSString *)details
{
    NSMutableDictionary *info = [NSMutableDictionary dictionaryWithObject:message
                                                                   forKey:NSLocalizedDescriptionKey];
    if (details)
        info[NSLocalizedRecoverySuggestionErrorKey] = details;
    NSError *e = [NSError errorWithDomain:GnmErrorDomain code:GnmErrorEngineReported userInfo:info];
    if (_collected)
        [_collected addObject:e];
    else if (self.messageHandler)
        self.messageHandler (e);
    else
        NSLog (@"Gnumeric: %@%@", message, details ? [@"\n" stringByAppendingString:details] : @"");
}

- (void)_reportProgress:(double)fraction message:(NSString *)message
{
    if (self.progressHandler)
        self.progressHandler (fraction, message);
}

- (NSError *)_errorWithCode:(GnmErrorCode)code description:(NSString *)description
             collected:(NSArray<NSError *> *)collected
{
    NSMutableDictionary *info = [NSMutableDictionary dictionary];
    NSMutableArray<NSString *> *lines = [NSMutableArray array];
    for (NSError *e in collected) {
        [lines addObject:e.localizedDescription];
        if (e.localizedRecoverySuggestion)
            [lines addObject:e.localizedRecoverySuggestion];
    }
    info[NSLocalizedDescriptionKey] = description;
    if (lines.count)
        info[NSLocalizedRecoverySuggestionErrorKey] = [lines componentsJoinedByString:@"\n"];
    if (collected.count)
        info[NSUnderlyingErrorKey] = collected.firstObject;
    return [NSError errorWithDomain:GnmErrorDomain code:code userInfo:info];
}

#pragma mark - Workbooks

static char *
uri_for_url (NSURL *url)
{
    if (url.isFileURL)
        return go_shell_arg_to_uri (url.path.fileSystemRepresentation);
    return g_strdup (url.absoluteString.UTF8String);
}

- (GnmWorkbook *)openWorkbookAtURL:(NSURL *)url error:(NSError **)error
{
    NSAssert (NSThread.isMainThread, @"engine access off the main thread");
    GOIOContext *ioc = go_io_context_new (_cc);
    char *uri = uri_for_url (url);

    [self _beginCollectingMessages];
    WorkbookView *wbv = workbook_view_new_from_uri (uri, NULL, ioc, NULL);
    BOOL failed = (wbv == NULL) || go_io_error_occurred (ioc);
    if (failed || go_io_warning_occurred (ioc))
        go_io_error_display (ioc);   /* routes through our command context */
    NSArray<NSError *> *messages = [self _endCollectingMessages];
    g_free (uri);
    g_object_unref (ioc);

    if (failed) {
        if (wbv)
            g_object_unref (wb_view_get_workbook (wbv));
        if (error)
            *error = [self _errorWithCode:GnmErrorOpenFailed
                              description:[NSString stringWithFormat:@"Could not open “%@”.", url.lastPathComponent]
                                collected:messages];
        return nil;
    }
    for (NSError *warning in messages)
        if (self.messageHandler)
            self.messageHandler (warning);

    workbook_recalc (wb_view_get_workbook (wbv));
    return [[GnmWorkbook alloc] initWithWorkbookView:wbv engine:self];
}

- (GnmWorkbook *)newWorkbookWithSheetCount:(NSUInteger)sheetCount
{
    Workbook *wb = workbook_new_with_sheets ((int) MAX (sheetCount, 1u));
    WorkbookView *wbv = workbook_view_new (wb);   /* consumes the workbook reference */
    return [[GnmWorkbook alloc] initWithWorkbookView:wbv engine:self];
}

- (NSString *)saverIdentifierForFileName:(NSString *)fileName
{
    GOFileSaver *fs = go_file_saver_for_file_name (fileName.UTF8String);
    return fs ? GnmString (go_file_saver_get_id (fs)) : nil;
}

- (void)dealloc
{
    free (_argv0);
}

@end
