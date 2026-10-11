// Editing through the engine's commands: set text, undo and redo with
// labels, dirty tracking, clear, insert and delete, and the two paths that
// patches/0001 decouples from GTK (an insert that would push data off the
// sheet, and a hide-all question answered by the delegate).
#import "GnmTest.h"

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
