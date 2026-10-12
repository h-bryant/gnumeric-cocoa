// Cell comments through the engine's command: set, read back, listed in
// a range, changed, removed, undone and redone, and cleared with the
// selection's comments.
#import "GnmTest.h"

@interface CommentRecorder : NSObject <GnmSheetDelegate>
@property (nonatomic) NSInteger objectChanges;
@end
@implementation CommentRecorder
- (void)sheetObjectsDidChange:(GnmSheet *)sheet { _objectChanges++; }
@end

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
        CommentRecorder *rec = [[CommentRecorder alloc] init];
        s.delegate = rec;
        GNM_ASSERT ([s commentAtColumn:2 row:2] == nil, @"no comment yet");
        GNM_ASSERT ([s commentsInRange:GnmCellRangeMake (0, 0, 10, 10)].count == 0, @"none in range");

        /* set */
        GNM_ASSERT ([s setCommentText:@"Check this" author:@"Tester" atColumn:2 row:2 error:&error], @"set: %@", error);
        GNM_ASSERT (rec.objectChanges > 0, @"the sheet reported its objects changed");
        GnmCellComment *c = [s commentAtColumn:2 row:2];
        GNM_ASSERT (c != nil, @"comment set");
        GNM_ASSERT_EQ_STR (c.text, @"Check this");
        GNM_ASSERT_EQ_STR (c.author, @"Tester");
        GNM_ASSERT (c.column == 2 && c.row == 2, @"position %ld,%ld", (long) c.column, (long) c.row);
        GNM_ASSERT_EQ_STR (wb.undoLabel ?: @"", @"Setting comment of C3");
        GNM_ASSERT (wb.isModified, @"dirty");

        /* listed by range, anchored cell only */
        GNM_ASSERT ([s commentsInRange:GnmCellRangeMake (0, 0, 10, 10)].count == 1, @"one in range");
        GNM_ASSERT ([s commentsInRange:GnmCellRangeMake (2, 2, 2, 2)].count == 1, @"the cell itself");
        GNM_ASSERT ([s commentsInRange:GnmCellRangeMake (3, 3, 10, 10)].count == 0, @"not beyond");
        GNM_ASSERT ([s commentAtColumn:3 row:2] == nil, @"the neighbor has none");

        /* change */
        GNM_ASSERT ([s setCommentText:@"Checked" author:@"Tester 2" atColumn:2 row:2 error:&error], @"change: %@", error);
        GNM_ASSERT_EQ_STR ([s commentAtColumn:2 row:2].text, @"Checked");
        GNM_ASSERT_EQ_STR ([s commentAtColumn:2 row:2].author, @"Tester 2");
        [wb undo];
        GNM_ASSERT_EQ_STR ([s commentAtColumn:2 row:2].text, @"Check this");
        [wb redo];
        GNM_ASSERT_EQ_STR ([s commentAtColumn:2 row:2].text, @"Checked");

        /* a second one, found by the search */
        GNM_ASSERT ([s setText:@"value" atColumn:0 row:0 autocorrect:NO error:&error], @"A1: %@", error);
        GNM_ASSERT ([s setCommentText:@"first cell" author:@"Tester" atColumn:0 row:0 error:&error], @"set A1: %@", error);
        GNM_ASSERT ([s commentsInRange:GnmCellRangeMake (0, 0, 10, 10)].count == 2, @"two in range");
        GnmSearchOptions *o = [[GnmSearchOptions alloc] init];
        o.searchText = @"first";
        o.searchesComments = YES;
        o.scope = GnmSearchScopeSheet;
        NSArray<GnmSearchMatch *> *m = [wb findMatches:o inSheet:s error:&error];
        GNM_ASSERT (m.count == 1 && m.firstObject.locus == GnmSearchMatchComment, @"found by comment: %@", m);

        /* remove with empty text, and with the selection's clear */
        GNM_ASSERT ([s setCommentText:@"" author:nil atColumn:2 row:2 error:&error], @"remove: %@", error);
        GNM_ASSERT ([s commentAtColumn:2 row:2] == nil, @"removed");
        GNM_ASSERT_EQ_STR (wb.undoLabel ?: @"", @"Clearing comment of C3");
        [wb undo];
        GNM_ASSERT_EQ_STR ([s commentAtColumn:2 row:2].text ?: @"", @"Checked");
        [wb redo];
        GNM_ASSERT ([s commentAtColumn:2 row:2] == nil, @"removed again");
        [s selectCellAtColumn:0 row:0];
        GNM_ASSERT ([s clearSelection:GnmClearComments error:&error], @"clear comments: %@", error);
        GNM_ASSERT ([s commentAtColumn:0 row:0] == nil, @"cleared with the selection");
        GNM_ASSERT_EQ_STR ([s displayTextOfCellAtColumn:0 row:0], @"value");
        [wb undo];
        GNM_ASSERT_EQ_STR ([s commentAtColumn:0 row:0].text ?: @"", @"first cell");

        GNM_ASSERT (stray.count == 0, @"stray messages: %@", stray);
        wb = nil;
      }
        [engine shutdown];
        return gnm_test_finish ("comments");
    }
}
