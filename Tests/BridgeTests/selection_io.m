// The selection and the view's first scrolling cell go into the file and
// come back: each sheet view's edit position and range, the focused sheet
// (the .gnumeric SelectedTab), and the top-left cell (TopLeft, xlsx's
// topLeftCell), with the engine's refusals of a bad top-left answered
// quietly by the bridge.
#import "GnmTest.h"

int main (void)
{
    @autoreleasepool {
        GnmEngineConfiguration *cfg = gnm_test_configuration (NO);
        cfg.xmlCompressionLevel = @0;
        GnmEngine *engine = gnm_test_start_engine_with (cfg);
      @autoreleasepool {
        NSMutableArray<NSError *> *stray = [NSMutableArray array];
        engine.messageHandler = ^(NSError *e) { [stray addObject:e]; };
        NSString *outdir = gnm_test_env ("GNM_TEST_OUT");
        NSError *error = nil;

        GnmWorkbook *wb = [engine newWorkbookWithSheetCount:2];
        GnmSheet *s0 = wb.sheets[0], *s1 = wb.sheets[1];
        GNM_ASSERT (s0.initialTopLeft.column == 0 && s0.initialTopLeft.row == 0, @"a new sheet starts at A1");
        GNM_ASSERT ([s0 setText:@"x" atColumn:3 row:19 autocorrect:NO error:&error], @"set text: %@", error);
        [s0 selectRange:GnmCellRangeMake (2, 10, 4, 25) editPosition:GnmCellCoordinateMake (3, 19)];
        s0.initialTopLeft = GnmCellCoordinateMake (1, 5);
        GNM_ASSERT (s0.initialTopLeft.column == 1 && s0.initialTopLeft.row == 5, @"top left set: %ld,%ld",
                    (long) s0.initialTopLeft.column, (long) s0.initialTopLeft.row);
        /* outside the sheet: ignored, without the engine's critical warning */
        s0.initialTopLeft = GnmCellCoordinateMake (-1, 5);
        s0.initialTopLeft = GnmCellCoordinateMake (0, s0.rowCount);
        GNM_ASSERT (s0.initialTopLeft.column == 1 && s0.initialTopLeft.row == 5, @"bad top left ignored");
        /* frozen panes: a cell before the unfrozen corner is ignored too */
        [s1 freezePanesWithUnfrozenTopLeft:GnmCellCoordinateMake (2, 3) frozenTopLeft:GnmCellCoordinateMake (0, 0)];
        GNM_ASSERT (s1.isFrozen, @"frozen");
        GnmCellCoordinate before = s1.initialTopLeft;
        s1.initialTopLeft = GnmCellCoordinateMake (1, 1);
        GNM_ASSERT (s1.initialTopLeft.column == before.column && s1.initialTopLeft.row == before.row, @"top left before the unfrozen corner ignored");
        s1.initialTopLeft = GnmCellCoordinateMake (5, 8);
        GNM_ASSERT (s1.initialTopLeft.column == 5 && s1.initialTopLeft.row == 8, @"top left past the corner set");
        [wb selectSheet:s1];
        GNM_ASSERT (wb.currentSheet == s1, @"sheet 2 focused");

        NSURL *gnm = [NSURL fileURLWithPath:[outdir stringByAppendingPathComponent:@"selection-io.gnumeric"]];
        GNM_ASSERT ([wb writeToURL:gnm error:&error], @"save .gnumeric: %@", error);
        NSURL *xlsx = [NSURL fileURLWithPath:[outdir stringByAppendingPathComponent:@"selection-io.xlsx"]];
        GNM_ASSERT ([wb writeToURL:xlsx error:&error], @"save xlsx: %@", error);
        wb = nil;

        wb = [engine openWorkbookAtURL:gnm error:&error];
        GNM_ASSERT (wb != nil, @"reopen .gnumeric: %@", error);
        if (wb) {
            s0 = wb.sheets[0]; s1 = wb.sheets[1];
            GNM_ASSERT (wb.currentSheet == s1, @"SelectedTab restored: %@", wb.currentSheet.name);
            GNM_ASSERT (s0.editPosition.column == 3 && s0.editPosition.row == 19, @"edit position restored: %ld,%ld",
                        (long) s0.editPosition.column, (long) s0.editPosition.row);
            GnmCellRange r = s0.selectedRange;
            GNM_ASSERT (r.start.column == 2 && r.start.row == 10 && r.end.column == 4 && r.end.row == 25, @"selection restored: %ld,%ld-%ld,%ld",
                        (long) r.start.column, (long) r.start.row, (long) r.end.column, (long) r.end.row);
            GNM_ASSERT (s0.initialTopLeft.column == 1 && s0.initialTopLeft.row == 5, @"top left restored: %ld,%ld",
                        (long) s0.initialTopLeft.column, (long) s0.initialTopLeft.row);
            GNM_ASSERT (s1.isFrozen && s1.initialTopLeft.column == 5 && s1.initialTopLeft.row == 8, @"frozen sheet's top left restored: %ld,%ld",
                        (long) s1.initialTopLeft.column, (long) s1.initialTopLeft.row);
            wb = nil;
        }

        wb = [engine openWorkbookAtURL:xlsx error:&error];
        GNM_ASSERT (wb != nil, @"reopen xlsx: %@", error);
        if (wb) {
            s0 = wb.sheets[0];
            GNM_ASSERT (s0.editPosition.column == 3 && s0.editPosition.row == 19, @"xlsx edit position restored: %ld,%ld",
                        (long) s0.editPosition.column, (long) s0.editPosition.row);
            GNM_ASSERT (s0.initialTopLeft.column == 1 && s0.initialTopLeft.row == 5, @"xlsx top left restored: %ld,%ld",
                        (long) s0.initialTopLeft.column, (long) s0.initialTopLeft.row);
            wb = nil;
        }
        GNM_ASSERT (stray.count == 0, @"stray messages: %@", stray);
      }
        [engine shutdown];
        return gnm_test_finish ("selection_io");
    }
}
