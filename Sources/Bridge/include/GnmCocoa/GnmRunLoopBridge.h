// Runs the default GLib main context from the main thread's CFRunLoop so the
// engine's idles, timeouts, and GIO completions fire while AppKit owns the
// loop.  Modeled on the "CFRunLoop is in control" half of GTK's
// gdk/quartz/gdkeventloop-quartz.c (HANDOFF.md §4, Phase 1).
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

NS_SWIFT_UI_ACTOR NS_SWIFT_NAME(RunLoopBridge)
@interface GnmRunLoopBridge : NSObject

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

/// Idempotent.  Must be called on the main thread; the bridge stays attached
/// for the life of the process (GLib's main context cannot be handed back
/// cleanly once sources are attached).
+ (void)attachToMainRunLoop;
@property (class, nonatomic, readonly, getter=isAttached) BOOL attached;

/// Dispatch everything that is ready right now without waiting.  Tests use it;
/// the app never needs to.
+ (void)dispatchPendingWork;

@end

NS_ASSUME_NONNULL_END
