#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Domain of every NSError the bridge produces.  Errors the engine reports
/// through its command context carry the engine's own message text in
/// NSLocalizedDescriptionKey and any detail lines in
/// NSLocalizedRecoverySuggestionErrorKey.
FOUNDATION_EXPORT NSErrorDomain const GnmErrorDomain;

typedef NS_ERROR_ENUM(GnmErrorDomain, GnmErrorCode) {
    GnmErrorEngineNotRunning = 1,
    GnmErrorEngineAlreadyRunning = 2,
    GnmErrorOpenFailed = 3,
    GnmErrorSaveFailed = 4,
    GnmErrorUnknownFormat = 5,
    GnmErrorEngineReported = 6,
    /// An engine command refused or failed; the engine's own messages are in
    /// the recovery suggestion and the underlying error.
    GnmErrorCommandFailed = 7,
};

NS_ASSUME_NONNULL_END
