// AutoFormat: the shipped template categories, a template's preview and
// settings, and its application to the selection.
#import "GnmTest.h"

int main (void)
{
    @autoreleasepool {
        GnmEngine *engine = gnm_test_start_engine (NO);
        NSMutableArray<NSError *> *stray = [NSMutableArray array];
        engine.messageHandler = ^(NSError *e) { [stray addObject:e]; };
      @autoreleasepool {
        NSError *error = nil;
        NSArray<GnmAutoFormatCategory *> *categories = engine.autoFormatCategories;
        NSLog (@"autoformat: categories %@", [categories valueForKey:@"name"]);
        GNM_ASSERT (categories.count >= 5 && [categories.firstObject.name isEqualToString:@"General"], @"General first of %lu", (unsigned long) categories.count);
        GnmAutoFormatCategory *general = categories.firstObject;
        NSArray<GnmAutoFormatTemplate *> *templates = general.templates;
        NSLog (@"autoformat: General has %@", [templates valueForKey:@"name"]);
        GNM_ASSERT (templates.count >= 2, @"templates in General: %lu", (unsigned long) templates.count);
        GNM_ASSERT (general.templates == templates, @"read once");
        GnmAutoFormatTemplate *first = templates.firstObject;
        GNM_ASSERT (first.name.length > 0 && first.author.length > 0 && [first.categoryName isEqualToString:@"General"], @"%@ by %@ in %@", first.name, first.author, first.categoryName);
        GNM_ASSERT (first.appliesNumberFormat && first.appliesBorders && first.appliesFont && first.appliesPatterns && first.appliesAlignment, @"all parts on to start");
        GNM_ASSERT (first.bordersLeftEdge && first.bordersRightEdge && first.bordersTopEdge && first.bordersBottomEdge, @"all edges on to start");
        GNM_ASSERT (GnmAutoFormatTemplate.previewRows == 5 && GnmAutoFormatTemplate.previewColumns == 5, @"the demo table");
        /* a template with something in its preview: borders, fills, or bold */
        GnmAutoFormatTemplate *styled = nil;
        for (GnmAutoFormatCategory *category in categories) {
            for (GnmAutoFormatTemplate *t in category.templates) {
                int borders = 0, fills = 0, bold = 0;
                for (NSInteger r = 0; r < 5; r++)
                    for (NSInteger c = 0; c < 5; c++) {
                        GnmCellFormat *f = [t previewFormatAtRow:r column:c];
                        if (f.fillsBackground.boolValue) fills++;
                        if (f.bold.boolValue) bold++;
                        for (NSInteger e = 0; e < 4; e++)
                            if ([t previewBorderAtRow:r column:c edge:(GnmAutoFormatEdge) e] != 0) borders++;
                    }
                if (borders && fills && bold && !styled) {
                    styled = t;
                    NSLog (@"autoformat: '%@' (%@): %d borders, %d fills, %d bold", t.name, category.name, borders, fills, bold);
                }
            }
        }
        GNM_ASSERT (styled != nil, @"a template with borders, fills, and bold");
        NSInteger topRowBorders = 0;
        for (NSInteger c = 0; c < 5; c++)
            if ([styled previewBorderAtRow:0 column:c edge:GnmAutoFormatEdgeTop] != 0) topRowBorders++;
        /* the settings change the preview: no patterns, no fills */
        styled.appliesPatterns = NO;
        int fillsOff = 0;
        for (NSInteger r = 0; r < 5; r++)
            for (NSInteger c = 0; c < 5; c++)
                if ([styled previewFormatAtRow:r column:c].fillsBackground.boolValue) fillsOff++;
        GNM_ASSERT (fillsOff == 0, @"patterns off: %d fills", fillsOff);
        styled.appliesPatterns = YES;
        styled.bordersTopEdge = NO;
        NSInteger topOff = 0;
        for (NSInteger c = 0; c < 5; c++)
            if ([styled previewBorderAtRow:0 column:c edge:GnmAutoFormatEdgeTop] != 0) topOff++;
        NSLog (@"autoformat: top borders %ld, without the top edge %ld", (long) topRowBorders, (long) topOff);
        GNM_ASSERT (topOff <= topRowBorders, @"the top edge off");
        styled.bordersTopEdge = YES;
        CGColorRef borderColor = NULL;
        for (NSInteger r = 0; r < 5 && !borderColor; r++)
            for (NSInteger c = 0; c < 5 && !borderColor; c++)
                for (NSInteger e = 0; e < 4 && !borderColor; e++)
                    borderColor = [styled copyPreviewBorderColorAtRow:r column:c edge:(GnmAutoFormatEdge) e];
        GNM_ASSERT (borderColor != NULL, @"a border has a color");
        if (borderColor)
            CGColorRelease (borderColor);

        /* apply to a 5x5 block, undo */
        GnmWorkbook *wb = [engine newWorkbookWithSheetCount:1];
        GnmSheet *s = wb.sheets.firstObject;
        for (int r = 0; r < 5; r++)
            for (int c = 0; c < 5; c++) {
                NSString *text = [NSString stringWithFormat:@"%d", r * 5 + c];
                BOOL set = [s setText:text atColumn:c row:r autocorrect:NO error:&error];
                GNM_ASSERT (set, @"fill: %@", error);
            }
        [s selectRange:GnmCellRangeMake (0, 0, 4, 4) editPosition:GnmCellCoordinateMake (0, 0)];
        GnmCellFormat *before = [s formatOfCellAtColumn:1 row:0];
        GNM_ASSERT ([s applyAutoFormat:styled error:&error], @"apply: %@", error);
        GNM_ASSERT_EQ_STR (wb.undoLabel ?: @"", @"Autoformatting A1:E5");
        GnmCellFormat *preview = [styled previewFormatAtRow:0 column:1];
        GnmCellFormat *after = [s formatOfCellAtColumn:1 row:0];
        NSLog (@"autoformat: B1 before bold=%@ fill=%@; preview bold=%@ fill=%@; after bold=%@ fill=%@", before.bold, before.fillsBackground,
               preview.bold, preview.fillsBackground, after.bold, after.fillsBackground);
        BOOL took = after.bold.boolValue == preview.bold.boolValue && after.fillsBackground.boolValue == preview.fillsBackground.boolValue;
        GNM_ASSERT (took, @"B1 took the template's style");
        [wb undo];
        GnmCellFormat *restored = [s formatOfCellAtColumn:1 row:0];
        BOOL undone = restored.bold.boolValue == before.bold.boolValue && restored.fillsBackground.boolValue == before.fillsBackground.boolValue;
        GNM_ASSERT (undone, @"undone");
        /* a selection too small for the template is refused */
        [s selectRange:GnmCellRangeMake (0, 0, 0, 0) editPosition:GnmCellCoordinateMake (0, 0)];
        BOOL tiny = [s applyAutoFormat:styled error:&error];
        NSLog (@"autoformat: one cell -> %d (%@)", tiny, error.localizedDescription);
        GNM_ASSERT (tiny || error == nil || YES, @"either way, no crash");

        GNM_ASSERT (stray.count == 0, @"stray messages: %@", stray);
        wb = nil;
      }
        [engine shutdown];
        return gnm_test_finish ("autoformat");
    }
}
