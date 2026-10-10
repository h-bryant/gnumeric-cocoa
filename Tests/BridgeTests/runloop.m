// GLib sources must fire from the Cocoa run loop: idles, timeouts (on time),
// GIO completions from worker threads, and wake-ups from other threads.
#import "GnmTest.h"
#include <glib.h>
#include <gio/gio.h>

static NSMutableArray<NSString *> *events;
static BOOL on_main (void) { return NSThread.isMainThread; }

static gboolean idle_cb (gpointer data)
{
    [events addObject:[NSString stringWithFormat:@"idle main=%d", on_main ()]];
    return G_SOURCE_REMOVE;
}

static CFAbsoluteTime t_timeout_start;
static gboolean timeout_cb (gpointer data)
{
    double ms = (CFAbsoluteTimeGetCurrent () - t_timeout_start) * 1000;
    [events addObject:[NSString stringWithFormat:@"timeout main=%d ms=%.0f", on_main (), ms]];
    GNM_ASSERT (ms >= 95 && ms < 600, @"100 ms timeout fired after %.0f ms", ms);
    return G_SOURCE_REMOVE;
}

static int ticks;
static gboolean tick_cb (gpointer data)
{
    ticks++;
    return ticks < 5 ? G_SOURCE_CONTINUE : G_SOURCE_REMOVE;
}

static void load_done (GObject *src, GAsyncResult *res, gpointer data)
{
    char *contents = NULL; gsize len = 0;
    gboolean ok = g_file_load_contents_finish (G_FILE (src), res, &contents, &len, NULL, NULL);
    [events addObject:[NSString stringWithFormat:@"gio main=%d ok=%d len=%zu", on_main (), ok, (size_t) len]];
    g_free (contents);
}

static gboolean from_thread_cb (gpointer data)
{
    double ms = (CFAbsoluteTimeGetCurrent () - *(CFAbsoluteTime *) data) * 1000;
    [events addObject:[NSString stringWithFormat:@"thread-idle main=%d ms=%.0f", on_main (), ms]];
    GNM_ASSERT (ms < 500, @"cross-thread idle took %.0f ms (fd path broken?)", ms);
    return G_SOURCE_REMOVE;
}

static gboolean nested_cb (gpointer data);

static void spin (NSTimeInterval seconds, BOOL (^done)(void))
{
    NSDate *end = [NSDate dateWithTimeIntervalSinceNow:seconds];
    while (!done () && [end timeIntervalSinceNow] > 0) {
        @autoreleasepool {
            [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:end];
        }
    }
}

int main (void)
{
    @autoreleasepool {
        events = [NSMutableArray array];
        GnmEngine *engine = gnm_test_start_engine (YES);
        GNM_ASSERT (GnmRunLoopBridge.isAttached, @"attached by the engine");

        /* 1. idle and timeout from the main thread */
        g_idle_add (idle_cb, NULL);
        t_timeout_start = CFAbsoluteTimeGetCurrent ();
        g_timeout_add (100, timeout_cb, NULL);
        g_timeout_add (10, tick_cb, NULL);
        spin (2, ^{ return (BOOL) (events.count >= 2 && ticks >= 5); });
        GNM_ASSERT (events.count >= 2, @"idle and timeout fired: %@", events);
        GNM_ASSERT (ticks == 5, @"repeating timeout ticks %d", ticks);
        GNM_ASSERT ([events[0] hasPrefix:@"idle main=1"], @"idle first and on main: %@", events);

        /* 2. a GIO async read: a GLib worker thread completes it and wakes the
         *    main context through its wake-up descriptor */
        [events removeAllObjects];
        NSString *samples = gnm_test_env ("GNM_TEST_SAMPLES");
        GFile *f = g_file_new_for_path ([samples stringByAppendingPathComponent:@"chart-tests.gnumeric"].fileSystemRepresentation);
        g_file_load_contents_async (f, NULL, load_done, NULL);
        spin (3, ^{ return (BOOL) (events.count >= 1); });
        GNM_ASSERT (events.count == 1 && [events[0] hasPrefix:@"gio main=1 ok=1"], @"gio completion: %@", events);
        g_object_unref (f);

        /* 3. an idle added from a foreign thread while the loop is asleep */
        [events removeAllObjects];
        __block CFAbsoluteTime t0 = 0;
        dispatch_after (dispatch_time (DISPATCH_TIME_NOW, 200 * NSEC_PER_MSEC),
                        dispatch_get_global_queue (QOS_CLASS_DEFAULT, 0), ^{
            t0 = CFAbsoluteTimeGetCurrent ();
            g_idle_add (from_thread_cb, &t0);
        });
        spin (3, ^{ return (BOOL) (events.count >= 1); });
        GNM_ASSERT (events.count == 1 && [events[0] hasPrefix:@"thread-idle main=1"], @"cross-thread idle: %@", events);

        /* 4. a nested run loop inside a GLib callback must not deadlock */
        [events removeAllObjects];
        g_idle_add (nested_cb, NULL);
        spin (3, ^{ return (BOOL) ([events containsObject:@"outer-done"]); });
        GNM_ASSERT ([events containsObject:@"outer-done"] && [events containsObject:@"idle main=1"],
                    @"nested loop: %@", events);

        /* 5. dispatchPendingWork runs ready sources synchronously */
        [events removeAllObjects];
        g_idle_add (idle_cb, NULL);
        [GnmRunLoopBridge dispatchPendingWork];
        GNM_ASSERT (events.count == 1, @"dispatchPendingWork: %@", events);

        [engine shutdown];
    }
    return gnm_test_finish ("runloop");
}

static gboolean nested_cb (gpointer data)
{
    [events addObject:@"outer"];
    g_idle_add (idle_cb, NULL);
    spin (1, ^{ return (BOOL) ([events containsObject:@"idle main=1"]); });
    [events addObject:@"outer-done"];
    return G_SOURCE_REMOVE;
}
