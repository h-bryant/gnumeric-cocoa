// Open and save round trips, including error reporting through the command
// context.
#import "GnmTest.h"

int main (void)
{
    @autoreleasepool {
        /* The app's choice: .gnumeric files as plain XML (level 0). */
        GnmEngineConfiguration *cfg = gnm_test_configuration (NO);
        cfg.xmlCompressionLevel = @0;
        GnmEngine *engine = gnm_test_start_engine_with (cfg);
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
        /* and with the compression level at 0, so is the .gnumeric file */
        head = [[NSFileHandle fileHandleForReadingAtPath:gnm.path] readDataOfLength:5];
        GNM_ASSERT ([head isEqualToData:[@"<?xml" dataUsingEncoding:NSUTF8StringEncoding]], @".gnumeric at level 0 is plain XML");

        /* a staged save (NSDocument's way): the file is written, the
         * location stays until adopted */
        wb = [engine openWorkbookAtURL:gnm error:&error];
        GNM_ASSERT (wb != nil, @"reopen: %@", error);
        NSURL *staged = [NSURL fileURLWithPath:[outdir stringByAppendingPathComponent:@"bridge-staged.gnumeric"]];
        [[NSFileManager defaultManager] removeItemAtURL:staged error:NULL];
        GNM_ASSERT ([wb writeToURL:staged adoptingURL:NO error:&error], @"staged save: %@", error);
        GNM_ASSERT ([wb.fileURL.path isEqualToString:gnm.path], @"location kept: %@", wb.fileURL);
        GNM_ASSERT (!wb.isModified, @"clean after a staged save");
        head = [[NSFileHandle fileHandleForReadingAtPath:staged.path] readDataOfLength:5];
        GNM_ASSERT ([head isEqualToData:[@"<?xml" dataUsingEncoding:NSUTF8StringEncoding]], @"staged file written");
        [wb adoptFileURL:staged];
        GNM_ASSERT ([wb.fileURL.path isEqualToString:staged.path], @"adopted: %@", wb.fileURL);
        GNM_ASSERT_EQ_STR (wb.displayName, @"bridge-staged.gnumeric");
        /* the document's saver for its .xml type: the always-uncompressed
         * twin, by id, since a staged name lacks the extension */
        NSURL *stagedXml = [NSURL fileURLWithPath:[outdir stringByAppendingPathComponent:@"bridge-staged.xml.sb-1234"]];
        GNM_ASSERT ([wb writeToURL:stagedXml saverIdentifier:@"Gnumeric_XmlIO:sax:0" adoptingURL:NO error:&error], @"staged xml: %@", error);
        GNM_ASSERT ([wb.fileURL.path isEqualToString:staged.path], @"location kept after the xml save");
        head = [[NSFileHandle fileHandleForReadingAtPath:stagedXml.path] readDataOfLength:5];
        GNM_ASSERT ([head isEqualToData:[@"<?xml" dataUsingEncoding:NSUTF8StringEncoding]], @"sax:0 writes plain XML under any name");
        GNM_ASSERT ([engine saverIdentifierForFileName:@"x.gnumeric.sb-1234"] == nil, @"a staged name has no saver of its own");
        [[NSFileManager defaultManager] removeItemAtURL:stagedXml error:NULL];
        wb = nil;

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

        /* delimited text: a CSV opens through the engine's text importer and
         * the current sheet saves back as CSV (Gnumeric_stf:stf_csv) */
        {
            NSURL *csv = [NSURL fileURLWithPath:[outdir stringByAppendingPathComponent:@"bridge-cells.csv"]];
            [@"name,value\nalpha,1\nbeta,2.5\n" writeToURL:csv atomically:YES encoding:NSUTF8StringEncoding error:NULL];
            GnmWorkbook *text = [engine openWorkbookAtURL:csv error:&error];
            GNM_ASSERT (text != nil, @"open csv: %@", error);
            GnmSheet *ts = text.sheets.firstObject;
            GNM_ASSERT_EQ_STR ([ts displayTextOfCellAtColumn:0 row:1] ?: @"", @"alpha");
            GNM_ASSERT_EQ_STR ([ts displayTextOfCellAtColumn:1 row:2] ?: @"", @"2.5");
            GNM_ASSERT ([ts setText:@"gamma" atColumn:0 row:3 autocorrect:NO error:&error], @"edit csv: %@", error);
            NSURL *out = [NSURL fileURLWithPath:[outdir stringByAppendingPathComponent:@"bridge-cells-out.csv"]];
            GNM_ASSERT ([text writeToURL:out saverIdentifier:@"Gnumeric_stf:stf_csv" adoptingURL:NO error:&error], @"save csv: %@", error);
            NSString *written = [NSString stringWithContentsOfURL:out encoding:NSUTF8StringEncoding error:NULL];
            GNM_ASSERT ([written containsString:@"beta,2.5"] && [written containsString:@"gamma"], @"csv written: %@", written);
            GNM_ASSERT_EQ_STR ([engine saverIdentifierForFileName:@"x.csv"] ?: @"", @"Gnumeric_stf:stf_csv");
            /* Repeat Export: the CSV save was an export; a later edit reaches the file again */
            GNM_ASSERT ([text.lastExportURL.path isEqualToString:out.path], @"last export %@", text.lastExportURL);
            GNM_ASSERT (text.lastExporterDescription.length > 0 && text.lastExporterWritesSingleSheet, @"exporter %@", text.lastExporterDescription);
            GNM_ASSERT ([ts setText:@"delta" atColumn:0 row:4 autocorrect:NO error:&error], @"edit for repeat: %@", error);
            GNM_ASSERT ([text repeatExportWithError:&error], @"repeat: %@", error);
            written = [NSString stringWithContentsOfURL:out encoding:NSUTF8StringEncoding error:NULL];
            GNM_ASSERT ([written containsString:@"delta"], @"repeated export holds the edit: %@", written);
            GNM_ASSERT ([text.lastExportURL.path isEqualToString:out.path], @"still remembered");
            text = nil; ts = nil;
        }

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
        GNM_ASSERT (wb.lastExportURL == nil && ![wb repeatExportWithError:&error] && error, @"nothing to repeat yet: %@", error);
        error = nil;
        NSURL *bad = [NSURL fileURLWithPath:[outdir stringByAppendingPathComponent:@"x.nonsense"]];
        GNM_ASSERT (![wb writeToURL:bad error:&error] && error.code == GnmErrorUnknownFormat, @"unknown format: %@", error);
        error = nil;
        GNM_ASSERT (![wb writeToURL:bad saverIdentifier:@"No_Such:saver" error:&error] && error.code == GnmErrorUnknownFormat, @"unknown saver");
        error = nil;
        NSURL *unwritable = [NSURL fileURLWithPath:@"/nonexistent-dir/x.gnumeric"];
        GNM_ASSERT (![wb writeToURL:unwritable error:&error] && error.code == GnmErrorSaveFailed, @"unwritable: %@", error);
        NSLog (@"unwritable error: %@ / %@", error.localizedDescription, error.localizedRecoverySuggestion);

        /* a copy for Send To: the document's state stays */
        GnmSheet *copySheet = wb.sheets.firstObject;
        GNM_ASSERT ([copySheet setText:@"changed" atColumn:0 row:0 autocorrect:NO error:&error], @"edit before copy: %@", error);
        GNM_ASSERT (wb.isModified, @"modified before the copy");
        NSURL *copy = [NSURL fileURLWithPath:[outdir stringByAppendingPathComponent:@"bridge-copy.gnumeric"]];
        error = nil;
        GNM_ASSERT ([wb writeCopyToURL:copy saverIdentifier:@"Gnumeric_XmlIO:sax:0" error:&error], @"copy: %@", error);
        GNM_ASSERT (wb.isModified, @"still modified after the copy");
        GNM_ASSERT ([wb.fileURL.lastPathComponent isEqualToString:gnm.lastPathComponent], @"location kept: %@", wb.fileURL);
        NSString *copied = [NSString stringWithContentsOfURL:copy encoding:NSUTF8StringEncoding error:NULL];
        GNM_ASSERT ([copied containsString:@"changed"], @"the copy holds the edit: %lu bytes", (unsigned long) copied.length);
        error = nil;
        GNM_ASSERT (![wb writeCopyToURL:unwritable saverIdentifier:@"Gnumeric_XmlIO:sax" error:&error] && error.code == GnmErrorSaveFailed, @"copy unwritable: %@", error);
        error = nil;
        GNM_ASSERT (![wb writeCopyToURL:copy saverIdentifier:@"No_Such:saver" error:&error] && error.code == GnmErrorUnknownFormat, @"copy unknown saver");
        wb = nil;

        GNM_ASSERT (stray.count == 0, @"stray engine messages: %@", stray);
      }
        [engine shutdown];
        GNM_ASSERT (GnmEngine.shared == nil, @"shared cleared after shutdown");
    }
    return gnm_test_finish ("workbook_io");
}
