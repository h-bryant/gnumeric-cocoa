// The plugin manager (dialog-plugin-manager.c): goffice's plugins, each
// one activated or deactivated on its own, all at once, marked for
// deactivation at the next start when it cannot go now, the directories
// searched, and a rescan.
#import <Foundation/Foundation.h>
#import <GnmCocoa/GnmEngine.h>

NS_ASSUME_NONNULL_BEGIN

NS_SWIFT_UI_ACTOR NS_SWIFT_NAME(Plugin)
@interface GnmPlugin : NSObject
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
/// "Gnumeric_fnTimeSeriesAnalysis".
@property (nonatomic, readonly, copy) NSString *identifier;
@property (nonatomic, readonly, copy) NSString *name;
/// The plugin's description.
@property (nonatomic, readonly, copy) NSString *summary;
@property (nonatomic, readonly, copy) NSString *directory;
@property (nonatomic, readonly, getter=isActive) BOOL active;
/// Whether it can be deactivated now (not while something uses it).
@property (nonatomic, readonly) BOOL canDeactivate;
/// Marked to stay inactive at the next start (`setPlugin:markedFor
/// Deactivation:`); the GTK's way out for one that cannot go now.
@property (nonatomic, readonly, getter=isMarkedForDeactivation) BOOL markedForDeactivation;
/// Identifiers of the plugins it needs.
@property (nonatomic, readonly, copy) NSArray<NSString *> *dependencyIdentifiers;
/// Its services, "description (identifier)" each.
@property (nonatomic, readonly, copy) NSArray<NSString *> *serviceDescriptions;
@end

@interface GnmEngine (Plugins)
/// Every plugin found, by name.
@property (nonatomic, readonly, copy) NSArray<GnmPlugin *> *availablePlugins;
- (nullable GnmPlugin *)pluginWithIdentifier:(NSString *)identifier NS_SWIFT_NAME(plugin(withIdentifier:));
/// Names of the plugin's dependencies that are inactive (the GTK asks
/// before activating them along).
- (NSArray<NSString *> *)inactiveDependencyNamesOfPlugin:(GnmPlugin *)plugin NS_SWIFT_NAME(inactiveDependencyNames(of:));
/// `go_plugin_activate` (its dependencies too); NO with the engine's
/// message and details.
- (BOOL)activatePlugin:(GnmPlugin *)plugin error:(NSError **)error NS_SWIFT_NAME(activate(_:));
/// `go_plugin_deactivate`; NO with the message when it cannot go.
- (BOOL)deactivatePlugin:(GnmPlugin *)plugin error:(NSError **)error NS_SWIFT_NAME(deactivate(_:));
- (void)setPlugin:(GnmPlugin *)plugin markedForDeactivation:(BOOL)marked NS_SWIFT_NAME(setPlugin(_:markedForDeactivation:));
/// The dialog's Activate All (`go_plugin_db_activate_plugin_list`).
- (BOOL)activateAllPluginsWithError:(NSError **)error NS_SWIFT_NAME(activateAllPlugins());
/// The preference: new plugins found at a start are activated.
@property (nonatomic) BOOL activatesNewPlugins;
/// The directories always searched (the GTK dialog's system rows): the
/// engine's own plugins, the user's, goffice's, and any on
/// `GNUMERIC_PLUGIN_PATH`.
@property (nonatomic, readonly, copy) NSArray<NSString *> *systemPluginDirectories;
/// Further directories searched at the next start (the preference).
@property (nonatomic, copy) NSArray<NSString *> *extraPluginDirectories;
/// Look for plugins again now (`go_plugins_rescan`): the new ones, or
/// nil with the message when the scan failed.
- (nullable NSArray<GnmPlugin *> *)rescanPluginsWithError:(NSError **)error NS_SWIFT_NAME(rescanPlugins());
@end

NS_ASSUME_NONNULL_END
