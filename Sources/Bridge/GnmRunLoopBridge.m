// GLib main context <-> CFRunLoop integration.
//
// This is the "CFRunLoop is in control" half of GTK's
// gdk/quartz/gdkeventloop-quartz.c (gtk-3-24), which is the arrangement a
// Cocoa app is always in: NSApplication owns the loop, and a run-loop
// observer drives one GLib iteration per CFRunLoop cycle.
//
// Per cycle:
//   BeforeSources  prepare / query / poll(0) / check / dispatch for sources at
//                  or above G_PRIORITY_DEFAULT, so GLib work interleaves with
//                  AppKit events even when the loop never sleeps.
//   BeforeWaiting  prepare / query, then a non-blocking poll; if nothing is
//                  ready, hand the descriptors to the select thread and arm a
//                  CFRunLoopTimer for GLib's timeout.
//   AfterWaiting   collect the select thread's results, check, dispatch.
//
// macOS cannot wait on file descriptors and the run loop at once, hence the
// select thread: it blocks in poll() on GLib's descriptors (including GLib's
// own wake-up pipe, which is how g_idle_add from another thread reaches us)
// and signals a CFRunLoopSource when one becomes ready.  The state machine
// and its restart race fix are GTK's.
#import <GnmCocoa/GnmRunLoopBridge.h>
#include <glib.h>
#include <pthread.h>
#include <unistd.h>
#include <fcntl.h>
#include <string.h>

/* ------------------------------------------------------------------------
 * Select thread
 */
typedef enum {
    BEFORE_START,
    WAITING,              /* idle, waiting for descriptors from the main thread */
    POLLING_QUEUED,       /* main thread submitted descriptors; thread not yet on them */
    POLLING_RESTART,      /* polling, but must poll again before reporting */
    POLLING_DESCRIPTORS,  /* polling */
} SelectThreadState;

static SelectThreadState select_thread_state = BEFORE_START;
static pthread_t select_thread;
static pthread_mutex_t select_thread_mutex = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t select_thread_cond = PTHREAD_COND_INITIALIZER;

#define SELECT_THREAD_LOCK() pthread_mutex_lock (&select_thread_mutex)
#define SELECT_THREAD_UNLOCK() pthread_mutex_unlock (&select_thread_mutex)
#define SELECT_THREAD_SIGNAL() pthread_cond_signal (&select_thread_cond)
#define SELECT_THREAD_WAIT() pthread_cond_wait (&select_thread_cond, &select_thread_mutex)

static GPollFD *current_pollfds;   /* what the thread is polling */
static guint current_n_pollfds;
static GPollFD *next_pollfds;      /* what it should pick up next */
static guint next_n_pollfds;
static int select_thread_wakeup_pipe[2];
static CFRunLoopSourceRef select_main_thread_source;
static CFRunLoopRef main_thread_run_loop;
static GPollFunc poll_func;   /* GLib's default poll function */

static void
select_thread_set_state (SelectThreadState new_state)
{
    SelectThreadState old_state = select_thread_state;
    if (old_state == new_state)
        return;
    select_thread_state = new_state;
    if (old_state == WAITING && new_state != WAITING)
        SELECT_THREAD_SIGNAL ();
}

static void
signal_main_thread (void)
{
    CFRunLoopSourceSignal (select_main_thread_source);
    CFRunLoopWakeUp (main_thread_run_loop);
}

static void *
select_thread_func (void *arg)
{
    char c;
    pthread_setname_np ("GnmCocoa GLib poll");
    SELECT_THREAD_LOCK ();
    while (TRUE) {
        switch (select_thread_state) {
        case BEFORE_START:
            g_assert_not_reached ();
        case WAITING:
            SELECT_THREAD_WAIT ();
            break;
        case POLLING_QUEUED:
            g_free (current_pollfds);
            current_pollfds = next_pollfds;
            current_n_pollfds = next_n_pollfds;
            next_pollfds = NULL;
            next_n_pollfds = 0;
            select_thread_set_state (POLLING_DESCRIPTORS);
            break;
        case POLLING_RESTART:
            select_thread_set_state (POLLING_DESCRIPTORS);
            break;
        case POLLING_DESCRIPTORS:
            SELECT_THREAD_UNLOCK ();
            poll_func (current_pollfds, current_n_pollfds, -1);
            SELECT_THREAD_LOCK ();
            while (read (select_thread_wakeup_pipe[0], &c, 1) == 1)
                ;
            if (select_thread_state == POLLING_DESCRIPTORS) {
                signal_main_thread ();
                select_thread_set_state (WAITING);
            }
            break;
        }
    }
    return NULL;
}

static void
main_thread_source_perform (void *info)
{
    /* Nothing to do: AfterWaiting collects the results. */
}

static void
select_thread_start (void)
{
    g_return_if_fail (select_thread_state == BEFORE_START);
    if (pipe (select_thread_wakeup_pipe) != 0)
        g_error ("GnmRunLoopBridge: pipe failed");
    fcntl (select_thread_wakeup_pipe[0], F_SETFL, O_NONBLOCK);
    fcntl (select_thread_wakeup_pipe[0], F_SETFD, FD_CLOEXEC);
    fcntl (select_thread_wakeup_pipe[1], F_SETFD, FD_CLOEXEC);

    CFRunLoopSourceContext source_context = { 0 };
    source_context.perform = main_thread_source_perform;
    select_main_thread_source = CFRunLoopSourceCreate (NULL, 0, &source_context);
    CFRunLoopAddSource (main_thread_run_loop, select_main_thread_source, kCFRunLoopCommonModes);

    select_thread_state = WAITING;
    if (pthread_create (&select_thread, NULL, select_thread_func, NULL) != 0)
        g_error ("GnmRunLoopBridge: cannot create the poll thread");
}

static gboolean
pollfds_equal (GPollFD const *a, guint na, GPollFD const *b, guint nb)
{
    if (na != nb)
        return FALSE;
    for (guint i = 0; i < na; i++)
        if (a[i].fd != b[i].fd || a[i].events != b[i].events)
            return FALSE;
    return TRUE;
}

/* Returns -1 when an asynchronous poll was started, 0 when there is nothing
 * to poll, or the number of descriptors already ready. */
static int
select_thread_start_poll (GPollFD *ufds, guint nfds, int timeout)
{
    int n_ready;
    gboolean have_new_pollfds = FALSE;

    if (nfds == 0)
        return 0;

    n_ready = poll_func (ufds, nfds, 0);
    if (n_ready > 0 || timeout == 0)
        return n_ready;

    SELECT_THREAD_LOCK ();
    if (select_thread_state == BEFORE_START)
        select_thread_start ();

    if (select_thread_state == POLLING_QUEUED) {
        if (!pollfds_equal (ufds, nfds, next_pollfds, next_n_pollfds - 1)) {
            g_free (next_pollfds);
            next_pollfds = NULL;
            next_n_pollfds = 0;
            have_new_pollfds = TRUE;
        }
    } else if (select_thread_state == POLLING_RESTART || select_thread_state == POLLING_DESCRIPTORS) {
        /* Same descriptors: keep polling, but re-poll once more before
         * reporting so a result collected before this iteration's reads is
         * not reported stale (GTK's race note). */
        if (!pollfds_equal (ufds, nfds, current_pollfds, current_n_pollfds - 1))
            have_new_pollfds = TRUE;
        else if (nfds != 1)   /* the lone GLib wake-up pipe needs no restart */
            select_thread_set_state (POLLING_RESTART);
    } else
        have_new_pollfds = TRUE;

    if (have_new_pollfds) {
        g_assert (next_pollfds == NULL);
        next_n_pollfds = nfds + 1;
        next_pollfds = g_new (GPollFD, nfds + 1);
        memcpy (next_pollfds, ufds, nfds * sizeof (GPollFD));
        next_pollfds[nfds].fd = select_thread_wakeup_pipe[0];
        next_pollfds[nfds].events = G_IO_IN;
        next_pollfds[nfds].revents = 0;
        if (select_thread_state != POLLING_QUEUED && select_thread_state != WAITING) {
            char c = 'A';
            (void) !write (select_thread_wakeup_pipe[1], &c, 1);
        }
        select_thread_set_state (POLLING_QUEUED);
    }
    SELECT_THREAD_UNLOCK ();
    return -1;
}

static int
select_thread_collect_poll (GPollFD *ufds, guint nfds)
{
    int n_ready = 0;
    SELECT_THREAD_LOCK ();
    if (select_thread_state == WAITING) {   /* the poll completed */
        for (guint i = 0; i < nfds; i++) {
            if (ufds[i].fd == -1)
                continue;
            g_assert (ufds[i].fd == current_pollfds[i].fd);
            g_assert (ufds[i].events == current_pollfds[i].events);
            if (current_pollfds[i].revents) {
                ufds[i].revents = current_pollfds[i].revents;
                n_ready++;
            }
        }
    }
    SELECT_THREAD_UNLOCK ();
    return n_ready;
}

/* ------------------------------------------------------------------------
 * Run loop observer
 */
static int current_loop_level;
static int acquired_loop_level = -1;
static gboolean run_loop_polling_async;
static int run_loop_max_priority;
static CFRunLoopTimerRef run_loop_timer;
static GPollFD *run_loop_pollfds;
static guint run_loop_pollfds_size;
static guint run_loop_n_pollfds;
static gboolean attached;

static int
query_main_context (GMainContext *context, int max_priority, int *timeout)
{
    int nfds;
    if (!run_loop_pollfds) {
        run_loop_pollfds_size = 16;
        run_loop_pollfds = g_new (GPollFD, run_loop_pollfds_size);
    }
    while ((nfds = g_main_context_query (context, max_priority, timeout,
                                         run_loop_pollfds, run_loop_pollfds_size)) > (int) run_loop_pollfds_size) {
        g_free (run_loop_pollfds);
        run_loop_pollfds_size = nfds;
        run_loop_pollfds = g_new (GPollFD, nfds);
    }
    return nfds;
}

static void
run_loop_entry (void)
{
    if (acquired_loop_level == -1) {
        if (g_main_context_acquire (NULL))
            acquired_loop_level = current_loop_level;
        /* else another thread owns the context; try again at the next entry */
    }
}

static void
run_loop_before_sources (void)
{
    GMainContext *context = g_main_context_default ();
    int max_priority, nfds;

    g_main_context_prepare (context, &max_priority);
    max_priority = MIN (max_priority, G_PRIORITY_DEFAULT);
    nfds = query_main_context (context, max_priority, NULL);
    if (nfds)
        poll_func (run_loop_pollfds, nfds, 0);
    if (g_main_context_check (context, max_priority, run_loop_pollfds, nfds)) {
        @autoreleasepool {
            g_main_context_dispatch (context);
        }
    }
}

static void
dummy_timer_callback (CFRunLoopTimerRef timer, void *info)
{
}

static void
run_loop_before_waiting (void)
{
    GMainContext *context = g_main_context_default ();
    int timeout, n_ready;

    g_main_context_prepare (context, &run_loop_max_priority);
    run_loop_n_pollfds = query_main_context (context, run_loop_max_priority, &timeout);
    n_ready = select_thread_start_poll (run_loop_pollfds, run_loop_n_pollfds, timeout);

    if (n_ready > 0 || timeout == 0) {
        CFRunLoopWakeUp (main_thread_run_loop);   /* no sleeping allowed */
    } else if (timeout > 0) {
        run_loop_timer = CFRunLoopTimerCreate (NULL, CFAbsoluteTimeGetCurrent () + timeout / 1000.,
                                               0, 0, 0, dummy_timer_callback, NULL);
        CFRunLoopAddTimer (main_thread_run_loop, run_loop_timer, kCFRunLoopCommonModes);
    }
    run_loop_polling_async = n_ready < 0;
}

static void
run_loop_after_waiting (void)
{
    GMainContext *context = g_main_context_default ();

    if (run_loop_timer) {
        CFRunLoopRemoveTimer (main_thread_run_loop, run_loop_timer, kCFRunLoopCommonModes);
        CFRelease (run_loop_timer);
        run_loop_timer = NULL;
    }
    if (run_loop_polling_async) {
        select_thread_collect_poll (run_loop_pollfds, run_loop_n_pollfds);
        run_loop_polling_async = FALSE;
    }
    if (g_main_context_check (context, run_loop_max_priority, run_loop_pollfds, run_loop_n_pollfds)) {
        @autoreleasepool {
            g_main_context_dispatch (context);
        }
    }
}

static void
run_loop_exit (void)
{
    /* +1 because the observer already decremented current_loop_level */
    if ((current_loop_level + 1) == acquired_loop_level) {
        g_main_context_release (NULL);
        acquired_loop_level = -1;
    }
}

static void
run_loop_observer_callback (CFRunLoopObserverRef observer, CFRunLoopActivity activity, void *info)
{
    switch (activity) {
    case kCFRunLoopEntry:
        current_loop_level++;
        run_loop_entry ();
        break;
    case kCFRunLoopBeforeSources:
        run_loop_before_sources ();
        break;
    case kCFRunLoopBeforeWaiting:
        run_loop_before_waiting ();
        break;
    case kCFRunLoopAfterWaiting:
        run_loop_after_waiting ();
        break;
    case kCFRunLoopExit:
        g_return_if_fail (current_loop_level > 0);
        current_loop_level--;
        run_loop_exit ();
        break;
    default:
        break;
    }
}

/* ------------------------------------------------------------------------ */

@implementation GnmRunLoopBridge

+ (void)attachToMainRunLoop
{
    NSAssert (NSThread.isMainThread, @"GnmRunLoopBridge must be attached from the main thread");
    if (attached)
        return;
    attached = YES;

    poll_func = g_main_context_get_poll_func (NULL);
    main_thread_run_loop = CFRunLoopGetMain ();

    CFRunLoopObserverRef observer = CFRunLoopObserverCreate (
        NULL, kCFRunLoopAllActivities, true, 0, run_loop_observer_callback, NULL);
    CFRunLoopAddObserver (main_thread_run_loop, observer, kCFRunLoopCommonModes);

    /* We are attached from inside a running loop most of the time (an app
     * delegate, a test's main), so take ownership now rather than at the next
     * Entry notification. */
    if (acquired_loop_level == -1 && g_main_context_acquire (NULL))
        acquired_loop_level = current_loop_level;
}

+ (BOOL)isAttached
{
    return attached;
}

+ (void)dispatchPendingWork
{
    NSAssert (NSThread.isMainThread, @"engine access off the main thread");
    GMainContext *context = g_main_context_default ();
    gboolean owned = g_main_context_acquire (NULL);
    @autoreleasepool {
        for (int i = 0; i < 1000 && g_main_context_iteration (context, FALSE); i++)
            ;
    }
    if (owned)
        g_main_context_release (NULL);
}

@end
