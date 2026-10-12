// Sheet objects through the bridge: stable wrappers, hit testing, moving
// and resizing with undo, deleting with undo, restacking, what is not
// selectable, and drawing with the stacking order.
#import "GnmTest.h"

@interface ObjectRecorder : NSObject <GnmSheetDelegate>
@property (nonatomic) NSInteger changes;
@end
@implementation ObjectRecorder
- (void)sheetObjectsDidChange:(GnmSheet *)sheet { _changes++; }
@end

static BOOL
rect_close (CGRect a, CGRect b)
{
    return fabs (a.origin.x - b.origin.x) <= 1 && fabs (a.origin.y - b.origin.y) <= 1
        && fabs (a.size.width - b.size.width) <= 1 && fabs (a.size.height - b.size.height) <= 1;
}

int main (void)
{
    @autoreleasepool {
        GnmEngine *engine = gnm_test_start_engine (NO);
        NSMutableArray<NSError *> *stray = [NSMutableArray array];
        engine.messageHandler = ^(NSError *e) { [stray addObject:e]; };
      @autoreleasepool {
        NSError *error = nil;
        NSURL *url = [NSURL fileURLWithPath:[gnm_test_env ("GNM_TEST_SAMPLES") stringByAppendingPathComponent:@"chart-tests.gnumeric"]];
        GnmWorkbook *wb = [engine openWorkbookAtURL:url error:&error];
        GNM_ASSERT (wb != nil, @"open: %@", error);
        if (!wb) { [engine shutdown]; return gnm_test_finish ("objects"); }
        GnmSheet *s = wb.sheets.firstObject;
        [wb selectSheet:s];
        ObjectRecorder *rec = [[ObjectRecorder alloc] init];
        s.delegate = rec;

        NSArray<GnmSheetObject *> *objects = s.sheetObjects;
        GNM_ASSERT (objects.count >= 2, @"%lu objects", (unsigned long) objects.count);
        if (objects.count < 2) { [engine shutdown]; return gnm_test_finish ("objects"); }
        GnmSheetObject *chart = objects.firstObject;   /* the front object: an image in this sample */
        GNM_ASSERT ([chart.typeName isEqualToString:@"SheetObjectGraph"] || [chart.typeName isEqualToString:@"SheetObjectImage"],
                    @"type '%@'", chart.typeName);
        GNM_ASSERT ([[objects valueForKey:@"typeName"] containsObject:@"SheetObjectGraph"], @"the sample has charts: %@",
                    [objects valueForKey:@"typeName"]);
        GNM_ASSERT (chart.isAttached && chart.isVisible && chart.isSelectable && chart.canResize, @"chart state");
        CGRect f0 = chart.frame;
        GNM_ASSERT (f0.size.width > 50 && f0.size.height > 50, @"frame %@", NSStringFromRect (f0));
        NSLog (@"first object: %@", chart);

        /* wrappers are stable; hit testing finds the front object */
        GNM_ASSERT (s.sheetObjects.firstObject == chart, @"stable wrapper");
        GNM_ASSERT ([s sheetObjectAtPoint:CGPointMake (CGRectGetMidX (f0), CGRectGetMidY (f0))] == chart, @"hit");
        GNM_ASSERT ([s sheetObjectAtPoint:CGPointMake (-10, -10)] == nil, @"miss");

        /* move by (50, 25): the anchor is recomputed from the frame */
        CGRect moved = CGRectOffset (f0, 50, 25);
        rec.changes = 0;
        GNM_ASSERT ([s setFrames:@[[NSValue valueWithRect:moved]] ofSheetObjects:@[chart] resizing:NO error:&error], @"move: %@", error);
        GNM_ASSERT (rect_close (chart.frame, moved), @"moved to %@, wanted %@", NSStringFromRect (chart.frame), NSStringFromRect (moved));
        GNM_ASSERT_EQ_STR (wb.undoLabel ?: @"", @"Move 1 Object");
        GNM_ASSERT (rec.changes > 0, @"delegate heard the move");
        [wb undo];
        GNM_ASSERT (CGRectEqualToRect (chart.frame, f0), @"undo restores %@", NSStringFromRect (chart.frame));

        /* resize: 40 pixels wider */
        CGRect grown = f0;
        grown.size.width += 40;
        GNM_ASSERT ([s setFrames:@[[NSValue valueWithRect:grown]] ofSheetObjects:@[chart] resizing:YES error:&error], @"resize: %@", error);
        GNM_ASSERT (rect_close (chart.frame, grown), @"grown to %@", NSStringFromRect (chart.frame));
        GNM_ASSERT_EQ_STR (wb.undoLabel ?: @"", @"Resize 1 Object");
        [wb undo];
        GNM_ASSERT (CGRectEqualToRect (chart.frame, f0), @"resize undone");

        /* two objects in one command */
        GnmSheetObject *second = objects[1];
        CGRect g0 = second.frame;
        NSArray *twoFrames = @[[NSValue valueWithRect:CGRectOffset (f0, 10, 10)], [NSValue valueWithRect:CGRectOffset (g0, 10, 10)]];
        NSArray *two = @[chart, second];
        GNM_ASSERT ([s setFrames:twoFrames ofSheetObjects:two resizing:NO error:&error], @"move two: %@", error);
        GNM_ASSERT_EQ_STR (wb.undoLabel ?: @"", @"Move 2 Objects");
        GNM_ASSERT (rect_close (second.frame, CGRectOffset (g0, 10, 10)), @"second moved");
        [wb undo];
        GNM_ASSERT (CGRectEqualToRect (second.frame, g0), @"both back");
        GNM_ASSERT (![s setFrames:@[] ofSheetObjects:@[chart] resizing:NO error:&error], @"frame count mismatch refused");

        /* delete and undo */
        NSUInteger count = objects.count;
        rec.changes = 0;
        GNM_ASSERT ([s deleteSheetObjects:@[chart] error:&error], @"delete: %@", error);
        GNM_ASSERT (!chart.isAttached && CGRectIsEmpty (chart.frame) && s.sheetObjects.count == count - 1, @"deleted: attached %d count %lu",
                    chart.isAttached, (unsigned long) s.sheetObjects.count);
        GNM_ASSERT (![s.sheetObjects containsObject:chart], @"gone from the list");
        GNM_ASSERT (rec.changes > 0, @"delegate heard the removal");
        GNM_ASSERT ([s setFrames:@[[NSValue valueWithRect:moved]] ofSheetObjects:@[chart] resizing:NO error:&error], @"a detached object is skipped");
        GNM_ASSERT_EQ_STR (wb.undoLabel ?: @"", @"Delete Object");
        [wb undo];
        GNM_ASSERT (chart.isAttached && s.sheetObjects.count == count && [s.sheetObjects containsObject:chart], @"delete undone");
        GNM_ASSERT (CGRectEqualToRect (chart.frame, f0), @"frame back after the undo");
        GNM_ASSERT ([s sheetObjectAtPoint:CGPointMake (CGRectGetMidX (f0), CGRectGetMidY (f0))] == chart, @"same wrapper after the undo");

        /* stacking order */
        GNM_ASSERT ([s restackSheetObject:chart direction:GnmSheetObjectPushToBack error:&error], @"push to back: %@", error);
        GNM_ASSERT (s.sheetObjects.lastObject == chart, @"now last");
        GNM_ASSERT ([wb.undoLabel containsString:@"Back"], @"undo label '%@'", wb.undoLabel);
        GNM_ASSERT ([s restackSheetObject:chart direction:GnmSheetObjectPullToFront error:&error], @"pull to front: %@", error);
        GNM_ASSERT (s.sheetObjects.firstObject == chart, @"front again");
        [wb undo];
        GNM_ASSERT (s.sheetObjects.lastObject == chart, @"undo of the pull");
        [wb undo];
        GNM_ASSERT (s.sheetObjects.firstObject == chart, @"undo of the push");

        /* an autofilter's combo is a sheet object the user cannot select;
         * drawing with it present must not crash (no cairo renderer) */
        [s setText:@"h" atColumn:50 row:50 autocorrect:NO error:NULL];
        [s setText:@"1" atColumn:50 row:51 autocorrect:NO error:NULL];
        [s selectRange:GnmCellRangeMake (50, 50, 50, 51) editPosition:GnmCellCoordinateMake (50, 50)];
        GNM_ASSERT ([s toggleAutofilter:&error], @"filter: %@", error);
        GnmSheetObject *combo = nil;
        for (GnmSheetObject *o in s.sheetObjects)
            if ([o.typeName isEqualToString:@"GnmFilterCombo"])
                combo = o;
        GNM_ASSERT (combo != nil && !combo.isSelectable && combo.isAttached, @"combo found, not selectable");
        {
            CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB ();
            CGContextRef ctx = CGBitmapContextCreate (NULL, 400, 300, 8, 0, space, kCGImageAlphaPremultipliedLast);
            CGContextTranslateCTM (ctx, 0, 300);
            CGContextScaleCTM (ctx, 1, -1);
            [s drawSheetObjectsInRect:CGRectMake (0, 0, 400, 300) context:ctx];
            [s drawSheetObjectsInRect:CGRectMake ([s leftEdgeOfColumn:50] - 20, [s topEdgeOfRow:50] - 20, 100, 100) context:ctx];
            CGContextRelease (ctx);
            CGColorSpaceRelease (space);
        }
        [wb undo];
        GNM_ASSERT (!combo.isAttached, @"combo gone with the filter");

        wb = nil; s = nil; objects = nil; chart = nil; second = nil; combo = nil;
        GNM_ASSERT (stray.count == 0, @"stray engine messages: %@", stray);
      }
        [engine shutdown];
    }
    return gnm_test_finish ("objects");
}
