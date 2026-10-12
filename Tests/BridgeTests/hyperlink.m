// Hyperlinks: a web link on an empty cell (the target as its text, the
// blue underline), reading back, editing, an internal link followed to
// its range, the target checks, the mailto builder, the link ranges,
// removal, and undo.
#import "GnmTest.h"

int main (void)
{
    @autoreleasepool {
        GnmEngine *engine = gnm_test_start_engine (NO);
        NSMutableArray<NSError *> *stray = [NSMutableArray array];
        engine.messageHandler = ^(NSError *e) { [stray addObject:e]; };
      @autoreleasepool {
        NSError *error = nil;
        GnmWorkbook *wb = [engine newWorkbookWithSheetCount:2];
        GnmSheet *s = wb.sheets.firstObject;
        GNM_ASSERT ([s hyperlinkAtColumn:0 row:0] == nil, @"none at first");
        GNM_ASSERT ([s setHyperlink:nil error:&error], @"removing nothing is nothing");
        GNM_ASSERT (wb.undoLabel == nil, @"no command for that: %@", wb.undoLabel);

        /* a web link on the empty A1 */
        [s selectCellAtColumn:0 row:0];
        GnmHyperlink *web = [[GnmHyperlink alloc] initWithKind:GnmHyperlinkWeb target:@"https://www.gnumeric.org/" tip:@"The project"];
        GNM_ASSERT ([s setHyperlink:web error:&error], @"web: %@", error);
        GNM_ASSERT_EQ_STR (wb.undoLabel ?: @"", @"Add Hyperlink");
        GNM_ASSERT_EQ_STR ([s displayTextOfCellAtColumn:0 row:0] ?: @"", @"https://www.gnumeric.org/");
        GnmHyperlink *read = [s hyperlinkAtColumn:0 row:0];
        GNM_ASSERT (read && read.kind == GnmHyperlinkWeb, @"read back: %@", read);
        GNM_ASSERT_EQ_STR (read.target, @"https://www.gnumeric.org/");
        GNM_ASSERT_EQ_STR (read.tip ?: @"", @"The project");
        GnmCellFormat *format = s.formatOfSelection;
        GNM_ASSERT (format.underline.integerValue == GnmUnderlineStyleSingle, @"underlined: %@", format.underline);
        const CGFloat *rgb = format.textColor ? CGColorGetComponents (format.textColor) : NULL;
        GNM_ASSERT (rgb && rgb[0] < 0.01 && rgb[1] < 0.01 && rgb[2] > 0.99, @"blue text");

        /* editing keeps the text and changes the target */
        GnmHyperlink *edited = [[GnmHyperlink alloc] initWithKind:GnmHyperlinkWeb target:@"https://gitlab.gnome.org/GNOME/gnumeric" tip:nil];
        GNM_ASSERT ([s setHyperlink:edited error:&error], @"edit: %@", error);
        GNM_ASSERT_EQ_STR (wb.undoLabel ?: @"", @"Edit Hyperlink");
        GNM_ASSERT_EQ_STR ([s displayTextOfCellAtColumn:0 row:0] ?: @"", @"https://www.gnumeric.org/");
        GNM_ASSERT_EQ_STR ([s hyperlinkAtColumn:0 row:0].target, @"https://gitlab.gnome.org/GNOME/gnumeric");
        GNM_ASSERT ([s hyperlinkAtColumn:0 row:0].tip == nil, @"no tip now");

        /* an internal link on A3 to the second sheet, followed */
        GnmSheet *second = wb.sheets[1];
        NSString *target = [NSString stringWithFormat:@"%@!B2:C3", second.name];
        GNM_ASSERT ([wb defineName:@"block" expression:@"A1:A3" scope:nil inSheet:s error:&error], @"name: %@", error);
        GNM_ASSERT ([s isValidInternalTarget:@"D5"] && [s isValidInternalTarget:target] && [s isValidInternalTarget:@"block"],
                    @"ranges and range names are targets");
        /* Sheet_Title names a string, not a range */
        GNM_ASSERT (![s isValidInternalTarget:@"Sheet_Title"] && ![s isValidInternalTarget:@"nonsense"] && ![s isValidInternalTarget:@""],
                    @"other names and texts are not");
        [s selectCellAtColumn:0 row:2];
        GnmHyperlink *internal = [[GnmHyperlink alloc] initWithKind:GnmHyperlinkInternal target:target tip:nil];
        GNM_ASSERT ([s setHyperlink:internal error:&error], @"internal: %@", error);
        GNM_ASSERT ([s hyperlinkAtColumn:0 row:2].kind == GnmHyperlinkInternal, @"kind");
        GNM_ASSERT_EQ_STR ([s hyperlinkAtColumn:0 row:2].target, target);
        GNM_ASSERT ([s followInternalHyperlinkAtColumn:0 row:2 error:&error], @"follow: %@", error);
        GNM_ASSERT (wb.currentSheet == second, @"the second sheet is focused: %@", wb.currentSheet.name);
        GnmCellRange sel = second.selectedRange;
        GNM_ASSERT (sel.start.column == 1 && sel.start.row == 1 && sel.end.column == 2 && sel.end.row == 2, @"B2:C3 selected");
        GNM_ASSERT (![s followInternalHyperlinkAtColumn:0 row:0 error:&error] && [error.localizedDescription containsString:@"Link target"],
                    @"a web link is not followed here: %@", error);
        [wb selectSheet:s];

        /* the other kinds and the mailto builder */
        NSString *mail = [GnmHyperlink emailTargetForAddress:@"henry@example.org" subject:@"Hello there"];
        NSLog (@"hyperlink: mailto target '%@'", mail);
        GNM_ASSERT ([mail hasPrefix:@"mailto:henry"] && [mail containsString:@"?subject=Hello"], @"mailto: %@", mail);
        GNM_ASSERT_EQ_STR ([GnmHyperlink emailTargetForAddress:@"" subject:@"x"], @"");
        [s selectCellAtColumn:0 row:4];
        GNM_ASSERT ([s setHyperlink:[[GnmHyperlink alloc] initWithKind:GnmHyperlinkEmail target:mail tip:nil] error:&error], @"email: %@", error);
        GNM_ASSERT ([s hyperlinkAtColumn:0 row:4].kind == GnmHyperlinkEmail, @"email kind");
        [s selectCellAtColumn:0 row:6];
        GNM_ASSERT ([s setHyperlink:[[GnmHyperlink alloc] initWithKind:GnmHyperlinkExternalFile target:@"/tmp/notes.txt" tip:@"notes"] error:&error], @"file: %@", error);
        GNM_ASSERT ([s hyperlinkAtColumn:0 row:6].kind == GnmHyperlinkExternalFile, @"file kind");

        /* the link ranges */
        NSArray *ranges = [s hyperlinkRangesInRange:GnmCellRangeMake (0, 0, 5, 20)];
        GNM_ASSERT (ranges.count == 4, @"four linked cells: %lu", (unsigned long) ranges.count);
        GnmCellRange first;
        [ranges.firstObject getValue:&first];
        GNM_ASSERT (first.start.column == 0 && first.start.row == 0 && first.end.row == 0, @"A1 first");

        /* removal and undo */
        [s selectCellAtColumn:0 row:0];
        GNM_ASSERT ([s setHyperlink:nil error:&error], @"remove: %@", error);
        GNM_ASSERT_EQ_STR (wb.undoLabel ?: @"", @"Remove Hyperlink");
        GNM_ASSERT ([s hyperlinkAtColumn:0 row:0] == nil, @"removed");
        GNM_ASSERT_EQ_STR ([s displayTextOfCellAtColumn:0 row:0] ?: @"", @"https://www.gnumeric.org/");
        [wb undo];
        GNM_ASSERT ([s hyperlinkAtColumn:0 row:0] != nil, @"back after undo");
        GNM_ASSERT ([s hyperlinkRangesInRange:GnmCellRangeMake (0, 0, 5, 20)].count == 4, @"four again");

        GNM_ASSERT (stray.count == 0, @"stray messages: %@", stray);
        wb = nil;
      }
        [engine shutdown];
        return gnm_test_finish ("hyperlink");
    }
}
