// Engine lifecycle: the ssconvert startup and shutdown sequence
// (docs/architecture.md §2) wrapped in one main-thread singleton.
#import <Foundation/Foundation.h>
#import <GnmCocoa/GnmError.h>

NS_ASSUME_NONNULL_BEGIN

@class GnmWorkbook;

/// What `GnmEngine.start` needs to know before `gnm_init()`.
NS_SWIFT_UI_ACTOR NS_SWIFT_NAME(EngineConfiguration)
@interface GnmEngineConfiguration : NSObject <NSCopying>

/// Used as argv[0].  For a bare executable it is also the NSUserDefaults
/// domain GSettings writes to (docs/architecture.md §2), so tests must keep
/// `persistsPreferences` off.
@property (nonatomic, copy) NSString *programName;

/// `gnm_conf_set_persistence`.  Default NO.  When YES, `shutdown` also stores
/// the active plugin list the way the GTK app does, so later launches still
/// load plugins.
@property (nonatomic) BOOL persistsPreferences;

/// Directory holding `gschemas.compiled`; exported as GSETTINGS_SCHEMA_DIR
/// before `gnm_init()`.  Nil leaves GIO's default search path alone.
@property (nonatomic, copy, nullable) NSString *settingsSchemaDirectory;

/// Extra plugin directories, exported as GNUMERIC_PLUGIN_PATH.
@property (nonatomic, copy) NSArray<NSString *> *extraPluginDirectories;

/// Attach `GnmRunLoopBridge` to the main run loop at start.  Default YES.
@property (nonatomic) BOOL integratesMainRunLoop;

@end

/// Engine-reported messages that are not tied to a specific bridge call
/// (for example warnings while a plugin loads).
typedef void (^GnmEngineMessageHandler)(NSError *error) NS_SWIFT_NAME(Engine.MessageHandler);
typedef void (^GnmEngineProgressHandler)(double fraction, NSString *_Nullable message) NS_SWIFT_NAME(Engine.ProgressHandler);

NS_SWIFT_UI_ACTOR NS_SWIFT_NAME(Engine)
@interface GnmEngine : NSObject

/// The running engine, or nil before `start` and after `shutdown`.
@property (class, nonatomic, readonly, nullable) GnmEngine *shared;

/// Runs `gnm_pre_parse_init`, `gnm_init`, plugin loading, and installs the
/// command context.  Fails if an engine is already running.  The engine can be
/// started once per process; `shutdown` is final.
+ (nullable GnmEngine *)startWithConfiguration:(GnmEngineConfiguration *)configuration
                                         error:(NSError **)error;

/// `gnm_shutdown` and `gnm_pre_parse_shutdown`.  Every GnmWorkbook must have
/// been released first.
- (void)shutdown;

@property (nonatomic, readonly, copy) GnmEngineConfiguration *configuration;
@property (nonatomic, readonly, copy) NSString *version;
@property (nonatomic, readonly) NSUInteger availablePluginCount;
@property (nonatomic, readonly) NSUInteger activePluginCount;
@property (nonatomic, readonly, copy) NSString *libraryDirectory;
@property (nonatomic, readonly, copy) NSString *dataDirectory;
@property (nonatomic, readonly, copy) NSString *localeDirectory;

@property (nonatomic, copy, nullable) GnmEngineMessageHandler messageHandler;
@property (nonatomic, copy, nullable) GnmEngineProgressHandler progressHandler;

/// Opens any format the loaded file openers understand, recalculates, and
/// returns a workbook with one attached Cocoa control.
- (nullable GnmWorkbook *)openWorkbookAtURL:(NSURL *)url error:(NSError **)error;

/// A new empty workbook with `sheetCount` sheets of the default size.
- (GnmWorkbook *)newWorkbookWithSheetCount:(NSUInteger)sheetCount;

/// Identifiers of the file savers that can write the given file name, in the
/// order goffice would choose them (first is the default).
- (nullable NSString *)saverIdentifierForFileName:(NSString *)fileName;

@end

NS_ASSUME_NONNULL_END
