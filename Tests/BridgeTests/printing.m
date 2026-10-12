// Printing: the page setup read and set (undoable), pagination of a sheet
// in portrait and landscape, fit to one page, a page drawn into a bitmap
// (cells, header), the selection, the print area, and repeating rows.
#import "GnmTest.h"
#import <CoreGraphics/CoreGraphics.h>
#import <ImageIO/ImageIO.h>

static NSInteger
dark_pixels (CGContextRef ctx, int width, int from_row, int to_row)
{
    unsigned char *data = CGBitmapContextGetData (ctx);
    size_t stride = CGBitmapContextGetBytesPerRow (ctx);
    NSInteger count = 0;
    for (int y = from_row; y < to_row; y++)
        for (int x = 0; x < width; x++) {
            unsigned char *p = data + y * stride + x * 4;
            if (p[0] < 200 || p[1] < 200 || p[2] < 200)
                count++;
        }
    return count;
}

int main (void)
{
    @autoreleasepool {
        GnmEngine *engine = gnm_test_start_engine (NO);
        NSMutableArray<NSError *> *stray = [NSMutableArray array];
        engine.messageHandler = ^(NSError *e) { [stray addObject:e]; };
      @autoreleasepool {
        NSError *error = nil;
        GnmWorkbook *wb = [engine newWorkbookWithSheetCount:1];
        GnmSheet *s = wb.sheets.firstObject;
        for (int r = 0; r < 80; r++)
            for (int c = 0; c < 12; c++) {
                NSString *text = [NSString stringWithFormat:@"%d", r * 12 + c];
                GNM_ASSERT ([s setText:text atColumn:c row:r autocorrect:NO error:&error], @"fill: %@", error);
            }

        /* the defaults */
        GnmPrintSettings *defaults = s.printSettings;
        NSLog (@"printing: paper %@ (%@) %gx%g pt, orientation %ld, margins top %g bottom %g header %g footer %g left %g right %g, scale %g%%, header '%@|%@|%@' footer '%@|%@|%@'",
               defaults.paperName, defaults.paperDisplayName, defaults.paperWidth, defaults.paperHeight, (long) defaults.orientation,
               defaults.topMargin, defaults.bottomMargin, defaults.headerMargin, defaults.footerMargin, defaults.leftMargin, defaults.rightMargin,
               defaults.scalePercentage, defaults.headerLeft, defaults.headerMiddle, defaults.headerRight, defaults.footerLeft, defaults.footerMiddle, defaults.footerRight);
        GNM_ASSERT (defaults.paperWidth > 400 && defaults.paperHeight > defaults.paperWidth && defaults.orientation == GnmPageOrientationPortrait, @"a portrait paper");
        GNM_ASSERT (defaults.topMargin >= defaults.headerMargin && defaults.scalePercentage == 100, @"sane defaults");
        GNM_ASSERT (GnmPrintSettings.paperDisplayNames[@"iso_a4"] != nil && GnmPrintSettings.paperDisplayNames[@"na_letter"] != nil, @"papers listed");

        /* pages in portrait: more than one */
        GnmPrintJob *job = [s printJobForSelectionOnly:NO ignoringPrintArea:NO];
        NSLog (@"printing: portrait pages %ld, first %@, last %@; page size %gx%g", (long) job.pageCount, [job rangeNameOfPage:0],
               [job rangeNameOfPage:job.pageCount - 1], job.pageSize.width, job.pageSize.height);
        GNM_ASSERT (job.pageCount >= 2 && [[job rangeNameOfPage:0] hasPrefix:@"A1:"], @"paginated: %ld %@", (long) job.pageCount, [job rangeNameOfPage:0]);
        GNM_ASSERT (job.pageSize.width == defaults.paperWidth && job.pageSize.height == defaults.paperHeight, @"the paper");
        NSInteger portraitPages = job.pageCount;

        /* landscape at half size, recorded and undone */
        GnmPrintSettings *settings = [defaults copy];
        settings.orientation = GnmPageOrientationLandscape;
        settings.scalePercentage = 50;
        settings.printsGridLines = YES;
        settings.printsTitles = YES;
        settings.headerMiddle = @"&[TAB] page &[PAGE] of &[PAGES]";
        GNM_ASSERT ([s setPrintSettings:settings forAllSheets:NO error:&error], @"set: %@", error);
        GNM_ASSERT_EQ_STR (wb.undoLabel ?: @"", @"Page Setup For Sheet1");
        GnmPrintSettings *read = s.printSettings;
        GNM_ASSERT (read.orientation == GnmPageOrientationLandscape && read.paperWidth > read.paperHeight, @"landscape: %g x %g", read.paperWidth, read.paperHeight);
        GNM_ASSERT (read.scalePercentage == 50 && read.printsGridLines && read.printsTitles, @"options back");
        GNM_ASSERT_EQ_STR (read.headerMiddle, @"&[TAB] page &[PAGE] of &[PAGES]");
        job = [s printJobForSelectionOnly:NO ignoringPrintArea:NO];
        NSLog (@"printing: landscape half-size pages %ld", (long) job.pageCount);
        GNM_ASSERT (job.pageCount < portraitPages, @"fewer pages at half size");
        [wb undo];
        GNM_ASSERT (s.printSettings.orientation == GnmPageOrientationPortrait, @"undone");
        [wb redo];
        GNM_ASSERT (s.printSettings.orientation == GnmPageOrientationLandscape, @"redone");

        /* fit to one page */
        settings.orientation = GnmPageOrientationPortrait;
        settings.scaling = GnmPrintScalingFitPages;
        settings.fitColumns = 1;
        settings.fitRows = 1;
        GNM_ASSERT ([s setPrintSettings:settings forAllSheets:NO error:&error], @"fit: %@", error);
        job = [s printJobForSelectionOnly:NO ignoringPrintArea:NO];
        GNM_ASSERT (job.pageCount == 1, @"one page: %ld", (long) job.pageCount);
        NSLog (@"printing: fit scale %g%%", s.printSettings.scalePercentage);
        GNM_ASSERT (s.printSettings.scalePercentage < 100, @"shrunk");

        /* a page drawn: cells in the middle, the header at the top */
        int width = (int) job.pageSize.width, height = (int) job.pageSize.height;
        CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB ();
        CGContextRef ctx = CGBitmapContextCreate (NULL, width, height, 8, width * 4, space, (CGBitmapInfo) kCGImageAlphaPremultipliedLast);
        CGContextSetRGBFillColor (ctx, 1, 1, 1, 1);
        CGContextFillRect (ctx, CGRectMake (0, 0, width, height));
        CGContextTranslateCTM (ctx, 0, height);
        CGContextScaleCTM (ctx, 1, -1);
        [job drawPage:0 inContext:ctx];
        NSInteger top = dark_pixels (ctx, width, 0, (int) settings.topMargin), body = dark_pixels (ctx, width, (int) settings.topMargin, height - (int) settings.bottomMargin);
        NSLog (@"printing: dark pixels header band %ld, body %ld", (long) top, (long) body);
        GNM_ASSERT (body > 2000, @"cells drawn: %ld", (long) body);
        GNM_ASSERT (top > 20, @"the header drawn: %ld", (long) top);
        CGImageRef image = CGBitmapContextCreateImage (ctx);
        NSString *out = [NSString stringWithFormat:@"%s/printing-page1.png", getenv ("GNM_TEST_OUT") ?: "."];
        CFURLRef url = (__bridge CFURLRef) [NSURL fileURLWithPath:out];
        CGImageDestinationRef dest = CGImageDestinationCreateWithURL (url, CFSTR ("public.png"), 1, NULL);
        if (dest) {
            CGImageDestinationAddImage (dest, image, NULL);
            CGImageDestinationFinalize (dest);
            CFRelease (dest);
        }
        CGImageRelease (image);
        CGContextRelease (ctx);
        CGColorSpaceRelease (space);

        /* the selection, the print area, repeating rows */
        [s selectRange:GnmCellRangeMake (0, 0, 1, 1) editPosition:GnmCellCoordinateMake (0, 0)];
        job = [s printJobForSelectionOnly:YES ignoringPrintArea:NO];
        GNM_ASSERT (job.pageCount == 1, @"the selection on one page");
        GNM_ASSERT_EQ_STR ([job rangeNameOfPage:0], @"A1:B2");
        GNM_ASSERT_EQ_STR (s.printAreaName, @"");
        GNM_ASSERT ([s setPrintArea:@"A1:C3" error:&error], @"print area: %@", error);
        GNM_ASSERT_EQ_STR (wb.undoLabel ?: @"", @"Set Print Area to A1:C3");
        GNM_ASSERT_EQ_STR (s.printAreaName, @"A1:C3");
        job = [s printJobForSelectionOnly:NO ignoringPrintArea:NO];
        GNM_ASSERT_EQ_STR ([job rangeNameOfPage:0], @"A1:C3");
        job = [s printJobForSelectionOnly:NO ignoringPrintArea:YES];
        GNM_ASSERT ([[job rangeNameOfPage:0] hasPrefix:@"A1:"] && ![[job rangeNameOfPage:0] isEqualToString:@"A1:C3"], @"ignored: %@", [job rangeNameOfPage:0]);
        error = nil;
        GNM_ASSERT (![s setPrintArea:@"junk" error:&error] && error, @"refused: %@", error);
        GNM_ASSERT ([s setPrintArea:nil error:&error], @"clear: %@", error);
        GNM_ASSERT_EQ_STR (wb.undoLabel ?: @"", @"Clear Print Area");
        GNM_ASSERT_EQ_STR (s.printAreaName, @"");
        [wb undo];
        GNM_ASSERT_EQ_STR (s.printAreaName, @"A1:C3");
        [wb undo];
        settings.scaling = GnmPrintScalingPercentage;
        settings.scalePercentage = 100;
        settings.repeatTop = @"$1:$1";
        GNM_ASSERT ([s setPrintSettings:settings forAllSheets:YES error:&error], @"repeat: %@", error);
        GNM_ASSERT_EQ_STR (wb.undoLabel ?: @"", @"Page Setup For All Sheets");
        job = [s printJobForSelectionOnly:NO ignoringPrintArea:NO];
        GNM_ASSERT (job.pageCount >= 2, @"pages again: %ld", (long) job.pageCount);
        NSLog (@"printing: with the first row repeated, page 2 is %@", [job rangeNameOfPage:1]);
        ctx = CGBitmapContextCreate (NULL, width, height, 8, width * 4, CGColorSpaceCreateDeviceRGB (), (CGBitmapInfo) kCGImageAlphaPremultipliedLast);
        CGContextTranslateCTM (ctx, 0, height);
        CGContextScaleCTM (ctx, 1, -1);
        for (NSInteger p = 0; p < job.pageCount; p++)
            [job drawPage:p inContext:ctx];
        CGContextRelease (ctx);

        GNM_ASSERT (stray.count == 0, @"stray messages: %@", stray);
        wb = nil;
      }
        [engine shutdown];
        return gnm_test_finish ("printing");
    }
}
