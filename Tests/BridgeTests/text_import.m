// Text import through a session over the engine's parse options: the
// guesses from a file, previews, the chosen lines, separators and
// quotes, fixed widths, column formats and choices, trimming, an
// encoding, and the parse into a new workbook.
#import "GnmTest.h"

static NSURL *
write_file (NSString *dir, NSString *name, NSData *bytes)
{
    NSURL *url = [NSURL fileURLWithPath:[dir stringByAppendingPathComponent:name]];
    [bytes writeToURL:url atomically:YES];
    return url;
}

static NSString *
joined (NSArray<NSArray<NSString *> *> *lines)
{
    NSMutableArray *rows = [NSMutableArray array];
    for (NSArray *line in lines)
        [rows addObject:[line componentsJoinedByString:@"|"]];
    return [rows componentsJoinedByString:@"/"];
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

        /* a semicolon file with a quoted field and a leading zero */
        NSURL *semi = write_file (dir, @"import-semi.txt",
                                  [@"id;name;amount\n007;Smith, J.;1.5\n008;\"Jones; A.\";2\n" dataUsingEncoding:NSUTF8StringEncoding]);
        GnmTextImportSession *session = [GnmTextImportSession sessionWithContentsOfURL:semi encoding:nil error:&error];
        GNM_ASSERT (session != nil, @"session: %@", error);
        GNM_ASSERT_EQ_STR (session.name, @"import-semi.txt");
        GNM_ASSERT ([session.encoding isEqualToString:@"UTF-8"] || [session.encoding isEqualToString:@"ASCII"],
                    @"plain bytes: %@", session.encoding);   /* go_guess_encoding says ASCII for pure ASCII */
        GNM_ASSERT ([session.url isEqual:semi], @"url kept");
        GNM_ASSERT (session.lineCount == 3, @"lines %ld", (long) session.lineCount);
        GNM_ASSERT (session.kind == GnmTextImportSeparated, @"guessed separated");
        NSLog (@"guessed separators '%@' for a .txt (a .csv is guessed by CSV rules)", session.separatorCharacters);
        session.separatorCharacters = @";";
        GNM_ASSERT_EQ_STR (session.separatorCharacters, @";");
        GNM_ASSERT_EQ_STR (session.quoteCharacter, @"\"");
        GNM_ASSERT (session.startLine == 1 && session.stopLine == 3, @"whole range %ld-%ld", (long) session.startLine, (long) session.stopLine);
        GNM_ASSERT (session.lineBreaks & GnmTextLineBreaksUnix, @"unix breaks guessed: %lu", (unsigned long) session.lineBreaks);
        NSArray *preview = [session previewLines:10];
        GNM_ASSERT_EQ_STR (joined (preview), @"id|name|amount/007|Smith, J.|1.5/008|Jones; A.|2");
        GNM_ASSERT ([session previewLines:2].count == 2, @"preview limit");
        GNM_ASSERT (session.columnCount == 3, @"columns %ld", (long) session.columnCount);
        NSArray<NSString *> *guessed = session.columnFormats;
        GNM_ASSERT (guessed.count == 3, @"a format per column: %@", guessed);
        NSLog (@"guessed formats: %@", guessed);

        /* the header line left out */
        session.startLine = 2;
        GNM_ASSERT_EQ_STR (joined ([session previewLines:10]), @"007|Smith, J.|1.5/008|Jones; A.|2");
        session.startLine = 0;   /* clamped */
        GNM_ASSERT (session.startLine == 1, @"clamped start %ld", (long) session.startLine);
        session.stopLine = 99;
        GNM_ASSERT (session.stopLine == 3, @"clamped stop %ld", (long) session.stopLine);
        session.startLine = 2;

        /* the import: the id column as text keeps its zero */
        session.columnFormats = @[@"@", @"General", @"General"];
        GnmWorkbook *wb = [engine importTextSession:session error:&error];
        GNM_ASSERT (wb != nil, @"import: %@", error);
        GNM_ASSERT (wb.sheets.count == 1, @"one sheet");
        GnmSheet *s = wb.sheets.firstObject;
        GNM_ASSERT_EQ_STR (s.name, @"import-semi.txt");
        GNM_ASSERT_EQ_STR ([s displayTextOfCellAtColumn:0 row:0], @"007");
        GNM_ASSERT_EQ_STR ([s displayTextOfCellAtColumn:1 row:0], @"Smith, J.");
        GNM_ASSERT_EQ_STR ([s displayTextOfCellAtColumn:2 row:0], @"1.5");
        GNM_ASSERT_EQ_STR ([s displayTextOfCellAtColumn:1 row:1], @"Jones; A.");
        GNM_ASSERT ([s isCellEmptyAtColumn:0 row:2], @"two rows only");
        /* The location is recorded at the engine's write-only level, as its
         * own text opener does (so Save asks where); NSDocument keeps the
         * file for the document. */
        GNM_ASSERT_EQ_STR (wb.displayName, @"Untitled");
        GNM_ASSERT (!wb.isModified, @"clean after import");
        wb = nil;

        /* without the text format the zero goes; a column left out */
        session.columnFormats = @[];
        session.importedColumns = @[@YES, @NO, @YES];
        wb = [engine importTextSession:session error:&error];
        GNM_ASSERT (wb != nil, @"import 2: %@", error);
        s = wb.sheets.firstObject;
        GNM_ASSERT_EQ_STR ([s displayTextOfCellAtColumn:0 row:0], @"7");
        GNM_ASSERT_EQ_STR ([s displayTextOfCellAtColumn:1 row:0], @"1.5");
        GNM_ASSERT ([s isCellEmptyAtColumn:2 row:0], @"only two columns imported");
        wb = nil;
        session.importedColumns = @[];

        /* separators: a comma instead, custom strings, merged duplicates */
        GnmTextImportSession *text = [GnmTextImportSession sessionWithText:@"a,,b::c\n" name:@"inline"];
        text.separatorCharacters = @",";
        GNM_ASSERT_EQ_STR (joined ([text previewLines:5]), @"a||b::c");
        text.mergesAdjacentSeparators = YES;
        GNM_ASSERT_EQ_STR (joined ([text previewLines:5]), @"a|b::c");
        text.mergesAdjacentSeparators = NO;
        text.customSeparators = @[@"::"];
        GNM_ASSERT_EQ_STR ([text.customSeparators componentsJoinedByString:@" "], @"::");
        GNM_ASSERT_EQ_STR (joined ([text previewLines:5]), @"a||b|c");
        text.quoteCharacter = @"'";
        GNM_ASSERT_EQ_STR (text.quoteCharacter, @"'");
        text.quoteCharacter = @"";
        GNM_ASSERT_EQ_STR (text.quoteCharacter, @"");

        /* Windows line breaks, tabs */
        GnmTextImportSession *tabs = [GnmTextImportSession sessionWithText:@"a\tb\r\nc\td\r\n" name:@"tabs"];
        tabs.lineBreaks = GnmTextLineBreaksWindows;
        GNM_ASSERT (tabs.lineBreaks == GnmTextLineBreaksWindows, @"breaks set");
        tabs.separatorCharacters = @"\t";
        GNM_ASSERT (tabs.lineCount == 2, @"two lines: %ld", (long) tabs.lineCount);
        GNM_ASSERT_EQ_STR (joined ([tabs previewLines:5]), @"a|b/c|d");
        GNM_ASSERT (tabs.stopLine == 2, @"range follows the line count");

        /* fixed width */
        GnmTextImportSession *fixed = [GnmTextImportSession sessionWithText:@"abc  12\ndef  34\n" name:@"fixed"];
        fixed.kind = GnmTextImportFixedWidth;
        GNM_ASSERT (fixed.kind == GnmTextImportFixedWidth, @"kind set");
        [fixed discoverSplitPositions];
        NSLog (@"discovered splits: %@", fixed.splitPositions);
        fixed.splitPositions = @[@5];
        GNM_ASSERT_EQ_STR ([fixed.splitPositions componentsJoinedByString:@","], @"5");
        GNM_ASSERT_EQ_STR (joined ([fixed previewLines:5]), @"abc  |12/def  |34");
        fixed.trimming = GnmTextTrimmingBoth;
        GNM_ASSERT (fixed.trimming == GnmTextTrimmingBoth, @"trimming set");
        wb = [engine importTextSession:fixed error:&error];
        GNM_ASSERT (wb != nil, @"fixed import: %@", error);
        s = wb.sheets.firstObject;
        GNM_ASSERT_EQ_STR ([s displayTextOfCellAtColumn:0 row:0], @"abc");
        GNM_ASSERT_EQ_STR ([s displayTextOfCellAtColumn:1 row:1], @"34");
        GNM_ASSERT (wb.fileURL == nil, @"no file for inline text");
        wb = nil;

        /* an encoding guessed from the bytes, and given */
        const unsigned char latin[] = { 'c', 'a', 'f', 0xe9, ',', '1', '\n' };
        NSURL *latinURL = write_file (dir, @"import-latin1.csv", [NSData dataWithBytes:latin length:sizeof latin]);
        GnmTextImportSession *guessedLatin = [GnmTextImportSession sessionWithContentsOfURL:latinURL encoding:nil error:&error];
        GNM_ASSERT (guessedLatin != nil, @"latin session: %@", error);
        NSLog (@"guessed encoding for Latin-1 bytes: %@", guessedLatin.encoding);
        GNM_ASSERT_EQ_STR (joined ([guessedLatin previewLines:5]), @"café|1");
        GnmTextImportSession *givenLatin = [GnmTextImportSession sessionWithContentsOfURL:latinURL encoding:@"ISO-8859-1" error:&error];
        GNM_ASSERT (givenLatin != nil, @"latin session 2: %@", error);
        GNM_ASSERT_EQ_STR (givenLatin.encoding, @"ISO-8859-1");
        GNM_ASSERT_EQ_STR (joined ([givenLatin previewLines:5]), @"café|1");
        /* an encoding the bytes are not in: the guesser falls back to one
         * that reads them */
        GnmTextImportSession *wrong = [GnmTextImportSession sessionWithContentsOfURL:latinURL encoding:@"UTF-8" error:&error];
        GNM_ASSERT (wrong != nil && ![wrong.encoding isEqualToString:@"UTF-8"], @"fell back from UTF-8 to %@", wrong.encoding);
        GNM_ASSERT_EQ_STR (joined ([wrong previewLines:5]), @"café|1");

        /* the locale that reads numbers */
        GnmTextImportSession *german = [GnmTextImportSession sessionWithText:@"1,5;x\n" name:@"german"];
        german.separatorCharacters = @";";
        german.locale = @"de_DE.UTF-8";
        GNM_ASSERT_EQ_STR (german.locale, @"de_DE.UTF-8");
        wb = [engine importTextSession:german error:&error];
        GNM_ASSERT (wb != nil, @"german import: %@", error);
        NSLog (@"1,5 read in de_DE: %@", [wb.sheets.firstObject displayTextOfCellAtColumn:0 row:0]);
        wb = nil;

        GNM_ASSERT (stray.count == 0, @"stray messages: %@", stray);
      }
        [engine shutdown];
        return gnm_test_finish ("text_import");
    }
}
