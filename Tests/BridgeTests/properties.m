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

        GNM_ASSERT (stray.count == 0, @"stray messages: %@", stray);
        wb = nil;
      }
        [engine shutdown];
        return gnm_test_finish ("properties");
    }
}
