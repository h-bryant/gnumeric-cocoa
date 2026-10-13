// The engine's preferences through GnmPreferences: the GTK defaults
// (persistence off, so the schema's values), round trips of every kind,
// and what the engine does with them (the sort defaults the Sort dialog
// starts from, the compression level the saver uses).
#import "GnmTest.h"

int main (void)
{
    @autoreleasepool {
        GnmEngineConfiguration *cfg = gnm_test_configuration (NO);
        cfg.xmlCompressionLevel = nil;   /* the schema's default, not the tests' 0 */
        GnmEngine *engine = gnm_test_start_engine_with (cfg);
        NSMutableArray<NSError *> *stray = [NSMutableArray array];
        engine.messageHandler = ^(NSError *e) { [stray addObject:e]; };
      @autoreleasepool {
        GnmPreferences *p = engine.preferences;
        GNM_ASSERT (p == engine.preferences, @"one object");

        /* the schema's defaults */
        GNM_ASSERT (p.xmlCompressionLevel == 9, @"compression default %ld", (long) p.xmlCompressionLevel);
        GNM_ASSERT (p.newWorkbookSheetCount == 1, @"sheets default %ld", (long) p.newWorkbookSheetCount);
        GNM_ASSERT (p.newWorkbookRowCount == 65536 && p.newWorkbookColumnCount == 256, @"size defaults %ld x %ld",
                    (long) p.newWorkbookRowCount, (long) p.newWorkbookColumnCount);
        GNM_ASSERT (fabs (p.defaultZoom - 1.0) < 1e-9, @"zoom default %g", p.defaultZoom);
        GNM_ASSERT (p.defaultFontName.length > 0 && p.defaultFontSize > 0 && !p.defaultFontBold && !p.defaultFontItalic,
                    @"font default %@ %g", p.defaultFontName, p.defaultFontSize);
        GNM_ASSERT (p.enterMovesDirection == GnmEnterDirectionDown, @"enter default %ld", (long) p.enterMovesDirection);
        GNM_ASSERT (p.autocorrectsInitialCapitals && p.autocorrectsFirstLetter && p.autocorrectsNamesOfDays
                    && p.autocorrectsReplacements, @"autocorrect defaults");
        GNM_ASSERT (p.undoMaximumSteps == 20 && p.undoMaximumSize == 100000 && !p.undoShowsSheetName
                    && p.undoMaximumDescriptorWidth == 40, @"undo defaults %ld %ld %d %ld",
                    (long) p.undoMaximumSteps, (long) p.undoMaximumSize, p.undoShowsSheetName,
                    (long) p.undoMaximumDescriptorWidth);
        GNM_ASSERT (p.sortRetainsFormats && !p.sortIsCaseSensitive && p.sortAscending && p.sortInitialClauseCount == 10,
                    @"sort defaults %d %d %d %ld", p.sortRetainsFormats, p.sortIsCaseSensitive, p.sortAscending,
                    (long) p.sortInitialClauseCount);
        GNM_ASSERT (p.autosaveTime == 0, @"autosave default %ld", (long) p.autosaveTime);
        p.autosaveTime = 120;
        GNM_ASSERT (p.autosaveTime == 120, @"autosave round trip %ld", (long) p.autosaveTime);
        p.autosaveTime = 0;
        NSLog (@"defaults: font %@ %g, sheets %ld, undo %ld/%ld", p.defaultFontName, p.defaultFontSize,
               (long) p.newWorkbookSheetCount, (long) p.undoMaximumSteps, (long) p.undoMaximumSize);

        /* the Tools, Screen, and Header/Footer keys */
        GNM_ASSERT (p.autocompletes && p.autocompleteMinimumCharacters == 3 && p.showsFunctionNameTooltips && p.showsFunctionArgumentTooltips,
                    @"editing tool defaults %d %ld %d %d", p.autocompletes, (long) p.autocompleteMinimumCharacters,
                    p.showsFunctionNameTooltips, p.showsFunctionArgumentTooltips);
        GNM_ASSERT (p.screenHorizontalDPI > 50 && p.screenVerticalDPI > 50, @"dpi %g %g", p.screenHorizontalDPI, p.screenVerticalDPI);
        p.autocompletes = NO;
        p.autocompleteMinimumCharacters = 5;
        p.showsFunctionNameTooltips = NO;
        p.newWorkbookShowsFunctionMarkers = YES;
        p.screenHorizontalDPI = 110;
        GNM_ASSERT (!p.autocompletes && p.autocompleteMinimumCharacters == 5 && !p.showsFunctionNameTooltips && p.newWorkbookShowsFunctionMarkers,
                    @"editing tools set");
        GNM_ASSERT (fabs (p.screenHorizontalDPI - 110) < 1e-9, @"dpi set %g", p.screenHorizontalDPI);
        p.autocompletes = YES;
        p.autocompleteMinimumCharacters = 3;
        p.showsFunctionNameTooltips = YES;
        p.newWorkbookShowsFunctionMarkers = NO;
        p.screenHorizontalDPI = 96;

        /* round trips */
        p.xmlCompressionLevel = 0;
        GNM_ASSERT (p.xmlCompressionLevel == 0, @"compression 0");
        p.xmlCompressionLevel = 12;   /* clamped by the engine */
        GNM_ASSERT (p.xmlCompressionLevel == 9, @"compression clamped to %ld", (long) p.xmlCompressionLevel);
        p.newWorkbookSheetCount = 1;
        GNM_ASSERT (p.newWorkbookSheetCount == 1, @"sheets 1");
        p.defaultZoom = 1.5;
        GNM_ASSERT (fabs (p.defaultZoom - 1.5) < 1e-9, @"zoom 1.5");
        p.defaultFontName = @"Helvetica";
        p.defaultFontSize = 12;
        p.defaultFontBold = YES;
        GNM_ASSERT_EQ_STR (p.defaultFontName, @"Helvetica");
        GNM_ASSERT (fabs (p.defaultFontSize - 12) < 1e-9 && p.defaultFontBold, @"font set");
        p.enterMovesDirection = GnmEnterDirectionRight;
        GNM_ASSERT (p.enterMovesDirection == GnmEnterDirectionRight, @"enter right");
        p.enterMovesDirection = GnmEnterDirectionUp;
        GNM_ASSERT (p.enterMovesDirection == GnmEnterDirectionUp, @"enter up");
        p.autocorrectsNamesOfDays = NO;
        GNM_ASSERT (!p.autocorrectsNamesOfDays, @"names of days off");
        p.undoMaximumSteps = 50;
        p.undoShowsSheetName = YES;
        GNM_ASSERT (p.undoMaximumSteps == 50 && p.undoShowsSheetName, @"undo set");
        p.undoShowsSheetName = NO;

        /* what the engine does with them */
        p.sortAscending = NO;
        p.sortIsCaseSensitive = YES;
        p.sortRetainsFormats = NO;
        GNM_ASSERT (!GnmSheet.sortDefaultsToAscending && GnmSheet.sortDefaultsToCaseSensitive
                    && !GnmSheet.sortDefaultsToRetainingFormats, @"the Sort dialog's defaults follow");
        p.sortAscending = YES;
        p.sortIsCaseSensitive = NO;
        p.sortRetainsFormats = YES;

        /* a new workbook with the preferred sheet count, and the saver's
         * compression: plain XML at 0, gzip otherwise */
        p.newWorkbookSheetCount = 2;
        GnmWorkbook *wb = [engine newWorkbookWithSheetCount:p.newWorkbookSheetCount];
        GNM_ASSERT (wb.sheets.count == 2, @"two sheets: %lu", (unsigned long) wb.sheets.count);
        NSError *error = nil;
        NSString *dir = gnm_test_env ("GNM_TEST_OUT");
        NSURL *plain = [NSURL fileURLWithPath:[dir stringByAppendingPathComponent:@"preferences-plain.gnumeric"]];
        NSURL *packed = [NSURL fileURLWithPath:[dir stringByAppendingPathComponent:@"preferences-packed.gnumeric"]];
        p.xmlCompressionLevel = 0;
        GNM_ASSERT ([wb writeToURL:plain adoptingURL:NO error:&error], @"save plain: %@", error);
        p.xmlCompressionLevel = 9;
        GNM_ASSERT ([wb writeToURL:packed adoptingURL:NO error:&error], @"save packed: %@", error);
        NSData *plainData = [NSData dataWithContentsOfURL:plain];
        NSData *packedData = [NSData dataWithContentsOfURL:packed];
        GNM_ASSERT (plainData.length > 5 && memcmp (plainData.bytes, "<?xml", 5) == 0, @"level 0 is plain XML");
        GNM_ASSERT (packedData.length > 2 && ((const unsigned char *) packedData.bytes)[0] == 0x1f
                    && ((const unsigned char *) packedData.bytes)[1] == 0x8b, @"level 9 is gzip");
        NSLog (@"plain %lu bytes, packed %lu bytes", (unsigned long) plainData.length, (unsigned long) packedData.length);
        /* the Tools page's effect on autocompletion */
        GnmSheet *ps = wb.sheets.firstObject;
        GNM_ASSERT ([ps setText:@"hello" atColumn:0 row:0 autocorrect:NO error:&error], @"hello: %@", error);
        GNM_ASSERT_EQ_STR ([ps completionForText:@"hel" atColumn:0 row:1] ?: @"", @"hello");
        GNM_ASSERT ([ps completionForText:@"he" atColumn:0 row:1] == nil, @"two characters are under the default minimum");
        p.autocompleteMinimumCharacters = 5;
        GNM_ASSERT ([ps completionForText:@"hel" atColumn:0 row:1] == nil, @"under a raised minimum");
        p.autocompleteMinimumCharacters = 3;
        p.autocompletes = NO;
        GNM_ASSERT ([ps completionForText:@"hel" atColumn:0 row:1] == nil, @"off by preference");
        p.autocompletes = YES;
        GNM_ASSERT_EQ_STR ([ps completionForText:@"hel" atColumn:0 row:1] ?: @"", @"hello");
        wb = nil;

        GNM_ASSERT (stray.count == 0, @"stray messages: %@", stray);
      }
        [engine shutdown];
        return gnm_test_finish ("preferences");
    }
}
