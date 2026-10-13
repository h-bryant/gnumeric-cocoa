// The advanced filter in place, to a range, and its refusals; sheets
// hidden and shown again.
#import "GnmTest.h"

static NSString *
cell (GnmSheet *s, int col, int row)
{
    return [s displayTextOfCellAtColumn:col row:row] ?: @"-";
}

int main (void)
{
    @autoreleasepool {
        GnmEngine *engine = gnm_test_start_engine (NO);
        NSMutableArray<NSError *> *stray = [NSMutableArray array];
        engine.messageHandler = ^(NSError *e) { [stray addObject:e]; };
      @autoreleasepool {
        NSError *error = nil;
        GnmWorkbook *wb = [engine newWorkbookWithSheetCount:2];
        GnmSheet *s = wb.sheets.firstObject;
        [wb selectSheet:s];
        NSArray *names = @[@"Name", @"apple", @"pear", @"apple", @"fig", @"kiwi"], *qty = @[@"Qty", @"3", @"5", @"7", @"1", @"9"];
        for (int r = 0; r < 6; r++) {
            GNM_ASSERT ([s setText:names[r] atColumn:0 row:r autocorrect:NO error:&error], @"name: %@", error);
            GNM_ASSERT ([s setText:qty[r] atColumn:1 row:r autocorrect:NO error:&error], @"qty: %@", error);
        }
        GNM_ASSERT ([s setText:@"Qty" atColumn:3 row:0 autocorrect:NO error:&error] && [s setText:@">4" atColumn:3 row:1 autocorrect:NO error:&error], @"criteria: %@", error);

        /* in place: the rows under 5 hidden */
        [s selectRange:GnmCellRangeMake (0, 0, 1, 5) editPosition:GnmCellCoordinateMake (0, 0)];
        GnmAdvancedFilter *filter = [[GnmAdvancedFilter alloc] init];
        filter.listRange = @"A1:B6";
        filter.criteriaRange = @"D1:D2";
        GNM_ASSERT ([s applyAdvancedFilter:filter output:[GnmAnalysisOutput inPlace] error:&error], @"in place: %@", error);
        NSLog (@"filter: in place, rows visible %d %d %d %d %d", [s isRowVisible:1], [s isRowVisible:2], [s isRowVisible:3], [s isRowVisible:4], [s isRowVisible:5]);
        GNM_ASSERT (![s isRowVisible:1] && [s isRowVisible:2] && [s isRowVisible:3] && ![s isRowVisible:4] && [s isRowVisible:5], @"5, 7, 9 stay");
        [s showAllFilteredRows];
        GNM_ASSERT ([s isRowVisible:1] && [s isRowVisible:4], @"shown again");
        /* copied to G1 */
        GNM_ASSERT ([s applyAdvancedFilter:filter output:[GnmAnalysisOutput inRangeNamed:@"G1"] error:&error], @"copy: %@", error);
        NSLog (@"filter: copied: %@ %@ / %@ %@ / %@ %@ / %@ %@ / %@ undo '%@'", cell (s, 6, 0), cell (s, 7, 0), cell (s, 6, 1), cell (s, 7, 1),
               cell (s, 6, 2), cell (s, 7, 2), cell (s, 6, 3), cell (s, 7, 3), cell (s, 6, 4), wb.undoLabel);
        /* the tool writes a three-line heading, then the header row and the matches */
        GNM_ASSERT_EQ_STR (cell (s, 6, 3), @"Name");
        GNM_ASSERT_EQ_STR (cell (s, 6, 4), @"pear");
        GNM_ASSERT_EQ_STR (cell (s, 7, 6), @"9");
        GNM_ASSERT ([s isCellEmptyAtColumn:6 row:7], @"three matches");
        [wb undo];
        GNM_ASSERT ([s isCellEmptyAtColumn:6 row:4], @"undone");
        /* unique records only on the names: the second apple dropped */
        GnmAdvancedFilter *unique = [[GnmAdvancedFilter alloc] init];
        unique.listRange = @"A1:A6";
        GNM_ASSERT ([s setText:@"Name" atColumn:3 row:3 autocorrect:NO error:&error] && [s setText:@"a*" atColumn:3 row:4 autocorrect:NO error:&error], @"criteria 2: %@", error);
        unique.criteriaRange = @"D4:D5";
        unique.uniqueOnly = YES;
        GNM_ASSERT ([s applyAdvancedFilter:unique output:[GnmAnalysisOutput inRangeNamed:@"J1"] error:&error], @"unique: %@", error);
        NSLog (@"filter: unique: %@ %@ %@ %@", cell (s, 9, 3), cell (s, 9, 4), cell (s, 9, 5), cell (s, 9, 6));
        GNM_ASSERT_EQ_STR (cell (s, 9, 4), @"apple");
        GNM_ASSERT ([s isCellEmptyAtColumn:9 row:5], @"one apple");
        /* refusals */
        error = nil;
        filter.criteriaRange = @"nowhere";
        GNM_ASSERT (![s applyAdvancedFilter:filter output:[GnmAnalysisOutput inPlace] error:&error]
                    && [error.localizedDescription containsString:@"criteria range is invalid"], @"bad criteria range: %@", error);
        error = nil;
        GNM_ASSERT ([s setText:@">100" atColumn:3 row:1 autocorrect:NO error:&error], @"criteria 3: %@", error);
        filter.criteriaRange = @"D1:D2";
        GNM_ASSERT (![s applyAdvancedFilter:filter output:[GnmAnalysisOutput inPlace] error:&error]
                    && [error.localizedDescription containsString:@"No matching records"], @"no matches in place: %@", error);
        error = nil;
        /* copied, no match is not a refusal: the heading and header alone */
        GNM_ASSERT ([s applyAdvancedFilter:filter output:[GnmAnalysisOutput inRangeNamed:@"G1"] error:&error], @"no matches copied: %@", error);
        NSLog (@"filter: no matches copied: %@ / %@", cell (s, 6, 3), cell (s, 6, 4));
        GNM_ASSERT ([s isCellEmptyAtColumn:6 row:4], @"nothing under the header");
        [wb undo];

        /* sheets hidden and shown */
        GnmSheet *second = wb.sheets[1];
        GNM_ASSERT ([wb setSheet:second visible:NO error:&error] && !second.isVisible && s.isVisible, @"hide: %@", error);
        NSLog (@"visibility: undo '%@'", wb.undoLabel);
        GNM_ASSERT (wb.canUndo, @"undoable");
        GNM_ASSERT (![wb setSheet:s visible:NO error:&error] && [error.localizedDescription containsString:@"At least one sheet"], @"last visible: %@", error);
        error = nil;
        GNM_ASSERT ([wb setSheet:second visible:YES error:&error] && second.isVisible, @"show: %@", error);
        [wb undo];
        GNM_ASSERT (!second.isVisible, @"hidden again by undo");
        [wb undo];
        GNM_ASSERT (second.isVisible, @"shown again by undo");

        GNM_ASSERT (stray.count == 0, @"stray messages: %@", stray);
        wb = nil;
      }
        [engine shutdown];
        return gnm_test_finish ("filter_visibility");
    }
}
