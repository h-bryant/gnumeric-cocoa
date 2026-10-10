// Open and save round trips, including error reporting through the command
// context.
#import "GnmTest.h"

int main (void)
{
    @autoreleasepool {
        GnmEngine *engine = gnm_test_start_engine (NO);
      @autoreleasepool {   /* every workbook must be gone before shutdown */
        NSMutableArray<NSError *> *stray = [NSMutableArray array];
        engine.messageHandler = ^(NSError *e) { [stray addObject:e]; };

        NSString *samples = gnm_test_env ("GNM_TEST_SAMPLES");
        NSString *outdir = gnm_test_env ("GNM_TEST_OUT");
        NSError *error = nil;

        /* xlsx in */
        NSURL *xlsx = [NSURL fileURLWithPath:[samples stringByAppendingPathComponent:@"excel12/cellstyle.xlsx"]];
        GnmWorkbook *wb = [engine openWorkbookAtURL:xlsx error:&error];
        GNM_ASSERT (wb != nil, @"open xlsx: %@", error);
        if (!wb) { [engine shutdown]; return gnm_test_finish ("workbook_io"); }
        NSString *a1 = [wb.sheets.firstObject displayTextOfCellAtColumn:0 row:0];
        NSString *sheetName = wb.sheets.firstObject.name;

        /* save as .gnumeric by file name, as explicit saver, and as xlsx */
        NSURL *gnm = [NSURL fileURLWithPath:[outdir stringByAppendingPathComponent:@"bridge-roundtrip.gnumeric"]];
        GNM_ASSERT ([wb writeToURL:gnm error:&error], @"save .gnumeric: %@", error);
        GNM_ASSERT ([wb.fileURL.path isEqualToString:gnm.path], @"workbook adopted the new URL: %@", wb.fileURL);
        GNM_ASSERT (!wb.isModified, @"clean after save");
        NSURL *xml = [NSURL fileURLWithPath:[outdir stringByAppendingPathComponent:@"bridge-roundtrip.xml"]];
        GNM_ASSERT ([wb writeToURL:xml saverIdentifier:@"Gnumeric_XmlIO:sax" error:&error], @"save xml: %@", error);
        NSURL *x2 = [NSURL fileURLWithPath:[outdir stringByAppendingPathComponent:@"bridge-roundtrip.xlsx"]];
        GNM_ASSERT ([wb writeToURL:x2 error:&error], @"save xlsx: %@", error);
        wb = nil;

        /* uncompressed XML must be diffable text (HANDOFF.md Phase 2) */
        NSData *head = [[NSFileHandle fileHandleForReadingAtPath:xml.path] readDataOfLength:5];
        GNM_ASSERT ([head isEqualToData:[@"<?xml" dataUsingEncoding:NSUTF8StringEncoding]], @".xml saver output is plain XML");

        for (NSURL *u in @[gnm, xml, x2]) {
            GnmWorkbook *back = [engine openWorkbookAtURL:u error:&error];
            GNM_ASSERT (back != nil, @"reopen %@: %@", u.lastPathComponent, error);
            if (!back) continue;
            GNM_ASSERT_EQ_STR (back.sheets.firstObject.name, sheetName);
            GNM_ASSERT_EQ_STR ([back.sheets.firstObject displayTextOfCellAtColumn:0 row:0] ?: @"", a1 ?: @"");
        }

        /* a new workbook */
        GnmWorkbook *fresh = [engine newWorkbookWithSheetCount:3];
        GNM_ASSERT (fresh.sheets.count == 3, @"new workbook sheets %lu", (unsigned long) fresh.sheets.count);
        GNM_ASSERT (fresh.fileURL == nil, @"new workbook has no URL");
        GNM_ASSERT_EQ_STR (fresh.displayName, @"Untitled");
        fresh = nil;

        /* saver lookup */
        GNM_ASSERT_EQ_STR ([engine saverIdentifierForFileName:@"x.gnumeric"], @"Gnumeric_XmlIO:sax");
        GNM_ASSERT ([[engine saverIdentifierForFileName:@"x.xlsx"] hasPrefix:@"Gnumeric_Excel:xlsx"], @"xlsx saver");
        GNM_ASSERT ([engine saverIdentifierForFileName:@"x.nonsense"] == nil, @"unknown extension");

        /* errors: missing file, garbage file, unknown save format */
        error = nil;
        NSURL *missing = [NSURL fileURLWithPath:[outdir stringByAppendingPathComponent:@"does-not-exist.gnumeric"]];
        GNM_ASSERT ([engine openWorkbookAtURL:missing error:&error] == nil, @"missing file opens");
        GNM_ASSERT (error.domain == GnmErrorDomain && error.code == GnmErrorOpenFailed, @"error %@", error);
        GNM_ASSERT (error.localizedRecoverySuggestion.length > 0, @"engine message carried: %@", error.userInfo);
        NSLog (@"missing-file error: %@ / %@", error.localizedDescription, error.localizedRecoverySuggestion);

        NSURL *garbage = [NSURL fileURLWithPath:[outdir stringByAppendingPathComponent:@"garbage.gnumeric"]];
        /* gzip magic followed by junk: the Gnumeric XML opener claims it by
         * probe and then fails to parse it.  (Plain text would simply import
         * as CSV, which is not an error.) */
        unsigned char junk[] = { 0x1f, 0x8b, 0x08, 0x00, 'g', 'a', 'r', 'b', 'a', 'g', 'e', '!', 0, 1, 2, 3 };
        [[NSData dataWithBytes:junk length:sizeof junk] writeToURL:garbage atomically:YES];
        error = nil;
        GnmWorkbook *g = [engine openWorkbookAtURL:garbage error:&error];
        GNM_ASSERT (g == nil && error.code == GnmErrorOpenFailed, @"garbage file: wb=%@ error=%@", g, error);
        NSLog (@"garbage-file error: %@ / %@", error.localizedDescription, error.localizedRecoverySuggestion);
        g = nil;

        wb = [engine openWorkbookAtURL:gnm error:&error];
        error = nil;
        NSURL *bad = [NSURL fileURLWithPath:[outdir stringByAppendingPathComponent:@"x.nonsense"]];
        GNM_ASSERT (![wb writeToURL:bad error:&error] && error.code == GnmErrorUnknownFormat, @"unknown format: %@", error);
        error = nil;
        GNM_ASSERT (![wb writeToURL:bad saverIdentifier:@"No_Such:saver" error:&error] && error.code == GnmErrorUnknownFormat, @"unknown saver");
        error = nil;
        NSURL *unwritable = [NSURL fileURLWithPath:@"/nonexistent-dir/x.gnumeric"];
        GNM_ASSERT (![wb writeToURL:unwritable error:&error] && error.code == GnmErrorSaveFailed, @"unwritable: %@", error);
        NSLog (@"unwritable error: %@ / %@", error.localizedDescription, error.localizedRecoverySuggestion);
        wb = nil;

        GNM_ASSERT (stray.count == 0, @"stray engine messages: %@", stray);
      }
        [engine shutdown];
        GNM_ASSERT (GnmEngine.shared == nil, @"shared cleared after shutdown");
    }
    return gnm_test_finish ("workbook_io");
}
