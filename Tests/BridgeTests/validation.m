// Data validation: set on the selection and read back, the editor's
// check with the delegate's choices and the engine's own words, the
// in-cell list, the input message, undo, clearing, and the refusals.
#import "GnmTest.h"

@interface Recorder : NSObject <GnmWorkbookDelegate>
@property (nonatomic) GnmValidationStatus answer;
@property (nonatomic, copy) NSString *message;
@property (nonatomic, copy) NSString *title;
@property (nonatomic) GnmValidationAction action;
@property (nonatomic) NSInteger count;
@end

@implementation Recorder
- (GnmValidationStatus)workbook:(GnmWorkbook *)workbook presentValidationMessage:(NSString *)message title:(NSString *)title
                         action:(GnmValidationAction)action
{
    self.message = message;
    self.title = title;
    self.action = action;
    self.count++;
    return self.answer;
}
@end

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
        for (int r = 0; r < 5; r++) {
            NSString *item = [NSString stringWithFormat:@"%d", r + 1];
            GNM_ASSERT ([s setText:item atColumn:1 row:r autocorrect:NO error:&error], @"list: %@", error);
        }

        /* nothing at first */
        GNM_ASSERT ([s validationAtColumn:0 row:0] == nil, @"no validation");
        GNM_ASSERT ([s validateText:@"anything" atColumn:0 row:0] == GnmValidationStatusValid, @"nothing to check");

        /* whole numbers between 1 and 10 on A1, with an input message */
        [s selectCellAtColumn:0 row:0];
        GnmCellValidation *v = [[GnmCellValidation alloc] init];
        v.kind = GnmValidationKindWholeNumber;
        v.op = GnmValidationOperatorBetween;
        v.firstExpression = @"1";
        v.secondExpression = @"10";
        v.errorTitle = @"Range";
        v.errorMessage = @"1 to 10 only";
        GnmInputMessage *hint = [[GnmInputMessage alloc] initWithTitle:@"Hint" message:@"Enter 1 to 10"];
        GNM_ASSERT ([s setValidation:v inputMessage:hint error:&error], @"set: %@", error);
        GNM_ASSERT_EQ_STR (wb.undoLabel ?: @"", @"Set validation");
        GnmCellValidation *read = [s validationAtColumn:0 row:0];
        GNM_ASSERT (read && read.kind == GnmValidationKindWholeNumber && read.op == GnmValidationOperatorBetween, @"read back: %@", read);
        GNM_ASSERT_EQ_STR (read.firstExpression, @"1");
        GNM_ASSERT_EQ_STR (read.secondExpression, @"10");
        GNM_ASSERT (read.action == GnmValidationActionStop && read.allowsBlank && read.usesDropdown, @"flags: %@", read);
        GNM_ASSERT_EQ_STR (read.errorTitle, @"Range");
        GNM_ASSERT_EQ_STR (read.errorMessage, @"1 to 10 only");
        GnmInputMessage *readHint = [s inputMessageAtColumn:0 row:0];
        GNM_ASSERT (readHint && [readHint.title isEqualToString:@"Hint"] && [readHint.message isEqualToString:@"Enter 1 to 10"], @"hint: %@ %@", readHint.title, readHint.message);
        GNM_ASSERT ([s validationAtColumn:0 row:1] == nil, @"only the selection");

        /* the editor's check without a delegate: Stop discards */
        GNM_ASSERT ([s validateText:@"5" atColumn:0 row:0] == GnmValidationStatusValid, @"5 passes");
        GNM_ASSERT ([s validateText:@"" atColumn:0 row:0] == GnmValidationStatusValid, @"blank allowed");
        GNM_ASSERT ([s validateText:@"11" atColumn:0 row:0] == GnmValidationStatusDiscard, @"11 discarded");
        GNM_ASSERT ([s validateText:@"2.5" atColumn:0 row:0] == GnmValidationStatusDiscard, @"2.5 is not whole");
        GNM_ASSERT ([s validateText:@"abc" atColumn:0 row:0] == GnmValidationStatusDiscard, @"text refused");
        GNM_ASSERT ([s isCellEmptyAtColumn:0 row:0], @"the cell is restored");

        /* with a delegate: the dialog's words and the chosen answer */
        Recorder *recorder = [[Recorder alloc] init];
        wb.delegate = recorder;
        recorder.answer = GnmValidationStatusEdit;
        GNM_ASSERT ([s validateText:@"11" atColumn:0 row:0] == GnmValidationStatusEdit, @"re-edit");
        GNM_ASSERT (recorder.count == 1 && recorder.action == GnmValidationActionStop, @"asked once as Stop: %ld %ld", (long) recorder.count, (long) recorder.action);
        GNM_ASSERT_EQ_STR (recorder.title, @"Range");
        GNM_ASSERT_EQ_STR (recorder.message, @"1 to 10 only");
        GNM_ASSERT ([s validateText:@"5" atColumn:0 row:0] == GnmValidationStatusValid && recorder.count == 1, @"a pass asks nothing");

        /* a warning that the user accepts, with the engine's own words */
        v.action = GnmValidationActionWarning;
        v.errorTitle = @"";
        v.errorMessage = @"";
        GNM_ASSERT ([s setValidation:v inputMessage:nil error:&error], @"warning: %@", error);
        GNM_ASSERT ([s inputMessageAtColumn:0 row:0] == nil, @"hint cleared");
        recorder.answer = GnmValidationStatusValid;
        GNM_ASSERT ([s validateText:@"11" atColumn:0 row:0] == GnmValidationStatusValid, @"accepted");
        NSLog (@"validation: engine words: title '%@' message '%@'", recorder.title, recorder.message);
        GNM_ASSERT ([recorder.message containsString:@"out of permitted range"] && recorder.action == GnmValidationActionWarning, @"words: %@", recorder.message);
        v.action = GnmValidationActionNone;
        GNM_ASSERT ([s setValidation:v inputMessage:nil error:&error], @"none: %@", error);
        NSInteger asked = recorder.count;
        GNM_ASSERT ([s validateText:@"11" atColumn:0 row:0] == GnmValidationStatusValid && recorder.count == asked, @"None accepts silently");

        /* undo */
        [wb undo];
        [wb undo];
        GNM_ASSERT ([s validationAtColumn:0 row:0].action == GnmValidationActionStop, @"undone to the first");
        [wb undo];
        GNM_ASSERT ([s validationAtColumn:0 row:0] == nil && [s inputMessageAtColumn:0 row:0] == nil, @"undone to none");

        /* in a list, with the in-cell choices */
        [s selectCellAtColumn:2 row:0];
        GnmCellValidation *list = [[GnmCellValidation alloc] init];
        list.kind = GnmValidationKindInList;
        list.firstExpression = @"$B$1:$B$5";
        GNM_ASSERT ([s setValidation:list inputMessage:nil error:&error], @"list: %@", error);
        GNM_ASSERT_EQ_STR ([[s validationChoicesAtColumn:2 row:0] componentsJoinedByString:@","], @"1,2,3,4,5");
        GNM_ASSERT ([s validationChoicesAtColumn:3 row:0] == nil, @"no list elsewhere");
        GNM_ASSERT ([s validateText:@"3" atColumn:2 row:0] == GnmValidationStatusValid, @"in the list");
        recorder.answer = GnmValidationStatusDiscard;
        GNM_ASSERT ([s validateText:@"7" atColumn:2 row:0] == GnmValidationStatusDiscard, @"not in the list");
        GNM_ASSERT ([recorder.message containsString:@"does not contain the new value"], @"list words: %@", recorder.message);
        list.usesDropdown = NO;
        GNM_ASSERT ([s setValidation:list inputMessage:nil error:&error], @"no dropdown: %@", error);
        GNM_ASSERT ([s validationChoicesAtColumn:2 row:0] == nil, @"list off");

        /* custom, relative to the cell */
        [s selectCellAtColumn:0 row:2];
        GnmCellValidation *custom = [[GnmCellValidation alloc] init];
        custom.kind = GnmValidationKindCustom;
        custom.firstExpression = @"A3>0";
        GNM_ASSERT ([s setValidation:custom inputMessage:nil error:&error], @"custom: %@", error);
        GNM_ASSERT_EQ_STR ([s validationAtColumn:0 row:2].firstExpression, @"A3>0");
        GNM_ASSERT ([s validateText:@"5" atColumn:0 row:2] == GnmValidationStatusValid, @"custom passes");
        GNM_ASSERT ([s validateText:@"-1" atColumn:0 row:2] == GnmValidationStatusDiscard, @"custom fails");
        GNM_ASSERT ([recorder.message containsString:@"is not true"], @"custom words: %@", recorder.message);

        /* text length, then cleared */
        [s selectCellAtColumn:0 row:4];
        GnmCellValidation *length = [[GnmCellValidation alloc] init];
        length.kind = GnmValidationKindTextLength;
        length.op = GnmValidationOperatorLessOrEqual;
        length.firstExpression = @"3";
        GNM_ASSERT ([s setValidation:length inputMessage:nil error:&error], @"length: %@", error);
        GNM_ASSERT ([s validateText:@"abc" atColumn:0 row:4] == GnmValidationStatusValid, @"3 letters");
        GNM_ASSERT ([s validateText:@"abcd" atColumn:0 row:4] == GnmValidationStatusDiscard, @"4 letters");
        GNM_ASSERT ([s setValidation:nil inputMessage:nil error:&error], @"clear: %@", error);
        GNM_ASSERT ([s validationAtColumn:0 row:4] == nil, @"cleared");

        /* refusals */
        error = nil;
        GnmCellValidation *bad = [[GnmCellValidation alloc] init];
        bad.kind = GnmValidationKindNumber;
        bad.firstExpression = @"1";
        bad.secondExpression = @"";
        GNM_ASSERT (![s setValidation:bad inputMessage:nil error:&error] && [error.localizedDescription containsString:@"second value"], @"missing: %@", error);
        error = nil;
        bad.secondExpression = @"=(";
        GNM_ASSERT (![s setValidation:bad inputMessage:nil error:&error] && error, @"unparsable: %@", error);
        NSLog (@"validation: parse refusal '%@'", error.localizedDescription);

        /* the labels */
        GNM_ASSERT ([GnmCellValidation operandCountForKind:GnmValidationKindAny operator:GnmValidationOperatorBetween] == 0, @"any takes none");
        GNM_ASSERT ([GnmCellValidation operandCountForKind:GnmValidationKindInList operator:GnmValidationOperatorBetween] == 1, @"list takes one");
        GNM_ASSERT ([GnmCellValidation operandCountForKind:GnmValidationKindDate operator:GnmValidationOperatorNotBetween] == 2, @"not between takes two");
        GNM_ASSERT_EQ_STR ([GnmCellValidation firstOperandLabelForKind:GnmValidationKindNumber operator:GnmValidationOperatorLessThan], @"Max:");
        GNM_ASSERT_EQ_STR ([GnmCellValidation firstOperandLabelForKind:GnmValidationKindInList operator:GnmValidationOperatorBetween], @"Source");

        GNM_ASSERT (stray.count == 0, @"stray messages: %@", stray);
        wb.delegate = nil;
        wb = nil;
      }
        [engine shutdown];
        return gnm_test_finish ("validation");
    }
}
