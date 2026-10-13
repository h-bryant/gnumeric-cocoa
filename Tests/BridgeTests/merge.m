// Data → Merge: the zone copied to one sheet per data row with the fields
// filled, the dialog's refusals, the trimming, and undo.
#import "GnmTest.h"

int main (void)
{
    @autoreleasepool {
        GnmEngine *engine = gnm_test_start_engine (NO);
        NSMutableArray<NSError *> *stray = [NSMutableArray array];
        engine.messageHandler = ^(NSError *e) { [stray addObject:e]; };
      @autoreleasepool {
        NSError *error = nil;
        GnmWorkbook *wb = [engine newWorkbookWithSheetCount:1];
        GnmSheet *s = wb.sheets.firstObject;
        /* the zone A1:B3: a letter with the name in B1 and the city in B2 */
        GNM_ASSERT ([s setText:@"Dear" atColumn:0 row:0 autocorrect:NO error:&error], @"zone: %@", error);
        GNM_ASSERT ([s setText:@"City" atColumn:0 row:1 autocorrect:NO error:&error], @"zone: %@", error);
        GNM_ASSERT ([s setText:@"=B1&\" of \"&B2" atColumn:0 row:2 autocorrect:NO error:&error], @"zone formula: %@", error);
        /* the data: names in D1:D3, cities in E1:E3, a short column in F1:F2 */
        NSArray *names = @[@"Ann", @"Bob", @"Cy"], *cities = @[@"Austin", @"Bryan", @"Conroe"];
        for (NSUInteger i = 0; i < 3; i++) {
            GNM_ASSERT ([s setText:names[i] atColumn:3 row:(NSInteger) i autocorrect:NO error:&error], @"names: %@", error);
            GNM_ASSERT ([s setText:cities[i] atColumn:4 row:(NSInteger) i autocorrect:NO error:&error], @"cities: %@", error);
        }
        GNM_ASSERT ([s setText:@"1" atColumn:5 row:0 autocorrect:NO error:&error] && [s setText:@"2" atColumn:5 row:1 autocorrect:NO error:&error], @"short: %@", error);

        /* the dialog's checks */
        GNM_ASSERT ([s isRangeText:@"A1:B3" singleCell:NO] && [s isRangeText:@"B1" singleCell:YES], @"ranges");
        GNM_ASSERT (![s isRangeText:@"A1:B3" singleCell:YES] && ![s isRangeText:@"junk" singleCell:NO] && ![s isRangeText:@"" singleCell:NO], @"not ranges");
        NSInteger shortest = 0, longest = 0;
        NSArray *namesAndShort = @[@"D1:D3", @"F1:F2"], *namesAndJunk = @[@"D1:D3", @"junk"];
        NSArray *namesAndCities = @[@"D1:D3", @"E1:E3"], *twoFields = @[@"B1", @"B2"], *twoOutside = @[@"C1", @"C2"];
        BOOL lengthsOK = [s mergeDataLengths:namesAndShort shortest:&shortest longest:&longest];
        GNM_ASSERT (lengthsOK && shortest == 2 && longest == 3, @"lengths %ld %ld", (long) shortest, (long) longest);
        BOOL badLengths = [s mergeDataLengths:namesAndJunk shortest:&shortest longest:&longest];
        GNM_ASSERT (!badLengths, @"bad length text");

        /* refusals */
        error = nil;
        GNM_ASSERT (![s mergeDataIntoZone:@"A1:B3" fields:@[@"C1"] data:@[@"D1:D3"] trimmingToShortest:NO error:&error], @"field outside");
        GNM_ASSERT_EQ_STR (error.localizedDescription, @"One field is not part of the merge zone!");
        error = nil;
        BOOL outside = [s mergeDataIntoZone:@"A1:B3" fields:twoOutside data:namesAndCities trimmingToShortest:NO error:&error];
        GNM_ASSERT (!outside, @"two outside");
        GNM_ASSERT_EQ_STR (error.localizedDescription, @"2 fields are not part of the merge zone!");
        error = nil;
        BOOL unequal = [s mergeDataIntoZone:@"A1:B3" fields:twoFields data:namesAndShort trimmingToShortest:NO error:&error];
        GNM_ASSERT (!unequal, @"unequal");
        GNM_ASSERT ([error.localizedDescription hasPrefix:@"The data columns range in length from 2 to 3."], @"question: %@", error.localizedDescription);
        error = nil;
        GNM_ASSERT (![s mergeDataIntoZone:@"junk" fields:@[@"B1"] data:@[@"D1:D3"] trimmingToShortest:NO error:&error], @"bad zone");
        GNM_ASSERT (![s mergeDataIntoZone:@"A1:B3" fields:@[] data:@[] trimmingToShortest:NO error:&error], @"nothing to merge");
        GNM_ASSERT (wb.sheets.count == 1, @"nothing added by refusals: %lu", (unsigned long) wb.sheets.count);

        /* the merge: three sheets */
        BOOL merged = [s mergeDataIntoZone:@"A1:B3" fields:twoFields data:namesAndCities trimmingToShortest:NO error:&error];
        GNM_ASSERT (merged, @"merge: %@", error);
        GNM_ASSERT_EQ_STR (wb.undoLabel ?: @"", @"Merging data into Sheet1!A1:B3");
        GNM_ASSERT (wb.sheets.count == 4, @"three new sheets: %lu", (unsigned long) wb.sheets.count);
        for (NSUInteger i = 0; i < 3; i++) {
            GnmSheet *t = wb.sheets[i + 1];
            GNM_ASSERT_EQ_STR ([t displayTextOfCellAtColumn:0 row:0] ?: @"", @"Dear");
            GNM_ASSERT_EQ_STR ([t displayTextOfCellAtColumn:1 row:0] ?: @"", names[i]);
            GNM_ASSERT_EQ_STR ([t displayTextOfCellAtColumn:1 row:1] ?: @"", cities[i]);
            NSString *expected = [NSString stringWithFormat:@"%@ of %@", names[i], cities[i]];
            GNM_ASSERT_EQ_STR ([t displayTextOfCellAtColumn:0 row:2] ?: @"", expected);
            GNM_ASSERT ([t displayTextOfCellAtColumn:3 row:0] == nil, @"outside the zone not copied");
        }
        [wb undo];
        GNM_ASSERT (wb.sheets.count == 1, @"undo removes the sheets: %lu", (unsigned long) wb.sheets.count);
        [wb redo];
        GNM_ASSERT (wb.sheets.count == 4, @"redo brings them back");
        [wb undo];

        /* trimming to the shortest column */
        BOOL trimmed = [s mergeDataIntoZone:@"A1:B3" fields:twoFields data:namesAndShort trimmingToShortest:YES error:&error];
        GNM_ASSERT (trimmed, @"trimmed merge: %@", error);
        GNM_ASSERT (wb.sheets.count == 3, @"two sheets for two rows: %lu", (unsigned long) wb.sheets.count);
        GNM_ASSERT_EQ_STR ([wb.sheets[2] displayTextOfCellAtColumn:1 row:1] ?: @"", @"2");
        [wb undo];

        GNM_ASSERT (stray.count == 0, @"stray messages: %@", stray);
        wb = nil;
      }
        [engine shutdown];
        return gnm_test_finish ("merge");
    }
}
