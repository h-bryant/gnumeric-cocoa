// The plugin manager: the list, activation and deactivation, marks, the
// preference, the directories, and a rescan.
#import "GnmTest.h"

int main (void)
{
    @autoreleasepool {
        GnmEngine *engine = gnm_test_start_engine (NO);
        NSMutableArray<NSError *> *stray = [NSMutableArray array];
        engine.messageHandler = ^(NSError *e) { [stray addObject:e]; };
      @autoreleasepool {
        NSError *error = nil;
        NSArray<GnmPlugin *> *plugins = engine.availablePlugins;
        NSLog (@"plugins: %lu available, %lu active", (unsigned long) plugins.count, (unsigned long) engine.activePluginCount);
        GNM_ASSERT (plugins.count == engine.availablePluginCount && plugins.count > 20, @"the list: %lu", (unsigned long) plugins.count);
        /* collated (g_utf8_collate ignores punctuation and case at the first
         * level): compare the letters and digits alone */
        NSArray *names = [plugins valueForKey:@"name"];
        NSCharacterSet *noise = NSCharacterSet.alphanumericCharacterSet.invertedSet;
        NSArray *keys = [names valueForKey:@"lowercaseString"];
        NSMutableArray *stripped = [NSMutableArray array];
        for (NSString *key in keys)
            [stripped addObject:[[key componentsSeparatedByCharactersInSet:noise] componentsJoinedByString:@""]];
        NSArray *sorted = [stripped sortedArrayUsingSelector:@selector (compare:)];
        BOOL collated = [stripped isEqualToArray:sorted];
        GNM_ASSERT (collated, @"by name: %@", names);
        GnmPlugin *tsa = [engine pluginWithIdentifier:@"Gnumeric_fnTimeSeriesAnalysis"];
        GNM_ASSERT (tsa != nil && [tsa.name length] > 0 && [tsa.summary length] > 0 && [tsa.directory hasSuffix:@"fn-tsa"], @"the TSA plugin: %@ '%@' '%@' '%@'", tsa, tsa.name, tsa.summary, tsa.directory);
        GNM_ASSERT ([plugins containsObject:tsa], @"listed");
        GNM_ASSERT ([engine pluginWithIdentifier:@"No_Such_Plugin"] == nil, @"unknown identifier");
        GNM_ASSERT (tsa.serviceDescriptions.count > 0, @"services: %@", tsa.serviceDescriptions);
        NSLog (@"plugins: TSA services %@ dependencies %@", tsa.serviceDescriptions, tsa.dependencyIdentifiers);
        if (tsa.isActive)
            GNM_ASSERT ([engine deactivatePlugin:tsa error:&error], @"deactivate to start: %@", error);
        GNM_ASSERT (!tsa.isActive, @"inactive to start");
        NSUInteger activeBefore = engine.activePluginCount;
        GNM_ASSERT ([engine inactiveDependencyNamesOfPlugin:tsa].count == 0, @"no inactive dependencies: %@", [engine inactiveDependencyNamesOfPlugin:tsa]);
        GNM_ASSERT ([engine activatePlugin:tsa error:&error] && tsa.isActive, @"activate: %@", error);
        GNM_ASSERT (engine.activePluginCount == activeBefore + 1, @"one more active");
        GNM_ASSERT ([engine activatePlugin:tsa error:&error], @"activating again is nothing");
        NSLog (@"plugins: TSA can deactivate: %d", tsa.canDeactivate);
        if (tsa.canDeactivate) {
            GNM_ASSERT ([engine deactivatePlugin:tsa error:&error] && !tsa.isActive, @"deactivate: %@", error);
            GNM_ASSERT (engine.activePluginCount == activeBefore, @"back to %lu active", (unsigned long) activeBefore);
            GNM_ASSERT ([engine activatePlugin:tsa error:&error], @"active again: %@", error);
        }
        GNM_ASSERT (!tsa.isMarkedForDeactivation, @"not marked");
        [engine setPlugin:tsa markedForDeactivation:YES];
        GNM_ASSERT (tsa.isMarkedForDeactivation, @"marked");
        [engine setPlugin:tsa markedForDeactivation:NO];
        GNM_ASSERT (!tsa.isMarkedForDeactivation, @"unmarked");

        /* the preference and the directories */
        BOOL newPlugins = engine.activatesNewPlugins;
        engine.activatesNewPlugins = !newPlugins;
        GNM_ASSERT (engine.activatesNewPlugins == !newPlugins, @"the preference flips");
        engine.activatesNewPlugins = newPlugins;
        NSLog (@"plugins: system directories %@ extra %@", engine.systemPluginDirectories, engine.extraPluginDirectories);
        BOOL inSystem = [tsa.directory hasPrefix:engine.systemPluginDirectories.firstObject];
        GNM_ASSERT (inSystem && engine.systemPluginDirectories.count >= 2, @"the engine's directory holds TSA: %@", engine.systemPluginDirectories);
        NSArray *extraBefore = engine.extraPluginDirectories;
        NSArray *extraSet = @[@"/tmp/no-plugins-here", @"/tmp/none-either"];
        engine.extraPluginDirectories = extraSet;
        BOOL extraKept = [engine.extraPluginDirectories isEqualToArray:extraSet];
        GNM_ASSERT (extraKept, @"extra directories kept in order: %@", engine.extraPluginDirectories);
        engine.extraPluginDirectories = extraBefore;
        GNM_ASSERT ([engine.extraPluginDirectories isEqualToArray:extraBefore], @"restored: %@", engine.extraPluginDirectories);

        /* a rescan finds nothing new */
        NSArray *found = [engine rescanPluginsWithError:&error];
        GNM_ASSERT (found != nil && found.count == 0, @"rescan: %@ %@", found, error);
        GNM_ASSERT (engine.availablePlugins.count == plugins.count, @"still %lu plugins", (unsigned long) plugins.count);

        /* Activate All activates the rest, unless one fails to load */
        BOOL all = [engine activateAllPluginsWithError:&error];
        NSLog (@"plugins: activate all -> %d (%@); %lu active", all, error.localizedDescription, (unsigned long) engine.activePluginCount);
        GNM_ASSERT (engine.activePluginCount >= activeBefore + 1, @"no fewer active after Activate All");

        GNM_ASSERT (stray.count == 0, @"stray messages: %@", stray);
      }
        [engine shutdown];
        return gnm_test_finish ("plugins");
    }
}
