// The chart editor: the guru's later pages over a working copy of a
// chart's graph.  The editor duplicates the graph (`gog_graph_dup`), the
// app edits the copy through the object tree (chart, plots, series, axes,
// titles, legend, grids), and `apply` commits the copy with the engine's
// "Reconfigure Graph" command (`cmd_so_graph_config`), undoable.  Cancel
// is just releasing the editor.
//
// Nodes are stable wrappers of the copy's objects.  Each offers the
// generic properties goffice registers on the class (booleans, numbers,
// texts, and the string choices the GTK editor shows as combos), the data
// dimensions of datasets (series names and values, axis bounds, label
// texts) as expressions in the sheet's syntax, and the style (lines, fill,
// markers, font, text angle) for styled objects.
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <GnmCocoa/GnmSheetObject.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, GnmChartPropertyKind) {
    /// `value` is an NSNumber holding a BOOL.
    GnmChartPropertyBoolean = 0,
    /// `value` is an NSNumber holding an integer within `minimum`...`maximum`.
    GnmChartPropertyInteger,
    /// `value` is an NSNumber holding a double within `minimum`...`maximum`.
    GnmChartPropertyNumber,
    /// `value` is an NSString.
    GnmChartPropertyText,
    /// `value` is one of `choices` (an engine string); `choiceLabels` are
    /// what to show.
    GnmChartPropertyChoice,
} NS_SWIFT_NAME(ChartProperty.Kind);

/// One editable GObject property of a chart object.
NS_SWIFT_UI_ACTOR NS_SWIFT_NAME(ChartProperty)
@interface GnmChartProperty : NSObject
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
/// The engine's property name ("invert-axis").
@property (nonatomic, readonly, copy) NSString *name;
/// What to show ("Invert").
@property (nonatomic, readonly, copy) NSString *label;
@property (nonatomic, readonly) GnmChartPropertyKind kind;
@property (nonatomic, readonly, copy, nullable) id value;
@property (nonatomic, readonly, copy) NSArray<NSString *> *choices;
@property (nonatomic, readonly, copy) NSArray<NSString *> *choiceLabels;
@property (nonatomic, readonly) double minimum;
@property (nonatomic, readonly) double maximum;
@end

typedef NS_ENUM(NSInteger, GnmChartDataKind) {
    /// One value: a label's text, an axis bound, a series name.
    GnmChartDataScalar = 0,
    /// A range or list of values: a series' categories or values.
    GnmChartDataVector,
    /// A two-dimensional range (surface and contour plots).
    GnmChartDataMatrix,
} NS_SWIFT_NAME(ChartDimension.Kind);

/// One data dimension of a chart object (`gog_dataset_get_dim`).
NS_SWIFT_UI_ACTOR NS_SWIFT_NAME(ChartDimension)
@interface GnmChartDimension : NSObject
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@property (nonatomic, readonly) NSInteger index;
/// "Name", "X", "Y", "Minimum", "Text", ...
@property (nonatomic, readonly, copy) NSString *label;
@property (nonatomic, readonly) GnmChartDataKind kind;
/// The expression in the sheet's syntax (`A1:A5`, `Sheet2!$B$2`,
/// `"Sales"`, `1,2,3`), empty when unset.
@property (nonatomic, readonly, copy) NSString *text;
@property (nonatomic, readonly) BOOL isSet;
@end

/// A styled object's style as a value: read it from a node, change the
/// fields, and apply it back.  Fields a part does not use are ignored;
/// an "automatic" part keeps the theme's choice.
NS_SWIFT_UI_ACTOR NS_SWIFT_NAME(ChartStyle)
@interface GnmChartStyle : NSObject <NSCopying>
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
/// Which parts the object uses (`GOStyle.interesting_fields`).
@property (nonatomic, readonly) BOOL hasOutline;
@property (nonatomic, readonly) BOOL hasLine;
@property (nonatomic, readonly) BOOL hasFill;
@property (nonatomic, readonly) BOOL hasMarker;
@property (nonatomic, readonly) BOOL hasFont;
@property (nonatomic, readonly) BOOL hasTextLayout;

// Line (or outline, for objects that have one and not the other).
@property (nonatomic) BOOL lineAutomatic;
/// nil draws no line.
@property (nonatomic, nullable) CGColorRef lineColor;
/// Points; 0 is a hairline.
@property (nonatomic) double lineWidth;
/// An index into `lineDashNames`.
@property (nonatomic) NSInteger lineDash;
@property (class, nonatomic, readonly) NSArray<NSString *> *lineDashNames;

// Fill.
@property (nonatomic) BOOL fillAutomatic;
/// NO leaves the area unfilled; YES fills it with `fillColor` (a
/// gradient or image fill the file brought along keeps its kind and
/// takes the color as its base).
@property (nonatomic) BOOL fillSolid;
@property (nonatomic, nullable) CGColorRef fillColor;

// Marker.
@property (nonatomic) BOOL markerAutomatic;
/// An index into `markerShapeNames`; 0 is no marker.
@property (nonatomic) NSInteger markerShape;
@property (nonatomic) NSInteger markerSize;
@property (nonatomic, nullable) CGColorRef markerFillColor;
@property (nonatomic, nullable) CGColorRef markerOutlineColor;
@property (class, nonatomic, readonly) NSArray<NSString *> *markerShapeNames;

// Font.
@property (nonatomic) BOOL fontAutomatic;
@property (nonatomic, copy) NSString *fontFamily;
@property (nonatomic) double fontSize;
@property (nonatomic) BOOL fontBold;
@property (nonatomic) BOOL fontItalic;
@property (nonatomic) BOOL fontColorAutomatic;
@property (nonatomic, nullable) CGColorRef fontColor;

// Text layout.
@property (nonatomic) BOOL textAngleAutomatic;
/// Degrees, counterclockwise.
@property (nonatomic) double textAngle;
@end

/// One object of the working copy's tree.
NS_SWIFT_UI_ACTOR NS_SWIFT_NAME(ChartNode)
@interface GnmChartNode : NSObject
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
/// The engine's display name ("Chart1", "Series2", "X-Axis1").
@property (nonatomic, readonly, copy) NSString *name;
/// The role under the parent ("Chart", "Plot", "Series", "Title",
/// "Legend", "X-Axis", "Label", "MajorGrid"); empty for the graph.
@property (nonatomic, readonly, copy) NSString *role;
/// The goffice class ("GogXYPlot", "GogAxis", ...).
@property (nonatomic, readonly, copy) NSString *typeName;
@property (nonatomic, readonly, nullable) GnmChartNode *parent;
@property (nonatomic, readonly, copy) NSArray<GnmChartNode *> *children;
/// NO once removed from the tree.
@property (nonatomic, readonly) BOOL isAttached;
@property (nonatomic, readonly) BOOL canDelete;
/// Whether `moveNode:forward:` can reorder it among its siblings
/// (series order, plot order).
@property (nonatomic, readonly) BOOL canMoveForward;
@property (nonatomic, readonly) BOOL canMoveBackward;
/// Roles a child can be added under now ("Title", "Legend", "Series",
/// "MajorGrid", "Label", ...), as the GTK guru's add menu lists them.
@property (nonatomic, readonly, copy) NSArray<NSString *> *addableRoles;
/// The editable properties, most specific class first.
@property (nonatomic, readonly, copy) NSArray<GnmChartProperty *> *properties;
/// The data dimensions, empty for objects without data.
@property (nonatomic, readonly, copy) NSArray<GnmChartDimension *> *dimensions;
/// A copy of the style, nil for objects without one.
@property (nonatomic, readonly, nullable) GnmChartStyle *style;
@end

NS_SWIFT_UI_ACTOR NS_SWIFT_NAME(ChartEditor)
@interface GnmChartEditor : NSObject
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
/// An editor over a copy of the chart's graph; nil unless `object` is a
/// chart on a sheet.
- (nullable instancetype)initWithSheetObject:(GnmSheetObject *)object NS_SWIFT_NAME(init(editing:));
@property (nonatomic, readonly) GnmSheetObject *sheetObject;
/// The graph: the root of the tree.
@property (nonatomic, readonly) GnmChartNode *root;
/// Grows with every change, for the app to know when to redraw.
@property (nonatomic, readonly) NSInteger changeCount;

/// Render the working copy into a context (y downward, as a flipped
/// view's) at `size` points.
- (void)drawPreviewInContext:(CGContextRef)context size:(CGSize)size NS_SWIFT_NAME(drawPreview(in:size:));
/// Commit the copy to the sheet object as "Reconfigure Graph".  The
/// editor keeps working on the same graph afterwards; a second apply
/// commits a further command.
- (BOOL)applyWithError:(NSError **)error NS_SWIFT_NAME(apply());

/// Add a child under `node` for a role from its `addableRoles`.
- (nullable GnmChartNode *)addChildWithRole:(NSString *)role toNode:(GnmChartNode *)node NS_SWIFT_NAME(addChild(role:to:));
- (BOOL)removeNode:(GnmChartNode *)node NS_SWIFT_NAME(remove(_:));
- (BOOL)moveNode:(GnmChartNode *)node forward:(BOOL)forward NS_SWIFT_NAME(move(_:forward:));
/// Set a property: an NSNumber for booleans and numbers, an NSString for
/// texts and choices.
- (BOOL)setValue:(id)value forProperty:(GnmChartProperty *)property ofNode:(GnmChartNode *)node NS_SWIFT_NAME(setValue(_:for:of:));
/// Set a dimension from an expression in the sheet's syntax (a range, a
/// list such as `1,2,3`, a cell, or for scalars plain text); empty
/// clears it.  A vector or matrix that does not parse is an error.
- (BOOL)setText:(NSString *)text forDimension:(GnmChartDimension *)dimension ofNode:(GnmChartNode *)node
          error:(NSError **)error NS_SWIFT_NAME(setText(_:for:of:));
- (BOOL)applyStyle:(GnmChartStyle *)style toNode:(GnmChartNode *)node NS_SWIFT_NAME(apply(_:to:));
@end

NS_ASSUME_NONNULL_END
