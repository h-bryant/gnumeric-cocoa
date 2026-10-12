// Sheet objects through the bridge: stable wrappers, hit testing, moving
// and resizing with undo, deleting with undo, restacking, what is not
// selectable, and drawing with the stacking order.
#import "GnmTest.h"
#import <AppKit/NSPasteboard.h>
#import <ImageIO/ImageIO.h>

/* A solid PNG of the given pixel size. */
static NSData *
make_png (int w, int h)
{
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB ();
    CGContextRef ctx = CGBitmapContextCreate (NULL, w, h, 8, 0, space, kCGImageAlphaPremultipliedLast);
    CGContextSetRGBFillColor (ctx, 0.2, 0.4, 0.8, 1);
    CGContextFillRect (ctx, CGRectMake (0, 0, w, h));
    CGImageRef image = CGBitmapContextCreateImage (ctx);
    NSMutableData *data = [NSMutableData data];
    CGImageDestinationRef dest = CGImageDestinationCreateWithData ((__bridge CFMutableDataRef) data, CFSTR ("public.png"), 1, NULL);
    CGImageDestinationAddImage (dest, image, NULL);
    CGImageDestinationFinalize (dest);
    CFRelease (dest);
    CGImageRelease (image);
    CGContextRelease (ctx);
    CGColorSpaceRelease (space);
    return data;
}

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

        /* the plot type catalogue, and a chart built from the selection */
        NSArray<GnmPlotType *> *types = GnmPlotType.allTypes;
        GNM_ASSERT (types.count > 50, @"%lu plot types", (unsigned long) types.count);
        GNM_ASSERT (types.firstObject.familyPriority >= types.lastObject.familyPriority, @"families by priority");
        NSLog (@"first plot type: %@ (priority %ld), %lu types", types.firstObject, (long) types.firstObject.familyPriority,
               (unsigned long) types.count);
        GnmPlotType *column = nil;
        for (GnmPlotType *t in types)
            if (column == nil && [t.family isEqualToString:@"Column"] && [t.engine isEqualToString:@"GogBarColPlot"])
                column = t;
        GNM_ASSERT (column != nil && column.name.length > 0 && column.summary.length > 0, @"a column type: %@", column);
        NSData *png = column.sampleImageData;
        GNM_ASSERT (png.length > 8 && ((unsigned char const *) png.bytes)[1] == 'P' && ((unsigned char const *) png.bytes)[2] == 'N',
                    @"sample image is a PNG of %lu bytes", (unsigned long) png.length);
        CGSize chartSize = s.defaultChartSize;
        GNM_ASSERT (chartSize.width > 100 && chartSize.height > 100 && chartSize.width > chartSize.height, @"default size %@",
                    NSStringFromSize (chartSize));
        [s selectRange:GnmCellRangeMake (0, 0, 3, 5) editPosition:GnmCellCoordinateMake (0, 0)];   /* A1:D6: labels and three series */
        CGRect where = CGRectMake (400, 300, chartSize.width, chartSize.height);
        NSUInteger before = s.sheetObjects.count;
        GnmSheetObject *inserted = [s insertChartOfType:column seriesLayout:GnmChartSeriesLayoutAuto sharedAbscissa:NO frame:where error:&error];
        GNM_ASSERT (inserted != nil, @"insert chart: %@", error);
        GNM_ASSERT (inserted.isAttached && [inserted.typeName isEqualToString:@"SheetObjectGraph"] && s.sheetObjects.count == before + 1,
                    @"chart on the sheet: %@", inserted);
        GNM_ASSERT (rect_close (inserted.frame, where), @"chart at %@", NSStringFromRect (inserted.frame));
        GNM_ASSERT (s.sheetObjects.firstObject == inserted && inserted.isSelectable && inserted.canResize, @"new chart in front");
        GNM_ASSERT_EQ_STR (wb.undoLabel ?: @"", @"Insert 1 Object");
        {
            CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB ();
            CGContextRef ctx = CGBitmapContextCreate (NULL, 900, 700, 8, 0, space, kCGImageAlphaPremultipliedLast);
            CGContextTranslateCTM (ctx, 0, 700);
            CGContextScaleCTM (ctx, 1, -1);
            CGContextSetRGBFillColor (ctx, 1, 1, 1, 1);
            CGContextFillRect (ctx, CGRectMake (0, 0, 900, 700));
            [s drawSheetObjectsInRect:where context:ctx];
            unsigned char const *pixels = CGBitmapContextGetData (ctx);
            size_t stride = CGBitmapContextGetBytesPerRow (ctx);
            unsigned dark = 0;
            for (int y = (int) where.origin.y; y < (int) CGRectGetMaxY (where); y += 3)
                for (int x = (int) where.origin.x; x < (int) CGRectGetMaxX (where); x += 3)
                    if (pixels[(size_t) (700 - 1 - y) * stride + (size_t) x * 4] < 128)
                        dark++;
            GNM_ASSERT (dark > 50, @"the chart drew something (%u dark samples)", dark);
            CGContextRelease (ctx);
            CGColorSpaceRelease (space);
        }
        [wb undo];
        GNM_ASSERT (!inserted.isAttached && s.sheetObjects.count == before, @"insertion undone");
        [wb redo];
        GNM_ASSERT (inserted.isAttached && s.sheetObjects.count == before + 1, @"insertion redone");
        [wb undo];
        GnmPlotType *pie = nil;
        for (GnmPlotType *t in types)
            if (pie == nil && [t.engine isEqualToString:@"GogPiePlot"])
                pie = t;
        GNM_ASSERT (pie != nil, @"a pie type");
        [s selectRange:GnmCellRangeMake (0, 1, 1, 5) editPosition:GnmCellCoordinateMake (0, 1)];   /* A2:B6: labels and one series */
        inserted = [s insertChartOfType:pie seriesLayout:GnmChartSeriesLayoutColumns sharedAbscissa:YES frame:where error:&error];
        GNM_ASSERT (inserted != nil && inserted.isAttached, @"pie: %@", error);
        [wb undo];

        /* copy and paste objects through the engine's clipboard; the
         * pasteboard carries a PNG of the first for other applications */
        NSUInteger n0 = s.sheetObjects.count;
        [s copySheetObjects:@[chart] cut:NO];
        GNM_ASSERT ([NSPasteboard.generalPasteboard dataForType:NSPasteboardTypePNG].length > 100, @"PNG on the pasteboard");
        GNM_ASSERT (wb.canPaste, @"can paste");
        [s selectCellAtColumn:30 row:30];
        [s paste];
        GNM_ASSERT (s.sheetObjects.count == n0 + 1, @"pasted a copy: %lu objects", (unsigned long) s.sheetObjects.count);
        GnmSheetObject *pasted = s.sheetObjects.firstObject;
        NSLog (@"pasted %@; AE31 at %g,%g; original %@", pasted, [s leftEdgeOfColumn:30], [s topEdgeOfRow:30], NSStringFromRect (f0));
        /* paste_object puts the copy's anchor cell at the target, keeping
         * the original's offset within its cell: within one cell of AE31 */
        GNM_ASSERT (pasted != chart && [pasted.typeName isEqualToString:chart.typeName]
                    && pasted.frame.origin.x >= [s leftEdgeOfColumn:30] - 1 && pasted.frame.origin.x <= [s leftEdgeOfColumn:31] + 1
                    && pasted.frame.origin.y >= [s topEdgeOfRow:30] - 1 && pasted.frame.origin.y <= [s topEdgeOfRow:31] + 1,
                    @"copy at AE31: %@", pasted);
        NSLog (@"paste undo label: %@", wb.undoLabel);
        [wb undo];
        GNM_ASSERT (s.sheetObjects.count == n0 && !pasted.isAttached, @"paste undone: %lu objects", (unsigned long) s.sheetObjects.count);
        /* a cut deletes now and pastes later */
        [s copySheetObjects:@[chart] cut:YES];
        GNM_ASSERT (!chart.isAttached && s.sheetObjects.count == n0 - 1, @"cut removed it");
        GNM_ASSERT_EQ_STR (wb.undoLabel ?: @"", @"Cut Object");
        [s selectCellAtColumn:30 row:40];
        [s paste];
        GNM_ASSERT (s.sheetObjects.count == n0, @"the cut object pasted back");
        [wb undo];
        [wb undo];
        GNM_ASSERT (chart.isAttached && s.sheetObjects.count == n0, @"cut undone");
        GNM_ASSERT (CGRectEqualToRect (chart.frame, f0), @"chart where it was");

        /* objects as image files: a chart in its vector and raster formats */
        {
            NSArray<GnmImageFormat *> *formats = [s imageFormatsForSheetObject:inserted.isAttached ? inserted : chart];
            GnmSheetObject *graph = nil;
            for (GnmSheetObject *o in s.sheetObjects)
                if (graph == nil && [o.typeName isEqualToString:@"SheetObjectGraph"])
                    graph = o;
            formats = [s imageFormatsForSheetObject:graph];
            NSArray *names = [formats valueForKey:@"name"];
            GNM_ASSERT ([names containsObject:@"png"] && [names containsObject:@"svg"] && [names containsObject:@"pdf"], @"chart formats: %@", formats);
            GnmImageFormat *png = nil, *svg = nil;
            for (GnmImageFormat *f in formats) {
                if ([f.name isEqualToString:@"png"]) png = f;
                if ([f.name isEqualToString:@"svg"]) svg = f;
            }
            GNM_ASSERT (png.usesResolution && !svg.usesResolution && [png.fileExtension isEqualToString:@"png"], @"format details: %@ %@", png, svg);
            NSString *outdir = gnm_test_env ("GNM_TEST_OUT");
            NSURL *pngURL = [NSURL fileURLWithPath:[outdir stringByAppendingPathComponent:@"chart-export.png"]];
            NSURL *svgURL = [NSURL fileURLWithPath:[outdir stringByAppendingPathComponent:@"chart-export.svg"]];
            GNM_ASSERT ([s writeImageOfSheetObject:graph format:png resolution:150 toURL:pngURL error:&error], @"write png: %@", error);
            GNM_ASSERT ([s writeImageOfSheetObject:graph format:svg resolution:-1 toURL:svgURL error:&error], @"write svg: %@", error);
            NSData *pngHead = [[NSFileHandle fileHandleForReadingAtPath:pngURL.path] readDataOfLength:4];
            unsigned char magic[] = { 0x89, 'P', 'N', 'G' };
            GNM_ASSERT ([pngHead isEqualToData:[NSData dataWithBytes:magic length:4]], @"png written");
            NSString *svgText = [NSString stringWithContentsOfFile:svgURL.path encoding:NSUTF8StringEncoding error:NULL];
            GNM_ASSERT ([svgText containsString:@"<svg"], @"svg written: %@", [svgText substringToIndex:MIN (60, svgText.length)]);
            NSURL *bad = [NSURL fileURLWithPath:@"/nonexistent-dir/chart.png"];
            GNM_ASSERT (![s writeImageOfSheetObject:graph format:png resolution:150 toURL:bad error:&error] && error != nil, @"unwritable: %@", error);
            error = nil;
        }

        /* an image from data, and one pasted from the system pasteboard */
        NSData *solid = make_png (40, 30);
        CGSize natural = [s naturalSizeOfImageData:solid];
        GNM_ASSERT (natural.width > 30 && natural.width > natural.height, @"natural size %@", NSStringFromSize (natural));
        GNM_ASSERT (CGSizeEqualToSize ([s naturalSizeOfImageData:[@"not an image" dataUsingEncoding:NSUTF8StringEncoding]], CGSizeZero),
                    @"garbage is not an image");
        GnmSheetObject *picture = [s insertImageData:solid frame:CGRectMake (100, 100, natural.width, natural.height) error:&error];
        GNM_ASSERT (picture != nil && picture.isAttached && [picture.typeName isEqualToString:@"SheetObjectImage"], @"image: %@", error);
        GNM_ASSERT (rect_close (picture.frame, CGRectMake (100, 100, natural.width, natural.height)), @"image at %@", NSStringFromRect (picture.frame));
        GNM_ASSERT_EQ_STR (wb.undoLabel ?: @"", @"Insert 1 Object");
        GNM_ASSERT ([s insertImageData:[@"junk" dataUsingEncoding:NSUTF8StringEncoding] frame:picture.frame error:&error] == nil, @"junk refused");
        /* the image's own format comes first; written back, it is a PNG */
        NSArray<GnmImageFormat *> *pictureFormats = [s imageFormatsForSheetObject:picture];
        GNM_ASSERT (pictureFormats.count > 0 && [pictureFormats.firstObject.name isEqualToString:@"png"], @"image formats: %@", pictureFormats);
        NSURL *pictureURL = [NSURL fileURLWithPath:[gnm_test_env ("GNM_TEST_OUT") stringByAppendingPathComponent:@"image-export.png"]];
        GNM_ASSERT ([s writeImageOfSheetObject:picture format:pictureFormats.firstObject resolution:-1 toURL:pictureURL error:&error], @"write image: %@", error);
        NSData *written = [NSData dataWithContentsOfURL:pictureURL];
        GNM_ASSERT (written.length > 8 && ((const unsigned char *) written.bytes)[1] == 'P', @"image written: %lu bytes", (unsigned long) written.length);
        [wb undo];
        GNM_ASSERT (!picture.isAttached, @"image insertion undone");
        [NSPasteboard.generalPasteboard clearContents];
        [NSPasteboard.generalPasteboard setData:solid forType:NSPasteboardTypePNG];
        GNM_ASSERT (wb.canPaste, @"can paste an image");
        [s selectCellAtColumn:5 row:60];
        [s paste];
        GnmSheetObject *pastedImage = s.sheetObjects.firstObject;
        GNM_ASSERT ([pastedImage.typeName isEqualToString:@"SheetObjectImage"] && fabs (pastedImage.frame.origin.x - [s leftEdgeOfColumn:5]) <= 1
                    && fabs (pastedImage.frame.origin.y - [s topEdgeOfRow:60]) <= 1, @"pasteboard image at F61: %@", pastedImage);
        [wb undo];
        GNM_ASSERT (!pastedImage.isAttached, @"pasteboard image undone");
        [NSPasteboard.generalPasteboard clearContents];

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
