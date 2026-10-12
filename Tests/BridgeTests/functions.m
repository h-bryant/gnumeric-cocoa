// The function catalog: groups by name, SUM in Mathematics with its
// summary, arguments, and counts, a variadic maximum, a lookup by name
// in either case, and nothing for an unknown name.
#import "GnmTest.h"

int main (void)
{
    @autoreleasepool {
        GnmEngine *engine = gnm_test_start_engine (NO);
        NSMutableArray<NSError *> *stray = [NSMutableArray array];
        engine.messageHandler = ^(NSError *e) { [stray addObject:e]; };
      @autoreleasepool {
        NSArray<GnmFunctionGroup *> *groups = engine.functionGroups;
        NSMutableArray *names = [NSMutableArray array];
        NSInteger total = 0;
        for (GnmFunctionGroup *g in groups) {
            [names addObject:[NSString stringWithFormat:@"%@ (%lu)", g.name, (unsigned long) g.functions.count]];
            total += g.functions.count;
        }
        NSLog (@"functions: %lu groups, %ld functions: %@", (unsigned long) groups.count, (long) total, [names componentsJoinedByString:@", "]);
        GNM_ASSERT (groups.count >= 10 && total > 300, @"a full catalog");
        GnmFunctionGroup *math = nil;
        for (GnmFunctionGroup *g in groups)
            if ([g.name isEqualToString:@"Mathematics"])
                math = g;
        GNM_ASSERT (math != nil, @"Mathematics group");
        GnmFunctionInfo *sum = nil;
        for (GnmFunctionInfo *f in math.functions)
            if ([f.name isEqualToString:@"SUM"])
                sum = f;
        GNM_ASSERT (sum != nil, @"SUM in Mathematics");
        NSLog (@"functions: SUM '%@' args %@ / %@ min %ld max %ld examples %@ description '%@'", sum.summary, sum.argumentNames, sum.argumentDescriptions,
               (long) sum.minimumArguments, (long) sum.maximumArguments, sum.examples, sum.descriptionText);
        GNM_ASSERT (sum.summary.length > 3 && sum.argumentNames.count >= 1 && sum.maximumArguments == -1, @"SUM's help");
        GNM_ASSERT_EQ_STR (sum.groupName, @"Mathematics");
        GnmFunctionInfo *vlookup = [engine functionNamed:@"vlookup"];
        GNM_ASSERT (vlookup && [vlookup.name isEqualToString:@"VLOOKUP"] && vlookup.minimumArguments == 3 && vlookup.argumentNames.count >= 3,
                    @"VLOOKUP by name in lower case: %@ %ld", vlookup.name, (long) vlookup.minimumArguments);
        GNM_ASSERT ([engine functionNamed:@"NOSUCHFUNCTION"] == nil, @"unknown");
        GNM_ASSERT ([engine functionNamed:@""] == nil, @"empty");
        GnmFunctionInfo *pi = [engine functionNamed:@"PI"];
        GNM_ASSERT (pi && pi.minimumArguments == 0 && pi.maximumArguments == 0, @"PI takes none: %ld %ld", (long) pi.minimumArguments, (long) pi.maximumArguments);
        GNM_ASSERT (stray.count == 0, @"stray messages: %@", stray);
      }
        [engine shutdown];
        return gnm_test_finish ("functions");
    }
}
