// The plugin manager over goffice's plugin database, as
// dialog-plugin-manager.c drives it.
#import "GnmPrivate.h"
#include <gnumeric-conf.h>
#include <gutils.h>
#include <goffice/goffice.h>
#include <goffice/app/go-plugin.h>
#include <goffice/app/go-plugin-service.h>

@interface GnmPlugin ()
- (instancetype)initWithPlugin:(GOPlugin *)plugin NS_DESIGNATED_INITIALIZER;
@property (nonatomic, readonly) GOPlugin *enginePlugin;
@end

@implementation GnmPlugin {
    GOPlugin *_plugin;
}

- (instancetype)initWithPlugin:(GOPlugin *)plugin
{
    if (!(self = [super init]))
        return nil;
    _plugin = g_object_ref (plugin);
    return self;
}

- (void)dealloc
{
    if (_plugin)
        g_object_unref (_plugin);
}

- (GOPlugin *)enginePlugin { return _plugin; }
- (NSString *)identifier { return GnmString (go_plugin_get_id (_plugin)); }
- (NSString *)name { return GnmString (go_plugin_get_name (_plugin)); }
- (NSString *)summary { return GnmString (go_plugin_get_description (_plugin)); }
- (NSString *)directory { return GnmString (go_plugin_get_dir_name (_plugin)); }
- (BOOL)isActive { return go_plugin_is_active (_plugin); }
- (BOOL)canDeactivate { return go_plugin_can_deactivate (_plugin); }
- (BOOL)isMarkedForDeactivation { return go_plugin_db_is_plugin_marked_for_deactivation (_plugin); }

- (NSArray<NSString *> *)dependencyIdentifiers
{
    NSMutableArray *result = [NSMutableArray array];
    GSList *ids = go_plugin_get_dependencies_ids (_plugin);
    for (GSList *l = ids; l; l = l->next)
        [result addObject:GnmString (l->data)];
    g_slist_free_full (ids, g_free);
    return result;
}

- (NSArray<NSString *> *)serviceDescriptions
{
    NSMutableArray *result = [NSMutableArray array];
    for (GSList *l = go_plugin_get_services (_plugin); l; l = l->next) {
        GOPluginService *service = l->data;
        [result addObject:[NSString stringWithFormat:@"%@ (%@)", GnmString (go_plugin_service_get_description (service)),
                           GnmString (go_plugin_service_get_id (service))]];
    }
    return result;
}

- (BOOL)isEqual:(id)other
{
    return [other isKindOfClass:GnmPlugin.class] && ((GnmPlugin *) other)->_plugin == _plugin;
}

- (NSUInteger)hash { return (NSUInteger) _plugin; }

- (NSString *)description
{
    return [NSString stringWithFormat:@"<%@ %@ %@>", self.class, self.identifier, self.isActive ? @"active" : @"inactive"];
}

@end

static void
collect_error_info (GOErrorInfo *info, NSMutableArray<NSString *> *lines, int depth)
{
    for (GSList *l = go_error_info_peek_details (info); l; l = l->next) {
        GOErrorInfo *detail = l->data;
        NSString *indent = [@"" stringByPaddingToLength:(NSUInteger) depth * 2 withString:@" " startingAtIndex:0];
        [lines addObject:[indent stringByAppendingString:GnmString (go_error_info_peek_message (detail))]];
        collect_error_info (detail, lines, depth + 1);
    }
}

/* An NSError from a GOErrorInfo (freed here) under the dialog's heading. */
static BOOL
fail_with_error_info (GnmEngine *engine, GOErrorInfo *info, NSString *heading, NSError **error)
{
    NSMutableArray<NSString *> *lines = [NSMutableArray array];
    const char *message = go_error_info_peek_message (info);
    if (message && *message)
        [lines addObject:GnmString (message)];
    collect_error_info (info, lines, lines.count ? 1 : 0);
    go_error_info_free (info);
    if (error) {
        NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
        userInfo[NSLocalizedDescriptionKey] = heading;
        if (lines.count)
            userInfo[NSLocalizedRecoverySuggestionErrorKey] = [lines componentsJoinedByString:@"\n"];
        *error = [NSError errorWithDomain:GnmErrorDomain code:GnmErrorCommandFailed userInfo:userInfo];
    }
    return NO;
}

static gint
plugin_name_cmp (gconstpointer a, gconstpointer b)
{
    return g_utf8_collate (go_plugin_get_name ((GOPlugin *) a), go_plugin_get_name ((GOPlugin *) b));
}

@implementation GnmEngine (Plugins)

- (NSArray<GnmPlugin *> *)availablePlugins
{
    NSAssert (NSThread.isMainThread, @"engine access off the main thread");
    GSList *sorted = g_slist_sort (g_slist_copy (go_plugins_get_available_plugins ()), plugin_name_cmp);
    NSMutableArray *result = [NSMutableArray array];
    for (GSList *l = sorted; l; l = l->next)
        [result addObject:[[GnmPlugin alloc] initWithPlugin:l->data]];
    g_slist_free (sorted);
    return result;
}

- (GnmPlugin *)pluginWithIdentifier:(NSString *)identifier
{
    NSAssert (NSThread.isMainThread, @"engine access off the main thread");
    GOPlugin *plugin = go_plugins_get_plugin_by_id (identifier.UTF8String);
    return plugin ? [[GnmPlugin alloc] initWithPlugin:plugin] : nil;
}

- (NSArray<NSString *> *)inactiveDependencyNamesOfPlugin:(GnmPlugin *)plugin
{
    NSAssert (NSThread.isMainThread, @"engine access off the main thread");
    NSMutableArray *names = [NSMutableArray array];
    for (NSString *identifier in plugin.dependencyIdentifiers) {
        GOPlugin *dependency = go_plugins_get_plugin_by_id (identifier.UTF8String);
        if (!dependency)
            [names addObject:[NSString stringWithFormat:@"Unknown plugin with id=\"%@\"", identifier]];
        else if (!go_plugin_is_active (dependency))
            [names addObject:GnmString (go_plugin_get_name (dependency))];
    }
    return names;
}

- (BOOL)activatePlugin:(GnmPlugin *)plugin error:(NSError **)error
{
    NSAssert (NSThread.isMainThread, @"engine access off the main thread");
    if (plugin.isActive)
        return YES;
    GOErrorInfo *info = NULL;
    go_plugin_activate (plugin.enginePlugin, &info);
    if (info)
        return fail_with_error_info (self, info, [NSString stringWithFormat:@"Error while activating plugin “%@”.", plugin.name], error);
    return YES;
}

- (BOOL)deactivatePlugin:(GnmPlugin *)plugin error:(NSError **)error
{
    NSAssert (NSThread.isMainThread, @"engine access off the main thread");
    if (!plugin.isActive)
        return YES;
    GOErrorInfo *info = NULL;
    go_plugin_deactivate (plugin.enginePlugin, &info);
    if (info)
        return fail_with_error_info (self, info, [NSString stringWithFormat:@"Error while deactivating plugin “%@”.", plugin.name], error);
    if (plugin.isActive) {
        if (error)
            *error = [self _errorWithCode:GnmErrorCommandFailed
                             description:[NSString stringWithFormat:@"The plugin “%@” cannot be deactivated while it is in use.", plugin.name]
                               collected:@[]];
        return NO;
    }
    return YES;
}

- (void)setPlugin:(GnmPlugin *)plugin markedForDeactivation:(BOOL)marked
{
    NSAssert (NSThread.isMainThread, @"engine access off the main thread");
    go_plugin_db_mark_plugin_for_deactivation (plugin.enginePlugin, marked ? TRUE : FALSE);
}

- (BOOL)activateAllPluginsWithError:(NSError **)error
{
    NSAssert (NSThread.isMainThread, @"engine access off the main thread");
    GOErrorInfo *info = NULL;
    go_plugin_db_activate_plugin_list (go_plugins_get_available_plugins (), &info);
    if (info)
        return fail_with_error_info (self, info, @"Errors while activating plugins", error);
    return YES;
}

- (BOOL)activatesNewPlugins { return gnm_conf_get_plugins_activate_newplugins (); }
- (void)setActivatesNewPlugins:(BOOL)activates { gnm_conf_set_plugins_activate_newplugins (activates ? TRUE : FALSE); }

- (NSArray<NSString *> *)systemPluginDirectories
{
    /* pm_gui_load_directory_page */
    NSMutableArray *result = [NSMutableArray array];
    char *sys = g_build_filename (gnm_sys_lib_dir (), "plugins", NULL);
    [result addObject:GnmString (sys)];
    g_free (sys);
    if (gnm_usr_dir (TRUE)) {
        char *usr = g_build_filename (gnm_usr_dir (TRUE), "plugins", NULL);
        [result addObject:GnmString (usr)];
        g_free (usr);
    }
    char *go = go_plugins_get_plugin_dir ();
    [result addObject:GnmString (go)];
    g_free (go);
    const char *path = g_getenv ("GNUMERIC_PLUGIN_PATH");
    if (path && *path) {
        for (NSString *dir in [GnmString (path) componentsSeparatedByString:@":"])
            if (dir.length)
                [result addObject:dir];
    }
    return result;
}

- (NSArray<NSString *> *)extraPluginDirectories
{
    NSMutableArray *result = [NSMutableArray array];
    for (GSList *l = gnm_conf_get_plugins_extra_dirs (); l; l = l->next)
        [result addObject:GnmString (l->data)];
    return result;
}

- (void)setExtraPluginDirectories:(NSArray<NSString *> *)directories
{
    GSList *list = NULL;
    for (NSString *dir in directories.reverseObjectEnumerator)
        list = g_slist_prepend (list, g_strdup (dir.UTF8String));
    gnm_conf_set_plugins_extra_dirs (list);   /* takes the list */
}

- (NSArray<GnmPlugin *> *)rescanPluginsWithError:(NSError **)error
{
    NSAssert (NSThread.isMainThread, @"engine access off the main thread");
    GOErrorInfo *info = NULL;
    GSList *added = NULL;
    go_plugins_rescan (&info, &added);
    NSMutableArray *result = [NSMutableArray array];
    for (GSList *l = added; l; l = l->next)
        [result addObject:[[GnmPlugin alloc] initWithPlugin:l->data]];
    g_slist_free (added);
    if (info) {
        fail_with_error_info (self, info, @"Errors while reading info about available plugins.", error);
        return nil;
    }
    return result;
}

@end
