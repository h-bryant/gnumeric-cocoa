// Minimal assertions for the bridge tests.  These are plain programs because
// XCTest ships with Xcode.app, which is not installed yet (HANDOFF.md §8);
// each file is written so it can move into an XCTestCase method unchanged.
#import <Foundation/Foundation.h>
#import <GnmCocoa/GnmCocoa.h>

static int gnm_test_failures;

#define GNM_ASSERT(cond, ...) do { \
    if (!(cond)) { \
        gnm_test_failures++; \
        NSLog (@"FAIL %s:%d: %s: %@", __FILE__, __LINE__, #cond, [NSString stringWithFormat:__VA_ARGS__]); \
    } \
} while (0)

#define GNM_ASSERT_EQ_STR(a, b) GNM_ASSERT ([(a) isEqualToString:(b)], @"'%@' != '%@'", (a), (b))

static inline NSString *gnm_test_env (const char *name) {
    const char *v = getenv (name);
    if (!v) { fprintf (stderr, "missing environment variable %s (run via run.sh)\n", name); exit (2); }
    return [NSString stringWithUTF8String:v];
}

static inline GnmEngineConfiguration *gnm_test_configuration (BOOL runLoop) {
    GnmEngineConfiguration *cfg = [[GnmEngineConfiguration alloc] init];
    cfg.programName = @"gnm-bridge-test";
    cfg.persistsPreferences = NO;                     /* docs/architecture.md §2 trap */
    cfg.settingsSchemaDirectory = gnm_test_env ("GNM_TEST_SCHEMA_DIR");
    cfg.integratesMainRunLoop = runLoop;
    return cfg;
}

static inline GnmEngine *gnm_test_start_engine_with (GnmEngineConfiguration *cfg) {
    NSError *error = nil;
    GnmEngine *engine = [GnmEngine startWithConfiguration:cfg error:&error];
    if (!engine) { NSLog (@"engine start failed: %@", error); exit (1); }
    return engine;
}

static inline GnmEngine *gnm_test_start_engine (BOOL runLoop) {
    return gnm_test_start_engine_with (gnm_test_configuration (runLoop));
}

static inline int gnm_test_finish (const char *name) {
    if (gnm_test_failures) {
        fprintf (stderr, "%s: %d failure(s)\n", name, gnm_test_failures);
        return 1;
    }
    printf ("%s: ok\n", name);
    return 0;
}
