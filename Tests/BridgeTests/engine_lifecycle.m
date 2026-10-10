// Engine start, plugin loading, workbook and sheet facts, shutdown.
#import "GnmTest.h"

@interface Recorder : NSObject <GnmWorkbookDelegate, GnmSheetDelegate>
@property (nonatomic) NSMutableArray<NSString *> *events;
@end
@implementation Recorder
- (instancetype)init { self = [super init]; _events = [NSMutableArray array]; return self; }
- (void)workbook:(GnmWorkbook *)workbook didFocusSheet:(GnmSheet *)sheet {
    [_events addObject:[NSString stringWithFormat:@"focus:%@", sheet.name]];
}
- (void)workbook:(GnmWorkbook *)workbook selectionDescriptionDidChange:(NSString *)text {
    [_events addObject:[NSString stringWithFormat:@"selection:%@", text]];
}
- (void)workbook:(GnmWorkbook *)workbook editLineDidChange:(NSString *)text {
    [_events addObject:[NSString stringWithFormat:@"editline:%@", text]];
}
- (void)sheet:(GnmSheet *)sheet cursorDidMoveToRange:(GnmCellRange)range {
    [_events addObject:[NSString stringWithFormat:@"cursor:%ld,%ld-%ld,%ld",
                        (long) range.start.column, (long) range.start.row,
                        (long) range.end.column, (long) range.end.row]];
}
- (void)sheet:(GnmSheet *)sheet needsDisplayInRange:(GnmCellRange)range {
    [_events addObject:@"redraw-range"];
}
@end

int main (void)
{
    @autoreleasepool {
        GnmEngine *engine = gnm_test_start_engine (NO);
      @autoreleasepool {   /* every workbook must be gone before shutdown */
        GNM_ASSERT (GnmEngine.shared == engine, @"shared engine");
        GNM_ASSERT ([engine.version hasPrefix:@"1.12."], @"version %@", engine.version);
        GNM_ASSERT (engine.availablePluginCount >= 40, @"available plugins %lu", (unsigned long) engine.availablePluginCount);
        GNM_ASSERT (engine.activePluginCount >= 40, @"active plugins %lu", (unsigned long) engine.activePluginCount);
        GNM_ASSERT ([engine.libraryDirectory length] > 0, @"libdir");
        NSLog (@"engine %@, plugins %lu/%lu, libdir %@", engine.version,
               (unsigned long) engine.activePluginCount, (unsigned long) engine.availablePluginCount,
               engine.libraryDirectory);

        /* Second start must fail cleanly. */
        NSError *error = nil;
        GnmEngine *again = [GnmEngine startWithConfiguration:engine.configuration error:&error];
        GNM_ASSERT (again == nil && error.code == GnmErrorEngineAlreadyRunning, @"second start");

        NSString *samples = gnm_test_env ("GNM_TEST_SAMPLES");
        NSURL *url = [NSURL fileURLWithPath:[samples stringByAppendingPathComponent:@"chart-tests.gnumeric"]];
        error = nil;
        GnmWorkbook *wb = [engine openWorkbookAtURL:url error:&error];
        GNM_ASSERT (wb != nil, @"open failed: %@", error);
        if (!wb) { [engine shutdown]; return gnm_test_finish ("engine_lifecycle"); }

        GNM_ASSERT_EQ_STR (wb.displayName, @"chart-tests.gnumeric");
        GNM_ASSERT ([wb.fileURL.path hasSuffix:@"chart-tests.gnumeric"], @"fileURL %@", wb.fileURL);
        GNM_ASSERT (!wb.isModified, @"freshly opened workbook is clean");
        GNM_ASSERT (wb.sheets.count == 24, @"sheet count %lu", (unsigned long) wb.sheets.count);
        GnmSheet *s0 = wb.sheets.firstObject;
        GNM_ASSERT_EQ_STR (s0.name, @"XY");
        GNM_ASSERT (s0.index == 0, @"index");
        /* The file records which sheet was current; it need not be the first. */
        GNM_ASSERT (wb.currentSheet != nil && [wb.sheets containsObject:wb.currentSheet], @"current sheet %@", wb.currentSheet.name);
        GNM_ASSERT (s0.columnCount == 256 || s0.columnCount == 16384, @"columns %ld", (long) s0.columnCount);
        GNM_ASSERT (s0.rowCount >= 65536, @"rows %ld", (long) s0.rowCount);
        GNM_ASSERT_EQ_STR ([s0 displayTextOfCellAtColumn:0 row:0], @"10");
        GNM_ASSERT ([s0 isCellEmptyAtColumn:200 row:200], @"far cell empty");
        GNM_ASSERT ([s0 displayTextOfCellAtColumn:200 row:200] == nil, @"empty cell text is nil");
        GNM_ASSERT_EQ_STR ([s0 nameOfColumn:0], @"A");
        GNM_ASSERT_EQ_STR ([s0 nameOfColumn:27], @"AB");
        GNM_ASSERT_EQ_STR ([s0 nameOfRow:9], @"10");

        /* Geometry: positive sizes, consistent edges, inverse lookups. */
        CGFloat w0 = [s0 widthOfColumn:0], h0 = [s0 heightOfRow:0];
        GNM_ASSERT (w0 > 10 && h0 > 5, @"default cell size %gx%g", w0, h0);
        GNM_ASSERT ([s0 leftEdgeOfColumn:0] == 0 && [s0 topEdgeOfRow:0] == 0, @"origin");
        GNM_ASSERT ([s0 leftEdgeOfColumn:1] == w0, @"left edge of B");
        GNM_ASSERT ([s0 leftEdgeOfColumn:3] == [s0 widthOfColumn:0] + [s0 widthOfColumn:1] + [s0 widthOfColumn:2], @"edges sum");
        GNM_ASSERT ([s0 columnAtX:0] == 0, @"col at 0");
        GNM_ASSERT ([s0 columnAtX:w0 - 1] == 0, @"col at w0-1");
        GNM_ASSERT ([s0 columnAtX:w0] == 1, @"col at w0");
        GNM_ASSERT ([s0 rowAtY:h0 * 5 + 1] == 5, @"row at 5.x");
        GNM_ASSERT ([s0 rowAtY:[s0 topEdgeOfRow:1000] + 2] == 1000, @"row 1000 lookup");
        GNM_ASSERT ([s0 columnAtX:-50] == 0 && [s0 rowAtY:-50] == 0, @"negative clamps");
        GNM_ASSERT ([s0 columnAtX:1e9] == s0.columnCount - 1, @"far x clamps to last column");
        CGRect f = [s0 frameOfCellAtColumn:2 row:3];
        GNM_ASSERT (f.origin.x == [s0 leftEdgeOfColumn:2] && f.size.height == [s0 heightOfRow:3], @"frame");
        GnmCellRange used = s0.usedRange;
        GNM_ASSERT (used.end.column >= used.start.column && used.end.row > 0, @"used range %ld,%ld-%ld,%ld",
                    (long) used.start.column, (long) used.start.row, (long) used.end.column, (long) used.end.row);
        GnmCellCoordinate ext = s0.scrollableExtent;
        GNM_ASSERT (ext.row >= used.end.row, @"scrollable extent covers used range");

        /* Selection round trip through the engine's SheetView and vtable. */
        Recorder *rec = [[Recorder alloc] init];
        wb.delegate = rec;
        s0.delegate = rec;
        [wb selectSheet:s0];   /* status text only follows the current sheet's view */
        GNM_ASSERT (wb.currentSheet == s0, @"current sheet after selectSheet");
        [s0 selectCellAtColumn:3 row:7];
        GNM_ASSERT (s0.editPosition.column == 3 && s0.editPosition.row == 7, @"edit position");
        GnmCellRange sel = s0.selectedRange;
        GNM_ASSERT (sel.start.column == 3 && sel.end.row == 7, @"selected range");
        GNM_ASSERT ([rec.events containsObject:@"cursor:3,7-3,7"], @"cursor_bound notification: %@", rec.events);
        GNM_ASSERT ([rec.events containsObject:@"selection:D8"], @"selection description: %@", rec.events);
        [s0 selectRange:GnmCellRangeMake (0, 0, 2, 2) editPosition:GnmCellCoordinateMake (1, 1)];
        GNM_ASSERT (s0.selectedRange.end.column == 2 && s0.editPosition.column == 1, @"range selection");

        /* Sheet focus through the view. */
        GnmSheet *s1 = wb.sheets[1];
        [wb selectSheet:s1];
        GNM_ASSERT (wb.currentSheet == s1, @"current sheet after focus");
        GNM_ASSERT (([rec.events containsObject:[NSString stringWithFormat:@"focus:%@", s1.name]]), @"focus event: %@", rec.events);

        /* Every sheet has a stable wrapper and a name. */
        NSArray *first = wb.sheets, *second = wb.sheets;
        GNM_ASSERT ([first isEqualToArray:second], @"stable wrappers");
        for (GnmSheet *s in wb.sheets)
            GNM_ASSERT (s.name.length > 0 && s.workbook == wb, @"sheet %ld", (long) s.index);

        /* Releasing the wrapper disposes the engine objects; then shutdown. */
        __weak GnmSheet *weakSheet = s0;
        wb = nil; s0 = nil; s1 = nil; first = second = nil;
        rec = nil;
      }
        /* The inner pool drained every autoreleased reference. */
        [engine shutdown];
        GNM_ASSERT (GnmEngine.shared == nil, @"shared cleared after shutdown");
    }
    return gnm_test_finish ("engine_lifecycle");
}
