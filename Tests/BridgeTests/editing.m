// Editing through the engine's commands: set text, undo and redo with
// labels, dirty tracking, clear, insert and delete, and the two paths that
// patches/0001 decouples from GTK (an insert that would push data off the
// sheet, and a hide-all question answered by the delegate).
#import "GnmTest.h"
#import <AppKit/NSPasteboard.h>

@interface EditRecorder : NSObject <GnmWorkbookDelegate>
@property (nonatomic) NSMutableArray<NSString *> *events;
@property (nonatomic) BOOL answer;
@property (nonatomic) NSString *lastQuestion;
@end
@implementation EditRecorder
- (instancetype)init { self = [super init]; _events = [NSMutableArray array]; return self; }
- (void)workbookModifiedStateDidChange:(GnmWorkbook *)workbook {
    [_events addObject:[NSString stringWithFormat:@"dirty:%d", workbook.isModified]];
}
- (void)workbook:(GnmWorkbook *)workbook undoLabelDidChange:(NSString *)undo redoLabel:(NSString *)redo {
    [_events addObject:[NSString stringWithFormat:@"labels:%@/%@", undo ?: @"-", redo ?: @"-"]];
}
- (void)workbook:(GnmWorkbook *)workbook sheetDidChange:(GnmSheet *)sheet {
    [_events addObject:[@"sheet:" stringByAppendingString:sheet.name]];
}
- (void)workbook:(GnmWorkbook *)workbook autoExpressionDidChange:(NSString *)text {
    [_events addObject:[@"auto:" stringByAppendingString:text]];
}
- (BOOL)workbook:(GnmWorkbook *)workbook askYesNo:(NSString *)question defaultAnswer:(BOOL)defaultAnswer {
    _lastQuestion = question;
    [_events addObject:@"asked"];
    return _answer;
}
@end

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
        if (!wb) { [engine shutdown]; return gnm_test_finish ("editing"); }
        EditRecorder *rec = [[EditRecorder alloc] init];
        wb.delegate = rec;
        GnmSheet *s = wb.sheets.firstObject;
        [wb selectSheet:s];
        GNM_ASSERT (!wb.canUndo && !wb.canRedo && !wb.isModified, @"clean start");

        /* set text: a number, a formula, a string */
        GNM_ASSERT ([s setText:@"42" atColumn:5 row:5 autocorrect:YES error:&error], @"set number: %@", error);
        /* the same text again is nothing to do, not a failure (the engine
         * returns TRUE without a message; the cell editor's end of editing
         * used to turn that into an alert) */
        NSString *undoBeforeRepeat = wb.undoLabel;
        error = nil;
        GNM_ASSERT ([s setText:@"42" atColumn:5 row:5 autocorrect:YES error:&error] && error == nil, @"unchanged text: %@", error);
        GNM_ASSERT ([wb.undoLabel ?: @"" isEqualToString:undoBeforeRepeat ?: @""], @"no command for an unchanged cell: %@", wb.undoLabel);
        GNM_ASSERT ([s setText:@"" atColumn:30 row:30 autocorrect:YES error:&error] && error == nil, @"blank into a blank cell: %@", error);

        /* a sentinel command: everything below undoes back to it */
        GNM_ASSERT ([s setText:@"sentinel" atColumn:40 row:40 autocorrect:NO error:&error], @"sentinel");
        NSString *sentinelLabel = wb.undoLabel;

        /* cells inserted and deleted with a shift (the GTK dialogs' first
         * two choices): a block at J10:K11, cells inserted at J10 shifting
         * right push it to L10, shifting down push it to J12 */
        GNM_ASSERT ([s setText:@"j10" atColumn:9 row:9 autocorrect:NO error:&error], @"j10");
        GNM_ASSERT ([s setText:@"k11" atColumn:10 row:10 autocorrect:NO error:&error], @"k11");
        GnmCellRange one = { { 9, 9 }, { 9, 9 } };
        GNM_ASSERT ([s insertCellsInRange:one shiftingDown:NO error:&error], @"insert shifting right: %@", error);
        GNM_ASSERT_EQ_STR ([s displayTextOfCellAtColumn:10 row:9] ?: @"", @"j10");
        GNM_ASSERT ([s displayTextOfCellAtColumn:9 row:9] == nil || [[s displayTextOfCellAtColumn:9 row:9] length] == 0, @"J10 empty now");
        GNM_ASSERT_EQ_STR ([s displayTextOfCellAtColumn:10 row:10] ?: @"", @"k11");   /* row 11 untouched */
        GNM_ASSERT ([wb.undoLabel hasPrefix:@"Shift"], @"undo label: %@", wb.undoLabel);
        [wb undo];
        GNM_ASSERT_EQ_STR ([s displayTextOfCellAtColumn:9 row:9] ?: @"", @"j10");
        GNM_ASSERT ([s insertCellsInRange:one shiftingDown:YES error:&error], @"insert shifting down: %@", error);
        GNM_ASSERT_EQ_STR ([s displayTextOfCellAtColumn:9 row:10] ?: @"", @"j10");
        [wb undo];
        GNM_ASSERT ([s deleteCellsInRange:one shiftingUp:YES error:&error], @"delete shifting up: %@", error);
        GNM_ASSERT ([s displayTextOfCellAtColumn:9 row:9] == nil || [[s displayTextOfCellAtColumn:9 row:9] length] == 0, @"J10 gone");
        [wb undo];
        GNM_ASSERT_EQ_STR ([s displayTextOfCellAtColumn:9 row:9] ?: @"", @"j10");
        GnmCellRange kcell = { { 9, 10 }, { 9, 10 } };   /* J11, empty: K11 shifts left into it */
        GNM_ASSERT ([s deleteCellsInRange:kcell shiftingUp:NO error:&error], @"delete shifting left: %@", error);
        GNM_ASSERT_EQ_STR ([s displayTextOfCellAtColumn:9 row:10] ?: @"", @"k11");
        [wb undo];

        /* today's date and the time of day as the GTK actions type them */
        [s selectCellAtColumn:12 row:12];
        NSString *today = [s currentDateTimeTextWithDate:YES time:NO];
        NSString *now = [s currentDateTimeTextWithDate:NO time:YES];
        NSString *both = [s currentDateTimeTextWithDate:YES time:YES];
        NSString *joined = [NSString stringWithFormat:@"%@ %@", today, now];
        GNM_ASSERT (today.length >= 8 && now.length >= 5 && [both isEqualToString:joined],
                    @"date '%@' time '%@' both '%@'", today, now, both);
        GNM_ASSERT ([s setText:today atColumn:12 row:12 autocorrect:YES error:&error], @"type the date: %@", error);
        GNM_ASSERT ([[s displayTextOfCellAtColumn:12 row:12] length] > 0, @"date shown: %@", [s displayTextOfCellAtColumn:12 row:12]);

        /* the name box and Go To: a cell, a range, another sheet, a bad address */
        GNM_ASSERT ([wb jumpToReference:@"C10" error:&error], @"jump: %@", error);
        GNM_ASSERT (s.editPosition.column == 2 && s.editPosition.row == 9, @"at C10: %ld,%ld", (long) s.editPosition.column, (long) s.editPosition.row);
        GNM_ASSERT ([wb jumpToReference:@"B2:D4" error:&error], @"jump to a range: %@", error);
        GNM_ASSERT (s.selectedRange.start.column == 1 && s.selectedRange.end.row == 3, @"B2:D4 selected");
        /* a word defines a name for the selection (the GTK name box), and
         * the name jumps back to it */
        GNM_ASSERT ([wb jumpToReference:@"myrange" error:&error], @"define a name: %@", error);
        [s selectCellAtColumn:0 row:0];
        GNM_ASSERT ([wb jumpToReference:@"myrange" error:&error], @"jump to the name: %@", error);
        GNM_ASSERT (s.selectedRange.start.column == 1 && s.selectedRange.start.row == 1 && s.selectedRange.end.row == 3,
                    @"the name's range selected: %ld,%ld", (long) s.selectedRange.start.column, (long) s.selectedRange.start.row);
        BOOL badOk = [wb jumpToReference:@"Sheet99!A1" error:&error];
        NSLog (@"jump to a missing sheet: ok=%d error=%@", badOk, error);
        GNM_ASSERT (!badOk && error != nil, @"a reference to a missing sheet is an error: %@", error);
        error = nil;
        if (wb.sheets.count > 1) {
            GnmSheet *other = wb.sheets[1];
            NSString *ref = [NSString stringWithFormat:@"%@!A1", other.name];
            GNM_ASSERT ([wb jumpToReference:ref error:&error], @"jump to another sheet: %@", error);
            GNM_ASSERT (wb.currentSheet == other, @"sheet switched to %@", wb.currentSheet.name);
            [wb selectSheet:s];
        }
        /* back to the sentinel, then past it */
        int guard = 0;
        while (wb.canUndo && ![wb.undoLabel isEqualToString:sentinelLabel] && guard++ < 20)
            [wb undo];
        GNM_ASSERT ([wb.undoLabel isEqualToString:sentinelLabel], @"back at the sentinel: %@", wb.undoLabel);
        [wb undo];
        GNM_ASSERT ([s displayTextOfCellAtColumn:40 row:40] == nil, @"sentinel undone");
        GNM_ASSERT_EQ_STR ([s displayTextOfCellAtColumn:5 row:5], @"42");
        GNM_ASSERT ([s setText:@"=F6*2" atColumn:6 row:5 autocorrect:YES error:&error], @"set formula: %@", error);
        GNM_ASSERT_EQ_STR ([s displayTextOfCellAtColumn:6 row:5], @"84");
        GNM_ASSERT ([s cellHasFormulaAtColumn:6 row:5], @"formula cell");
        GNM_ASSERT_EQ_STR ([s editingTextOfCellAtColumn:6 row:5], @"=F6*2");
        GNM_ASSERT ([s setText:@"hello" atColumn:7 row:5 autocorrect:NO error:&error], @"set string: %@", error);
        GNM_ASSERT_EQ_STR ([s displayTextOfCellAtColumn:7 row:5], @"hello");
        GNM_ASSERT (wb.isModified, @"dirty after edits");
        GNM_ASSERT ([rec.events containsObject:@"dirty:1"], @"dirty notification: %@", rec.events);
        GNM_ASSERT (wb.canUndo && !wb.canRedo, @"undo available");
        GNM_ASSERT (wb.undoLabel.length > 0, @"undo label '%@'", wb.undoLabel);
        NSLog (@"undo label: %@", wb.undoLabel);

        /* undo/redo */
        [wb undo];
        GNM_ASSERT ([s displayTextOfCellAtColumn:7 row:5] == nil, @"undo removed the string");
        GNM_ASSERT (wb.canRedo && wb.redoLabel.length > 0, @"redo label '%@'", wb.redoLabel);
        [wb redo];
        GNM_ASSERT_EQ_STR ([s displayTextOfCellAtColumn:7 row:5], @"hello");
        [wb undo]; [wb undo]; [wb undo];
        GNM_ASSERT (!wb.canUndo, @"stack drained");
        GNM_ASSERT ([s displayTextOfCellAtColumn:5 row:5] == nil, @"all undone");
        GNM_ASSERT (!wb.isModified, @"clean again after undoing everything");
        GNM_ASSERT ([rec.events.lastObject hasPrefix:@"labels:"] || [rec.events containsObject:@"dirty:0"], @"events: %@", rec.events);

        /* fill the selection, then clear it */
        [s selectRange:GnmCellRangeMake (10, 10, 11, 12) editPosition:GnmCellCoordinateMake (10, 10)];
        GNM_ASSERT ([s fillSelectionWithText:@"x" error:&error], @"fill: %@", error);
        GNM_ASSERT_EQ_STR ([s displayTextOfCellAtColumn:11 row:12], @"x");
        GNM_ASSERT ([s clearSelection:GnmClearValues error:&error], @"clear: %@", error);
        GNM_ASSERT ([s displayTextOfCellAtColumn:11 row:12] == nil, @"cleared");

        /* insert and delete rows shift data */
        NSString *a1 = [s displayTextOfCellAtColumn:0 row:0];
        GNM_ASSERT ([s insertRows:2 atRow:0 error:&error], @"insert rows: %@", error);
        GNM_ASSERT_EQ_STR ([s displayTextOfCellAtColumn:0 row:2] ?: @"", a1 ?: @"");
        GNM_ASSERT ([s deleteRows:NSMakeRange (0, 2) error:&error], @"delete rows: %@", error);
        GNM_ASSERT_EQ_STR ([s displayTextOfCellAtColumn:0 row:0] ?: @"", a1 ?: @"");
        GNM_ASSERT ([s insertColumns:1 atColumn:0 error:&error], @"insert column: %@", error);
        GNM_ASSERT_EQ_STR ([s displayTextOfCellAtColumn:1 row:0] ?: @"", a1 ?: @"");
        [wb undo];
        GNM_ASSERT_EQ_STR ([s displayTextOfCellAtColumn:0 row:0] ?: @"", a1 ?: @"");

        /* patch site 1: inserting columns that would push data off the sheet
         * is refused with a message through the command context, no dialog */
        [s setText:@"edge" atColumn:(s.columnCount - 1) row:0 autocorrect:NO error:NULL];
        error = nil;
        GNM_ASSERT (![s insertColumns:1 atColumn:0 error:&error], @"insert past the edge must fail");
        GNM_ASSERT (error.code == GnmErrorCommandFailed, @"error %@", error);
        GNM_ASSERT ([error.localizedRecoverySuggestion containsString:@"push data off the sheet"], @"engine message carried: %@", error.userInfo);
        NSLog (@"edge error: %@ / %@", error.localizedDescription, error.localizedRecoverySuggestion);
        [wb undo];   /* the edge cell */

        /* patch site 2: hiding every row asks; the delegate says no, then yes */
        [s selectRange:GnmCellRangeMake (0, 0, s.columnCount - 1, s.rowCount - 1) editPosition:GnmCellCoordinateMake (0, 0)];
        rec.answer = NO;
        error = nil;
        GNM_ASSERT (![s setSelectedColumns:NO hidden:YES error:&error], @"refused hide-all must fail");
        GNM_ASSERT ([rec.events containsObject:@"asked"], @"delegate was asked: %@", rec.events);
        GNM_ASSERT ([rec.lastQuestion containsString:@"hide all rows"], @"question: %@", rec.lastQuestion);
        GNM_ASSERT ([s isRowVisible:0], @"rows still visible");
        rec.answer = YES;
        GNM_ASSERT ([s setSelectedColumns:NO hidden:YES error:&error], @"accepted hide-all: %@", error);
        GNM_ASSERT (![s isRowVisible:0] && [s heightOfRow:0] == 0, @"rows hidden");
        [wb undo];
        GNM_ASSERT ([s isRowVisible:0], @"rows back after undo");

        /* a workbook with no delegate gets the default answer (no) */
        wb.delegate = nil;
        error = nil;
        GNM_ASSERT (![s setSelectedColumns:NO hidden:YES error:&error], @"default answer refuses");

        /* clipboard: copy puts tab-separated text on the pasteboard, paste is
         * one undoable command, cut moves, and foreign text imports */
        wb.delegate = rec;
        [s setText:@"a" atColumn:20 row:20 autocorrect:NO error:NULL];
        [s setText:@"=F6" atColumn:21 row:20 autocorrect:NO error:NULL];
        [s setText:@"42" atColumn:5 row:5 autocorrect:NO error:NULL];
        [s selectRange:GnmCellRangeMake (20, 20, 21, 20) editPosition:GnmCellCoordinateMake (20, 20)];
        [s copySelection];
        GNM_ASSERT (s.marchingAntsFrames.count == 1, @"ants after copy: %lu", (unsigned long) s.marchingAntsFrames.count);
        NSString *pasted = [NSPasteboard.generalPasteboard stringForType:NSPasteboardTypeString];
        GNM_ASSERT ([pasted hasPrefix:@"a\t42"], @"pasteboard text '%@'", pasted);
        [s selectCellAtColumn:20 row:25];
        [s paste];
        GNM_ASSERT_EQ_STR ([s displayTextOfCellAtColumn:20 row:25] ?: @"", @"a");
        GNM_ASSERT ([s cellHasFormulaAtColumn:21 row:25], @"formula pasted as a formula, not text");
        GNM_ASSERT_EQ_STR ([s editingTextOfCellAtColumn:21 row:25] ?: @"", @"=F11");   /* relative reference moved with the paste */
        [wb undo];
        GNM_ASSERT ([s displayTextOfCellAtColumn:20 row:25] == nil, @"paste is one undoable command");
        [s selectRange:GnmCellRangeMake (20, 20, 21, 20) editPosition:GnmCellCoordinateMake (20, 20)];
        [s cutSelection];
        [s selectCellAtColumn:20 row:30];
        [s paste];
        GNM_ASSERT ([s displayTextOfCellAtColumn:20 row:20] == nil && [[s displayTextOfCellAtColumn:20 row:30] isEqualToString:@"a"], @"cut moved the cells");
        /* text from another application replaces the engine's clipboard */
        [NSPasteboard.generalPasteboard clearContents];
        [NSPasteboard.generalPasteboard setString:@"1\t2.5\nx\t=1+1" forType:NSPasteboardTypeString];
        [s selectCellAtColumn:0 row:40];
        [s paste];
        GNM_ASSERT_EQ_STR ([s displayTextOfCellAtColumn:1 row:40] ?: @"", @"2.5");
        GNM_ASSERT_EQ_STR ([s displayTextOfCellAtColumn:0 row:41] ?: @"", @"x");
        /* Text import matches values, not formulas; "=1+1" stays text, as
         * it does when pasted into the GTK front end. */
        GNM_ASSERT_EQ_STR ([s displayTextOfCellAtColumn:1 row:41] ?: @"", @"=1+1");
        GNM_ASSERT (![s cellHasFormulaAtColumn:1 row:41], @"imported text is not a formula");
        [NSPasteboard.generalPasteboard clearContents];
        [NSPasteboard.generalPasteboard setString:@"2026-10-11" forType:NSPasteboardTypeString];
        [s selectCellAtColumn:0 row:42];
        [s paste];
        NSLog (@"single-cell paste of a date shows '%@'", [s displayTextOfCellAtColumn:0 row:42]);
        GNM_ASSERT ([s displayTextOfCellAtColumn:0 row:42].length > 0, @"single value pasted");

        /* column widths and row heights: points are zoom-independent, the
         * engine rounds through pixels, undo restores */
        CGFloat w0 = [s widthInPointsOfColumn:2];
        GNM_ASSERT (w0 > 0 && [s widthOfColumn:2] > 0, @"column 2 has a size");
        [s selectRange:GnmCellRangeMake (2, 0, 2, s.rowCount - 1) editPosition:GnmCellCoordinateMake (2, 0)];
        GNM_ASSERT ([s setSelectedColumns:YES sizeInPoints:100 error:&error], @"set width: %@", error);
        GNM_ASSERT (fabs ([s widthInPointsOfColumn:2] - 100) < 1, @"width now %g pt", [s widthInPointsOfColumn:2]);
        GNM_ASSERT ([wb.undoLabel containsString:@"width"], @"undo label '%@'", wb.undoLabel);
        [wb undo];
        GNM_ASSERT (fabs ([s widthInPointsOfColumn:2] - w0) < 0.01, @"width back to %g", [s widthInPointsOfColumn:2]);
        GNM_ASSERT ([s setColumns:YES inRange:NSMakeRange (2, 1) sizeInPixels:50 error:&error], @"set pixels: %@", error);
        GNM_ASSERT ([s widthOfColumn:2] == 50, @"width now %g px", [s widthOfColumn:2]);
        [wb undo];
        [s selectRange:GnmCellRangeMake (0, 5, 0, 5) editPosition:GnmCellCoordinateMake (0, 5)];
        GNM_ASSERT ([s setSelectedColumns:NO sizeInPoints:40 error:&error], @"set height: %@", error);
        GNM_ASSERT (fabs ([s heightInPointsOfRow:5] - 40) < 1, @"height now %g pt", [s heightInPointsOfRow:5]);
        [wb undo];
        CGFloat d0 = s.defaultColumnWidthInPoints;
        GNM_ASSERT ([s setDefaultSizeInPoints:d0 + 20 forColumns:YES error:&error], @"default width: %@", error);
        GNM_ASSERT (fabs (s.defaultColumnWidthInPoints - (d0 + 20)) < 0.01, @"default now %g", s.defaultColumnWidthInPoints);
        [wb undo];
        GNM_ASSERT (fabs (s.defaultColumnWidthInPoints - d0) < 0.01, @"default back");
        /* autofit grows a column to long content */
        [s setText:@"a rather long piece of text for autofitting" atColumn:30 row:0 autocorrect:NO error:NULL];
        CGFloat before = [s widthOfColumn:30];
        [s selectCellAtColumn:30 row:0];
        GNM_ASSERT ([s autofitSelectedColumns:YES error:&error], @"autofit: %@", error);
        GNM_ASSERT ([s widthOfColumn:30] > before * 2, @"autofit widened %g -> %g", before, [s widthOfColumn:30]);
        [wb undo];
        GNM_ASSERT ([s autofitSelectedCellsWidth:YES error:&error], @"autofit cells: %@", error);
        GNM_ASSERT ([s widthOfColumn:30] > before * 2, @"autofit cells widened to %g", [s widthOfColumn:30]);
        [wb undo]; [wb undo];

        /* fill down and right copy the first row/column over the selection;
         * autofill continues a series, or repeats it with the default increment */
        [s setText:@"x" atColumn:30 row:50 autocorrect:NO error:NULL];
        [s selectRange:GnmCellRangeMake (30, 50, 30, 53) editPosition:GnmCellCoordinateMake (30, 50)];
        GNM_ASSERT ([s fillDown:&error], @"fill down: %@", error);
        GNM_ASSERT_EQ_STR ([s displayTextOfCellAtColumn:30 row:53] ?: @"", @"x");
        [s selectRange:GnmCellRangeMake (30, 50, 33, 50) editPosition:GnmCellCoordinateMake (30, 50)];
        GNM_ASSERT ([s fillRight:&error], @"fill right: %@", error);
        GNM_ASSERT_EQ_STR ([s displayTextOfCellAtColumn:33 row:50] ?: @"", @"x");
        [wb undo]; [wb undo];
        GNM_ASSERT ([s displayTextOfCellAtColumn:30 row:53] == nil, @"fills undone");
        [s setText:@"1" atColumn:40 row:60 autocorrect:NO error:NULL];
        [s setText:@"2" atColumn:40 row:61 autocorrect:NO error:NULL];
        GNM_ASSERT ([s autofillFromRange:GnmCellRangeMake (40, 60, 40, 61) toRange:GnmCellRangeMake (40, 60, 40, 65)
                       defaultIncrement:NO error:&error], @"autofill: %@", error);
        GNM_ASSERT_EQ_STR ([s displayTextOfCellAtColumn:40 row:65] ?: @"", @"6");
        [wb undo];
        /* a single number repeats, unless the default increment of one is asked for */
        GNM_ASSERT ([s autofillFromRange:GnmCellRangeMake (40, 60, 40, 60) toRange:GnmCellRangeMake (40, 60, 40, 65)
                       defaultIncrement:NO error:&error], @"autofill copy: %@", error);
        GNM_ASSERT_EQ_STR ([s displayTextOfCellAtColumn:40 row:65] ?: @"", @"1");
        [wb undo];
        GNM_ASSERT ([s autofillFromRange:GnmCellRangeMake (40, 60, 40, 60) toRange:GnmCellRangeMake (40, 60, 40, 65)
                       defaultIncrement:YES error:&error], @"autofill increment: %@", error);
        GNM_ASSERT_EQ_STR ([s displayTextOfCellAtColumn:40 row:65] ?: @"", @"6");
        [wb undo];
        /* backwards: the target starts above the source (the engine shows a
         * real minus sign, U+2212) */
        GNM_ASSERT ([s autofillFromRange:GnmCellRangeMake (40, 60, 40, 61) toRange:GnmCellRangeMake (40, 56, 40, 61)
                       defaultIncrement:NO error:&error], @"inverse autofill: %@", error);
        GNM_ASSERT_EQ_STR ([s displayTextOfCellAtColumn:40 row:56] ?: @"", @"\u22123");
        [wb undo];

        /* the auto-expression follows the selection and the chosen function */
        [s setText:@"10" atColumn:60 row:80 autocorrect:NO error:NULL];
        [s setText:@"32" atColumn:60 row:81 autocorrect:NO error:NULL];
        [s selectRange:GnmCellRangeMake (60, 80, 60, 81) editPosition:GnmCellCoordinateMake (60, 80)];
        [wb recomputeAutoExpression];   /* the engine's own trigger is a timeout, unpumped here */
        GNM_ASSERT_EQ_STR (wb.autoExpressionFunction, @"sum");
        GNM_ASSERT_EQ_STR (wb.autoExpressionText, @"Sum = 42");
        GNM_ASSERT ([rec.events containsObject:@"auto:Sum = 42"], @"delegate saw the sum: %@", rec.events.lastObject);
        [wb setAutoExpressionFunction:@"average" label:@"Average"];
        GNM_ASSERT_EQ_STR (wb.autoExpressionText, @"Average = 21");
        [wb setAutoExpressionFunction:@"no-such-function" label:@"x"];
        GNM_ASSERT_EQ_STR (wb.autoExpressionFunction, @"average");
        [wb setAutoExpressionFunction:@"sum" label:@"Sum"];

        /* paste special: values only (the formula becomes its value),
         * transposed; and the quick sort by the selection's columns */
        [s setText:@"3" atColumn:70 row:90 autocorrect:NO error:NULL];
        [s setText:@"=BS91*2" atColumn:71 row:90 autocorrect:NO error:NULL];   /* 6 */
        [s selectRange:GnmCellRangeMake (70, 90, 71, 90) editPosition:GnmCellCoordinateMake (70, 90)];
        [s copySelection];
        [s selectCellAtColumn:70 row:95];
        [s pasteWithOptions:GnmPasteAsValues | GnmPasteTranspose];
        GNM_ASSERT_EQ_STR ([s displayTextOfCellAtColumn:70 row:95] ?: @"", @"3");
        GNM_ASSERT_EQ_STR ([s displayTextOfCellAtColumn:70 row:96] ?: @"", @"6");
        GNM_ASSERT (![s cellHasFormulaAtColumn:70 row:96], @"pasted as a value");
        [wb undo];
        [s setText:@"b" atColumn:80 row:100 autocorrect:NO error:NULL];
        [s setText:@"c" atColumn:80 row:101 autocorrect:NO error:NULL];
        [s setText:@"a" atColumn:80 row:102 autocorrect:NO error:NULL];
        [s setText:@"2" atColumn:81 row:100 autocorrect:NO error:NULL];
        [s setText:@"3" atColumn:81 row:101 autocorrect:NO error:NULL];
        [s setText:@"1" atColumn:81 row:102 autocorrect:NO error:NULL];
        [s selectRange:GnmCellRangeMake (80, 100, 81, 102) editPosition:GnmCellCoordinateMake (80, 100)];
        GNM_ASSERT ([s sortSelectionDescending:NO error:&error], @"sort: %@", error);
        GNM_ASSERT_EQ_STR ([s displayTextOfCellAtColumn:80 row:100] ?: @"", @"a");
        GNM_ASSERT_EQ_STR ([s displayTextOfCellAtColumn:81 row:100] ?: @"", @"1");   /* rows move together */
        GNM_ASSERT_EQ_STR ([s displayTextOfCellAtColumn:80 row:102] ?: @"", @"c");
        GNM_ASSERT ([wb.undoLabel hasPrefix:@"Sorting"], @"undo label '%@'", wb.undoLabel);
        GNM_ASSERT ([s sortSelectionDescending:YES error:&error], @"sort descending: %@", error);
        GNM_ASSERT_EQ_STR ([s displayTextOfCellAtColumn:80 row:100] ?: @"", @"c");
        [wb undo]; [wb undo];
        GNM_ASSERT_EQ_STR ([s displayTextOfCellAtColumn:80 row:100] ?: @"", @"b");

        /* frozen panes: the engine keeps the two corners, drops frozen
         * columns when none are asked for, and refuses a no-op */
        GNM_ASSERT (!s.isFrozen && s.frozenTopLeft.column == -1, @"not frozen at first");
        [s freezePanesWithUnfrozenTopLeft:GnmCellCoordinateMake (2, 3) frozenTopLeft:GnmCellCoordinateMake (0, 0)];
        GNM_ASSERT (s.isFrozen, @"frozen");
        GNM_ASSERT (s.unfrozenTopLeft.column == 2 && s.unfrozenTopLeft.row == 3, @"unfrozen at C4: %ld,%ld",
                    (long) s.unfrozenTopLeft.column, (long) s.unfrozenTopLeft.row);
        [s freezePanesWithUnfrozenTopLeft:GnmCellCoordinateMake (0, 5) frozenTopLeft:GnmCellCoordinateMake (0, 0)];
        GNM_ASSERT (s.isFrozen && s.unfrozenTopLeft.column == 0 && s.unfrozenTopLeft.row == 5, @"rows only");
        [s unfreezePanes];
        GNM_ASSERT (!s.isFrozen, @"unfrozen");
        [s freezePanesWithUnfrozenTopLeft:GnmCellCoordinateMake (0, 0) frozenTopLeft:GnmCellCoordinateMake (0, 0)];
        GNM_ASSERT (!s.isFrozen, @"freezing nothing is ignored");

        /* sheets: insert, duplicate, rename, move, remove, all undoable */
        NSUInteger sheetCount = wb.sheets.count;
        GnmSheet *added = [wb insertSheetBefore:nil error:&error];
        GNM_ASSERT (added != nil && wb.sheets.count == sheetCount + 1 && wb.sheets.lastObject == added, @"append: %@", error);
        GNM_ASSERT ([added.name hasPrefix:@"Sheet"], @"engine named it '%@'", added.name);
        GNM_ASSERT ([wb.undoLabel.lowercaseString containsString:@"sheet"], @"undo label '%@'", wb.undoLabel);
        GNM_ASSERT ([wb renameSheet:added to:@"Data" error:&error], @"rename: %@", error);
        GNM_ASSERT_EQ_STR (added.name, @"Data");
        GNM_ASSERT ([rec.events containsObject:@"sheet:Data"], @"delegate saw the rename: %@", rec.events.lastObject);
        GNM_ASSERT (![wb renameSheet:added to:s.name error:&error], @"duplicate name refused");
        GNM_ASSERT ([wb moveSheet:added toIndex:0 error:&error], @"move: %@", error);
        GNM_ASSERT (wb.sheets.firstObject == added, @"moved first (index %ld)", (long) added.index);
        [wb undo];
        GNM_ASSERT (wb.sheets.lastObject == added, @"move undone");
        GnmSheet *copy = [wb duplicateSheet:s error:&error];
        GNM_ASSERT (copy != nil && copy != s && copy.index == s.index + 1, @"duplicate: %@", error);
        GNM_ASSERT_EQ_STR ([copy displayTextOfCellAtColumn:3 row:3] ?: @"", [s displayTextOfCellAtColumn:3 row:3] ?: @"");
        GNM_ASSERT ([wb removeSheet:copy error:&error], @"remove copy: %@", error);
        GNM_ASSERT ([wb removeSheet:added error:&error], @"remove added: %@", error);
        GNM_ASSERT (wb.sheets.count == sheetCount, @"back to %lu sheets", (unsigned long) wb.sheets.count);
        [wb undo];
        GNM_ASSERT (wb.sheets.count == sheetCount + 1 && [wb.sheets.lastObject.name isEqualToString:@"Data"], @"removal undone: %@", wb.sheets.lastObject.name);
        [wb redo];
        GNM_ASSERT (wb.sheets.count == sheetCount, @"removal redone");
        [wb selectSheet:s];
        /* the Manage Sheets dialog's lock and sort */
        GNM_ASSERT (!s.isProtected, @"unlocked to start");
        GNM_ASSERT ([wb setSheet:s protected:YES error:&error] && s.isProtected, @"lock: %@", error);
        [wb undo];
        GNM_ASSERT (!s.isProtected, @"lock undone");
        GnmSheet *zebra = [wb insertSheetBefore:nil error:&error];
        GNM_ASSERT ([wb renameSheet:zebra to:@"Zebra" error:&error], @"rename: %@", error);
        GnmSheet *apple = [wb insertSheetBefore:nil error:&error];
        GNM_ASSERT ([wb renameSheet:apple to:@"apple" error:&error], @"rename: %@", error);
        GNM_ASSERT ([wb sortSheetsAscending:YES error:&error], @"sort: %@", error);
        NSArray *sortedNames = [wb.sheets valueForKey:@"name"];
        NSLog (@"sheets sorted ascending: %@", [sortedNames componentsJoinedByString:@","]);
        GNM_ASSERT (wb.sheets.firstObject == apple && wb.sheets.lastObject == zebra, @"collated, case-insensitively: %@", sortedNames);
        GNM_ASSERT ([wb sortSheetsAscending:NO error:&error] && wb.sheets.firstObject == zebra && wb.sheets.lastObject == apple, @"descending: %@", [wb.sheets valueForKey:@"name"]);
        [wb undo];
        [wb undo];
        GNM_ASSERT (wb.sheets.lastObject == apple && wb.sheets[wb.sheets.count - 2] == zebra, @"sorts undone: %@", [wb.sheets valueForKey:@"name"]);
        GNM_ASSERT ([wb removeSheet:zebra error:&error] && [wb removeSheet:apple error:&error], @"remove: %@", error);
        /* the format toolbar's one-click changes */
        GNM_ASSERT ([s setText:@"1234.5678" atColumn:7 row:7 autocorrect:NO error:&error], @"H8: %@", error);
        [s selectCellAtColumn:7 row:7];
        GNM_ASSERT ([s changeNumberFormatOfSelection:GnmNumberFormatPercentage error:&error], @"percent: %@", error);
        GNM_ASSERT_EQ_STR ([s formatOfCellAtColumn:7 row:7].numberFormat ?: @"", @"0%");
        GNM_ASSERT_EQ_STR ([s displayTextOfCellAtColumn:7 row:7] ?: @"", @"123457%");
        GNM_ASSERT_EQ_STR (wb.undoLabel ?: @"", @"Format as Percentage");
        GNM_ASSERT ([s changeNumberFormatOfSelection:GnmNumberFormatIncreasePrecision error:&error], @"more decimals: %@", error);
        GNM_ASSERT_EQ_STR ([s formatOfCellAtColumn:7 row:7].numberFormat ?: @"", @"0.0%");
        GNM_ASSERT ([s changeNumberFormatOfSelection:GnmNumberFormatDecreasePrecision error:&error], @"fewer decimals: %@", error);
        GNM_ASSERT_EQ_STR ([s formatOfCellAtColumn:7 row:7].numberFormat ?: @"", @"0%");
        GNM_ASSERT ([s changeNumberFormatOfSelection:GnmNumberFormatGeneral error:&error], @"general: %@", error);
        /* inc_dec on General counts the decimals the cell shows (the column
         * width cuts 1234.5678 to what fits) and adds one */
        NSString *shown = [s displayTextOfCellAtColumn:7 row:7] ?: @"";
        NSUInteger shownDecimals = [shown containsString:@"."] ? shown.length - [shown rangeOfString:@"."].location - 1 : 0;
        GNM_ASSERT ([s changeNumberFormatOfSelection:GnmNumberFormatIncreasePrecision error:&error], @"general plus one: %@", error);
        NSLog (@"editing: general '%@' + 1 decimal -> '%@' shows '%@'", shown, [s formatOfCellAtColumn:7 row:7].numberFormat, [s displayTextOfCellAtColumn:7 row:7]);
        NSString *expectedFixed = [@"0." stringByPaddingToLength:2 + shownDecimals + 1 withString:@"0" startingAtIndex:0];
        GNM_ASSERT_EQ_STR ([s formatOfCellAtColumn:7 row:7].numberFormat ?: @"", expectedFixed);
        GNM_ASSERT ([s changeNumberFormatOfSelection:GnmNumberFormatToggleThousands error:&error], @"thousands: %@", error);
        GNM_ASSERT_EQ_STR ([s formatOfCellAtColumn:7 row:7].numberFormat ?: @"", [@"#,##" stringByAppendingString:expectedFixed]);
        GNM_ASSERT ([s changeNumberFormatOfSelection:GnmNumberFormatAccounting error:&error], @"accounting: %@", error);
        NSLog (@"editing: accounting '%@' shows '%@'", [s formatOfCellAtColumn:7 row:7].numberFormat, [s displayTextOfCellAtColumn:7 row:7]);
        GNM_ASSERT ([[s formatOfCellAtColumn:7 row:7].numberFormat containsString:@"#,##0.00"], @"an accounting format: %@", [s formatOfCellAtColumn:7 row:7].numberFormat);
        GNM_ASSERT ([s toggleHorizontalAlignmentOfSelection:8 error:&error] && [s formatOfCellAtColumn:7 row:7].horizontalAlignment.intValue == 8, @"centered: %@", error);
        GNM_ASSERT_EQ_STR (wb.undoLabel ?: @"", @"Set Horizontal Alignment");
        GNM_ASSERT ([s toggleHorizontalAlignmentOfSelection:8 error:&error] && [s formatOfCellAtColumn:7 row:7].horizontalAlignment.intValue == 1, @"back to general: %@", error);
        GNM_ASSERT ([s toggleHorizontalAlignmentOfSelection:4 error:&error] && [s formatOfCellAtColumn:7 row:7].horizontalAlignment.intValue == 4, @"right: %@", error);
        [wb undo];
        GNM_ASSERT ([s formatOfCellAtColumn:7 row:7].horizontalAlignment.intValue == 1, @"alignment undone");
        /* the toolbar's indent, script, and border presets */
        [s selectCellAtColumn:7 row:7];
        GNM_ASSERT (s.indentOfSelection == 0 && s.fontScriptOfSelection == GnmFontScriptStandard, @"plain to start");
        GNM_ASSERT ([s increaseIndentOfSelectionWithError:&error] && s.indentOfSelection == 1, @"indent: %@ -> %ld", error, (long) s.indentOfSelection);
        GNM_ASSERT_EQ_STR (wb.undoLabel ?: @"", @"Increase Indent");
        GNM_ASSERT ([s formatOfCellAtColumn:7 row:7].horizontalAlignment.intValue == 2, @"indenting aligns left");
        GNM_ASSERT ([s decreaseIndentOfSelectionWithError:&error] && s.indentOfSelection == 0, @"dedent: %@", error);
        GNM_ASSERT ([s decreaseIndentOfSelectionWithError:&error] && s.indentOfSelection == 0, @"not below zero");
        GNM_ASSERT ([s toggleFontScriptOfSelection:GnmFontScriptSuperscript error:&error] && s.fontScriptOfSelection == GnmFontScriptSuperscript, @"superscript: %@", error);
        GNM_ASSERT ([s toggleFontScriptOfSelection:GnmFontScriptSubscript error:&error] && s.fontScriptOfSelection == GnmFontScriptSubscript, @"subscript: %@", error);
        GNM_ASSERT ([s toggleFontScriptOfSelection:GnmFontScriptSubscript error:&error] && s.fontScriptOfSelection == GnmFontScriptStandard, @"toggled off: %@", error);
        GNM_ASSERT (GnmSheet.allBorderPresets.count == 12 && [[GnmSheet nameOfBorderPreset:GnmBorderPresetTopAndDoubleBottom] isEqualToString:@"Top and Double Bottom"], @"the presets");
        [s selectRange:GnmCellRangeMake (7, 7, 8, 8) editPosition:GnmCellCoordinateMake (7, 7)];
        GNM_ASSERT ([s setBordersOfSelection:GnmBorderPresetAll error:&error], @"all borders: %@", error);
        GNM_ASSERT_EQ_STR (wb.undoLabel ?: @"", @"Set Borders");
        /* borders come with the selection's format, not a cell's */
        GnmCellFormat *(^formatAt)(int, int) = ^(int col, int row) {
            [s selectCellAtColumn:col row:row];
            return s.formatOfSelection;
        };
        GnmCellFormat *bordered = formatAt (7, 7);
        NSLog (@"editing: H8 borders top %@ bottom %@ left %@ right %@", [bordered borderStyleForEdge:GnmBorderEdgeTop], [bordered borderStyleForEdge:GnmBorderEdgeBottom],
               [bordered borderStyleForEdge:GnmBorderEdgeLeft], [bordered borderStyleForEdge:GnmBorderEdgeRight]);
        GNM_ASSERT ([bordered borderStyleForEdge:GnmBorderEdgeTop].intValue == 1 && [bordered borderStyleForEdge:GnmBorderEdgeRight].intValue == 1, @"H8 top and inner right thin");
        [s selectRange:GnmCellRangeMake (7, 7, 8, 8) editPosition:GnmCellCoordinateMake (7, 7)];
        GNM_ASSERT ([s setBordersOfSelection:GnmBorderPresetThickBottom error:&error], @"thick bottom: %@", error);
        GNM_ASSERT ([formatAt (7, 8) borderStyleForEdge:GnmBorderEdgeBottom].intValue == 5, @"H9 bottom thick: %@", [formatAt (7, 8) borderStyleForEdge:GnmBorderEdgeBottom]);
        [s selectRange:GnmCellRangeMake (7, 7, 8, 8) editPosition:GnmCellCoordinateMake (7, 7)];
        GNM_ASSERT ([s setBordersOfSelection:GnmBorderPresetNone error:&error], @"none: %@", error);
        GNM_ASSERT ([formatAt (7, 7) borderStyleForEdge:GnmBorderEdgeTop].intValue == 0, @"cleared: %@", [formatAt (7, 7) borderStyleForEdge:GnmBorderEdgeTop]);
        [wb undo];
        GNM_ASSERT ([formatAt (7, 8) borderStyleForEdge:GnmBorderEdgeBottom].intValue == 5, @"clearing undone");

        /* dragging the selection by its border: a move adjusts references,
         * a copy leaves the source */
        GNM_ASSERT ([s setText:@"7" atColumn:9 row:9 autocorrect:NO error:&error] && [s setText:@"=J10*2" atColumn:10 row:9 autocorrect:NO error:&error], @"J10 K10: %@", error);
        [s selectRange:GnmCellRangeMake (9, 9, 10, 9) editPosition:GnmCellCoordinateMake (9, 9)];
        GNM_ASSERT ([s dropSelectionAtColumn:9 row:12 copying:NO error:&error], @"move: %@", error);
        GNM_ASSERT_EQ_STR ([s displayTextOfCellAtColumn:9 row:12] ?: @"", @"7");
        GNM_ASSERT_EQ_STR ([s enteredTextOfCellAtColumn:10 row:12] ?: @"", @"=J13*2");
        GNM_ASSERT ([s displayTextOfCellAtColumn:9 row:9] == nil || [[s displayTextOfCellAtColumn:9 row:9] isEqualToString:@""], @"source emptied: '%@'", [s displayTextOfCellAtColumn:9 row:9]);
        NSLog (@"editing: move undo label '%@'", wb.undoLabel);
        [wb undo];
        GNM_ASSERT_EQ_STR ([s displayTextOfCellAtColumn:9 row:9] ?: @"", @"7");
        GNM_ASSERT_EQ_STR ([s enteredTextOfCellAtColumn:10 row:9] ?: @"", @"=J10*2");
        [s selectRange:GnmCellRangeMake (9, 9, 10, 9) editPosition:GnmCellCoordinateMake (9, 9)];
        GNM_ASSERT ([s dropSelectionAtColumn:9 row:15 copying:YES error:&error], @"copy: %@", error);
        GNM_ASSERT_EQ_STR ([s displayTextOfCellAtColumn:9 row:15] ?: @"", @"7");
        GNM_ASSERT_EQ_STR ([s enteredTextOfCellAtColumn:10 row:15] ?: @"", @"=J16*2");
        GNM_ASSERT_EQ_STR ([s displayTextOfCellAtColumn:9 row:9] ?: @"", @"7");
        GNM_ASSERT ([s dropSelectionAtColumn:9 row:9 copying:NO error:&error], @"dropping where it is is nothing");
        error = nil;
        GNM_ASSERT (![s dropSelectionAtColumn:s.columnCount - 1 row:9 copying:NO error:&error] && [error.localizedDescription containsString:@"off the sheet"], @"off the sheet: %@", error);
        /* a refusal the engine reports: a cut that would split an array */
        [s selectRange:GnmCellRangeMake (12, 20, 12, 22) editPosition:GnmCellCoordinateMake (12, 20)];
        GNM_ASSERT ([s enterArrayFormula:@"={1;2;3}" error:&error], @"array: %@", error);
        [s selectRange:GnmCellRangeMake (12, 20, 12, 20) editPosition:GnmCellCoordinateMake (12, 20)];
        error = nil;
        BOOL split = [s dropSelectionAtColumn:12 row:25 copying:NO error:&error];
        NSLog (@"editing: moving part of an array -> %d (%@ / %@)", split, error.localizedDescription, error.localizedRecoverySuggestion);
        GNM_ASSERT (!split && error != nil, @"the engine's refusal comes back as the error");
        /* the last sheet of a workbook stays (a fresh one: the engine's undo
         * stack keeps only a limited number of commands) */
        @autoreleasepool {
            GnmWorkbook *fresh = [engine newWorkbookWithSheetCount:3];
            GNM_ASSERT (fresh.sheets.count == 3, @"fresh workbook has %lu sheets", (unsigned long) fresh.sheets.count);
            GNM_ASSERT ([fresh removeSheet:fresh.sheets.lastObject error:&error] && [fresh removeSheet:fresh.sheets.lastObject error:&error],
                        @"remove two: %@", error);
            GNM_ASSERT (!fresh.canRemoveSheets && ![fresh removeSheet:fresh.sheets.firstObject error:&error], @"the last sheet stays");
            GNM_ASSERT (error.code == GnmErrorCommandFailed, @"error %@", error);
        }

        /* merge and unmerge */
        [s selectRange:GnmCellRangeMake (50, 70, 52, 71) editPosition:GnmCellCoordinateMake (50, 70)];
        GNM_ASSERT (!s.selectionHasMergedCells, @"no merges yet");
        GNM_ASSERT ([s mergeSelectionCentered:NO error:&error], @"merge: %@", error);
        GNM_ASSERT (s.selectionHasMergedCells, @"merged");
        GNM_ASSERT ([s unmergeSelection:&error], @"unmerge: %@", error);
        GNM_ASSERT (!s.selectionHasMergedCells, @"unmerged");
        [wb undo];
        GNM_ASSERT (s.selectionHasMergedCells, @"undo of unmerge restores the merge");
        [wb undo];
        [wb recalculateAll];

        /* autofilter: a small table, the buttons, the choices, a value
         * condition hiding rows, show all, custom and bucket conditions,
         * the filtered clear, undo of the removal */
        {
            char const *names[] = { "Name", "apple", "pear", "apple", NULL, "kiwi" };
            char const *qtys[] = { "Qty", "3", "5", "7", "1", "9" };
            for (int i = 0; i < 6; i++) {
                if (names[i])
                    [s setText:@(names[i]) atColumn:0 row:200 + i autocorrect:NO error:NULL];
                [s setText:@(qtys[i]) atColumn:1 row:200 + i autocorrect:NO error:NULL];
            }
        }
        [s selectRange:GnmCellRangeMake (0, 200, 1, 205) editPosition:GnmCellCoordinateMake (0, 200)];
        GNM_ASSERT (!s.editPositionIsInFilter && s.filterButtons.count == 0, @"no filter yet");
        GNM_ASSERT ([s toggleAutofilter:&error], @"add filter: %@", error);
        GNM_ASSERT (s.editPositionIsInFilter, @"edit position in the filter");
        GNM_ASSERT ([wb.undoLabel containsString:@"Autofilter"], @"undo label '%@'", wb.undoLabel);
        GNM_ASSERT (s.filterButtons.count == 2, @"%lu buttons", (unsigned long) s.filterButtons.count);
        GnmFilterButton *nameButton = s.filterButtons[0];
        GNM_ASSERT (nameButton.cell.column == 0 && nameButton.cell.row == 200 && !nameButton.isActive, @"button at A201");
        GNM_ASSERT (nameButton.frame.size.width > 0 && nameButton.frame.size.width <= 20
                    && CGRectGetMaxX (nameButton.frame) == [s leftEdgeOfColumn:1], @"button frame %@", NSStringFromRect (nameButton.frame));
        GNM_ASSERT (nameButton.filterRange.end.row == 205, @"filter range");
        GnmFilterChoices *choices = [s choicesForFilterButton:nameButton];
        NSArray *expected = @[@"apple", @"kiwi", @"pear"];
        GNM_ASSERT ([choices.values isEqualToArray:expected] && choices.hasBlanks, @"choices %@", choices.values);
        GNM_ASSERT (choices.current.kind == GnmFilterConditionShowAll, @"no condition yet");
        GNM_ASSERT ([s setFilterCondition:[choices conditionForValueAtIndex:0] forButton:nameButton error:&error], @"value condition: %@", error);
        GNM_ASSERT (s.hasFilteredRows, @"rows filtered");
        GNM_ASSERT ([s isRowVisible:201] && ![s isRowVisible:202] && [s isRowVisible:203] && ![s isRowVisible:204] && ![s isRowVisible:205],
                    @"only the apples show: %d %d %d %d %d", [s isRowVisible:201], [s isRowVisible:202], [s isRowVisible:203],
                    [s isRowVisible:204], [s isRowVisible:205]);
        GNM_ASSERT ([wb.undoLabel containsString:@"filter"], @"undo label '%@'", wb.undoLabel);
        nameButton = s.filterButtons[0];
        GNM_ASSERT (nameButton.isActive, @"button active");
        choices = [s choicesForFilterButton:nameButton];
        GNM_ASSERT (choices.current.kind == GnmFilterConditionValue && choices.current.valueIndex == 0, @"current is apple: kind %ld index %ld",
                    (long) choices.current.kind, (long) choices.current.valueIndex);
        /* the other field lists only the rows this one leaves */
        GnmFilterChoices *qtyChoices = [s choicesForFilterButton:s.filterButtons[1]];
        GNM_ASSERT (([qtyChoices.values isEqualToArray:@[@"3", @"7"]]) && !qtyChoices.hasBlanks, @"qty choices %@", qtyChoices.values);
        [s showAllFilteredRows];   /* drops the condition */
        GNM_ASSERT (!s.hasFilteredRows && [s isRowVisible:202] && !s.filterButtons[0].isActive, @"show all");
        [wb undo];
        GNM_ASSERT (s.hasFilteredRows && ![s isRowVisible:202], @"show all undone");
        GNM_ASSERT ([s setFilterCondition:[GnmFilterCriterion showAll] forButton:s.filterButtons[0] error:&error], @"clear condition: %@", error);
        GNM_ASSERT (!s.hasFilteredRows, @"condition cleared");
        /* custom: Qty > 4 */
        GNM_ASSERT ([s setFilterCondition:[GnmFilterCriterion customWithOperator:GnmFilterOperatorGreaterThan text:@"4"]
                                forButton:s.filterButtons[1] error:&error], @"custom: %@", error);
        GNM_ASSERT (![s isRowVisible:201] && [s isRowVisible:202] && [s isRowVisible:203] && ![s isRowVisible:204] && [s isRowVisible:205],
                    @"qty > 4");
        GnmFilterCriterion *cond = [s choicesForFilterButton:s.filterButtons[1]].current;
        GNM_ASSERT (cond.kind == GnmFilterConditionCustom && cond.firstOperator == GnmFilterOperatorGreaterThan
                    && [cond.firstText isEqualToString:@"4"] && cond.secondOperator == GnmFilterOperatorNone,
                    @"custom read back: kind %ld op %ld '%@'", (long) cond.kind, (long) cond.firstOperator, cond.firstText);
        /* text operators travel as wildcards */
        GNM_ASSERT ([s setFilterCondition:[GnmFilterCriterion customWithOperator:GnmFilterOperatorBeginsWith text:@"ap" joinedWithAnd:NO
                                                                        operator:GnmFilterOperatorEquals text:@"kiwi"]
                                forButton:s.filterButtons[0] error:&error], @"begins with: %@", error);
        cond = [s choicesForFilterButton:s.filterButtons[0]].current;
        GNM_ASSERT (cond.kind == GnmFilterConditionCustom && cond.firstOperator == GnmFilterOperatorBeginsWith
                    && [cond.firstText isEqualToString:@"ap"] && !cond.joinedWithAnd && cond.secondOperator == GnmFilterOperatorEquals
                    && [cond.secondText isEqualToString:@"kiwi"], @"wildcards read back: op %ld '%@' / op %ld '%@'",
                    (long) cond.firstOperator, cond.firstText, (long) cond.secondOperator, cond.secondText);
        GNM_ASSERT ([s isRowVisible:203] && [s isRowVisible:205] && ![s isRowVisible:202], @"apple 7 and kiwi 9 show");
        /* bucket: the top 2 quantities */
        GNM_ASSERT ([s setFilterCondition:[GnmFilterCriterion showAll] forButton:s.filterButtons[0] error:&error], @"clear: %@", error);
        GNM_ASSERT ([s setFilterCondition:[GnmFilterCriterion bucketTop:YES count:2 percent:NO] forButton:s.filterButtons[1] error:&error], @"bucket: %@", error);
        GNM_ASSERT ([s isRowVisible:203] && [s isRowVisible:205] && ![s isRowVisible:201] && ![s isRowVisible:202] && ![s isRowVisible:204], @"top 2");
        cond = [s choicesForFilterButton:s.filterButtons[1]].current;
        GNM_ASSERT (cond.kind == GnmFilterConditionBucket && cond.isTop && !cond.isPercent && cond.count == 2, @"bucket read back");
        /* the filtered clear skips the rows the filter hides (commands.c
         * cmd_selection_clear_row_handler) */
        [s selectRange:GnmCellRangeMake (0, 201, 1, 205) editPosition:GnmCellCoordinateMake (0, 201)];
        GNM_ASSERT ([s clearSelection:GnmClearValues | GnmClearFilteredRowsOnly error:&error], @"filtered clear: %@", error);
        GNM_ASSERT ([[s displayTextOfCellAtColumn:0 row:202] isEqualToString:@"pear"] && [s displayTextOfCellAtColumn:0 row:203] == nil,
                    @"hidden pear kept, visible apple cleared: '%@' '%@'", [s displayTextOfCellAtColumn:0 row:202], [s displayTextOfCellAtColumn:0 row:203]);
        [wb undo];
        GNM_ASSERT_EQ_STR ([s displayTextOfCellAtColumn:0 row:203] ?: @"", @"apple");
        /* remove and undo */
        [s selectCellAtColumn:0 row:200];
        GNM_ASSERT ([s toggleAutofilter:&error], @"remove filter: %@", error);
        GNM_ASSERT (s.filterButtons.count == 0 && !s.editPositionIsInFilter && [s isRowVisible:201], @"filter removed");
        [wb undo];
        /* gnm_filter_attach recreates the fields, so the undo brings the
         * filter back without its conditions (the GTK front end too) */
        GNM_ASSERT (s.filterButtons.count == 2 && s.editPositionIsInFilter, @"removal undone: %lu buttons", (unsigned long) s.filterButtons.count);
        GNM_ASSERT ([s toggleAutofilter:&error], @"remove again: %@", error);
        GNM_ASSERT (![s setFilterCondition:[GnmFilterCriterion blanks:YES] forButton:nameButton error:&error], @"a stale button is refused");
        /* a sheet with no filter: the edit position decides what is added */
        [s selectCellAtColumn:0 row:200];
        GNM_ASSERT ([s toggleAutofilter:&error] && s.filterButtons.count == 2, @"one cell adds over the region: %@", error);
        GNM_ASSERT ([s toggleAutofilter:&error], @"remove: %@", error);

        /* sheet resize: powers of two only, undoable */
        NSInteger cols = s.columnCount, rows = s.rowCount;
        GNM_ASSERT ([GnmWorkbook isValidSheetSizeWithColumns:256 rows:65536] && ![GnmWorkbook isValidSheetSizeWithColumns:100 rows:65536], @"valid sizes");
        GNM_ASSERT (GnmWorkbook.minimumSheetColumns == 128 && GnmWorkbook.maximumSheetRows == 16777216, @"limits");
        GNM_ASSERT ([wb resizeSheets:@[s] toColumns:cols * 2 rows:rows * 2 error:&error], @"resize: %@", error);
        GNM_ASSERT (s.columnCount == cols * 2 && s.rowCount == rows * 2, @"now %ld x %ld", (long) s.columnCount, (long) s.rowCount);
        GNM_ASSERT ([wb.undoLabel containsString:@"Resizing"], @"undo label '%@'", wb.undoLabel);
        [wb undo];
        GNM_ASSERT (s.columnCount == cols && s.rowCount == rows, @"size back");
        GNM_ASSERT (![wb resizeSheets:@[s] toColumns:100 rows:rows error:&error], @"odd size refused");

        /* tab colors: set through the workbook, read on the sheet, undoable */
        CGColorRef initialTab = [s copyTabColor];   /* the sample may carry one */
        CGColorRef red = CGColorCreateSRGB (1, 0, 0, 1);
        CGColorRef blue = CGColorCreateSRGB (0, 0, 1, 1);
        [rec.events removeAllObjects];
        GNM_ASSERT ([wb setTabColor:red textColor:blue ofSheet:s error:&error], @"tab color: %@", error);
        CGColorRef got = [s copyTabColor];
        GNM_ASSERT (got != NULL && CGColorGetComponents (got)[0] > 0.99 && CGColorGetComponents (got)[1] < 0.01, @"tab color read back");
        if (got) CGColorRelease (got);
        got = [s copyTabTextColor];
        GNM_ASSERT (got != NULL && CGColorGetComponents (got)[2] > 0.99, @"tab text color read back");
        if (got) CGColorRelease (got);
        GNM_ASSERT ([rec.events containsObject:[@"sheet:" stringByAppendingString:s.name]], @"delegate saw the color: %@", rec.events);
        GNM_ASSERT ([wb setTabColor:NULL textColor:NULL ofSheet:s error:&error], @"clear tab color: %@", error);
        GNM_ASSERT ([s copyTabColor] == NULL, @"cleared");
        [wb undo];
        got = [s copyTabColor];
        GNM_ASSERT (got != NULL, @"undo restores the color");
        if (got) CGColorRelease (got);
        [wb undo];
        got = [s copyTabColor];
        GNM_ASSERT ((got == NULL) == (initialTab == NULL) && (got == NULL || CGColorEqualToColor (got, initialTab)), @"undo again restores the original");
        if (got) CGColorRelease (got);
        if (initialTab) CGColorRelease (initialTab);
        CGColorRelease (red);
        CGColorRelease (blue);

        /* the Sort dialog's command: keys, a heading, by rows and by columns */
        {
            char const *table[][2] = { { "N", "V" }, { "b", "2" }, { "c", "3" }, { "a", "1" } };
            for (int i = 0; i < 4; i++) {
                [s setText:@(table[i][0]) atColumn:90 row:110 + i autocorrect:NO error:NULL];
                [s setText:@(table[i][1]) atColumn:91 row:110 + i autocorrect:NO error:NULL];
            }
        }
        [s selectCellAtColumn:90 row:111];
        GnmCellRange region = s.sortableRange;
        GNM_ASSERT (region.start.column == 90 && region.start.row == 110 && region.end.column == 91 && region.end.row == 113,
                    @"region around the cell: %ld,%ld-%ld,%ld", (long) region.start.column, (long) region.start.row,
                    (long) region.end.column, (long) region.end.row);
        NSLog (@"heading detected: %d", [s range:region hasHeadingByRows:YES]);
        NSString *keyName = [s sortKeyNameForIndex:91 inRange:region byRows:YES hasHeader:YES];
        GNM_ASSERT ([keyName hasPrefix:@"V ("] && [keyName hasSuffix:@"Column CN)"], @"key name '%@'", keyName);
        GNM_ASSERT_EQ_STR ([s sortKeyNameForIndex:91 inRange:region byRows:YES hasHeader:NO], @"Column CN");
        GnmSortKey *byV = [[GnmSortKey alloc] initWithIndex:91 descending:NO caseSensitive:NO byValue:YES];
        GNM_ASSERT ([s sortRange:region byRows:YES hasHeader:YES keys:@[byV] retainFormats:YES error:&error], @"sort by V: %@", error);
        GNM_ASSERT_EQ_STR ([s displayTextOfCellAtColumn:90 row:110] ?: @"", @"N");   /* heading kept */
        GNM_ASSERT_EQ_STR ([s displayTextOfCellAtColumn:90 row:111] ?: @"", @"a");
        GNM_ASSERT_EQ_STR ([s displayTextOfCellAtColumn:91 row:113] ?: @"", @"3");
        GnmSortKey *byN = [[GnmSortKey alloc] initWithIndex:90 descending:YES caseSensitive:YES byValue:YES];
        GNM_ASSERT ([s sortRange:region byRows:YES hasHeader:YES keys:(@[byN, byV]) retainFormats:NO error:&error], @"sort by N desc: %@", error);
        GNM_ASSERT_EQ_STR ([s displayTextOfCellAtColumn:90 row:111] ?: @"", @"c");
        GNM_ASSERT (![s sortRange:region byRows:YES hasHeader:YES keys:@[] retainFormats:YES error:&error], @"no keys refused");
        /* the locale's collation, and more than three keys */
        GNM_ASSERT ([s sortRange:region byRows:YES hasHeader:YES keys:@[byV] retainFormats:YES locale:@"C" error:&error], @"sort in C: %@", error);
        NSArray *four = @[byN, byV, byN, byV];
        GNM_ASSERT ([s sortRange:region byRows:YES hasHeader:YES keys:four retainFormats:YES locale:@"en_US.UTF-8" error:&error], @"four keys: %@", error);
        NSLog (@"sort with a locale and four keys: undo '%@'", wb.undoLabel);
        /* by columns: a row of keys */
        [s setText:@"x" atColumn:95 row:120 autocorrect:NO error:NULL];
        [s setText:@"z" atColumn:96 row:120 autocorrect:NO error:NULL];
        [s setText:@"y" atColumn:97 row:120 autocorrect:NO error:NULL];
        [s setText:@"2" atColumn:95 row:121 autocorrect:NO error:NULL];
        [s setText:@"3" atColumn:96 row:121 autocorrect:NO error:NULL];
        [s setText:@"1" atColumn:97 row:121 autocorrect:NO error:NULL];
        GnmSortKey *byRow = [[GnmSortKey alloc] initWithIndex:121 descending:NO caseSensitive:NO byValue:YES];
        GNM_ASSERT ([s sortRange:GnmCellRangeMake (95, 120, 97, 121) byRows:NO hasHeader:NO keys:@[byRow] retainFormats:YES error:&error],
                    @"sort by columns: %@", error);
        GNM_ASSERT_EQ_STR ([s displayTextOfCellAtColumn:95 row:120] ?: @"", @"y");
        GNM_ASSERT_EQ_STR ([s displayTextOfCellAtColumn:97 row:120] ?: @"", @"z");
        GNM_ASSERT_EQ_STR ([s sortKeyNameForIndex:121 inRange:GnmCellRangeMake (95, 120, 97, 121) byRows:NO hasHeader:NO], @"Row 122");
        NSLog (@"sort defaults: case %d formats %d ascending %d", GnmSheet.sortDefaultsToCaseSensitive,
               GnmSheet.sortDefaultsToRetainingFormats, GnmSheet.sortDefaultsToAscending);

        /* save the edited file and reopen */
        [s setText:@"saved" atColumn:3 row:3 autocorrect:NO error:NULL];
        NSURL *out = [NSURL fileURLWithPath:[gnm_test_env ("GNM_TEST_OUT") stringByAppendingPathComponent:@"bridge-edited.gnumeric"]];
        GNM_ASSERT ([wb writeToURL:out error:&error], @"save: %@", error);
        GNM_ASSERT (!wb.isModified, @"clean after save");
        wb = nil; s = nil;
        GnmWorkbook *back = [engine openWorkbookAtURL:out error:&error];
        GNM_ASSERT (back && [[back.sheets.firstObject displayTextOfCellAtColumn:3 row:3] isEqualToString:@"saved"], @"edit survived the round trip");
        back = nil;
        GNM_ASSERT (stray.count == 0, @"stray engine messages: %@", stray);
      }
        [engine shutdown];
    }
    return gnm_test_finish ("editing");
}
