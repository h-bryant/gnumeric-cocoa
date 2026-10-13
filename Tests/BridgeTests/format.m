// Cell formatting: read the common style of a selection (nil where it
// differs), apply changes as one undoable command, number format helpers.
#import "GnmTest.h"

static CGColorRef rgb (CGFloat r, CGFloat g, CGFloat b) { return CGColorCreateSRGB (r, g, b, 1); }
static BOOL color_is (CGColorRef c, CGFloat r, CGFloat g, CGFloat b) {
    if (!c) return NO;
    const CGFloat *k = CGColorGetComponents (c);
    return CGColorGetNumberOfComponents (c) == 4 && fabs (k[0] - r) < 0.02 && fabs (k[1] - g) < 0.02 && fabs (k[2] - b) < 0.02;
}

int main (void)
{
    @autoreleasepool {
        GnmEngine *engine = gnm_test_start_engine (NO);
      @autoreleasepool {
        NSError *error = nil;
        NSURL *url = [NSURL fileURLWithPath:[gnm_test_env ("GNM_TEST_SAMPLES") stringByAppendingPathComponent:@"format-tests.gnumeric"]];
        GnmWorkbook *wb = [engine openWorkbookAtURL:url error:&error];
        GNM_ASSERT (wb != nil, @"open: %@", error);
        if (!wb) { [engine shutdown]; return gnm_test_finish ("format"); }
        GnmSheet *s = wb.sheets.firstObject;
        [wb selectSheet:s];

        /* the sample's "Text" column: B6 shows 12.35 with format 0.00 */
        [s selectCellAtColumn:1 row:5];
        GnmCellFormat *f = s.formatOfSelection;
        GNM_ASSERT_EQ_STR (f.numberFormat ?: @"", @"0.00");
        GNM_ASSERT (f.bold != nil && !f.bold.boolValue, @"not bold");
        GNM_ASSERT (f.fontSize.doubleValue > 5, @"font size %@", f.fontSize);
        GNM_ASSERT (f.fontName.length > 0, @"font name %@", f.fontName);
        GNM_ASSERT (f.fillsBackground != nil && !f.fillsBackground.boolValue, @"no fill");
        GNM_ASSERT ([f borderStyleForEdge:GnmBorderEdgeTop] != nil && [f borderStyleForEdge:GnmBorderEdgeTop].integerValue == GnmBorderLineStyleNone, @"no top border");
        NSLog (@"B6: format %@ font %@ %@pt halign %@", f.numberFormat, f.fontName, f.fontSize, f.horizontalAlignment);

        /* the header row A4:B4 is bold with a cyan fill */
        [s selectRange:GnmCellRangeMake (0, 3, 1, 3) editPosition:GnmCellCoordinateMake (0, 3)];
        f = s.formatOfSelection;
        GNM_ASSERT (f.bold.boolValue, @"header bold");
        GNM_ASSERT (f.fillsBackground.boolValue && f.backgroundColor != NULL, @"header fill");
        GNM_ASSERT (color_is (f.backgroundColor, 0, 1, 1), @"cyan fill");

        /* a mixed selection reports nil for what differs */
        [s selectRange:GnmCellRangeMake (1, 3, 1, 5) editPosition:GnmCellCoordinateMake (1, 3)];
        f = s.formatOfSelection;
        GNM_ASSERT (f.bold == nil, @"bold differs over B4:B6");
        GNM_ASSERT (f.numberFormat == nil, @"format differs");
        GNM_ASSERT (f.fontName != nil, @"font name shared");

        /* apply: number format, bold, alignment, fill, borders */
        [s selectRange:GnmCellRangeMake (1, 5, 1, 6) editPosition:GnmCellCoordinateMake (1, 5)];
        GnmCellFormat *change = [[GnmCellFormat alloc] init];
        change.numberFormat = @"0.000";
        change.bold = @YES;
        change.italic = @YES;
        change.horizontalAlignment = @(GnmHorizontalAlignmentCenter);
        change.fillsBackground = @YES;
        CGColorRef yellow = rgb (1, 1, 0);
        change.backgroundColor = yellow;
        CGColorRef red = rgb (1, 0, 0);
        change.textColor = red;
        [change setBorderStyle:GnmBorderLineStyleThick color:NULL forEdge:GnmBorderEdgeBottom];
        [change setBorderStyle:GnmBorderLineStyleDashed color:red forEdge:GnmBorderEdgeLeft];
        GNM_ASSERT ([s applyFormat:change error:&error], @"apply: %@", error);
        GNM_ASSERT_EQ_STR ([s displayTextOfCellAtColumn:1 row:5] ?: @"", @"12.345");   /* the stored value */
        f = s.formatOfSelection;
        GNM_ASSERT_EQ_STR (f.numberFormat ?: @"", @"0.000");
        GNM_ASSERT (f.bold.boolValue && f.italic.boolValue, @"bold italic applied");
        GNM_ASSERT (f.horizontalAlignment.integerValue == GnmHorizontalAlignmentCenter, @"centered");
        GNM_ASSERT (color_is (f.backgroundColor, 1, 1, 0), @"yellow fill read back");
        GNM_ASSERT (f.contentsLocked.boolValue && !f.contentsHidden.boolValue, @"cells start locked and not hidden");
        GNM_ASSERT (color_is (f.textColor, 1, 0, 0), @"red text read back");
        GNM_ASSERT ([f borderStyleForEdge:GnmBorderEdgeBottom].integerValue == GnmBorderLineStyleThick, @"thick bottom border");
        GNM_ASSERT ([f borderStyleForEdge:GnmBorderEdgeLeft].integerValue == GnmBorderLineStyleDashed, @"dashed left border");
        GNM_ASSERT (color_is ([f borderColorForEdge:GnmBorderEdgeLeft], 1, 0, 0), @"red left border");
        GNM_ASSERT (wb.canUndo && [wb.undoLabel containsString:@"ormat"], @"undo label '%@'", wb.undoLabel);
        [wb undo];
        GNM_ASSERT_EQ_STR ([s displayTextOfCellAtColumn:1 row:5] ?: @"", @"12.35");
        f = s.formatOfSelection;
        GNM_ASSERT (f.bold != nil && !f.bold.boolValue, @"undo restored bold");
        CGColorRelease (yellow);
        CGColorRelease (red);

        /* removing a fill */
        [s selectRange:GnmCellRangeMake (0, 3, 1, 3) editPosition:GnmCellCoordinateMake (0, 3)];
        change = [[GnmCellFormat alloc] init];
        change.fillsBackground = @NO;
        GNM_ASSERT ([s applyFormat:change error:&error], @"clear fill: %@", error);
        GNM_ASSERT (!s.formatOfSelection.fillsBackground.boolValue, @"fill removed");
        [wb undo];

        /* the Protection page: B6:B7 unlocked and hidden, then the sheet protected */
        [s selectRange:GnmCellRangeMake (1, 5, 1, 6) editPosition:GnmCellCoordinateMake (1, 5)];
        GnmCellFormat *protection = [[GnmCellFormat alloc] init];
        protection.contentsLocked = @NO;
        protection.contentsHidden = @YES;
        GNM_ASSERT ([s applyFormat:protection error:&error], @"protection: %@", error);
        f = s.formatOfSelection;
        GNM_ASSERT (!f.contentsLocked.boolValue && f.contentsHidden.boolValue, @"unlocked and hidden read back");
        GNM_ASSERT ([s lockMessageForCellsInRange:GnmCellRangeMake (0, 0, 0, 0)] == nil, @"nothing locked while unprotected");
        GNM_ASSERT ([wb setSheet:s protected:YES error:&error], @"protect: %@", error);
        GNM_ASSERT (s.isProtected, @"protected");
        GNM_ASSERT ([s lockMessageForCellsInRange:GnmCellRangeMake (1, 5, 1, 6)] == nil, @"the unlocked cells may be edited");
        NSString *lockMessage = [s lockMessageForCellsInRange:GnmCellRangeMake (0, 0, 1, 6)];
        GNM_ASSERT_EQ_STR (lockMessage ?: @"", @"Sheet1!A1:B7 is locked. Unprotect the sheet to enable editing.");
        GNM_ASSERT ([wb setSheet:s protected:NO error:&error], @"unprotect: %@", error);
        GNM_ASSERT ([s lockMessageForCellsInRange:GnmCellRangeMake (0, 0, 1, 6)] == nil, @"editable again");
        [wb undo];   /* the unprotect */
        [wb undo];   /* the protect */
        [wb undo];   /* the protection format */
        GNM_ASSERT (!s.isProtected && s.formatOfSelection.contentsLocked.boolValue, @"back to locked and unprotected");

        /* format helpers */
        GNM_ASSERT ([GnmCellFormat familyOfNumberFormat:@"0.00%"] == GnmNumberFormatFamilyPercentage, @"percentage family");
        GNM_ASSERT ([GnmCellFormat familyOfNumberFormat:@"yyyy-mm-dd"] == GnmNumberFormatFamilyDate, @"date family");
        GNM_ASSERT ([GnmCellFormat familyOfNumberFormat:@"General"] == GnmNumberFormatFamilyGeneral, @"general family");
        NSString *num = [GnmCellFormat numberFormatForFamily:GnmNumberFormatFamilyNumber decimals:2 thousandsSeparator:YES];
        GNM_ASSERT_EQ_STR (num, @"#,##0.00");
        NSString *pct = [GnmCellFormat numberFormatForFamily:GnmNumberFormatFamilyPercentage decimals:1 thousandsSeparator:NO];
        GNM_ASSERT_EQ_STR (pct, @"0.0%");
        NSString *sci = [GnmCellFormat numberFormatForFamily:GnmNumberFormatFamilyScientific decimals:3 thousandsSeparator:NO];
        NSLog (@"generated: number %@ percent %@ scientific %@ currency %@", num, pct, sci,
               [GnmCellFormat numberFormatForFamily:GnmNumberFormatFamilyCurrency decimals:2 thousandsSeparator:YES]);
        GNM_ASSERT ([sci hasPrefix:@"0.000E"], @"scientific %@", sci);

        wb = nil; s = nil;
      }
        [engine shutdown];
    }
    return gnm_test_finish ("format");
}
