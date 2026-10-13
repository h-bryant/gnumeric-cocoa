// Draw cells and sheet objects through a CGContext (the grid view's path),
// at 1x and 2x, and check that pixels appeared where cells are.
#import "GnmTest.h"
#import <CoreGraphics/CoreGraphics.h>
#import <ImageIO/ImageIO.h>
#import <CoreServices/CoreServices.h>

static CGContextRef make_flipped_bitmap (size_t w, size_t h, CGFloat scale)
{
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB ();
    CGContextRef ctx = CGBitmapContextCreate (NULL, (size_t) (w * scale), (size_t) (h * scale), 8, 0, cs,
                                              kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little);
    CGColorSpaceRelease (cs);
    /* Quartz origin is bottom-left; present the sheet's y-down space the way
     * a flipped NSView's context does, with the backing scale in the CTM. */
    CGContextScaleCTM (ctx, scale, scale);
    CGContextTranslateCTM (ctx, 0, h);
    CGContextScaleCTM (ctx, 1, -1);
    return ctx;
}

static void write_png (CGContextRef ctx, NSString *path)
{
    CGImageRef img = CGBitmapContextCreateImage (ctx);
    CGImageDestinationRef dest = CGImageDestinationCreateWithURL ((__bridge CFURLRef) [NSURL fileURLWithPath:path],
                                                                   kUTTypePNG, 1, NULL);
    CGImageDestinationAddImage (dest, img, NULL);
    CGImageDestinationFinalize (dest);
    CFRelease (dest);
    CGImageRelease (img);
}

/* Count pixels that differ from the fill color. */
static size_t count_marked (CGContextRef ctx, uint32_t fill)
{
    uint32_t *p = CGBitmapContextGetData (ctx);
    size_t n = CGBitmapContextGetBytesPerRow (ctx) / 4 * CGBitmapContextGetHeight (ctx), marked = 0;
    for (size_t i = 0; i < n; i++)
        if (p[i] != fill)
            marked++;
    return marked;
}

static uint32_t pixel_at (CGContextRef ctx, size_t x, size_t y)
{
    uint32_t *p = CGBitmapContextGetData (ctx);
    return p[y * (CGBitmapContextGetBytesPerRow (ctx) / 4) + x];
}

int main (void)
{
    @autoreleasepool {
        GnmEngine *engine = gnm_test_start_engine (NO);
      @autoreleasepool {   /* every workbook must be gone before shutdown */
        NSString *samples = gnm_test_env ("GNM_TEST_SAMPLES");
        NSString *outdir = gnm_test_env ("GNM_TEST_OUT");
        NSError *error = nil;
        NSURL *url = [NSURL fileURLWithPath:[samples stringByAppendingPathComponent:@"chart-tests.gnumeric"]];
        GnmWorkbook *wb = [engine openWorkbookAtURL:url error:&error];
        GNM_ASSERT (wb != nil, @"open: %@", error);
        if (!wb) { [engine shutdown]; return gnm_test_finish ("render"); }
        GnmSheet *sheet = wb.sheets.firstObject;
        const uint32_t white = 0xffffffffu;

        /* 1x: the first columns and rows */
        size_t W = 480, H = 320;
        CGContextRef ctx = make_flipped_bitmap (W, H, 1);
        CGContextSetRGBFillColor (ctx, 1, 1, 1, 1);
        CGContextFillRect (ctx, CGRectMake (0, 0, W, H));
        [sheet drawCellsInRect:CGRectMake (0, 0, W, H) context:ctx backgroundColor:NULL];
        size_t marked = count_marked (ctx, white);
        GNM_ASSERT (marked > 2000, @"1x cells drew %zu marked pixels", marked);
        /* A1 holds "10": its cell must contain dark pixels; the grid line
         * below row 0 is light gray. */
        CGRect a1 = [sheet frameOfCellAtColumn:0 row:0];
        size_t dark = 0;
        for (size_t y = 0; y < (size_t) a1.size.height - 1; y++)
            for (size_t x = 0; x < (size_t) a1.size.width - 1; x++) {
                uint32_t px = pixel_at (ctx, x, y) & 0x00ffffff;
                if ((px & 0xff) < 0x60 && ((px >> 8) & 0xff) < 0x60 && ((px >> 16) & 0xff) < 0x60)
                    dark++;
            }
        GNM_ASSERT (dark > 10, @"A1 text pixels: %zu", dark);
        /* The grid line below row 0 sits at y == row height: cells occupy
         * [top, top + size) and the next row's top edge draws the line. */
        uint32_t gridline = pixel_at (ctx, 2, (size_t) a1.size.height) & 0x00ffffff;
        GNM_ASSERT (gridline == 0xc7c7c7, @"grid line pixel %06x (default grid color is #c7c7c7)", gridline);
        GNM_ASSERT ((pixel_at (ctx, 2, (size_t) a1.size.height - 1) & 0x00ffffff) == 0xffffff, @"cell interior above the line is white");
        write_png (ctx, [outdir stringByAppendingPathComponent:@"bridge-cells-1x.png"]);
        CGContextRelease (ctx);

        /* 1x with a partial, offset rect: nothing outside the rect is touched */
        ctx = make_flipped_bitmap (W, H, 1);
        CGContextSetRGBFillColor (ctx, 1, 1, 1, 1);
        CGContextFillRect (ctx, CGRectMake (0, 0, W, H));
        [sheet drawCellsInRect:CGRectMake (100, 50, 200, 100) context:ctx backgroundColor:NULL];
        GNM_ASSERT (pixel_at (ctx, 50, 25) == white && pixel_at (ctx, 350, 200) == white, @"outside rect untouched");
        GNM_ASSERT (count_marked (ctx, white) > 100, @"partial rect drew something");
        CGContextRelease (ctx);

        /* 2x: same content, backing scale in the CTM; expect roughly 4x the marks */
        ctx = make_flipped_bitmap (W, H, 2);
        CGContextSetRGBFillColor (ctx, 1, 1, 1, 1);
        CGContextFillRect (ctx, CGRectMake (0, 0, W, H));
        [sheet drawCellsInRect:CGRectMake (0, 0, W, H) context:ctx backgroundColor:NULL];
        size_t marked2x = count_marked (ctx, white);
        GNM_ASSERT (marked2x > 2.5 * marked && marked2x < 6 * marked, @"2x marks %zu vs 1x %zu", marked2x, marked);
        write_png (ctx, [outdir stringByAppendingPathComponent:@"bridge-cells-2x.png"]);
        CGContextRelease (ctx);

        /* Custom background color is honored */
        ctx = make_flipped_bitmap (64, 64, 1);
        CGColorRef blue = CGColorCreateGenericRGB (0, 0, 1, 1);
        [sheet drawCellsInRect:CGRectMake (0, 0, 64, 64) context:ctx backgroundColor:blue];
        size_t blue_count = 0;
        for (size_t y = 0; y < 64; y++)
            for (size_t x = 0; x < 64; x++)
                if ((pixel_at (ctx, x, y) & 0x00ffffff) == 0x0000ff)   /* exact: RGB passes straight through */
                    blue_count++;
        GNM_ASSERT (blue_count > 64 * 64 / 2, @"background pixels %zu of %d", blue_count, 64 * 64);
        CGColorRelease (blue);
        CGContextRelease (ctx);

        /* Sheet objects: the XY sheet carries a chart */
        NSArray<NSValue *> *frames = sheet.sheetObjectFrames;
        GNM_ASSERT (frames.count >= 1, @"object frames: %lu", (unsigned long) frames.count);
        if (frames.count) {
            NSRect f = frames.firstObject.rectValue;
            GNM_ASSERT (f.size.width > 50 && f.size.height > 50, @"chart frame %@", NSStringFromRect (f));
            size_t cw = (size_t) NSMaxX (f) + 10, ch = (size_t) NSMaxY (f) + 10;
            ctx = make_flipped_bitmap (cw, ch, 1);
            CGContextSetRGBFillColor (ctx, 1, 1, 1, 1);
            CGContextFillRect (ctx, CGRectMake (0, 0, cw, ch));
            [sheet drawSheetObjectsInRect:CGRectMake (0, 0, cw, ch) context:ctx];
            size_t chart_marks = count_marked (ctx, white);
            GNM_ASSERT (chart_marks > 1000, @"chart drew %zu marked pixels", chart_marks);
            /* and nothing outside the frame */
            GNM_ASSERT (pixel_at (ctx, cw - 2, ch - 2) == white, @"outside the chart frame");
            write_png (ctx, [outdir stringByAppendingPathComponent:@"bridge-chart.png"]);
            CGContextRelease (ctx);
        }

        /* A sheet with merged cells and borders renders without warnings */
        NSURL *fmt = [NSURL fileURLWithPath:[samples stringByAppendingPathComponent:@"format-tests.gnumeric"]];
        GnmWorkbook *wb2 = [engine openWorkbookAtURL:fmt error:&error];
        GNM_ASSERT (wb2 != nil, @"open format-tests: %@", error);
        if (wb2) {
            for (GnmSheet *s in wb2.sheets) {
                ctx = make_flipped_bitmap (800, 600, 1);
                [s drawCellsInRect:CGRectMake (0, 0, 800, 600) context:ctx backgroundColor:NULL];
                [s drawSheetObjectsInRect:CGRectMake (0, 0, 800, 600) context:ctx];
                CGContextRelease (ctx);
            }
            /* and a region deep in the sheet, past the used range */
            ctx = make_flipped_bitmap (300, 300, 1);
            CGFloat farY = [wb2.sheets.firstObject topEdgeOfRow:50000];
            [wb2.sheets.firstObject drawCellsInRect:CGRectMake (5000, farY, 300, 300) context:ctx backgroundColor:NULL];
            CGContextRelease (ctx);
        }
        wb2 = nil;
        /* A right-to-left sheet: the columns run leftward from the mirror
         * (item-grid's dir = -1), so A1's text lands at the right edge, the
         * left edge shows far, empty columns, and the grid line under A1
         * reaches the right edge. */
        GNM_ASSERT ([sheet toggleDisplayOption:GnmSheetDisplayOptionRightToLeft error:&error], @"toggle rtl: %@", error);
        GNM_ASSERT (sheet.isRightToLeft, @"sheet is right to left");
        ctx = make_flipped_bitmap (W, H, 1);
        CGContextSetRGBFillColor (ctx, 1, 1, 1, 1);
        CGContextFillRect (ctx, CGRectMake (0, 0, W, H));
        [sheet drawCellsInRect:CGRectMake (0, 0, W, H) context:ctx backgroundColor:NULL rightToLeftWidth:W];
        CGRect a1r = [sheet frameOfCellAtColumn:0 row:0];
        size_t dark_right = 0, dark_left = 0;
        for (size_t y = 2; y + 1 < (size_t) a1r.size.height; y++)
            for (size_t x = 2; x + 1 < (size_t) a1r.size.width; x++) {
                uint32_t pr = pixel_at (ctx, W - 1 - x, y), pl = pixel_at (ctx, x, y);
                if (((pr >> 16) & 0xff) < 0x80 && ((pr >> 8) & 0xff) < 0x80 && (pr & 0xff) < 0x80) dark_right++;
                if (((pl >> 16) & 0xff) < 0x80 && ((pl >> 8) & 0xff) < 0x80 && (pl & 0xff) < 0x80) dark_left++;
            }
        GNM_ASSERT (dark_right > 10, @"rtl: A1's text at the right edge (%zu dark pixels)", dark_right);
        GNM_ASSERT (dark_left == 0, @"rtl: nothing at the left edge (%zu dark pixels)", dark_left);
        uint32_t rtl_line = pixel_at (ctx, W - 3, (size_t) a1r.size.height) & 0x00ffffff;
        GNM_ASSERT (rtl_line == 0xc7c7c7, @"rtl: grid line pixel at the right edge %06x", rtl_line);
        write_png (ctx, [outdir stringByAppendingPathComponent:@"bridge-cells-rtl.png"]);
        CGContextRelease (ctx);
        GNM_ASSERT ([sheet toggleDisplayOption:GnmSheetDisplayOptionRightToLeft error:&error], @"toggle back: %@", error);
        GNM_ASSERT (!sheet.isRightToLeft, @"sheet is left to right again");

        wb = nil;
      }
        [engine shutdown];
        GNM_ASSERT (GnmEngine.shared == nil, @"shared cleared after shutdown");
    }
    return gnm_test_finish ("render");
}
