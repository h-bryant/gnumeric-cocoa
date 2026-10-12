// The chart editor through the bridge: the working copy's tree, generic
// properties, data dimensions as expressions, styles, adding, removing,
// and reordering objects, the preview, and the commit as "Reconfigure
// Graph" with undo and redo.
#import "GnmTest.h"

/* Dark samples in a rendering of the editor's preview. */
static unsigned
preview_ink (GnmChartEditor *editor, int w, int h)
{
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB ();
    CGContextRef ctx = CGBitmapContextCreate (NULL, w, h, 8, 0, space, (CGBitmapInfo) kCGImageAlphaPremultipliedLast);
    CGContextTranslateCTM (ctx, 0, h);
    CGContextScaleCTM (ctx, 1, -1);
    CGContextSetRGBFillColor (ctx, 1, 1, 1, 1);
    CGContextFillRect (ctx, CGRectMake (0, 0, w, h));
    [editor drawPreviewInContext:ctx size:CGSizeMake (w, h)];
    unsigned char const *pixels = CGBitmapContextGetData (ctx);
    size_t stride = CGBitmapContextGetBytesPerRow (ctx);
    unsigned dark = 0;
    for (int y = 0; y < h; y += 3)
        for (int x = 0; x < w; x += 3)
            if (pixels[(size_t) y * stride + (size_t) x * 4] < 128)
                dark++;
    CGContextRelease (ctx);
    CGColorSpaceRelease (space);
    return dark;
}

static GnmChartNode *
child_with_role (GnmChartNode *node, NSString *role)
{
    for (GnmChartNode *c in node.children)
        if ([c.role isEqualToString:role])
            return c;
    return nil;
}

static GnmChartProperty *
property_named (GnmChartNode *node, NSString *name)
{
    for (GnmChartProperty *p in node.properties)
        if ([p.name isEqualToString:name])
            return p;
    return nil;
}

static GnmChartDimension *
dimension_labeled (GnmChartNode *node, NSString *label)
{
    for (GnmChartDimension *d in node.dimensions)
        if ([d.label isEqualToString:label])
            return d;
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
        NSURL *url = [NSURL fileURLWithPath:[gnm_test_env ("GNM_TEST_SAMPLES") stringByAppendingPathComponent:@"chart-tests.gnumeric"]];
        GnmWorkbook *wb = [engine openWorkbookAtURL:url error:&error];
        GNM_ASSERT (wb != nil, @"open: %@", error);
        if (!wb) { [engine shutdown]; return gnm_test_finish ("chart"); }
        GnmSheet *s = wb.sheets.firstObject;
        [wb selectSheet:s];
        GnmSheetObject *chart = nil, *image = nil;
        for (GnmSheetObject *o in s.sheetObjects) {
            if (chart == nil && [o.typeName isEqualToString:@"SheetObjectGraph"])
                chart = o;
            if (image == nil && [o.typeName isEqualToString:@"SheetObjectImage"])
                image = o;
        }
        GNM_ASSERT (chart != nil, @"the sample has a chart on its first sheet");
        if (image)
            GNM_ASSERT ([[GnmChartEditor alloc] initWithSheetObject:image] == nil, @"no editor for an image");

        /* the tree */
        GnmChartEditor *editor = [[GnmChartEditor alloc] initWithSheetObject:chart];
        GNM_ASSERT (editor != nil && editor.sheetObject == chart, @"editor over the chart");
        GnmChartNode *root = editor.root;
        GNM_ASSERT_EQ_STR (root.typeName, @"GogGraph");
        GNM_ASSERT (root.role.length == 0 && root.parent == nil && root.isAttached && !root.canDelete, @"root: %@", root);
        GNM_ASSERT (editor.root == root, @"stable node");
        GnmChartNode *chartNode = child_with_role (root, @"Chart");
        GNM_ASSERT (chartNode != nil && chartNode.parent == root, @"the graph holds a chart: %@", root.children);
        NSLog (@"tree: %@ -> %@", root, chartNode.children);
        GnmChartNode *plot = child_with_role (chartNode, @"Plot");
        GnmChartNode *xAxis = child_with_role (chartNode, @"X-Axis");
        GNM_ASSERT (plot != nil && xAxis != nil, @"plot and X axis: %@", chartNode.children);
        GNM_ASSERT (plot.children.count >= 1 && [plot.children.firstObject.role isEqualToString:@"Series"], @"series under the plot");
        GNM_ASSERT ([chartNode.addableRoles containsObject:@"Title"] && [chartNode.addableRoles containsObject:@"Legend"],
                    @"chart additions: %@", chartNode.addableRoles);
        GNM_ASSERT ([plot.addableRoles containsObject:@"Series"], @"plot additions: %@", plot.addableRoles);
        GNM_ASSERT (![root.addableRoles containsObject:@"Series"], @"graph additions: %@", root.addableRoles);

        /* generic properties */
        GnmChartProperty *invert = property_named (xAxis, @"invert-axis");
        GNM_ASSERT (invert != nil && invert.kind == GnmChartPropertyBoolean && ![invert.value boolValue], @"invert: %@", invert);
        GNM_ASSERT_EQ_STR (invert.label, @"Invert");
        GnmChartProperty *pos = property_named (xAxis, @"pos-str");
        GNM_ASSERT (pos != nil && pos.kind == GnmChartPropertyChoice && pos.choices.count == 3 && [pos.choices containsObject:@"low"],
                    @"position choices: %@", pos);
        GNM_ASSERT (property_named (xAxis, @"id") == nil && property_named (xAxis, @"style") == nil && property_named (xAxis, @"type") == nil,
                    @"hidden properties stay hidden: %@", xAxis.properties);
        GNM_ASSERT (property_named (xAxis, @"compass") == nil, @"axes have no compass");
        GNM_ASSERT (![xAxis.properties.firstObject.name isEqualToString:@"invisible"],
                    @"specific class first: %@", xAxis.properties.firstObject);
        NSInteger changes = editor.changeCount;
        GNM_ASSERT ([editor setValue:@YES forProperty:invert ofNode:xAxis], @"set invert");
        GNM_ASSERT ([property_named (xAxis, @"invert-axis").value boolValue], @"invert read back");
        GNM_ASSERT ([editor setValue:@"high" forProperty:pos ofNode:xAxis], @"set position");
        GNM_ASSERT_EQ_STR ((NSString *) property_named (xAxis, @"pos-str").value, @"high");
        GNM_ASSERT (![editor setValue:@"sideways" forProperty:invert ofNode:xAxis], @"a string is refused for a boolean");
        GnmChartProperty *tick = property_named (xAxis, @"major-tick-size-pts");
        GNM_ASSERT (tick != nil && tick.kind == GnmChartPropertyInteger && tick.maximum == 20, @"tick size: %@", tick);
        GNM_ASSERT ([editor setValue:@99 forProperty:tick ofNode:xAxis], @"set tick size");
        GNM_ASSERT ([property_named (xAxis, @"major-tick-size-pts").value integerValue] == 20, @"clamped to the maximum");
        GNM_ASSERT (editor.changeCount == changes + 3, @"three changes counted: %ld", (long) (editor.changeCount - changes));

        /* a title with literal text, then a cell reference */
        GnmChartNode *title = [editor addChildWithRole:@"Title" toNode:chartNode];
        GNM_ASSERT (title != nil && title.isAttached && title.parent == chartNode && [title.role isEqualToString:@"Title"], @"title added: %@", title);
        GNM_ASSERT (child_with_role (chartNode, @"Title") == title, @"title in the tree");
        GNM_ASSERT ([editor addChildWithRole:@"Series" toNode:chartNode] == nil, @"a role the chart lacks is refused");
        GnmChartDimension *text = dimension_labeled (title, @"Text");
        GNM_ASSERT (text != nil && text.kind == GnmChartDataScalar && !text.isSet && text.text.length == 0, @"title text: %@", title.dimensions);
        GNM_ASSERT ([editor setText:@"Hello world" forDimension:text ofNode:title error:&error], @"literal text: %@", error);
        GNM_ASSERT_EQ_STR (dimension_labeled (title, @"Text").text, @"\"Hello world\"");
        GNM_ASSERT ([editor setText:@"A1" forDimension:text ofNode:title error:&error], @"cell reference: %@", error);
        GNM_ASSERT (dimension_labeled (title, @"Text").isSet && [dimension_labeled (title, @"Text").text hasSuffix:@"A1"],
                    @"reference read back: %@", dimension_labeled (title, @"Text"));
        GNM_ASSERT ([editor setText:@"  " forDimension:text ofNode:title error:&error], @"blank clears");
        GNM_ASSERT (!dimension_labeled (title, @"Text").isSet, @"cleared");
        GNM_ASSERT (title.style != nil && title.style.hasFont, @"a title has a font: %@", title.style);

        /* series data */
        GnmChartNode *series = plot.children.firstObject;
        GnmChartDimension *name = dimension_labeled (series, @"Name");
        GnmChartDimension *values = nil;
        for (GnmChartDimension *d in series.dimensions)
            if (values == nil && d.kind == GnmChartDataVector && d.isSet)
                values = d;
        GNM_ASSERT (name != nil && name.kind == GnmChartDataScalar && name.index == -1, @"series name: %@", series.dimensions);
        GNM_ASSERT (values != nil && values.text.length > 0, @"series values: %@", series.dimensions);
        NSLog (@"series %@: %@", series.name, series.dimensions);
        GNM_ASSERT (![editor setText:@"A1:A" forDimension:values ofNode:series error:&error] && error != nil,
                    @"a bad range is an error: %@", error);
        error = nil;
        GNM_ASSERT ([editor setText:@"1,2,3" forDimension:values ofNode:series error:&error], @"a list: %@", error);
        GNM_ASSERT ([dimension_labeled (series, values.label).text containsString:@"1"], @"list read back: %@", dimension_labeled (series, values.label));
        GNM_ASSERT ([editor setText:@"$B$1:$B$10" forDimension:values ofNode:series error:&error], @"a range: %@", error);
        GNM_ASSERT ([dimension_labeled (series, values.label).text hasSuffix:@"$B$1:$B$10"], @"range read back: %@",
                    dimension_labeled (series, values.label));
        GNM_ASSERT ([editor setText:@"Sales" forDimension:name ofNode:series error:&error], @"series name: %@", error);
        GNM_ASSERT_EQ_STR (dimension_labeled (series, @"Name").text, @"\"Sales\"");
        GNM_ASSERT ([series.name isEqualToString:@"Sales"] || series.name.length > 0, @"the series shows its name: %@", series.name);

        /* style: a red, thick line on the series */
        GnmChartStyle *style = series.style;
        GNM_ASSERT (style != nil && (style.hasLine || style.hasMarker), @"series style: %@", style);
        NSLog (@"series style to start with: auto line=%d fill=%d marker=%d", style.lineAutomatic, style.fillAutomatic, style.markerAutomatic);
        CGColorRef red = CGColorCreateSRGB (1, 0, 0, 1);
        style.lineAutomatic = NO;
        style.lineColor = red;
        style.lineWidth = 3;
        style.lineDash = 1;   /* solid */
        style.markerAutomatic = NO;
        style.markerShape = 7;   /* circle */
        style.markerSize = 9;
        GNM_ASSERT ([editor applyStyle:style toNode:series], @"apply style");
        GnmChartStyle *back = series.style;
        GNM_ASSERT (!back.lineAutomatic && back.lineWidth == 3 && back.lineColor != NULL, @"line read back: %@", back);
        if (back.lineColor) {
            const CGFloat *c = CGColorGetComponents (back.lineColor);
            GNM_ASSERT (c[0] > 0.99 && c[1] < 0.01 && c[2] < 0.01, @"red line: %g %g %g", c[0], c[1], c[2]);
        }
        GNM_ASSERT (!back.markerAutomatic && back.markerShape == 7 && back.markerSize == 9, @"marker read back: %@", back);
        GnmChartStyle *copy = [back copy];
        copy.lineAutomatic = YES;
        GNM_ASSERT (!back.lineAutomatic && copy.lineAutomatic, @"copies are independent");
        GNM_ASSERT (GnmChartStyle.lineDashNames.count > 5 && GnmChartStyle.markerShapeNames.count > 10, @"style names: %@ / %@",
                    GnmChartStyle.lineDashNames, GnmChartStyle.markerShapeNames);
        CGColorRelease (red);
        /* a title font */
        GnmChartStyle *titleStyle = title.style;
        titleStyle.fontAutomatic = NO;
        titleStyle.fontFamily = @"Helvetica";
        titleStyle.fontSize = 18;
        titleStyle.fontBold = YES;
        GNM_ASSERT ([editor applyStyle:titleStyle toNode:title], @"apply font");
        GnmChartStyle *fontBack = title.style;
        GNM_ASSERT (!fontBack.fontAutomatic && fontBack.fontSize == 18 && fontBack.fontBold && [fontBack.fontFamily isEqualToString:@"Helvetica"],
                    @"font read back: %@ %g bold=%d", fontBack.fontFamily, fontBack.fontSize, fontBack.fontBold);

        /* the legend's position */
        GnmChartNode *legend = child_with_role (chartNode, @"Legend") ?: [editor addChildWithRole:@"Legend" toNode:chartNode];
        GNM_ASSERT (legend != nil, @"legend");
        GnmChartProperty *compass = property_named (legend, @"compass");
        GNM_ASSERT (compass != nil && compass.kind == GnmChartPropertyChoice && [compass.choices containsObject:@"top"], @"compass: %@", compass);
        GNM_ASSERT ([editor setValue:@"top" forProperty:compass ofNode:legend], @"legend to the top");
        GNM_ASSERT_EQ_STR ((NSString *) property_named (legend, @"compass").value, @"top");

        /* reordering: a second series, then swap */
        GnmChartNode *second = [editor addChildWithRole:@"Series" toNode:plot];
        GNM_ASSERT (second != nil && plot.children.count >= 2 && plot.children.lastObject == second, @"second series: %@", plot.children);
        GNM_ASSERT (second.canMoveForward != second.canMoveBackward, @"an end series moves one way: fwd=%d back=%d",
                    second.canMoveForward, second.canMoveBackward);
        BOOL forward = second.canMoveForward;
        NSUInteger at = [plot.children indexOfObject:second];
        GNM_ASSERT ([editor moveNode:second forward:forward], @"move");
        GNM_ASSERT ([plot.children indexOfObject:second] != at, @"moved: %@", plot.children);
        GNM_ASSERT (![editor moveNode:root forward:YES], @"the graph does not move");

        /* removing */
        GNM_ASSERT (second.canDelete && [editor removeNode:second], @"remove the second series");
        GNM_ASSERT (!second.isAttached && ![plot.children containsObject:second] && second.children.count == 0, @"gone: %@", plot.children);
        GNM_ASSERT (second.properties.count == 0 && second.dimensions.count == 0 && second.style == nil && !second.canDelete,
                    @"a tombstone answers nothing: %@", second);
        GNM_ASSERT (![editor removeNode:second], @"removing twice fails");
        GNM_ASSERT (![editor removeNode:xAxis] || !xAxis.canDelete, @"an axis the plot needs stays");
        GNM_ASSERT (![editor removeNode:root], @"the graph stays");

        /* preview */
        GNM_ASSERT (preview_ink (editor, 400, 300) > 50, @"the preview draws");

        /* the plot's type changed in place: XY to Column keeps the series
         * and their values, Pie keeps one series and drops the axes */
        GnmPlotType *column = nil, *pie = nil;
        for (GnmPlotType *t in GnmPlotType.allTypes) {
            if (column == nil && [t.family isEqualToString:@"Column"] && [t.engine isEqualToString:@"GogBarColPlot"])
                column = t;
            if (pie == nil && [t.engine isEqualToString:@"GogPiePlot"])
                pie = t;
        }
        GNM_ASSERT (column != nil && pie != nil, @"types found");
        NSUInteger seriesBefore = plot.children.count;
        NSString *xBefore = dimension_labeled (plot.children.firstObject, @"X").text;
        NSString *yBefore = dimension_labeled (plot.children.firstObject, @"Y").text;
        GNM_ASSERT (![editor changeType:column ofPlot:xAxis], @"only plots change type");
        GnmChartNode *columnPlot = [editor changeType:column ofPlot:plot];
        GNM_ASSERT (columnPlot != nil && columnPlot.isAttached && [columnPlot.typeName isEqualToString:@"GogBarColPlot"], @"column plot: %@", columnPlot);
        GNM_ASSERT (!plot.isAttached && child_with_role (chartNode, @"Plot") == columnPlot, @"the old plot is gone: %@", chartNode.children);
        GNM_ASSERT (columnPlot.children.count == seriesBefore, @"series kept: %lu of %lu", (unsigned long) columnPlot.children.count, (unsigned long) seriesBefore);
        /* XY's X and Y are Excel's categories and values: a column plot's
         * Labels and Values */
        GNM_ASSERT_EQ_STR (dimension_labeled (columnPlot.children.firstObject, @"Labels").text, xBefore);
        GNM_ASSERT_EQ_STR (dimension_labeled (columnPlot.children.firstObject, @"Values").text, yBefore);
        GNM_ASSERT_EQ_STR (dimension_labeled (columnPlot.children.firstObject, @"Name").text, @"\"Sales\"");
        GNM_ASSERT (!columnPlot.children.firstObject.style.lineAutomatic, @"the series' style came along: %@", columnPlot.children.firstObject.style);
        GNM_ASSERT (child_with_role (chartNode, @"X-Axis") == xAxis && child_with_role (chartNode, @"Y-Axis") != nil, @"axes stay for a column plot");
        GNM_ASSERT ([property_named (xAxis, @"invert-axis").value boolValue], @"the kept axis keeps its inversion");
        GNM_ASSERT (preview_ink (editor, 400, 300) > 50, @"the column chart draws");
        GnmChartNode *piePlot = nil, *backAgain = nil;
        if (getenv ("CHART_TEST_SKIP_PIE") == NULL) {
        piePlot = [editor changeType:pie ofPlot:columnPlot];
        GNM_ASSERT (piePlot != nil && [piePlot.typeName isEqualToString:@"GogPiePlot"] && piePlot.children.count >= 1, @"pie plot: %@", piePlot);
        for (GnmChartNode *c in chartNode.children)
            if ([c.role hasSuffix:@"Axis"])
                NSLog (@"axis after pie: %@ deletable=%d", c, c.canDelete);
        GNM_ASSERT (child_with_role (chartNode, @"X-Axis") == nil, @"no axes for a pie: %@", chartNode.children);
        GNM_ASSERT (preview_ink (editor, 400, 300) > 50, @"the pie draws");
        backAgain = [editor changeType:column ofPlot:piePlot];
        GNM_ASSERT (backAgain != nil && child_with_role (chartNode, @"Y-Axis") != nil, @"axes come back: %@", chartNode.children);
        GNM_ASSERT (!xAxis.isAttached, @"the axes are new ones: %@", chartNode.children);
        plot = backAgain;
        } else
            plot = columnPlot;

        /* commit, undo, redo */
        NSString *undoBefore = wb.undoLabel;
        GNM_ASSERT ([editor applyWithError:&error], @"apply: %@", error);
        GNM_ASSERT_EQ_STR (wb.undoLabel ?: @"", @"Reconfigure Graph");
        GNM_ASSERT (chart.isAttached, @"the chart is still there");
        GnmChartEditor *check = [[GnmChartEditor alloc] initWithSheetObject:chart];
        GnmChartNode *liveChart = child_with_role (check.root, @"Chart");
        GNM_ASSERT (child_with_role (liveChart, @"Title") != nil, @"the live chart has the title");
        GNM_ASSERT_EQ_STR (child_with_role (liveChart, @"Plot").typeName, @"GogBarColPlot");
        GNM_ASSERT_EQ_STR (dimension_labeled (child_with_role (child_with_role (liveChart, @"Plot"), @"Series"), @"Name").text, @"\"Sales\"");
        GNM_ASSERT (editor.root != root && editor.root.isAttached, @"the editor moved to a fresh copy");
        [wb undo];
        GNM_ASSERT ([wb.undoLabel ?: @"" isEqualToString:undoBefore ?: @""], @"undone: %@", wb.undoLabel);
        check = [[GnmChartEditor alloc] initWithSheetObject:chart];
        GNM_ASSERT (child_with_role (child_with_role (check.root, @"Chart"), @"Title") == nil, @"the old graph is back");
        [wb redo];
        check = [[GnmChartEditor alloc] initWithSheetObject:chart];
        GNM_ASSERT (child_with_role (child_with_role (check.root, @"Chart"), @"Title") != nil, @"redone");
        [wb undo];
        check = nil;

        /* the editor outlives a deleted chart gracefully */
        GNM_ASSERT ([s deleteSheetObjects:@[chart] error:&error], @"delete: %@", error);
        GNM_ASSERT (![editor applyWithError:&error] && error != nil, @"apply on a deleted chart fails: %@", error);
        [wb undo];
        GNM_ASSERT (chart.isAttached, @"chart back");

        editor = nil; root = nil; chartNode = nil; plot = nil; xAxis = nil; title = nil; series = nil; legend = nil; second = nil;
        columnPlot = nil; piePlot = nil; backAgain = nil;
        liveChart = nil; style = nil; back = nil; copy = nil; titleStyle = nil; fontBack = nil;
        wb = nil; s = nil; chart = nil; image = nil;
        GNM_ASSERT (stray.count == 0, @"stray engine messages: %@", stray);
      }
        [engine shutdown];
    }
    return gnm_test_finish ("chart");
}
