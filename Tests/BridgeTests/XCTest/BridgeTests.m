// XCTest wrapper around the headless bridge programs.  Each program owns a
// process because the engine can be started only once per process
// (GnmEngine.h), so the test bundle launches the tool targets XcodeGen builds
// next to it and fails on a non-zero exit or an engine warning, exactly as
// Tests/BridgeTests/run.sh does.
#import <XCTest/XCTest.h>

@interface BridgeTests : XCTestCase
@end

@implementation BridgeTests

/// The repository root, from the scheme's environment or from this file's
/// compiled-in path (Tests/BridgeTests/XCTest/BridgeTests.m).
+ (NSString *)repositoryRoot
{
    NSString *env = NSProcessInfo.processInfo.environment[@"GNM_REPO_ROOT"];
    if (env.length)
        return env;
    NSString *file = @__FILE__;
    return [[[file stringByDeletingLastPathComponent] stringByDeletingLastPathComponent]
            stringByDeletingLastPathComponent].stringByDeletingLastPathComponent;
}

- (void)runProgram:(NSString *)name
{
    NSString *root = [self.class repositoryRoot];
    NSDictionary<NSString *, NSString *> *env = NSProcessInfo.processInfo.environment;
    NSString *prefix = env[@"GNM_PREFIX"];
    if (prefix.length == 0)
        prefix = [root stringByAppendingPathComponent:@"build/prefix"];
    NSString *schemas = [prefix stringByAppendingPathComponent:@"share/glib-2.0/schemas"];
    if (![NSFileManager.defaultManager fileExistsAtPath:[schemas stringByAppendingPathComponent:@"gschemas.compiled"]])
        schemas = @"/opt/homebrew/share/glib-2.0/schemas";
    NSString *outDir = [root stringByAppendingPathComponent:@"build/bridge-tests-xcode"];
    [NSFileManager.defaultManager createDirectoryAtPath:outDir withIntermediateDirectories:YES attributes:nil error:NULL];

    /* The tool targets land in the same products directory as this bundle. */
    NSURL *products = [[NSBundle bundleForClass:self.class].bundleURL URLByDeletingLastPathComponent];
    NSURL *program = [products URLByAppendingPathComponent:name];
    XCTAssertTrue([NSFileManager.defaultManager isExecutableFileAtPath:program.path],
                  @"%@ not built next to the test bundle (%@)", name, products.path);

    NSTask *task = [[NSTask alloc] init];
    task.executableURL = program;
    task.currentDirectoryURL = [NSURL fileURLWithPath:outDir];
    NSMutableDictionary *taskEnv = [env mutableCopy];
    taskEnv[@"GNM_TEST_SCHEMA_DIR"] = schemas;
    taskEnv[@"GNM_TEST_SAMPLES"] = [root stringByAppendingPathComponent:@"upstream/gnumeric/samples"];
    taskEnv[@"GNM_TEST_OUT"] = outDir;
    task.environment = taskEnv;
    NSPipe *pipe = [NSPipe pipe];
    task.standardOutput = pipe;
    task.standardError = pipe;

    NSError *error = nil;
    XCTAssertTrue([task launchAndReturnError:&error], @"launch %@: %@", name, error);
    NSData *data = [pipe.fileHandleForReading readDataToEndOfFile];
    [task waitUntilExit];
    NSString *output = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";

    XCTAttachment *attachment = [XCTAttachment attachmentWithString:output];
    attachment.name = [name stringByAppendingString:@" output"];
    [self addAttachment:attachment];

    XCTAssertEqual(task.terminationStatus, 0, @"%@ failed:\n%@", name, output);
    NSRegularExpression *warnings = [NSRegularExpression regularExpressionWithPattern:@"unknown type|CRITICAL|Unable to|failed to"
                                                                              options:0 error:NULL];
    NSTextCheckingResult *hit = [warnings firstMatchInString:output options:0 range:NSMakeRange(0, output.length)];
    XCTAssertNil(hit, @"%@ logged an engine warning:\n%@", name, output);
}

- (void)testEngineLifecycle { [self runProgram:@"engine_lifecycle"]; }
- (void)testWorkbookIO { [self runProgram:@"workbook_io"]; }
- (void)testRender { [self runProgram:@"render"]; }
- (void)testRunLoop { [self runProgram:@"runloop"]; }
- (void)testEditing { [self runProgram:@"editing"]; }
- (void)testFormat { [self runProgram:@"format"]; }
- (void)testObjects { [self runProgram:@"objects"]; }
- (void)testChart { [self runProgram:@"chart"]; }
- (void)testSearch { [self runProgram:@"search"]; }
- (void)testPreferences { [self runProgram:@"preferences"]; }

@end
