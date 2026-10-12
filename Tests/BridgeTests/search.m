// Find and Replace through the engine's search: the options' effects
// (case, whole words, regular expressions, numbers, scopes, ranges,
// cell kinds, comments, visiting order), the matches' descriptions, and
// the replace command with its query handler, error behaviors, string
// keeping, undo and redo.
#import "GnmTest.h"
#import "../../Sources/Bridge/GnmPrivate.h"   /* a comment set straight in the engine */

static NSArray<NSString *> *
references (NSArray<GnmSearchMatch *> *matches)
{
    NSMutableArray *refs = [NSMutableArray array];
    for (GnmSearchMatch *m in matches)
        [refs addObject:m.reference];
    return refs;
}

static NSString *
joined (NSArray<GnmSearchMatch *> *matches)
{
    return [references (matches) componentsJoinedByString:@","];
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
        GnmSheet *s1 = wb.sheets[0], *s2 = wb.sheets[1];
        [wb selectSheet:s1];
        /* Sheet1: strings, a number, an expression, a quoted number, a
         * comment, and two "x" cells for the visiting order. */
        GNM_ASSERT ([s1 setText:@"apple" atColumn:0 row:0 autocorrect:NO error:&error], @"A1: %@", error);
        GNM_ASSERT ([s1 setText:@"Apple pie" atColumn:0 row:1 autocorrect:NO error:&error], @"A2: %@", error);
        GNM_ASSERT ([s1 setText:@"=1+1" atColumn:1 row:0 autocorrect:NO error:&error], @"B1: %@", error);
        GNM_ASSERT ([s1 setText:@"2" atColumn:1 row:1 autocorrect:NO error:&error], @"B2: %@", error);
        GNM_ASSERT ([s1 setText:@"banana" atColumn:2 row:0 autocorrect:NO error:&error], @"C1: %@", error);
        GNM_ASSERT ([s1 setText:@"'12" atColumn:0 row:2 autocorrect:NO error:&error], @"A3: %@", error);
        GNM_ASSERT ([s1 setText:@"x" atColumn:1 row:2 autocorrect:NO error:&error], @"B3: %@", error);
        GNM_ASSERT ([s1 setText:@"x" atColumn:0 row:3 autocorrect:NO error:&error], @"A4: %@", error);
        GNM_ASSERT ([s2 setText:@"apple" atColumn:0 row:0 autocorrect:NO error:&error], @"Sheet2!A1: %@", error);
        {
            GnmCellPos pos = { 2, 1 };
            cell_set_comment (s1.engineSheet, &pos, "tester", "see apple", NULL);
        }
        NSString *baseline = wb.undoLabel;

        GnmSearchOptions *o = [[GnmSearchOptions alloc] init];
        GNM_ASSERT (o.scope == GnmSearchScopeWorkbook && o.ignoresCase && o.keepsStrings && !o.byRow
                    && o.searchesExpressionResults && !o.searchesComments, @"GTK defaults");
        o.scope = GnmSearchScopeSheet;

        /* plain, ignoring case, column major */
        o.searchText = @"apple";
        NSArray<GnmSearchMatch *> *m = [wb findMatches:o inSheet:s1 error:&error];
        GNM_ASSERT (m != nil, @"find: %@", error);
        GNM_ASSERT_EQ_STR (joined (m), @"Sheet1!A1,Sheet1!A2");
        GNM_ASSERT (m.firstObject.sheet == s1 && m.firstObject.column == 0 && m.firstObject.row == 0, @"first match position");
        GNM_ASSERT_EQ_STR (m.firstObject.cellName, @"A1");
        GNM_ASSERT_EQ_STR (m.firstObject.kindDescription, @"String");
        GNM_ASSERT_EQ_STR (m.lastObject.contents, @"Apple pie");
        GNM_ASSERT (m.firstObject.locus == GnmSearchMatchContents, @"contents locus");

        /* case */
        o.ignoresCase = NO;
        o.searchText = @"Apple";
        m = [wb findMatches:o inSheet:s1 error:&error];
        GNM_ASSERT_EQ_STR (joined (m), @"Sheet1!A2");
        o.ignoresCase = YES;

        /* whole words */
        o.searchText = @"appl";
        GNM_ASSERT ([wb findMatches:o inSheet:s1 error:&error].count == 2, @"partial word");
        o.matchesWholeWords = YES;
        GNM_ASSERT ([wb findMatches:o inSheet:s1 error:&error].count == 0, @"whole words only");
        o.matchesWholeWords = NO;

        /* regular expression */
        o.textKind = GnmSearchTextRegularExpression;
        o.searchText = @"^a.*e$";
        m = [wb findMatches:o inSheet:s1 error:&error];
        GNM_ASSERT_EQ_STR (joined (m), @"Sheet1!A1,Sheet1!A2");   /* "Apple pie" too, ignoring case */
        o.ignoresCase = NO;
        GNM_ASSERT_EQ_STR (joined ([wb findMatches:o inSheet:s1 error:&error]), @"Sheet1!A1");
        o.ignoresCase = YES;
        o.searchText = @"(";
        GNM_ASSERT ([wb findMatches:o inSheet:s1 error:&error] == nil && error != nil, @"bad pattern is an error");
        NSLog (@"bad pattern: %@", error.localizedDescription);
        o.textKind = GnmSearchTextPlain;

        /* scopes */
        o.searchText = @"apple";
        o.scope = GnmSearchScopeWorkbook;
        m = [wb findMatches:o inSheet:s1 error:&error];
        GNM_ASSERT_EQ_STR (joined (m), @"Sheet1!A1,Sheet1!A2,Sheet2!A1");
        GNM_ASSERT (m.lastObject.sheet == s2, @"the third match is on sheet 2");
        o.scope = GnmSearchScopeRange;
        o.rangeText = @"A1:A1";
        GNM_ASSERT_EQ_STR (joined ([wb findMatches:o inSheet:s1 error:&error]), @"Sheet1!A1");
        o.rangeText = @"Sheet2!A1:B2";
        GNM_ASSERT_EQ_STR (joined ([wb findMatches:o inSheet:s1 error:&error]), @"Sheet2!A1");
        o.rangeText = @"nonsense";
        error = nil;
        GNM_ASSERT ([wb findMatches:o inSheet:s1 error:&error] == nil && error != nil, @"a bad range is an error");
        NSLog (@"bad range: %@", error.localizedDescription);
        o.scope = GnmSearchScopeSheet;

        /* comments */
        o.searchesComments = YES;
        m = [wb findMatches:o inSheet:s1 error:&error];
        GNM_ASSERT_EQ_STR (joined (m), @"Sheet1!A1,Sheet1!A2,Sheet1!C2");
        GNM_ASSERT (m.lastObject.locus == GnmSearchMatchComment, @"comment locus");
        GNM_ASSERT_EQ_STR (m.lastObject.kindDescription, @"Comment");
        GNM_ASSERT_EQ_STR (m.lastObject.contents, @"see apple");
        o.searchesComments = NO;

        /* kinds: a quoted number's string, an expression's result, a number */
        o.searchText = @"2";
        m = [wb findMatches:o inSheet:s1 error:&error];
        GNM_ASSERT_EQ_STR (joined (m), @"Sheet1!A3,Sheet1!B1,Sheet1!B2");
        GNM_ASSERT_EQ_STR (m[0].kindDescription, @"String");
        GNM_ASSERT (m[1].locus == GnmSearchMatchResult, @"B1 matched by its result");
        GNM_ASSERT_EQ_STR (m[1].kindDescription, @"Result");
        GNM_ASSERT_EQ_STR (m[1].contents, @"2");
        GNM_ASSERT_EQ_STR (m[2].kindDescription, @"Number");
        o.searchesExpressionResults = NO;
        GNM_ASSERT_EQ_STR (joined ([wb findMatches:o inSheet:s1 error:&error]), @"Sheet1!A3,Sheet1!B2");
        o.searchesExpressionResults = YES;
        o.searchesStrings = NO;
        GNM_ASSERT_EQ_STR (joined ([wb findMatches:o inSheet:s1 error:&error]), @"Sheet1!B1,Sheet1!B2");
        o.searchesStrings = YES;
        o.searchText = @"1+1";
        GNM_ASSERT_EQ_STR (joined ([wb findMatches:o inSheet:s1 error:&error]), @"Sheet1!B1");
        GNM_ASSERT_EQ_STR ([wb findMatches:o inSheet:s1 error:&error].firstObject.kindDescription, @"Expression");
        GNM_ASSERT_EQ_STR ([wb findMatches:o inSheet:s1 error:&error].firstObject.contents, @"=1+1");

        /* a number: values equal to it, not strings containing it */
        o.textKind = GnmSearchTextNumber;
        o.searchText = @"2";
        m = [wb findMatches:o inSheet:s1 error:&error];
        GNM_ASSERT (m != nil, @"number find: %@", error);
        GNM_ASSERT ([references (m) containsObject:@"Sheet1!B2"] && ![references (m) containsObject:@"Sheet1!A3"],
                    @"number search: %@", joined (m));
        o.textKind = GnmSearchTextPlain;

        /* visiting order */
        o.searchText = @"x";
        GNM_ASSERT_EQ_STR (joined ([wb findMatches:o inSheet:s1 error:&error]), @"Sheet1!A4,Sheet1!B3");
        o.byRow = YES;
        GNM_ASSERT_EQ_STR (joined ([wb findMatches:o inSheet:s1 error:&error]), @"Sheet1!B3,Sheet1!A4");
        o.byRow = NO;

        /* nothing to look at */
        o.searchesStrings = o.searchesOtherValues = o.searchesExpressions = o.searchesExpressionResults = NO;
        error = nil;
        GNM_ASSERT ([wb findMatches:o inSheet:s1 error:&error] == nil && error != nil, @"no cell types is an error");
        o.searchesStrings = o.searchesOtherValues = o.searchesExpressions = o.searchesExpressionResults = YES;

        /* replace: every match, undo and redo as one command */
        o.searchText = @"apple";
        o.replaceText = @"pear";
        GNM_ASSERT ([wb replaceMatches:o inSheet:s1 queryHandler:nil error:&error], @"replace: %@", error);
        GNM_ASSERT_EQ_STR (wb.undoLabel, @"Search and Replace");
        GNM_ASSERT_EQ_STR ([s1 displayTextOfCellAtColumn:0 row:0], @"pear");
        GNM_ASSERT_EQ_STR ([s1 displayTextOfCellAtColumn:0 row:1], @"pear pie");
        GNM_ASSERT_EQ_STR ([s2 displayTextOfCellAtColumn:0 row:0], @"apple");   /* sheet scope */
        [wb undo];
        GNM_ASSERT_EQ_STR ([s1 displayTextOfCellAtColumn:0 row:0], @"apple");
        GNM_ASSERT_EQ_STR ([s1 displayTextOfCellAtColumn:0 row:1], @"Apple pie");
        [wb redo];
        GNM_ASSERT_EQ_STR ([s1 displayTextOfCellAtColumn:0 row:1], @"pear pie");
        [wb undo];

        /* preserving case */
        o.preservesCase = YES;
        GNM_ASSERT ([wb replaceMatches:o inSheet:s1 queryHandler:nil error:&error], @"replace preserving case: %@", error);
        GNM_ASSERT_EQ_STR ([s1 displayTextOfCellAtColumn:0 row:1], @"Pear pie");
        [wb undo];
        o.preservesCase = NO;

        /* the query handler: skip, replace and stop asking, then cancel */
        o.scope = GnmSearchScopeWorkbook;
        o.asksBeforeEachChange = YES;
        NSMutableArray<NSString *> *asked = [NSMutableArray array];
        GnmSearchQueryHandler skipThenStop = ^GnmSearchQueryAnswer (GnmSearchQuery *q) {
            [asked addObject:[NSString stringWithFormat:@"%@:%@>%@", q.location, q.currentText, q.replacementText]];
            if (asked.count == 1)
                return GnmSearchQuerySkip;
            q.asksAgain = NO;
            return GnmSearchQueryReplace;
        };
        BOOL replaced = [wb replaceMatches:o inSheet:s1 queryHandler:skipThenStop error:&error];
        GNM_ASSERT (replaced, @"replace with queries: %@", error);
        /* the quote: a kept string's replacement is typed as text, as the
         * GTK query dialog shows it */
        GNM_ASSERT_EQ_STR ([asked componentsJoinedByString:@" "], @"Sheet1!A1:apple>'pear Sheet1!A2:Apple pie>'pear pie");
        GNM_ASSERT_EQ_STR ([s1 displayTextOfCellAtColumn:0 row:0], @"apple");
        GNM_ASSERT_EQ_STR ([s1 displayTextOfCellAtColumn:0 row:1], @"pear pie");
        GNM_ASSERT_EQ_STR ([s2 displayTextOfCellAtColumn:0 row:0], @"pear");   /* no longer asked */
        [wb undo];
        GNM_ASSERT_EQ_STR ([s2 displayTextOfCellAtColumn:0 row:0], @"apple");
        [asked removeAllObjects];
        GnmSearchQueryHandler replaceThenCancel = ^GnmSearchQueryAnswer (GnmSearchQuery *q) {
            [asked addObject:q.location];
            return asked.count == 1 ? GnmSearchQueryReplace : GnmSearchQueryCancel;
        };
        replaced = [wb replaceMatches:o inSheet:s1 queryHandler:replaceThenCancel error:&error];
        GNM_ASSERT (replaced, @"cancelled replace keeps its changes: %@", error);
        GNM_ASSERT (asked.count == 2, @"asked twice, then stopped: %@", asked);
        GNM_ASSERT_EQ_STR ([s1 displayTextOfCellAtColumn:0 row:0], @"pear");
        GNM_ASSERT_EQ_STR ([s1 displayTextOfCellAtColumn:0 row:1], @"Apple pie");
        GNM_ASSERT_EQ_STR ([s2 displayTextOfCellAtColumn:0 row:0], @"apple");
        [wb undo];
        GNM_ASSERT_EQ_STR ([s1 displayTextOfCellAtColumn:0 row:0], @"apple");
        o.asksBeforeEachChange = NO;
        o.scope = GnmSearchScopeSheet;

        /* a comment (the sheet and workbook scopes visit comment-only
         * cells; a range scope visits cells with content only) */
        o.searchesComments = YES;
        GNM_ASSERT ([wb replaceMatches:o inSheet:s1 queryHandler:nil error:&error], @"replace in a comment: %@", error);
        m = [wb findMatches:o inSheet:s1 error:&error];
        GNM_ASSERT (m.count == 0, @"nothing matches any more: %@", joined (m));
        o.searchText = @"pear";
        m = [wb findMatches:o inSheet:s1 error:&error];
        GNM_ASSERT_EQ_STR (joined (m), @"Sheet1!A1,Sheet1!A2,Sheet1!C2");
        GNM_ASSERT (m.lastObject.locus == GnmSearchMatchComment, @"the comment changed: %@", joined (m));
        GNM_ASSERT_EQ_STR (m.lastObject.contents, @"see pear");
        [wb undo];
        o.searchText = @"apple";
        o.searchesComments = NO;

        /* error behaviors: a replacement that does not parse (a kept string
         * never fails to parse, so strings are not kept here) */
        NSString *before = wb.undoLabel;
        o.searchText = @"banana";
        o.replaceText = @"=1+";
        o.keepsStrings = NO;
        o.errorBehavior = GnmSearchErrorFail;
        error = nil;
        GNM_ASSERT (![wb replaceMatches:o inSheet:s1 queryHandler:nil error:&error] && error != nil, @"fail stops");
        GNM_ASSERT ([error.localizedDescription containsString:@"In cell C1"], @"names the cell: %@", error.localizedDescription);
        GNM_ASSERT_EQ_STR ([s1 displayTextOfCellAtColumn:2 row:0], @"banana");
        GNM_ASSERT ([wb.undoLabel ?: @"" isEqualToString:before ?: @""], @"nothing registered: %@", wb.undoLabel);
        o.errorBehavior = GnmSearchErrorSkip;
        GNM_ASSERT ([wb replaceMatches:o inSheet:s1 queryHandler:nil error:&error], @"skip: %@", error);
        GNM_ASSERT_EQ_STR ([s1 displayTextOfCellAtColumn:2 row:0], @"banana");
        o.errorBehavior = GnmSearchErrorMakeString;
        GNM_ASSERT ([wb replaceMatches:o inSheet:s1 queryHandler:nil error:&error], @"make string: %@", error);
        GNM_ASSERT_EQ_STR ([s1 displayTextOfCellAtColumn:2 row:0], @"=1+");
        GNM_ASSERT (![s1 cellHasFormulaAtColumn:2 row:0], @"a string, not a formula");
        [wb undo];
        o.errorBehavior = GnmSearchErrorMakeError;
        GNM_ASSERT ([wb replaceMatches:o inSheet:s1 queryHandler:nil error:&error], @"make error: %@", error);
        GNM_ASSERT ([s1 cellHasFormulaAtColumn:2 row:0], @"an ERROR() formula");
        NSLog (@"make error: C1 = %@ / %@", [s1 enteredTextOfCellAtColumn:2 row:0], [s1 displayTextOfCellAtColumn:2 row:0]);
        [wb undo];
        GNM_ASSERT_EQ_STR ([s1 displayTextOfCellAtColumn:2 row:0], @"banana");
        o.errorBehavior = GnmSearchErrorFail;
        o.keepsStrings = YES;

        /* strings stay strings, or not */
        o.searchText = @"12";
        o.replaceText = @"13";
        o.scope = GnmSearchScopeRange;
        o.rangeText = @"A3";
        GNM_ASSERT ([wb replaceMatches:o inSheet:s1 queryHandler:nil error:&error], @"keep strings: %@", error);
        o.searchText = @"13";
        m = [wb findMatches:o inSheet:s1 error:&error];
        GNM_ASSERT (m.count == 1, @"13 found: %@", joined (m));
        GNM_ASSERT_EQ_STR (m.firstObject.kindDescription, @"String");
        [wb undo];
        o.keepsStrings = NO;
        o.searchText = @"12";
        GNM_ASSERT ([wb replaceMatches:o inSheet:s1 queryHandler:nil error:&error], @"not keeping strings: %@", error);
        o.searchText = @"13";
        m = [wb findMatches:o inSheet:s1 error:&error];
        GNM_ASSERT (m.count == 1, @"13 found again: %@", joined (m));
        GNM_ASSERT_EQ_STR (m.firstObject.kindDescription, @"Number");
        [wb undo];
        o.keepsStrings = YES;

        /* the sheet's selection text and revealing a cell */
        [s1 selectRange:GnmCellRangeMake (0, 0, 1, 1) editPosition:GnmCellCoordinateMake (0, 0)];
        GNM_ASSERT_EQ_STR (s1.selectionText, @"Sheet1!$A$1:$B$2");   /* absolute, as the GTK Range field is filled */
        [s2 revealCellAtColumn:2 row:3];
        GNM_ASSERT (wb.currentSheet == s2, @"revealing focuses the sheet");
        GNM_ASSERT (s2.editPosition.column == 2 && s2.editPosition.row == 3, @"edit position moved");
        GNM_ASSERT_EQ_STR (s2.selectionText, @"Sheet2!$C$4");

        /* back where it started */
        while (wb.canUndo && ![wb.undoLabel ?: @"" isEqualToString:baseline ?: @""])
            [wb undo];
        GNM_ASSERT_EQ_STR ([s1 displayTextOfCellAtColumn:0 row:0], @"apple");
        GNM_ASSERT (stray.count == 0, @"stray messages: %@", stray);
      }
        [engine shutdown];
        return gnm_test_finish ("search");
    }
}
