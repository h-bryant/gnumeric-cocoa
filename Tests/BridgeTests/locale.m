// The engine's messages follow the process locale (gnm_pre_parse_init's
// setlocale, the catalogs under the locale directory): started under
// German, a new workbook's sheet is "Blatt1", a catalog lookup
// translates, the undo label is German, and "1,5" is a number.
#import "GnmTest.h"

int main (void)
{
    setenv ("LANG", "de_DE.UTF-8", 1);
    setenv ("LC_ALL", "de_DE.UTF-8", 1);
    setenv ("LANGUAGE", "de", 1);
    @autoreleasepool {
        GnmEngine *engine = gnm_test_start_engine (NO);
      @autoreleasepool {   /* every workbook must be gone before shutdown */
        NSError *error = nil;
        GNM_ASSERT ([engine.messagesLocale hasPrefix:@"de_DE"], @"messages locale %@", engine.messagesLocale);
        NSString *catalogs = [engine.localeDirectory stringByAppendingPathComponent:@"de/LC_MESSAGES"];
        NSArray *files = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:catalogs error:NULL] ?: @[];
        NSUInteger ours = [[files filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"self BEGINSWITH 'gnumeric-'"]] count];
        GNM_ASSERT (ours >= 2, @"engine and function catalogs in %@: %@", catalogs, files);
        NSString *translated = [engine localizedString:@"Sheet%d"];
        GNM_ASSERT ([translated isEqualToString:@"Blatt%d"], @"'Sheet%%d' in German: %@", translated);
        GNM_ASSERT ([[engine localizedString:@"No such message here"] isEqualToString:@"No such message here"], @"unknown messages come back as they are");
        GNM_ASSERT ([[engine localizedString:@"_Open"] isEqualToString:@"_Open"], @"a stock label is not a plain message");
        NSString *stock = [engine localizedString:@"_Open" context:@"Stock label"];
        GNM_ASSERT ([stock isEqualToString:@"Ö_ffnen"], @"'_Open' under its context: %@", stock);

        GnmWorkbook *wb = [engine newWorkbookWithSheetCount:1];
        GnmSheet *sheet = wb.sheets.firstObject;
        GNM_ASSERT ([sheet.name isEqualToString:@"Blatt1"], @"new sheet named %@", sheet.name);
        GNM_ASSERT ([sheet setText:@"1,5" atColumn:0 row:0 autocorrect:NO error:&error], @"typing 1,5: %@", error);
        GNM_ASSERT ([wb.undoLabel containsString:@"eingegeben"], @"undo label %@", wb.undoLabel);
        GNM_ASSERT ([sheet setText:@"=A1*2" atColumn:1 row:0 autocorrect:NO error:&error], @"typing the formula: %@", error);
        NSString *b1 = [sheet displayTextOfCellAtColumn:1 row:0];
        GNM_ASSERT ([b1 isEqualToString:@"3"], @"1,5 doubled shows %@ (a comma is the decimal separator)", b1);
        wb = nil;
      }
        [engine shutdown];
    }
    return gnm_test_finish ("locale");
}
