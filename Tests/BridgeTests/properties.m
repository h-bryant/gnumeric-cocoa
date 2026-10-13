// Edit → Select's array, dependents, and inputs; the workbook view's
// attributes; the document's metadata.
#import "GnmTest.h"

static NSString *
selection (GnmSheet *s)
{
    GnmCellRange r = s.selectedRange;
    return [NSString stringWithFormat:@"%ld,%ld-%ld,%ld", (long) r.start.column, (long) r.start.row, (long) r.end.column, (long) r.end.row];
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
        /* A1 10, A2 20, B1 =A1+A2, C1 =B1*2, an array in D1:D3 */
        GNM_ASSERT ([s setText:@"10" atColumn:0 row:0 autocorrect:NO error:&error] && [s setText:@"20" atColumn:0 row:1 autocorrect:NO error:&error], @"data: %@", error);
        GNM_ASSERT ([s setText:@"=A1+A2" atColumn:1 row:0 autocorrect:NO error:&error] && [s setText:@"=B1*2" atColumn:2 row:0 autocorrect:NO error:&error], @"formulas: %@", error);
        [s selectRange:GnmCellRangeMake (3, 0, 3, 2) editPosition:GnmCellCoordinateMake (3, 0)];
        GNM_ASSERT ([s enterArrayFormula:@"={1;2;3}" error:&error], @"array: %@", error);

        /* Select → Array */
        [s selectCellAtColumn:3 row:1];
        GNM_ASSERT ([s selectCurrentArray], @"the array is selected");
        GNM_ASSERT_EQ_STR (selection (s), @"3,0-3,2");
        [s selectCellAtColumn:0 row:0];
        GNM_ASSERT (![s selectCurrentArray], @"A1 is in no array");
        /* Select → Depends: B1 depends on A1 */
        GNM_ASSERT ([s selectDependents], @"A1 has dependents");
        NSLog (@"properties: dependents of A1: %@", selection (s));
        GNM_ASSERT ([selection (s) isEqualToString:@"1,0-1,0"], @"B1 selected: %@", selection (s));
        [s selectCellAtColumn:2 row:0];
        GNM_ASSERT (![s selectDependents], @"C1 has none");
        /* Select → Inputs: C1 reads B1 */
        GNM_ASSERT ([s selectInputs], @"C1 has inputs");
        GNM_ASSERT_EQ_STR (selection (s), @"1,0-1,0");
        [s selectCellAtColumn:0 row:0];
        GNM_ASSERT (![s selectInputs], @"a constant has no inputs");

        /* the view's attributes */
        GNM_ASSERT (wb.showsHorizontalScrollbar && wb.showsVerticalScrollbar && wb.showsSheetTabs, @"defaults on");
        GNM_ASSERT (!wb.isProtected, @"not protected");
        wb.showsSheetTabs = NO;
        wb.protected = YES;
        GNM_ASSERT (!wb.showsSheetTabs && wb.isProtected && wb.isModified, @"set and dirty");
        wb.showsSheetTabs = YES;
        wb.protected = NO;
        NSLog (@"properties: auto-completes %d, markers %d/%d", wb.autoCompletes, wb.showsFunctionCellMarkers, wb.showsExtensionMarkers);

        /* the document's metadata */
        NSArray *names = GnmWorkbook.standardDocumentPropertyNames;
        GNM_ASSERT (names.count == 9 && [names.firstObject isEqualToString:@"dc:title"], @"the names: %@", names);
        GNM_ASSERT_EQ_STR ([GnmWorkbook labelForDocumentProperty:@"dc:creator"], @"Author");
        NSDictionary *before = wb.documentProperties;
        NSLog (@"properties: metadata to start %@", before);
        NSDictionary *changes = @{@"dc:title": @"Quarterly", @"dc:creator": @"Henry", @"gsf:company": @""};
        GNM_ASSERT ([wb setDocumentProperties:changes error:&error], @"set: %@", error);
        GNM_ASSERT_EQ_STR (wb.documentProperties[@"dc:title"] ?: @"", @"Quarterly");
        GNM_ASSERT_EQ_STR (wb.documentProperties[@"dc:creator"] ?: @"", @"Henry");
        GNM_ASSERT_EQ_STR (wb.undoLabel ?: @"", @"Changing workbook properties");
        [wb undo];
        GNM_ASSERT (wb.documentProperties[@"dc:title"] == nil || [wb.documentProperties[@"dc:title"] isEqualToString:before[@"dc:title"] ?: @""], @"undone: %@", wb.documentProperties[@"dc:title"]);
        [wb redo];
        GNM_ASSERT_EQ_STR (wb.documentProperties[@"dc:title"] ?: @"", @"Quarterly");
        NSDictionary *removal = @{@"dc:title": @""};
        GNM_ASSERT ([wb setDocumentProperties:removal error:&error] && wb.documentProperties[@"dc:title"] == nil, @"removed: %@", wb.documentProperties[@"dc:title"]);
        NSDictionary *same = @{@"dc:creator": @"Henry"};
        NSString *label = wb.undoLabel;
        GNM_ASSERT ([wb setDocumentProperties:same error:&error] && [wb.undoLabel isEqualToString:label], @"no change, no command");

        /* custom properties of each type */
        GNM_ASSERT ([wb setDocumentProperty:@"project" type:GnmDocumentPropertyTypeString value:@"alpha" error:&error], @"string: %@", error);
        GNM_ASSERT ([wb setDocumentProperty:@"runs" type:GnmDocumentPropertyTypeInteger value:@"12" error:&error], @"integer: %@", error);
        GNM_ASSERT ([wb setDocumentProperty:@"weight" type:GnmDocumentPropertyTypeNumber value:@"2.5" error:&error], @"number: %@", error);
        GNM_ASSERT ([wb setDocumentProperty:@"final" type:GnmDocumentPropertyTypeBoolean value:@"TRUE" error:&error], @"boolean: %@", error);
        GNM_ASSERT ([wb setDocumentProperty:@"reviewed" type:GnmDocumentPropertyTypeTimestamp value:@"2026-10-13 09:30:00" error:&error], @"timestamp: %@", error);
        GNM_ASSERT_EQ_STR (wb.undoLabel ?: @"", @"Changing workbook properties");
        NSMutableDictionary<NSString *, GnmDocumentProperty *> *byName = [NSMutableDictionary dictionary];
        for (GnmDocumentProperty *prop in wb.allDocumentProperties)
            byName[prop.name] = prop;
        NSLog (@"properties: %@", wb.allDocumentProperties);
        GNM_ASSERT (byName[@"project"].type == GnmDocumentPropertyTypeString && [byName[@"project"].value isEqualToString:@"alpha"], @"string back: %@", byName[@"project"]);
        GNM_ASSERT (byName[@"runs"].type == GnmDocumentPropertyTypeInteger && [byName[@"runs"].value isEqualToString:@"12"], @"integer back: %@", byName[@"runs"]);
        GNM_ASSERT (byName[@"weight"].type == GnmDocumentPropertyTypeNumber && [byName[@"weight"].value isEqualToString:@"2.5"], @"number back: %@", byName[@"weight"]);
        GNM_ASSERT (byName[@"final"].type == GnmDocumentPropertyTypeBoolean && [byName[@"final"].value isEqualToString:@"TRUE"], @"boolean back: %@", byName[@"final"]);
        GNM_ASSERT (byName[@"reviewed"].type == GnmDocumentPropertyTypeTimestamp && [byName[@"reviewed"].value hasPrefix:@"2026-10-13"], @"timestamp back: %@", byName[@"reviewed"]);
        error = nil;
        GNM_ASSERT (![wb setDocumentProperty:@" " type:GnmDocumentPropertyTypeString value:@"x" error:&error] && error, @"empty name refused");
        error = nil;
        GNM_ASSERT (![wb removeDocumentProperty:@"nope" error:&error] && error, @"unknown name refused");
        GNM_ASSERT ([wb removeDocumentProperty:@"runs" error:&error], @"remove: %@", error);
        NSUInteger afterRemove = wb.allDocumentProperties.count;
        [wb undo];
        GNM_ASSERT (wb.allDocumentProperties.count == afterRemove + 1, @"undo restores the property: %lu", (unsigned long) wb.allDocumentProperties.count);
        [wb redo];
        GNM_ASSERT (wb.allDocumentProperties.count == afterRemove, @"redo removes it again");

        /* the Calculation page and the statistics */
        /* a new workbook recalculates automatically with iteration enabled (workbook.c) */
        GNM_ASSERT (wb.recalculatesAutomatically && wb.iterationEnabled, @"calculation defaults %d %d", wb.recalculatesAutomatically, wb.iterationEnabled);
        NSInteger defaultMaximum = wb.iterationMaximum;
        wb.iterationEnabled = NO;
        GNM_ASSERT (!wb.iterationEnabled, @"iteration off");
        wb.recalculatesAutomatically = NO;
        wb.iterationEnabled = YES;
        wb.iterationMaximum = 50;
        wb.iterationTolerance = 0.01;
        GNM_ASSERT (!wb.recalculatesAutomatically && wb.iterationEnabled && wb.iterationMaximum == 50 && fabs (wb.iterationTolerance - 0.01) < 1e-12,
                    @"calculation set %d %d %ld %g", wb.recalculatesAutomatically, wb.iterationEnabled, (long) wb.iterationMaximum, wb.iterationTolerance);
        GNM_ASSERT (wb.isModified, @"calculation settings mark the document");
        wb.recalculatesAutomatically = YES;
        wb.iterationEnabled = YES;
        wb.iterationMaximum = defaultMaximum;
        NSInteger cells = wb.cellCount;
        GNM_ASSERT (cells >= 7, @"cells counted: %ld", (long) cells);
        NSLog (@"statistics: %lu sheets, %ld cells, default iteration maximum %ld", (unsigned long) wb.sheets.count, (long) cells, (long) defaultMaximum);

        /* Go to Top/Bottom/First/Last around a block I1:K5, apart from
         * the other data (the guess joins adjacent columns) */
        for (NSInteger r = 0; r < 5; r++)
            for (NSInteger c = 8; c < 11; c++)
                GNM_ASSERT ([s setText:@"x" atColumn:c row:r autocorrect:NO error:&error], @"block: %@", error);
        [s selectCellAtColumn:9 row:2];
        [s navigateTo:GnmNavigationTargetTop];
        GNM_ASSERT_EQ_STR (selection (s), @"9,0-9,0");
        [s selectCellAtColumn:9 row:2];
        [s navigateTo:GnmNavigationTargetBottom];
        GNM_ASSERT_EQ_STR (selection (s), @"9,4-9,4");
        [s selectCellAtColumn:9 row:2];
        [s navigateTo:GnmNavigationTargetFirst];
        GNM_ASSERT_EQ_STR (selection (s), @"8,2-8,2");
        [s selectCellAtColumn:9 row:2];
        [s navigateTo:GnmNavigationTargetLast];
        GNM_ASSERT_EQ_STR (selection (s), @"10,2-10,2");

        GNM_ASSERT (stray.count == 0, @"stray messages: %@", stray);
        wb = nil;
      }
        [engine shutdown];
        return gnm_test_finish ("properties");
    }
}
