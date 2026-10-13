// Tools → Compare Sheets: the differences of two sheets as the GTK dialog
// lists them.
#import "GnmTest.h"

static GnmSheetDifference *
section (NSArray<GnmSheetDifference *> *tree, GnmDifferenceSection s)
{
    for (GnmSheetDifference *d in tree)
        if (d.section == s && d.direction == GnmDifferenceDirectionNone)
            return d;
    return nil;
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
        GnmSheet *old = wb.sheets[0], *new = wb.sheets[1];
        /* the same content on both, then differences on the new one */
        for (GnmSheet *s in @[old, new]) {
            GNM_ASSERT ([s setText:@"same" atColumn:0 row:0 autocorrect:NO error:&error], @"same: %@", error);
            GNM_ASSERT ([s setText:@"10" atColumn:1 row:0 autocorrect:NO error:&error], @"ten: %@", error);
            GNM_ASSERT ([s setText:@"gone" atColumn:2 row:2 autocorrect:NO error:&error], @"gone: %@", error);
        }
        GNM_ASSERT ([new differencesFromSheet:old].count == 0, @"equal sheets differ: %@", [new differencesFromSheet:old]);

        GNM_ASSERT ([new setText:@"=B1*2" atColumn:1 row:0 autocorrect:NO error:&error], @"changed: %@", error);
        GNM_ASSERT ([new setText:@"extra" atColumn:1 row:1 autocorrect:NO error:&error], @"added: %@", error);
        /* selection commands act on the focused sheet: reveal focuses */
        [new revealCellAtColumn:2 row:2];
        GNM_ASSERT ([new clearSelection:GnmClearValues error:&error], @"removed: %@", error);
        [new revealCellAtColumn:3 row:0];
        GnmCellFormat *bold = [[GnmCellFormat alloc] init];
        bold.bold = @YES;
        GNM_ASSERT ([new applyFormat:bold error:&error], @"bold: %@", error);
        [new revealCellAtColumn:3 row:1];
        GnmCellFormat *both = [[GnmCellFormat alloc] init];
        both.italic = @YES;
        both.underline = @(GnmUnderlineStyleDouble);
        GNM_ASSERT ([new applyFormat:both error:&error], @"italic and underline: %@", error);
        [new revealCellAtColumn:4 row:0];
        GNM_ASSERT ([new setSelectedColumns:YES sizeInPoints:120 error:&error], @"width: %@", error);

        NSArray<GnmSheetDifference *> *tree = [new differencesFromSheet:old];
        NSLog (@"tree: %@", tree);
        GnmSheetDifference *cells = section (tree, GnmDifferenceSectionCells);
        GnmSheetDifference *formatting = section (tree, GnmDifferenceSectionFormatting);
        GnmSheetDifference *colrow = section (tree, GnmDifferenceSectionColumnsRows);
        GNM_ASSERT (cells && formatting && colrow, @"three sections: %@", tree);
        GNM_ASSERT_EQ_STR (cells.text, @"Cells");
        GNM_ASSERT (cells.children.count == 3, @"three cell differences: %@", cells.children);
        NSMutableDictionary *byLocation = [NSMutableDictionary dictionary];
        for (GnmSheetDifference *d in cells.children)
            byLocation[d.location] = d;
        GnmSheetDifference *changed = byLocation[@"B1"], *added = byLocation[@"B2"], *removed = byLocation[@"C3"];
        GNM_ASSERT (changed.direction == GnmDifferenceDirectionChanged && added.direction == GnmDifferenceDirectionAdded
                    && removed.direction == GnmDifferenceDirectionRemoved, @"directions: %@", cells.children);
        GNM_ASSERT_EQ_STR (changed.text, @"Changed");
        GNM_ASSERT_EQ_STR (changed.beforeText, @"10");
        GNM_ASSERT_EQ_STR (changed.afterText, @"=B1*2");
        GNM_ASSERT (changed.beforeSheet == old && changed.afterSheet == new && changed.afterRange.start.column == 1, @"changed places");
        GNM_ASSERT (added.beforeSheet == nil && added.afterSheet == new, @"added has only a new place");
        GNM_ASSERT_EQ_STR (added.afterText, @"extra");
        GNM_ASSERT (removed.beforeSheet == old && removed.afterSheet == nil, @"removed has only an old place");
        GNM_ASSERT_EQ_STR (removed.beforeText, @"gone");

        GNM_ASSERT (formatting.children.count == 2, @"two formatting ranges: %@", formatting.children);
        GnmSheetDifference *boldDiff = nil, *various = nil;
        for (GnmSheetDifference *d in formatting.children) {
            if ([d.text isEqualToString:@"Bold"]) boldDiff = d;
            if ([d.text isEqualToString:@"Various"]) various = d;
        }
        GNM_ASSERT (boldDiff && various, @"a single-element and a various entry: %@", formatting.children);
        GNM_ASSERT_EQ_STR (boldDiff.location, @"D1");
        GNM_ASSERT_EQ_STR (boldDiff.beforeText, @"No");
        GNM_ASSERT_EQ_STR (boldDiff.afterText, @"Yes");
        GNM_ASSERT_EQ_STR (various.location, @"D2");
        GNM_ASSERT (various.children.count == 2, @"two elements under Various: %@", various.children);
        GNM_ASSERT_EQ_STR (various.children[0].text, @"Italic");
        GNM_ASSERT_EQ_STR (various.children[1].text, @"Underline");
        GNM_ASSERT_EQ_STR (various.children[1].beforeText, @"None");
        GNM_ASSERT_EQ_STR (various.children[1].afterText, @"Double");

        GNM_ASSERT (colrow.children.count == 1, @"one size difference: %@", colrow.children);
        GNM_ASSERT_EQ_STR (colrow.children[0].text, @"Size");
        GNM_ASSERT_EQ_STR (colrow.children[0].location, @"Column E");
        GNM_ASSERT ([colrow.children[0].afterText hasSuffix:@" pt"], @"points: %@", colrow.children[0].afterText);
        GNM_ASSERT (colrow.children[0].afterRange.start.column == 4 && colrow.children[0].afterRange.end.column == 4, @"the column");

        /* the other way round swaps added and removed */
        NSArray *reverse = [old differencesFromSheet:new];
        GnmSheetDifference *rcells = section (reverse, GnmDifferenceSectionCells);
        NSMutableDictionary *rby = [NSMutableDictionary dictionary];
        for (GnmSheetDifference *d in rcells.children)
            rby[d.location] = d;
        GnmSheetDifference *rb2 = rby[@"B2"], *rc3 = rby[@"C3"];
        GNM_ASSERT (rb2.direction == GnmDifferenceDirectionRemoved && rc3.direction == GnmDifferenceDirectionAdded, @"reversed: %@", rcells.children);

        GNM_ASSERT (stray.count == 0, @"stray messages: %@", stray);
        wb = nil;
      }
        [engine shutdown];
        return gnm_test_finish ("compare");
    }
}
