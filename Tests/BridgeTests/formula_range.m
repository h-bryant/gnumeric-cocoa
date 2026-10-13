// Range selection while typing a formula: where a click may put a
// reference (after an operator or a parenthesis, in place of the operand
// under or before the cursor, never after a closing parenthesis or in
// plain text), range names, where arrow keys move, autocompletion, and
// array formulas over the selection.
#import "GnmTest.h"

static NSString *
probe (GnmSheet *s, NSString *text, NSInteger cursor)
{
    NSRange r;
    if (![s formulaText:text cursorAt:cursor canTakeRange:&r])
        return @"no";
    return [NSString stringWithFormat:@"%lu+%lu", (unsigned long) r.location, (unsigned long) r.length];
}

int main (void)
{
    @autoreleasepool {
        GnmEngine *engine = gnm_test_start_engine (NO);
        NSMutableArray<NSError *> *stray = [NSMutableArray array];
        engine.messageHandler = ^(NSError *e) { [stray addObject:e]; };
      @autoreleasepool {
        GnmWorkbook *wb = [engine newWorkbookWithSheetCount:1];
        GnmSheet *s = wb.sheets.firstObject;
        GNM_ASSERT_EQ_STR (probe (s, @"hello", 5), @"no");
        GNM_ASSERT_EQ_STR (probe (s, @"", 0), @"no");
        GNM_ASSERT_EQ_STR (probe (s, @"=", 1), @"1+0");
        GNM_ASSERT_EQ_STR (probe (s, @"=SUM(", 5), @"5+0");
        GNM_ASSERT_EQ_STR (probe (s, @"=A1+", 4), @"4+0");
        GNM_ASSERT_EQ_STR (probe (s, @"=A1+B2", 6), @"4+2");
        GNM_ASSERT_EQ_STR (probe (s, @"=A1+B2", 2), @"1+2");
        GNM_ASSERT_EQ_STR (probe (s, @"=A1+B2", 3), @"1+2");
        GNM_ASSERT_EQ_STR (probe (s, @"=SUM(A1:B2)", 11), @"no");
        GNM_ASSERT_EQ_STR (probe (s, @"=SUM(A1:B2,", 11), @"11+0");
        GNM_ASSERT_EQ_STR (probe (s, @"=SUM(A1:B2)+", 12), @"12+0");
        GNM_ASSERT_EQ_STR (probe (s, @"=1+2*", 5), @"5+0");
        GNM_ASSERT_EQ_STR (probe (s, @"=SUM(", 4), @"no");   /* before the parenthesis of a call */
        GNM_ASSERT_EQ_STR (probe (s, @"=\"été\"&", 7), @"7+0");
        GNM_ASSERT_EQ_STR ([s nameOfRange:GnmCellRangeMake (0, 0, 0, 0)], @"A1");
        GNM_ASSERT_EQ_STR ([s nameOfRange:GnmCellRangeMake (0, 0, 2, 3)], @"A1:C4");

        /* autocompletion from the column above */
        NSError *error = nil;
        GNM_ASSERT ([s setText:@"apple" atColumn:0 row:0 autocorrect:NO error:&error], @"apple: %@", error);
        GNM_ASSERT ([s setText:@"apricot" atColumn:0 row:1 autocorrect:NO error:&error], @"apricot: %@", error);
        GNM_ASSERT ([s setText:@"banana" atColumn:0 row:2 autocorrect:NO error:&error], @"banana: %@", error);
        NSString *ap = [s completionForText:@"ap" atColumn:0 row:3];
        NSLog (@"autocomplete: 'ap' -> '%@', 'app' -> '%@', 'b' -> '%@'", ap, [s completionForText:@"app" atColumn:0 row:3], [s completionForText:@"b" atColumn:0 row:3]);
        GNM_ASSERT ([[s completionForText:@"app" atColumn:0 row:3] isEqualToString:@"apple"], @"the nearest above that matches");
        GNM_ASSERT ([ap isEqualToString:@"apricot"] || ap == nil, @"'ap' is the nearest, or too short for the preference: %@", ap);
        GNM_ASSERT ([s completionForText:@"zzz" atColumn:0 row:3] == nil, @"nothing matches");
        GNM_ASSERT ([s completionForText:@"=ap" atColumn:0 row:3] == nil, @"formulas are not completed");
        GNM_ASSERT ([s completionForText:@"app" atColumn:1 row:3] == nil, @"another column");
        GNM_ASSERT ([s setText:@"" atColumn:0 row:2 autocorrect:NO error:&error], @"blank: %@", error);
        GNM_ASSERT ([s completionForText:@"app" atColumn:0 row:4] == nil, @"the search stops at a blank");

        /* arrow moves: D1:D3 filled, the rest empty */
        for (NSInteger r = 0; r < 3; r++) {
            NSString *number = [NSString stringWithFormat:@"%ld", (long) r + 1];
            GNM_ASSERT ([s setText:number atColumn:3 row:r autocorrect:NO error:&error], @"D: %@", error);
        }
        GnmCellCoordinate d1 = GnmCellCoordinateMake (3, 0), c;
        c = [s cell:d1 movedByColumns:0 rows:1 base:d1 jumpingToBoundary:NO];
        GNM_ASSERT (c.column == 3 && c.row == 1, @"a step down: %ld,%ld", (long) c.column, (long) c.row);
        c = [s cell:d1 movedByColumns:0 rows:1 base:d1 jumpingToBoundary:YES];
        GNM_ASSERT (c.column == 3 && c.row == 2, @"a jump down to the end of the data: %ld,%ld", (long) c.column, (long) c.row);
        GnmCellCoordinate d6 = GnmCellCoordinateMake (3, 5);
        c = [s cell:d6 movedByColumns:0 rows:-1 base:d6 jumpingToBoundary:YES];
        GNM_ASSERT (c.column == 3 && c.row == 2, @"a jump up from an empty cell to the data: %ld,%ld", (long) c.column, (long) c.row);
        c = [s cell:d1 movedByColumns:-1 rows:0 base:d1 jumpingToBoundary:NO];
        GNM_ASSERT (c.column == 2 && c.row == 0, @"a step left: %ld,%ld", (long) c.column, (long) c.row);
        GnmCellCoordinate a1 = GnmCellCoordinateMake (0, 0);
        c = [s cell:a1 movedByColumns:-1 rows:0 base:a1 jumpingToBoundary:NO];
        GNM_ASSERT (c.column == 0 && c.row == 0, @"the edge holds: %ld,%ld", (long) c.column, (long) c.row);
        GnmCellCoordinate d3 = GnmCellCoordinateMake (3, 2);
        c = [s cell:d3 movedByColumns:0 rows:1 base:d3 jumpingToBoundary:YES];
        NSLog (@"arrows: a jump down from the end of the data goes to %ld,%ld; a jump right from D1 to %ld,%ld",
               (long) c.column, (long) c.row,
               (long) [s cell:d1 movedByColumns:1 rows:0 base:d1 jumpingToBoundary:YES].column,
               (long) [s cell:d1 movedByColumns:1 rows:0 base:d1 jumpingToBoundary:YES].row);
        GNM_ASSERT (c.column == 3 && c.row > 2, @"a jump down from the end of the data moves on: %ld,%ld", (long) c.column, (long) c.row);

        /* an array formula over E1:E3 */
        [s selectRange:GnmCellRangeMake (4, 0, 4, 2) editPosition:GnmCellCoordinateMake (4, 0)];
        GNM_ASSERT ([s enterArrayFormula:@"=D1:D3*2" error:&error], @"array: %@", error);
        NSLog (@"array: E1..E3 = '%@' '%@' '%@', entered '%@', undo '%@'",
               [s displayTextOfCellAtColumn:4 row:0], [s displayTextOfCellAtColumn:4 row:1], [s displayTextOfCellAtColumn:4 row:2],
               [s enteredTextOfCellAtColumn:4 row:1], wb.undoLabel);
        GNM_ASSERT_EQ_STR ([s displayTextOfCellAtColumn:4 row:0], @"2");
        GNM_ASSERT_EQ_STR ([s displayTextOfCellAtColumn:4 row:1], @"4");
        GNM_ASSERT_EQ_STR ([s displayTextOfCellAtColumn:4 row:2], @"6");
        GNM_ASSERT_EQ_STR (wb.undoLabel, @"Inserting array expression in E1:E3");
        /* one cell of it cannot be changed alone */
        error = nil;
        GNM_ASSERT (![s setText:@"x" atColumn:4 row:1 autocorrect:NO error:&error], @"a cell of an array changed alone");
        NSLog (@"array: changing one cell: %@", error.localizedDescription);
        GNM_ASSERT_EQ_STR ([s displayTextOfCellAtColumn:4 row:1], @"4");
        [s selectRange:GnmCellRangeMake (4, 1, 4, 1) editPosition:GnmCellCoordinateMake (4, 1)];
        error = nil;
        GNM_ASSERT (![s enterArrayFormula:@"=1" error:&error], @"an array over part of an array");
        NSLog (@"array: over part of one: %@", error.localizedDescription);
        [wb undo];
        GNM_ASSERT ([s displayTextOfCellAtColumn:4 row:2] == nil || [[s displayTextOfCellAtColumn:4 row:2] isEqualToString:@""], @"undone: '%@'", [s displayTextOfCellAtColumn:4 row:2]);
        /* not a formula: the selection takes the text */
        [s selectRange:GnmCellRangeMake (5, 0, 5, 1) editPosition:GnmCellCoordinateMake (5, 0)];
        GNM_ASSERT ([s enterArrayFormula:@"hello" error:&error], @"text: %@", error);
        NSLog (@"array: text fill undo '%@'", wb.undoLabel);
        GNM_ASSERT_EQ_STR ([s displayTextOfCellAtColumn:5 row:0], @"hello");
        GNM_ASSERT_EQ_STR ([s displayTextOfCellAtColumn:5 row:1], @"hello");
        GNM_ASSERT ([s enterArrayFormula:@"-" error:&error], @"a lone minus: %@", error);
        GNM_ASSERT_EQ_STR ([s displayTextOfCellAtColumn:5 row:0], @"-");
        /* function tooltips: the call around the cursor, the argument marked */
        GnmFunctionTooltip *tip = [s functionTooltipForText:@"=SUM(1," cursorAt:7];
        NSLog (@"tooltip '=SUM(1,': '%@' function %@ argument %ld", tip.text, tip.functionName, (long) tip.argumentIndex);
        GNM_ASSERT (tip && [tip.functionName isEqualToString:@"SUM"] && tip.argumentIndex == 1, @"SUM's second argument: %@", tip);
        GNM_ASSERT ([tip.text isEqualToString:@"SUM([values],\u25b6\u2026\u25c0)"], @"marked text: %@", tip.text);
        tip = [s functionTooltipForText:@"=IF(A1,SUM(B1" cursorAt:14];
        GNM_ASSERT (tip && [tip.functionName isEqualToString:@"SUM"] && tip.argumentIndex == 0, @"the inner call: %@", tip.functionName);
        tip = [s functionTooltipForText:@"=IF(SUM(1),2" cursorAt:12];
        NSLog (@"tooltip '=IF(SUM(1),2': '%@'", tip.text);
        GNM_ASSERT (tip && [tip.functionName isEqualToString:@"IF"] && tip.argumentIndex == 1, @"back in the outer call: %@ %ld", tip.functionName, (long) tip.argumentIndex);
        GNM_ASSERT ([tip.text hasPrefix:@"IF(cond,\u25b6[trueval]\u25c0,[falseval])\ntrueval: "], @"the argument's description: %@", tip.text);
        tip = [s functionTooltipForText:@"=PI(1,2,3" cursorAt:9];
        GNM_ASSERT (tip && [tip.text containsString:@"\u2620"] && [tip.text containsString:@"Too many arguments for PI"], @"too many: %@", tip.text);
        GNM_ASSERT ([s functionTooltipForText:@"=1+" cursorAt:3] == nil, @"no call");
        GNM_ASSERT ([s functionTooltipForText:@"hello" cursorAt:5] == nil, @"not a formula");
        GNM_ASSERT ([s functionTooltipForText:@"=SUM(1)" cursorAt:0] == nil, @"at the start");
        tip = [s functionTooltipForText:@"=PI(" cursorAt:4];
        NSLog (@"tooltip '=PI(': '%@'", tip.text);
        GNM_ASSERT (tip && [tip.text isEqualToString:@"PI()\nPI takes no arguments"], @"PI: %@", tip.text);
        /* a name being typed: the completions */
        tip = [s functionTooltipForText:@"=su" cursorAt:3];
        NSLog (@"tooltip '=su': %@ single %@ range %@", tip.completions, tip.completion, NSStringFromRange (tip.completionRange));
        GNM_ASSERT (tip && [tip.completions containsObject:@"SUM"] && tip.functionName == nil && tip.completion == nil, @"completions: %@", tip.completions);
        GNM_ASSERT (tip.completions.count == 9 && [tip.text hasSuffix:@"\u22ee"], @"nine of many and the ellipsis: %@", tip.text);
        /* as in the GTK, a name no longer than the prefix is ticked and not
         * counted, so "averageif" completes to the one longer name */
        tip = [s functionTooltipForText:@"=averageif" cursorAt:10];
        NSLog (@"tooltip '=averageif': %@ single %@ text '%@'", tip.completions, tip.completion, tip.text);
        GNM_ASSERT (tip && [tip.completion isEqualToString:@"AVERAGEIFS"] && tip.completionRange.location == 1 && tip.completionRange.length == 9, @"a single match: %@ %@", tip.completion, NSStringFromRange (tip.completionRange));
        GNM_ASSERT ([tip.text hasPrefix:@"\u2713 AVERAGEIF \t"] && [tip.text hasSuffix:@"\nF4 to complete"], @"ticked and the hint: %@", tip.text);
        tip = [s functionTooltipForText:@"=averageifs" cursorAt:11];
        GNM_ASSERT (tip && tip.completion == nil && tip.completions.count == 1, @"only the exact name: %@", tip.text);
        tip = [s functionTooltipForText:@"=1+su" cursorAt:5];
        GNM_ASSERT (tip && [tip.completions containsObject:@"SUM"], @"after an operator: %@", tip.completions);
        /* F4's other job: the reference at the cursor cycles abs/rel */
        NSRange cyc = NSMakeRange (0, 0);
        NSString *cycled = [s formulaText:@"=SUM(B1:B3" cursorAt:10 cycleReferenceIn:&cyc];
        GNM_ASSERT ([cycled isEqualToString:@"$B$1:$B$3"] && cyc.location == 5 && cyc.length == 5, @"relative to absolute: %@ %@", cycled, NSStringFromRange (cyc));
        cycled = [s formulaText:@"=SUM($B$1:$B$3)" cursorAt:8 cycleReferenceIn:&cyc];
        GNM_ASSERT ([cycled isEqualToString:@"B$1:B$3"] && cyc.length == 9, @"absolute to absolute row: %@", cycled);
        cycled = [s formulaText:@"=B$1" cursorAt:4 cycleReferenceIn:&cyc];
        GNM_ASSERT ([cycled isEqualToString:@"$B1"], @"absolute row to absolute column: %@", cycled);
        cycled = [s formulaText:@"=$B1+1" cursorAt:4 cycleReferenceIn:&cyc];
        GNM_ASSERT ([cycled isEqualToString:@"B1"] && cyc.location == 1 && cyc.length == 3, @"and back: %@ %@", cycled, NSStringFromRange (cyc));
        GNM_ASSERT ([s formulaText:@"=SUM(1," cursorAt:7 cycleReferenceIn:&cyc] == nil, @"nothing to cycle at a separator");
        GNM_ASSERT ([s formulaText:@"=SUM(1" cursorAt:6 cycleReferenceIn:&cyc] == nil, @"a constant is not a reference");
        GNM_ASSERT ([s formulaText:@"B1" cursorAt:2 cycleReferenceIn:&cyc] == nil, @"not a formula");
        tip = [s functionTooltipForText:@"=SUMI" cursorAt:5];
        GNM_ASSERT (tip && [tip.completions containsObject:@"SUMIF"] && [tip.completions containsObject:@"SUMIFS"], @"typed in capitals: %@", tip.completions);
        GNM_ASSERT ([s functionTooltipForText:@"=SUM(xyzzy" cursorAt:10] != nil, @"an unknown name inside a call still tips the call");

        /* the editor's style: a cell's whole format, and the font family
         * the engine draws */
        GnmCellFormat *f = [s formatOfCellAtColumn:0 row:0];
        NSLog (@"format of A1: font '%@' %@ pt bold %@ align %@; Sans -> '%@', Monospace -> '%@'", f.fontName, f.fontSize, f.bold, f.horizontalAlignment,
               [engine resolvedFontFamilyForName:@"Sans"], [engine resolvedFontFamilyForName:@"Monospace"]);
        GNM_ASSERT (f.fontName.length > 0 && f.fontSize.doubleValue > 0 && f.bold != nil && f.horizontalAlignment != nil, @"a whole style");
        GNM_ASSERT ([engine resolvedFontFamilyForName:@"Sans"].length > 0 && ![[engine resolvedFontFamilyForName:@"Sans"] isEqualToString:@"Sans"], @"Sans resolves to a real family");
        GNM_ASSERT_EQ_STR ([engine resolvedFontFamilyForName:@"Georgia"], @"Georgia");

        error = nil;
        /* Format → Sheet toggles and the zoom command */
        GNM_ASSERT (![s displaysFormulas], @"formulas off at first");
        GNM_ASSERT ([s toggleDisplayOption:GnmSheetDisplayOptionFormulas error:&error], @"toggle formulas: %@", error);
        GNM_ASSERT ([s displaysFormulas] && [s displayOption:GnmSheetDisplayOptionFormulas], @"formulas on");
        NSLog (@"display: undo '%@'", wb.undoLabel);
        GNM_ASSERT_EQ_STR (wb.undoLabel, @"Toggle displaying formulæ");
        [wb undo];
        GNM_ASSERT (![s displaysFormulas], @"formulas undone");
        GNM_ASSERT ([s toggleDisplayOption:GnmSheetDisplayOptionR1C1 error:&error] && [s usesR1C1], @"r1c1: %@", error);
        GNM_ASSERT_EQ_STR ([s nameOfColumn:2], @"3");
        [wb undo];
        GNM_ASSERT_EQ_STR ([s nameOfColumn:2], @"C");
        GNM_ASSERT ([s toggleDisplayOption:GnmSheetDisplayOptionHideGridLines error:&error] && [s hidesGridLines], @"grid: %@", error);
        [wb undo];
        GNM_ASSERT (![s hidesGridLines], @"grid undone");
        GNM_ASSERT ([s setZoomFactor:1.5 forAllSheets:NO error:&error] && fabs (s.zoomFactor - 1.5) < 1e-9, @"zoom: %@ %g", error, s.zoomFactor);
        NSLog (@"display: zoom undo '%@'", wb.undoLabel);
        GNM_ASSERT ([wb.undoLabel hasPrefix:@"Zoom"], @"zoom label: %@", wb.undoLabel);
        [wb undo];
        GNM_ASSERT (fabs (s.zoomFactor - 1) < 1e-9, @"zoom undone: %g", s.zoomFactor);

        GNM_ASSERT (stray.count == 0, @"stray messages: %@", stray);
        wb = nil;
      }
        [engine shutdown];
        return gnm_test_finish ("formula_range");
    }
}
