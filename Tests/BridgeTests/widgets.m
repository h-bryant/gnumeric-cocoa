// Form widgets: their kinds and configuration in the object sample,
// the configuration commands and their undo, and insertion.
#import "GnmTest.h"

static GnmSheetObject *
first_of_kind (NSArray<GnmSheetObject *> *objects, GnmWidgetKind kind)
{
    for (GnmSheetObject *o in objects)
        if (o.widgetKind == kind)
            return o;
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
        NSURL *url = [NSURL fileURLWithPath:[gnm_test_env ("GNM_TEST_SAMPLES") stringByAppendingPathComponent:@"object-tests.gnumeric"]];
        GnmWorkbook *wb = [engine openWorkbookAtURL:url error:&error];
        GNM_ASSERT (wb != nil, @"open: %@", error);
        if (!wb) { [engine shutdown]; return gnm_test_finish ("widgets"); }
        NSMutableArray<GnmSheetObject *> *objects = [NSMutableArray array];
        GnmSheet *host = nil;
        for (GnmSheet *sheet in wb.sheets)
            for (GnmSheetObject *o in sheet.sheetObjects)
                if (o.widgetKind != GnmWidgetKindNone) {
                    [objects addObject:o];
                    if (!host) host = sheet;
                }
        NSMutableDictionary *counts = [NSMutableDictionary dictionary];
        for (GnmSheetObject *o in objects)
            counts[[GnmSheet nameOfWidgetKind:o.widgetKind]] = @([counts[[GnmSheet nameOfWidgetKind:o.widgetKind]] intValue] + 1);
        NSLog (@"widgets: %@", counts);
        GNM_ASSERT (objects.count >= 20 && counts[@"Button"] && counts[@"Checkbox"] && counts[@"Scrollbar"] && counts[@"List"], @"the sample's widgets: %@", counts);
        GnmSheet *s = host;
        [wb selectSheet:s];

        GnmSheetObject *button = first_of_kind (objects, GnmWidgetKindButton);
        GnmSheet *buttonSheet = button.sheet;
        GnmWidgetSettings *settings = [buttonSheet widgetSettingsOfSheetObject:button];
        NSLog (@"widgets: button %@", settings);
        GNM_ASSERT (settings && settings.kind == GnmWidgetKindButton && [settings.title isEqualToString:@"Button Properties"], @"button settings: %@", settings);
        NSString *oldLabel = settings.label;
        settings.label = @"Press";
        settings.linkText = @"Z1";
        GNM_ASSERT ([buttonSheet applyWidgetSettings:settings toSheetObject:button error:&error], @"apply: %@", error);
        GnmWidgetSettings *after = [buttonSheet widgetSettingsOfSheetObject:button];
        GNM_ASSERT_EQ_STR (after.label, @"Press");
        GNM_ASSERT ([after.linkText hasSuffix:@"Z1"], @"link set: '%@'", after.linkText);
        [wb undo];
        after = [buttonSheet widgetSettingsOfSheetObject:button];
        GNM_ASSERT_EQ_STR (after.label, oldLabel);
        settings.linkText = @"not a ref(";
        GNM_ASSERT (![buttonSheet applyWidgetSettings:settings toSheetObject:button error:&error] && [error.localizedDescription containsString:@"not a valid reference"], @"bad link: %@", error);

        GnmSheetObject *check = first_of_kind (objects, GnmWidgetKindCheckbox);
        settings = [check.sheet widgetSettingsOfSheetObject:check];
        NSLog (@"widgets: checkbox %@", settings);
        settings.label = @"Agreed";
        GNM_ASSERT ([check.sheet applyWidgetSettings:settings toSheetObject:check error:&error], @"checkbox: %@", error);
        GNM_ASSERT_EQ_STR ([check.sheet widgetSettingsOfSheetObject:check].label, @"Agreed");

        GnmSheetObject *radio = first_of_kind (objects, GnmWidgetKindRadioButton);
        if (radio) {
            settings = [radio.sheet widgetSettingsOfSheetObject:radio];
            NSLog (@"widgets: radio %@", settings);
            settings.valueText = @"42";
            settings.label = @"Forty-two";
            GNM_ASSERT ([radio.sheet applyWidgetSettings:settings toSheetObject:radio error:&error], @"radio: %@", error);
            after = [radio.sheet widgetSettingsOfSheetObject:radio];
            GNM_ASSERT ([after.valueText isEqualToString:@"42"] && [after.label isEqualToString:@"Forty-two"], @"radio after: %@", after);
        }

        GnmSheetObject *scrollbar = first_of_kind (objects, GnmWidgetKindScrollbar);
        settings = [scrollbar.sheet widgetSettingsOfSheetObject:scrollbar];
        NSLog (@"widgets: scrollbar %@", settings);
        GNM_ASSERT ([settings.title isEqualToString:@"Scrollbar Properties"], @"title");
        settings.minimum = 5;
        settings.maximum = 50;
        settings.increment = 2;
        settings.pageIncrement = 8;
        settings.horizontal = !settings.horizontal;
        BOOL wasHorizontal = !settings.horizontal;
        GNM_ASSERT ([scrollbar.sheet applyWidgetSettings:settings toSheetObject:scrollbar error:&error], @"scrollbar: %@", error);
        GNM_ASSERT_EQ_STR (wb.undoLabel ?: @"", @"Configure Scrollbar");
        after = [scrollbar.sheet widgetSettingsOfSheetObject:scrollbar];
        BOOL rangeSet = after.minimum == 5 && after.maximum == 50 && after.increment == 2 && after.pageIncrement == 8 && after.horizontal != wasHorizontal;
        GNM_ASSERT (rangeSet, @"scrollbar after: %@", after);
        [wb undo];
        after = [scrollbar.sheet widgetSettingsOfSheetObject:scrollbar];
        GNM_ASSERT (after.horizontal == wasHorizontal && after.minimum != 5, @"scrollbar undone: %@", after);

        GnmSheetObject *list = first_of_kind (objects, GnmWidgetKindList);
        settings = [list.sheet widgetSettingsOfSheetObject:list];
        NSLog (@"widgets: list %@", settings);
        settings.contentText = @"A1:A3";
        settings.linkText = @"B1";
        settings.outputsIndex = YES;
        GNM_ASSERT ([list.sheet applyWidgetSettings:settings toSheetObject:list error:&error], @"list: %@", error);
        after = [list.sheet widgetSettingsOfSheetObject:list];
        GNM_ASSERT ([after.contentText hasSuffix:@"A1:A3"] && [after.linkText hasSuffix:@"B1"] && after.outputsIndex, @"list after: %@", after);
        GNM_ASSERT (![s widgetSettingsOfSheetObject:s.sheetObjects.firstObject] || s.sheetObjects.firstObject.widgetKind != GnmWidgetKindNone, @"a non-widget has no settings");
        wb = nil;

        /* insertion of every kind in a fresh workbook */
        wb = [engine newWorkbookWithSheetCount:1];
        s = wb.sheets.firstObject;
        for (NSInteger kind = GnmWidgetKindFrame; kind <= GnmWidgetKindCombo; kind++) {
            GnmSheetObject *made = [s insertWidgetOfKind:(GnmWidgetKind) kind frame:CGRectMake (20 * kind, 10, 100, 30) error:&error];
            GNM_ASSERT (made != nil && made.widgetKind == kind, @"insert %@: %@", [GnmSheet nameOfWidgetKind:(GnmWidgetKind) kind], error);
            GnmWidgetSettings *fresh = [s widgetSettingsOfSheetObject:made];
            GNM_ASSERT (fresh != nil && fresh.kind == kind, @"fresh settings for %@", [GnmSheet nameOfWidgetKind:(GnmWidgetKind) kind]);
        }
        GNM_ASSERT (s.sheetObjects.count == 9, @"nine widgets: %lu", (unsigned long) s.sheetObjects.count);
        GNM_ASSERT_EQ_STR (wb.undoLabel ?: @"", @"Insert 1 Object");
        [wb undo];
        GNM_ASSERT (s.sheetObjects.count == 8, @"one insertion undone");
        GNM_ASSERT ([s insertWidgetOfKind:GnmWidgetKindNone frame:CGRectMake (0, 0, 10, 10) error:&error] == nil, @"no kind, no widget");
        /* links on fresh widgets, left in place when the workbook goes */
        GnmSheetObject *fresh = [s insertWidgetOfKind:GnmWidgetKindButton frame:CGRectMake (10, 10, 80, 24) error:&error];
        GnmWidgetSettings *freshSettings = [s widgetSettingsOfSheetObject:fresh];
        freshSettings.linkText = @"C1";
        freshSettings.label = @"Go";
        GNM_ASSERT ([s applyWidgetSettings:freshSettings toSheetObject:fresh error:&error], @"fresh link: %@", error);
        GnmSheetObject *freshBar = [s insertWidgetOfKind:GnmWidgetKindScrollbar frame:CGRectMake (10, 50, 20, 100) error:&error];
        GnmWidgetSettings *barSettings = [s widgetSettingsOfSheetObject:freshBar];
        barSettings.linkText = @"C2";
        GNM_ASSERT ([s applyWidgetSettings:barSettings toSheetObject:freshBar error:&error], @"fresh bar link: %@", error);

        /* widgets that act: each change lands in the linked cell */
        GnmSheetObject *box = [s insertWidgetOfKind:GnmWidgetKindCheckbox frame:CGRectMake (10, 100, 80, 20) error:&error];
        GnmWidgetSettings *boxSettings = [s widgetSettingsOfSheetObject:box];
        boxSettings.linkText = @"C1";
        boxSettings.label = @"Agree";
        GNM_ASSERT ([s applyWidgetSettings:boxSettings toSheetObject:box error:&error], @"box link: %@", error);
        GNM_ASSERT (![s widgetIsActive:box], @"off to start");
        GNM_ASSERT ([s clickWidget:box error:&error], @"click: %@", error);
        GNM_ASSERT_EQ_STR ([s displayTextOfCellAtColumn:2 row:0] ?: @"", @"TRUE");
        GNM_ASSERT ([s widgetIsActive:box], @"the widget follows the cell");
        GNM_ASSERT_EQ_STR (wb.undoLabel ?: @"", @"Clicking checkbox");
        GNM_ASSERT ([s clickWidget:box error:&error] && ![s widgetIsActive:box], @"toggled off: %@", error);
        GNM_ASSERT_EQ_STR ([s displayTextOfCellAtColumn:2 row:0] ?: @"", @"FALSE");
        GnmSheetObject *loose = [s insertWidgetOfKind:GnmWidgetKindCheckbox frame:CGRectMake (10, 130, 80, 20) error:&error];
        GNM_ASSERT ([s clickWidget:loose error:&error] && [s widgetIsActive:loose], @"an unlinked checkbox toggles on its own: %@", error);
        GnmSheetObject *freshRadio = [s insertWidgetOfKind:GnmWidgetKindRadioButton frame:CGRectMake (10, 160, 80, 20) error:&error];
        GnmWidgetSettings *freshRadioSettings = [s widgetSettingsOfSheetObject:freshRadio];
        freshRadioSettings.linkText = @"C2";
        freshRadioSettings.valueText = @"7";
        GNM_ASSERT ([s applyWidgetSettings:freshRadioSettings toSheetObject:freshRadio error:&error], @"freshRadio link: %@", error);
        GNM_ASSERT ([s clickWidget:freshRadio error:&error], @"freshRadio click: %@", error);
        GNM_ASSERT_EQ_STR ([s displayTextOfCellAtColumn:2 row:1] ?: @"", @"7");
        GNM_ASSERT ([s widgetIsActive:freshRadio], @"the freshRadio is on");
        GnmSheetObject *pushButton = [s insertWidgetOfKind:GnmWidgetKindButton frame:CGRectMake (10, 190, 80, 24) error:&error];
        GnmWidgetSettings *pushSettings = [s widgetSettingsOfSheetObject:pushButton];
        pushSettings.linkText = @"C3";
        GNM_ASSERT ([s applyWidgetSettings:pushSettings toSheetObject:pushButton error:&error], @"button link: %@", error);
        GNM_ASSERT ([s clickWidget:pushButton error:&error], @"press: %@", error);
        GNM_ASSERT_EQ_STR ([s displayTextOfCellAtColumn:2 row:2] ?: @"", @"FALSE");
        GNM_ASSERT_EQ_STR (wb.undoLabel ?: @"", @"Released Button");
        [wb undo];
        GNM_ASSERT_EQ_STR ([s displayTextOfCellAtColumn:2 row:2] ?: @"", @"TRUE");
        GnmSheetObject *slider = [s insertWidgetOfKind:GnmWidgetKindSlider frame:CGRectMake (10, 220, 120, 20) error:&error];
        GnmWidgetSettings *sliderSettings = [s widgetSettingsOfSheetObject:slider];
        sliderSettings.linkText = @"C4";
        sliderSettings.minimum = 0;
        sliderSettings.maximum = 50;
        GNM_ASSERT ([s applyWidgetSettings:sliderSettings toSheetObject:slider error:&error], @"slider link: %@", error);
        GNM_ASSERT ([s setWidgetValue:33.4 forObject:slider error:&error], @"slide: %@", error);
        GNM_ASSERT_EQ_STR ([s displayTextOfCellAtColumn:2 row:3] ?: @"", @"33");
        GNM_ASSERT ([s widgetValue:slider] == 33, @"the widget follows: %g", [s widgetValue:slider]);
        GNM_ASSERT ([s setWidgetValue:99 forObject:slider error:&error] && [s widgetValue:slider] == 50, @"clamped: %g", [s widgetValue:slider]);
        GnmSheetObject *looseSpin = [s insertWidgetOfKind:GnmWidgetKindSpinButton frame:CGRectMake (10, 250, 80, 24) error:&error];
        GNM_ASSERT ([s setWidgetValue:4 forObject:looseSpin error:&error] && [s widgetValue:looseSpin] == 4, @"an unlinked spin button keeps its value: %g", [s widgetValue:looseSpin]);
        /* a list over A1:A3 with its choice in C5 */
        GNM_ASSERT ([s setText:@"red" atColumn:0 row:0 autocorrect:NO error:&error] && [s setText:@"green" atColumn:0 row:1 autocorrect:NO error:&error]
                    && [s setText:@"blue" atColumn:0 row:2 autocorrect:NO error:&error], @"colors: %@", error);
        GnmSheetObject *listWidget = [s insertWidgetOfKind:GnmWidgetKindList frame:CGRectMake (150, 100, 100, 60) error:&error];
        GnmWidgetSettings *listSettings = [s widgetSettingsOfSheetObject:listWidget];
        listSettings.contentText = @"A1:A3";
        listSettings.linkText = @"C5";
        NSLog (@"widgets: a fresh list outputs the index: %d", listSettings.outputsIndex);
        listSettings.outputsIndex = NO;
        GNM_ASSERT ([s applyWidgetSettings:listSettings toSheetObject:listWidget error:&error], @"list links: %@", error);
        NSArray *entries = [s widgetEntries:listWidget];
        NSArray *expectedEntries = @[@"red", @"green", @"blue"];
        GNM_ASSERT ([entries isEqualToArray:expectedEntries], @"entries: %@", entries);
        GNM_ASSERT ([s widgetSelection:listWidget] == 0, @"nothing chosen yet");
        GNM_ASSERT ([s chooseWidgetEntry:2 forObject:listWidget error:&error], @"choose: %@", error);
        GNM_ASSERT_EQ_STR ([s displayTextOfCellAtColumn:2 row:4] ?: @"", @"green");
        GNM_ASSERT ([s widgetSelection:listWidget] == 2, @"the second: %ld", (long) [s widgetSelection:listWidget]);
        listSettings.outputsIndex = YES;
        GNM_ASSERT ([s applyWidgetSettings:listSettings toSheetObject:listWidget error:&error], @"as index: %@", error);
        GNM_ASSERT ([s chooseWidgetEntry:3 forObject:listWidget error:&error], @"choose 3: %@", error);
        GNM_ASSERT_EQ_STR ([s displayTextOfCellAtColumn:2 row:4] ?: @"", @"3");
        GNM_ASSERT ([s widgetSelection:listWidget] == 3, @"the third by index");
        GnmSheetObject *looseList = [s insertWidgetOfKind:GnmWidgetKindCombo frame:CGRectMake (150, 170, 100, 24) error:&error];
        GNM_ASSERT (![s chooseWidgetEntry:1 forObject:looseList error:&error] && [error.localizedDescription containsString:@"output cell"], @"no output: %@", error);

        GNM_ASSERT (stray.count == 0, @"stray messages: %@", stray);
        wb = nil;
      }
        [engine shutdown];
        return gnm_test_finish ("widgets");
    }
}
