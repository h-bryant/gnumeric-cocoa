// Text export with options: the defaults the workbook starts from, the
// separator, quoting, line ending, sheet choice, format modes, and
// formulas in the written file, the options kept for the next export,
// and "remember as default" reaching a fresh workbook.
#import "GnmTest.h"

static NSString *
file_text (NSURL *url)
{
    return [NSString stringWithContentsOfURL:url encoding:NSUTF8StringEncoding error:NULL] ?: @"<unreadable>";
}

int main (void)
{
    @autoreleasepool {
        GnmEngine *engine = gnm_test_start_engine (NO);
        NSMutableArray<NSError *> *stray = [NSMutableArray array];
        engine.messageHandler = ^(NSError *e) { [stray addObject:e]; };
      @autoreleasepool {
        NSError *error = nil;
        NSString *dir = gnm_test_env ("GNM_TEST_OUT");
        GnmWorkbook *wb = [engine newWorkbookWithSheetCount:2];
        GnmSheet *s1 = wb.sheets[0], *s2 = wb.sheets[1];
        GNM_ASSERT ([s1 setText:@"name" atColumn:0 row:0 autocorrect:NO error:&error], @"A1: %@", error);
        GNM_ASSERT ([s1 setText:@"a, b" atColumn:1 row:0 autocorrect:NO error:&error], @"B1: %@", error);
        GNM_ASSERT ([s1 setText:@"say \"hi\"" atColumn:0 row:1 autocorrect:NO error:&error], @"A2: %@", error);
        GNM_ASSERT ([s1 setText:@"=1+1" atColumn:1 row:1 autocorrect:NO error:&error], @"B2: %@", error);
        GNM_ASSERT ([s1 setText:@"0.5" atColumn:0 row:2 autocorrect:NO error:&error], @"A3: %@", error);
        [s1 selectCellAtColumn:0 row:2];
        GnmCellFormat *percent = [[GnmCellFormat alloc] init];
        percent.numberFormat = @"0.00%";
        GNM_ASSERT ([s1 applyFormat:percent error:&error], @"percent format: %@", error);
        GNM_ASSERT_EQ_STR ([s1 displayTextOfCellAtColumn:0 row:2], @"50.00%");
        GNM_ASSERT ([s2 setText:@"second" atColumn:0 row:0 autocorrect:NO error:&error], @"Sheet2!A1: %@", error);

        /* the defaults (gnumeric-conf's stf_export keys) */
        GnmTextExportOptions *o = wb.textExportOptions;
        GNM_ASSERT (o.sheets.count == 0, @"no sheet list yet");
        GNM_ASSERT (o.lineEnding == GnmTextLineEndingUnix, @"eol default %ld", (long) o.lineEnding);
        GNM_ASSERT_EQ_STR (o.separator, @",");
        GNM_ASSERT_EQ_STR (o.quoteCharacter, @"\"");
        GNM_ASSERT (o.quoting == GnmTextQuotingAutomatic && o.format == GnmTextFormatAutomatic && !o.exportsFormulas,
                    @"defaults: quoting %ld format %ld", (long) o.quoting, (long) o.format);
        GNM_ASSERT (o.characterEncoding == nil && o.locale == nil, @"no encoding or locale by default: %@ %@",
                    o.characterEncoding, o.locale);
        NSLog (@"can transliterate: %d, unknown characters default %ld", GnmTextExportOptions.canTransliterate,
               (long) o.unknownCharacters);

        /* every sheet, the defaults: quotes where needed, values (the
         * automatic format keeps only dates and such as displayed), Unix
         * lines */
        NSURL *all = [NSURL fileURLWithPath:[dir stringByAppendingPathComponent:@"text-export-all.txt"]];
        GNM_ASSERT ([wb writeToURL:all textExportOptions:o rememberAsDefault:NO adoptingURL:NO error:&error], @"write all: %@", error);
        NSString *text = file_text (all);
        GNM_ASSERT_EQ_STR (text, @"name,\"a, b\"\n\"say \"\"hi\"\"\",2\n0.5,\nsecond\n");
        GNM_ASSERT (wb.textExportOptions.sheets.count == 0, @"the saver's own sheet list is cleared again");

        /* one sheet, a semicolon, quotes always, Windows lines, raw values,
         * formulas */
        o.sheets = @[s1];
        o.separator = @";";
        o.quoting = GnmTextQuotingAlways;
        o.lineEnding = GnmTextLineEndingWindows;
        o.format = GnmTextFormatRaw;
        o.exportsFormulas = YES;
        NSURL *one = [NSURL fileURLWithPath:[dir stringByAppendingPathComponent:@"text-export-one.txt"]];
        GNM_ASSERT ([wb writeToURL:one textExportOptions:o rememberAsDefault:NO adoptingURL:NO error:&error], @"write one: %@", error);
        text = file_text (one);
        GNM_ASSERT_EQ_STR (text, @"\"name\";\"a, b\"\r\n\"say \"\"hi\"\"\";\"=1+1\"\r\n\"0.5\";\"\"\r\n");

        /* the workbook remembers its last export's choices */
        GnmTextExportOptions *again = wb.textExportOptions;
        GNM_ASSERT (again.sheets.count == 1 && again.sheets.firstObject == s1, @"sheet list kept: %lu", (unsigned long) again.sheets.count);
        GNM_ASSERT_EQ_STR (again.separator, @";");
        GNM_ASSERT (again.quoting == GnmTextQuotingAlways && again.lineEnding == GnmTextLineEndingWindows
                    && again.format == GnmTextFormatRaw && again.exportsFormulas, @"options kept");

        /* the second sheet only, preserved formatting, no quotes, a single
         * quote character, Macintosh lines */
        o.sheets = @[s2, s1];
        o.quoting = GnmTextQuotingNever;
        o.quoteCharacter = @"'";
        o.lineEnding = GnmTextLineEndingMacintosh;
        o.format = GnmTextFormatPreserve;
        o.exportsFormulas = NO;
        o.separator = @"\t";
        NSURL *two = [NSURL fileURLWithPath:[dir stringByAppendingPathComponent:@"text-export-two.txt"]];
        GNM_ASSERT ([wb writeToURL:two textExportOptions:o rememberAsDefault:NO adoptingURL:NO error:&error], @"write two: %@", error);
        text = file_text (two);
        GNM_ASSERT_EQ_STR (text, @"second\rname\ta, b\rsay \"hi\"\t2\r50.00%\t\r");

        /* an encoding and the C locale */
        GNM_ASSERT ([s2 setText:@"café 1,5" atColumn:0 row:1 autocorrect:NO error:&error], @"Sheet2!A2: %@", error);
        o.sheets = @[s2];
        o.characterEncoding = @"ISO-8859-1";
        o.locale = @"C";
        o.lineEnding = GnmTextLineEndingUnix;
        NSURL *latin = [NSURL fileURLWithPath:[dir stringByAppendingPathComponent:@"text-export-latin1.txt"]];
        GNM_ASSERT ([wb writeToURL:latin textExportOptions:o rememberAsDefault:NO adoptingURL:NO error:&error], @"write latin1: %@", error);
        NSData *bytes = [NSData dataWithContentsOfURL:latin];
        NSString *decoded = [[NSString alloc] initWithData:bytes encoding:NSISOLatin1StringEncoding];
        GNM_ASSERT_EQ_STR (decoded, @"second\ncafé 1,5\n");
        GNM_ASSERT ([bytes length] == [decoded lengthOfBytesUsingEncoding:NSISOLatin1StringEncoding], @"one byte per character");
        GNM_ASSERT_EQ_STR (wb.textExportOptions.characterEncoding ?: @"", @"ISO-8859-1");
        GNM_ASSERT_EQ_STR (wb.textExportOptions.locale ?: @"", @"C");

        /* remembered as the default: a fresh workbook starts from it */
        o.separator = @"|";
        o.characterEncoding = nil;
        o.locale = nil;
        o.quoting = GnmTextQuotingAutomatic;
        NSURL *pipe = [NSURL fileURLWithPath:[dir stringByAppendingPathComponent:@"text-export-pipe.txt"]];
        GNM_ASSERT ([wb writeToURL:pipe textExportOptions:o rememberAsDefault:YES adoptingURL:NO error:&error], @"write pipe: %@", error);
        GnmWorkbook *fresh = [engine newWorkbookWithSheetCount:1];
        GnmTextExportOptions *inherited = fresh.textExportOptions;
        GNM_ASSERT_EQ_STR (inherited.separator, @"|");
        GNM_ASSERT (inherited.format == GnmTextFormatPreserve && inherited.quoting == GnmTextQuotingAutomatic
                    && inherited.quoteCharacter.length == 1, @"remembered format and quoting");
        fresh = nil;

        /* an empty sheet list after a non-empty one: all sheets again */
        o.sheets = @[];
        o.separator = @",";
        o.format = GnmTextFormatAutomatic;
        GNM_ASSERT ([wb writeToURL:all textExportOptions:o rememberAsDefault:NO adoptingURL:NO error:&error], @"write all again: %@", error);
        GNM_ASSERT ([file_text (all) hasPrefix:@"name,"] && [file_text (all) containsString:@"second"], @"all sheets: %@", file_text (all));

        /* the file-type saver is the one Save As "Text (configurable)" asks for */
        GNM_ASSERT_EQ_STR ([engine saverIdentifierForFileName:@"x.txt"] ?: @"", @"Gnumeric_stf:stf_assistant");

        GNM_ASSERT (stray.count == 0, @"stray messages: %@", stray);
        wb = nil;
      }
        [engine shutdown];
        return gnm_test_finish ("text_export");
    }
}
