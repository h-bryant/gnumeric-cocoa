// Defined names through the engine's commands: listing, defining for the
// workbook and a sheet, use by a cell, changing a definition, scope
// changes, removal, undo and redo, and the errors.
#import "GnmTest.h"

/* The editable names; every sheet also carries the engine's permanent
 * Print_Area and Sheet_Title. */
static NSString *
listed (NSArray<GnmDefinedName *> *names)
{
    NSMutableArray *parts = [NSMutableArray array];
    for (GnmDefinedName *n in names)
        if (n.isEditable)
            [parts addObject:[NSString stringWithFormat:@"%@[%@]=%@", n.name, n.scope ? n.scope.name : @"wb", n.expressionText]];
    return [parts componentsJoinedByString:@" "];
}

static GnmDefinedName *
named (NSArray<GnmDefinedName *> *names, NSString *name)
{
    for (GnmDefinedName *n in names)
        if ([n.name isEqualToString:name])
            return n;
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
        GnmSheet *s1 = wb.sheets[0], *s2 = wb.sheets[1];
        [wb selectSheet:s1];
        GNM_ASSERT ([s1 setText:@"1" atColumn:0 row:0 autocorrect:NO error:&error], @"A1: %@", error);
        GNM_ASSERT ([s1 setText:@"2" atColumn:0 row:1 autocorrect:NO error:&error], @"A2: %@", error);
        GNM_ASSERT ([s1 setText:@"3" atColumn:0 row:2 autocorrect:NO error:&error], @"A3: %@", error);
        GNM_ASSERT_EQ_STR (listed ([wb definedNamesForSheet:s1]), @"");
        NSArray<GnmDefinedName *> *permanent = [wb definedNamesForSheet:s1];
        GNM_ASSERT (permanent.count == 2 && !permanent[0].isEditable && permanent[0].scope == s1, @"the sheet's permanent names: %@", permanent);
        GNM_ASSERT_EQ_STR (named (permanent, @"Sheet_Title").expressionText ?: @"", @"\"Sheet1\"");

        /* a workbook name */
        GNM_ASSERT ([wb defineName:@"total" expression:@"Sheet1!$A$1:$A$3" scope:nil inSheet:s1 error:&error], @"define: %@", error);
        NSArray<GnmDefinedName *> *names = [wb definedNamesForSheet:s1];
        GNM_ASSERT_EQ_STR (listed (names), @"total[wb]=Sheet1!$A$1:$A$3");
        GNM_ASSERT (named (names, @"total").isEditable && !named (names, @"total").isInUse, @"editable, unused");
        GNM_ASSERT_EQ_STR (wb.undoLabel ?: @"", @"Define Name total");

        /* used by a cell, and from the other sheet */
        GNM_ASSERT ([s1 setText:@"=SUM(total)" atColumn:2 row:0 autocorrect:NO error:&error], @"C1: %@", error);
        GNM_ASSERT_EQ_STR ([s1 displayTextOfCellAtColumn:2 row:0], @"6");
        GNM_ASSERT (named ([wb definedNamesForSheet:s1], @"total").isInUse, @"in use now");
        GNM_ASSERT ([s2 setText:@"=SUM(total)" atColumn:0 row:0 autocorrect:NO error:&error], @"Sheet2!A1: %@", error);
        GNM_ASSERT_EQ_STR ([s2 displayTextOfCellAtColumn:0 row:0], @"6");
        GNM_ASSERT_EQ_STR (listed ([wb definedNamesForSheet:s2]), @"total[wb]=Sheet1!$A$1:$A$3");

        /* a sheet name, listed for its sheet only; a relative one shown
         * relative to the edit position */
        GNM_ASSERT ([wb defineName:@"local" expression:@"$B$2" scope:s2 inSheet:s2 error:&error], @"define local: %@", error);
        GNM_ASSERT_EQ_STR (listed ([wb definedNamesForSheet:s2]), @"local[Sheet2]=$B$2 total[wb]=Sheet1!$A$1:$A$3");   /* no prefix on its own sheet */
        GNM_ASSERT_EQ_STR (listed ([wb definedNamesForSheet:s1]), @"total[wb]=Sheet1!$A$1:$A$3");
        [s1 selectCellAtColumn:0 row:0];
        GNM_ASSERT ([wb defineName:@"below" expression:@"A2" scope:s1 inSheet:s1 error:&error], @"define relative: %@", error);
        GNM_ASSERT_EQ_STR (named ([wb definedNamesForSheet:s1], @"below").expressionText, @"A2");
        [s1 selectCellAtColumn:0 row:1];
        GNM_ASSERT_EQ_STR (named ([wb definedNamesForSheet:s1], @"below").expressionText, @"A3");   /* relative to the edit position */
        [s1 selectCellAtColumn:0 row:0];

        /* changing a definition */
        GNM_ASSERT ([wb defineName:@"total" expression:@"Sheet1!$A$1:$A$2" scope:nil inSheet:s1 error:&error], @"redefine: %@", error);
        GNM_ASSERT_EQ_STR (named ([wb definedNamesForSheet:s1], @"total").expressionText, @"Sheet1!$A$1:$A$2");
        GNM_ASSERT_EQ_STR ([s1 displayTextOfCellAtColumn:2 row:0], @"3");
        [wb undo];
        GNM_ASSERT_EQ_STR ([s1 displayTextOfCellAtColumn:2 row:0], @"6");
        [wb redo];
        GNM_ASSERT_EQ_STR ([s1 displayTextOfCellAtColumn:2 row:0], @"3");

        /* a constant and a formula as names */
        GNM_ASSERT ([wb defineName:@"rate" expression:@"0.05" scope:nil inSheet:s1 error:&error], @"constant: %@", error);
        GNM_ASSERT ([wb defineName:@"twice" expression:@"2*rate" scope:nil inSheet:s1 error:&error], @"formula: %@", error);
        GNM_ASSERT ([s1 setText:@"=twice" atColumn:3 row:0 autocorrect:NO error:&error], @"D1: %@", error);
        GNM_ASSERT_EQ_STR ([s1 displayTextOfCellAtColumn:3 row:0], @"0.1");

        /* scope changes */
        GnmDefinedName *rate = named ([wb definedNamesForSheet:s1], @"rate");
        GNM_ASSERT ([wb changeScopeOfName:rate toSheet:s1 error:&error], @"rescope: %@", error);
        GNM_ASSERT (named ([wb definedNamesForSheet:s1], @"rate").scope == s1, @"now a sheet name");
        GNM_ASSERT_EQ_STR (wb.undoLabel ?: @"", @"Change Scope of Name rate");
        [wb undo];
        GNM_ASSERT (named ([wb definedNamesForSheet:s1], @"rate").scope == nil, @"a workbook name again");

        /* errors: a bad name, an empty or unreadable expression, an
         * unknown name */
        error = nil;
        GNM_ASSERT (![wb defineName:@"1bad" expression:@"1" scope:nil inSheet:s1 error:&error] && error, @"bad name refused");
        NSLog (@"bad name: %@", error.localizedDescription);
        error = nil;
        GNM_ASSERT (![wb defineName:@"empty" expression:@"" scope:nil inSheet:s1 error:&error] && error, @"empty refused");
        error = nil;
        GNM_ASSERT (![wb defineName:@"broken" expression:@"=1+" scope:nil inSheet:s1 error:&error] && error, @"unreadable refused");
        NSLog (@"unreadable: %@", error.localizedDescription);
        error = nil;
        GNM_ASSERT (![wb defineName:@"unknown" expression:@"nosuchname*2" scope:nil inSheet:s1 error:&error] && error, @"unknown name refused");
        NSLog (@"unknown: %@", error.localizedDescription);
        GNM_ASSERT (named ([wb definedNamesForSheet:s1], @"broken") == nil, @"nothing defined by the failures");

        /* removal of a name in use: the cell shows an error, undo brings it back */
        GnmDefinedName *total = named ([wb definedNamesForSheet:s1], @"total");
        GNM_ASSERT (total.isInUse, @"total in use");
        GNM_ASSERT ([wb removeName:total error:&error], @"remove: %@", error);
        GNM_ASSERT (named ([wb definedNamesForSheet:s1], @"total") == nil, @"removed from the list");
        GNM_ASSERT_EQ_STR (wb.undoLabel ?: @"", @"Remove Name total");
        NSLog (@"C1 after removing its name: %@", [s1 displayTextOfCellAtColumn:2 row:0]);
        [wb undo];
        GNM_ASSERT (named ([wb definedNamesForSheet:s1], @"total") != nil, @"back after undo");
        GNM_ASSERT_EQ_STR ([s1 displayTextOfCellAtColumn:2 row:0], @"3");

        /* the name box defines names too (jumpToReference) */
        [s1 selectRange:GnmCellRangeMake (0, 0, 0, 2) editPosition:GnmCellCoordinateMake (0, 0)];
        GNM_ASSERT ([wb jumpToReference:@"column_a" error:&error], @"name box: %@", error);
        GNM_ASSERT_EQ_STR (named ([wb definedNamesForSheet:s1], @"column_a").expressionText ?: @"", @"Sheet1!$A$1:$A$3");

        GNM_ASSERT (stray.count == 0, @"stray messages: %@", stray);
        wb = nil;
      }
        [engine shutdown];
        return gnm_test_finish ("names");
    }
}
