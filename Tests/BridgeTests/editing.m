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
