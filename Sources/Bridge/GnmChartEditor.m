// GnmChartEditor: the guru's later pages over a copy of a chart's graph
// (GnmChartEditor.h).
#import "GnmPrivate.h"
#include <expr.h>

/* ------------------------------------------------------------------------ */

@implementation GnmChartProperty

- (instancetype)initWithName:(NSString *)name label:(NSString *)label kind:(GnmChartPropertyKind)kind value:(id)value
                     choices:(NSArray<NSString *> *)choices choiceLabels:(NSArray<NSString *> *)choiceLabels
                     minimum:(double)minimum maximum:(double)maximum
{
    if (!(self = [super init]))
        return nil;
    _name = [name copy];
    _label = [label copy];
    _kind = kind;
    _value = [value copy];
    _choices = [choices copy];
    _choiceLabels = [choiceLabels copy];
    _minimum = minimum;
    _maximum = maximum;
    return self;
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"<ChartProperty %@ (%@) = %@>", _name, _label, _value];
}

@end

@implementation GnmChartDimension

- (instancetype)initWithIndex:(NSInteger)index label:(NSString *)label kind:(GnmChartDataKind)kind text:(NSString *)text isSet:(BOOL)isSet
{
    if (!(self = [super init]))
        return nil;
    _index = index;
    _label = [label copy];
    _kind = kind;
    _text = [text copy];
    _isSet = isSet;
    return self;
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"<ChartDimension %ld %@ = '%@'>", (long) _index, _label, _text];
}

@end

/* ------------------------------------------------------------------------ */

@implementation GnmChartStyle {
    CGColorRef _lineColor, _fillColor, _markerFillColor, _markerOutlineColor, _fontColor;
    GOStyleFill _originalFillType;
}

static void
set_color (CGColorRef *slot, CGColorRef color)
{
    if (*slot == color)
        return;
    if (color)
        CGColorRetain (color);
    if (*slot)
        CGColorRelease (*slot);
    *slot = color;
}

- (CGColorRef)lineColor { return _lineColor; }
- (void)setLineColor:(CGColorRef)c { set_color (&_lineColor, c); }
- (CGColorRef)fillColor { return _fillColor; }
- (void)setFillColor:(CGColorRef)c { set_color (&_fillColor, c); }
- (CGColorRef)markerFillColor { return _markerFillColor; }
- (void)setMarkerFillColor:(CGColorRef)c { set_color (&_markerFillColor, c); }
- (CGColorRef)markerOutlineColor { return _markerOutlineColor; }
- (void)setMarkerOutlineColor:(CGColorRef)c { set_color (&_markerOutlineColor, c); }
- (CGColorRef)fontColor { return _fontColor; }
- (void)setFontColor:(CGColorRef)c { set_color (&_fontColor, c); }

- (void)dealloc
{
    set_color (&_lineColor, NULL);
    set_color (&_fillColor, NULL);
    set_color (&_markerFillColor, NULL);
    set_color (&_markerOutlineColor, NULL);
    set_color (&_fontColor, NULL);
}

- (instancetype)initWithStyle:(GOStyle const *)style
{
    if (!(self = [super init]))
        return nil;
    unsigned fields = style->interesting_fields;
    _hasOutline = (fields & GO_STYLE_OUTLINE) != 0;
    _hasLine = (fields & GO_STYLE_LINE) != 0;
    _hasFill = (fields & GO_STYLE_FILL) != 0;
    _hasMarker = (fields & GO_STYLE_MARKER) != 0;
    _hasFont = (fields & GO_STYLE_FONT) != 0;
    _hasTextLayout = (fields & GO_STYLE_TEXT_LAYOUT) != 0;

    _lineAutomatic = style->line.auto_color && style->line.auto_dash && style->line.auto_width;
    if (style->line.dash_type != GO_LINE_NONE)
        _lineColor = gnm_cocoa_cgcolor_from_go (style->line.color);
    _lineWidth = style->line.width;
    _lineDash = style->line.dash_type;

    _originalFillType = style->fill.type;
    _fillAutomatic = style->fill.auto_type && style->fill.auto_back && style->fill.auto_fore;
    _fillSolid = style->fill.type != GO_STYLE_FILL_NONE;
    _fillColor = gnm_cocoa_cgcolor_from_go (style->fill.pattern.back);

    _markerAutomatic = style->marker.auto_shape && style->marker.auto_outline_color && style->marker.auto_fill_color;
    GOMarker const *marker = go_style_get_marker (style);
    if (marker) {
        _markerShape = go_marker_get_shape (marker);
        _markerSize = go_marker_get_size (marker);
        _markerFillColor = gnm_cocoa_cgcolor_from_go (go_marker_get_fill_color (marker));
        _markerOutlineColor = gnm_cocoa_cgcolor_from_go (go_marker_get_outline_color (marker));
    }

    _fontAutomatic = style->font.auto_font;
    _fontFamily = @"";
    _fontSize = 10;
    if (style->font.font && style->font.font->desc) {
        PangoFontDescription const *desc = style->font.font->desc;
        _fontFamily = GnmString (pango_font_description_get_family (desc));
        _fontSize = pango_font_description_get_size (desc) / (double) PANGO_SCALE;
        _fontBold = pango_font_description_get_weight (desc) >= PANGO_WEIGHT_BOLD;
        _fontItalic = pango_font_description_get_style (desc) != PANGO_STYLE_NORMAL;
    }
    _fontColorAutomatic = style->font.auto_color;
    _fontColor = gnm_cocoa_cgcolor_from_go (style->font.color);

    _textAngleAutomatic = style->text_layout.auto_angle;
    _textAngle = style->text_layout.angle;
    return self;
}

- (id)copyWithZone:(NSZone *)zone
{
    GnmChartStyle *copy = [[GnmChartStyle allocWithZone:zone] initPrivate];
    copy->_hasOutline = _hasOutline;
    copy->_hasLine = _hasLine;
    copy->_hasFill = _hasFill;
    copy->_hasMarker = _hasMarker;
    copy->_hasFont = _hasFont;
    copy->_hasTextLayout = _hasTextLayout;
    copy->_lineAutomatic = _lineAutomatic;
    set_color (&copy->_lineColor, _lineColor);
    copy->_lineWidth = _lineWidth;
    copy->_lineDash = _lineDash;
    copy->_originalFillType = _originalFillType;
    copy->_fillAutomatic = _fillAutomatic;
    copy->_fillSolid = _fillSolid;
    set_color (&copy->_fillColor, _fillColor);
    copy->_markerAutomatic = _markerAutomatic;
    copy->_markerShape = _markerShape;
    copy->_markerSize = _markerSize;
    set_color (&copy->_markerFillColor, _markerFillColor);
    set_color (&copy->_markerOutlineColor, _markerOutlineColor);
    copy->_fontAutomatic = _fontAutomatic;
    copy->_fontFamily = [_fontFamily copy];
    copy->_fontSize = _fontSize;
    copy->_fontBold = _fontBold;
    copy->_fontItalic = _fontItalic;
    copy->_fontColorAutomatic = _fontColorAutomatic;
    set_color (&copy->_fontColor, _fontColor);
    copy->_textAngleAutomatic = _textAngleAutomatic;
    copy->_textAngle = _textAngle;
    return copy;
}

- (instancetype)initPrivate
{
    return [super init];
}

/* Write the fields into an engine style (a duplicate the caller owns). */
- (void)writeToStyle:(GOStyle *)style
{
    if (_hasLine || _hasOutline) {
        if (_lineAutomatic) {
            style->line.auto_color = style->line.auto_dash = style->line.auto_width = TRUE;
        } else {
            style->line.auto_color = style->line.auto_dash = style->line.auto_width = FALSE;
            style->line.auto_fore = FALSE;
            if (_lineColor == NULL) {
                style->line.dash_type = GO_LINE_NONE;
            } else {
                style->line.color = gnm_cocoa_go_from_cgcolor (_lineColor);
                style->line.fore = style->line.color;
                style->line.dash_type = (_lineDash <= GO_LINE_NONE || _lineDash >= GO_LINE_MAX) ? GO_LINE_SOLID : (GOLineDashType) _lineDash;
            }
            style->line.width = MAX (_lineWidth, 0);
        }
    }
    if (_hasFill) {
        if (_fillAutomatic) {
            style->fill.auto_type = style->fill.auto_back = style->fill.auto_fore = TRUE;
        } else {
            style->fill.auto_type = style->fill.auto_back = style->fill.auto_fore = FALSE;
            style->fill.auto_pattern = FALSE;
            if (!_fillSolid) {
                style->fill.type = GO_STYLE_FILL_NONE;
            } else {
                if (_originalFillType == GO_STYLE_FILL_NONE || style->fill.type == GO_STYLE_FILL_NONE) {
                    style->fill.type = GO_STYLE_FILL_PATTERN;
                    style->fill.pattern.pattern = GO_PATTERN_SOLID;
                }
                if (_fillColor) {
                    style->fill.pattern.back = gnm_cocoa_go_from_cgcolor (_fillColor);
                    if (style->fill.type == GO_STYLE_FILL_PATTERN)
                        style->fill.pattern.fore = style->fill.pattern.back;
                }
            }
        }
    }
    if (_hasMarker) {
        if (_markerAutomatic) {
            style->marker.auto_shape = style->marker.auto_outline_color = style->marker.auto_fill_color = TRUE;
        } else {
            style->marker.auto_shape = style->marker.auto_outline_color = style->marker.auto_fill_color = FALSE;
            GOMarker *marker = go_style_get_marker (style) ? go_marker_dup (go_style_get_marker (style)) : go_marker_new ();
            go_marker_set_shape (marker, (_markerShape < 0 || _markerShape >= GO_MARKER_MAX) ? GO_MARKER_NONE : (GOMarkerShape) _markerShape);
            go_marker_set_size (marker, (int) MAX (_markerSize, 1));
            if (_markerFillColor)
                go_marker_set_fill_color (marker, gnm_cocoa_go_from_cgcolor (_markerFillColor));
            if (_markerOutlineColor)
                go_marker_set_outline_color (marker, gnm_cocoa_go_from_cgcolor (_markerOutlineColor));
            go_style_set_marker (style, marker);   /* takes the marker */
        }
    }
    if (_hasFont) {
        if (_fontAutomatic) {
            style->font.auto_font = TRUE;
        } else {
            style->font.auto_font = FALSE;
            NSMutableString *name = [NSMutableString stringWithString:_fontFamily.length ? _fontFamily : @"Sans"];
            if (_fontBold)
                [name appendString:@" Bold"];
            if (_fontItalic)
                [name appendString:@" Italic"];
            [name appendFormat:@" %g", _fontSize > 0 ? _fontSize : 10];
            GOFont const *font = go_font_new_by_name (name.UTF8String);
            if (font)
                go_style_set_font (style, font);   /* takes the reference */
        }
        if (_fontColorAutomatic) {
            style->font.auto_color = TRUE;
        } else if (_fontColor) {
            style->font.auto_color = FALSE;
            style->font.color = gnm_cocoa_go_from_cgcolor (_fontColor);
        }
    }
    if (_hasTextLayout) {
        if (_textAngleAutomatic) {
            style->text_layout.auto_angle = TRUE;
        } else {
            style->text_layout.auto_angle = FALSE;
            go_style_set_text_angle (style, _textAngle);
            style->text_layout.auto_angle = FALSE;
        }
    }
}

+ (NSArray<NSString *> *)lineDashNames
{
    static NSArray *names;
    if (names == nil) {
        NSMutableArray *list = [NSMutableArray array];
        for (int i = 0; i < GO_LINE_MAX; i++)
            [list addObject:GnmString (go_line_dash_as_label ((GOLineDashType) i))];
        names = list;
    }
    return names;
}

+ (NSArray<NSString *> *)markerShapeNames
{
    static NSArray *names;
    if (names == nil) {
        NSMutableArray *list = [NSMutableArray array];
        for (int i = 0; i < GO_MARKER_MAX; i++) {
            NSString *s = GnmString (go_marker_shape_as_str ((GOMarkerShape) i));
            s = [[s stringByReplacingOccurrencesOfString:@"-" withString:@" "] capitalizedString];
            [list addObject:s];
        }
        names = list;
    }
    return names;
}

@end

/* ------------------------------------------------------------------------ */

/* A node does not keep its object alive: goffice frees a tree parent
 * first and children through it, and a series freed after its plot reads
 * the plot's description from freed memory.  The editor's graph keeps
 * everything attached alive; an object that leaves the tree goes at once,
 * and its node becomes a tombstone (`isAttached` NO, empty name). */
static void
cb_node_object_gone (gpointer data, G_GNUC_UNUSED GObject *where)
{
    GnmChartNode *node = (__bridge GnmChartNode *) data;   /* held for the call: the editor may drop it */
    [node _objectGone];
}

@implementation GnmChartNode {
    GogObject *_object;
    __weak GnmChartEditor *_editor;
    NSString *_lastName;
}

- (instancetype)initWithObject:(GogObject *)object editor:(GnmChartEditor *)editor
{
    if (!(self = [super init]))
        return nil;
    _object = object;
    _editor = editor;
    g_object_weak_ref (G_OBJECT (object), cb_node_object_gone, (__bridge void *) self);
    return self;
}

- (void)dealloc
{
    if (_object)
        g_object_weak_unref (G_OBJECT (_object), cb_node_object_gone, (__bridge void *) self);
}

- (void)_objectGone
{
    if (_object == NULL)
        return;
    GogObject *object = _object;   /* being finalized: not to be touched */
    _object = NULL;
    [_editor _forgetNodeForObject:object];
}

- (GogObject *)object { return _object; }

- (NSString *)name
{
    if (_object)
        _lastName = GnmString (gog_object_get_name (_object));
    return _lastName ?: @"";
}
- (NSString *)role { return _object && _object->role ? GnmString (_object->role->id) : @""; }
- (NSString *)typeName { return _object ? GnmString (G_OBJECT_TYPE_NAME (_object)) : @""; }

- (BOOL)isAttached
{
    GnmChartEditor *editor = _editor;
    return _object != NULL && editor != nil && gog_object_get_graph (_object) == editor.graph;
}

- (GnmChartNode *)parent
{
    GogObject *parent = _object ? gog_object_get_parent (_object) : NULL;
    return parent ? [_editor _nodeForObject:parent] : nil;
}

- (NSArray<GnmChartNode *> *)children
{
    NSMutableArray *result = [NSMutableArray array];
    GnmChartEditor *editor = _editor;
    if (editor == nil || _object == NULL)
        return result;
    for (GSList *l = _object->children; l; l = l->next)
        [result addObject:[editor _nodeForObject:l->data]];
    return result;
}

- (BOOL)canDelete { return _object != NULL && gog_object_is_deletable (_object); }

- (BOOL)canMoveForward
{
    gboolean inc = FALSE, dec = FALSE;
    if (_object)
        gog_object_can_reorder (_object, &inc, &dec);
    return inc;
}

- (BOOL)canMoveBackward
{
    gboolean inc = FALSE, dec = FALSE;
    if (_object)
        gog_object_can_reorder (_object, &inc, &dec);
    return dec;
}

- (NSArray<NSString *> *)addableRoles
{
    NSMutableArray *result = [NSMutableArray array];
    if (_object == NULL)
        return result;
    GSList *roles = gog_object_possible_additions (_object);
    for (GSList *l = roles; l; l = l->next)
        [result addObject:GnmString (((GogObjectRole const *) l->data)->id)];
    g_slist_free (roles);
    return result;
}

/* Properties the editor hides: identity, layout the sheet object or the
 * chart's grid decide, references to other objects, and parts the GTK
 * editor handles elsewhere or not at all. */
static BOOL
property_is_hidden (GParamSpec *spec)
{
    static NSSet *hidden;
    if (hidden == nil)
        hidden = [NSSet setWithArray:@[@"id", @"position", @"is-position-manual", @"anchor", @"manual-size", @"style", @"theme",
                                       @"document", @"guru-hints", @"plot-group", @"x-axis", @"y-axis", @"z-axis", @"circ-axis",
                                       @"radial-axis", @"pseudo-3d-axis", @"color-axis", @"bubble-axis", @"cross-axis-id",
                                       @"plot-area", @"is-plot-area-manual", @"xpos", @"ypos", @"rows", @"columns", @"width-pts",
                                       @"height-pts", @"pos", @"metrics", @"metrics-unit", @"metrics-ratio", @"axis-ref",
                                       @"color-map-name", @"fill-type", @"polar-unit", @"span-start", @"span-end",
                                       @"circular-rotation", @"display-factor"]];
    NSString *name = GnmString (spec->name);
    if ([hidden containsObject:name])
        return YES;
    if ([name isEqualToString:@"type"] && (spec->owner_type == GOG_TYPE_AXIS || spec->owner_type == GOG_TYPE_GRID))
        return YES;
    return NO;
}

static NSString *
property_label (GParamSpec *spec)
{
    static NSDictionary *labels;
    if (labels == nil)
        labels = @{
            @"invisible": @"Hidden", @"padding-pts": @"Padding (pt)", @"swatch-size-pts": @"Swatch size (pt)",
            @"swatch-padding-pts": @"Swatch padding (pt)", @"major-tick-size-pts": @"Major tick size (pt)",
            @"minor-tick-size-pts": @"Minor tick size (pt)", @"pos-str": @"Position", @"map-name": @"Scale",
            @"assigned-format-string-XL": @"Number format", @"theme-name": @"Theme", @"invert-axis": @"Invert",
            @"major-tick-labeled": @"Show labels", @"major-tick-in": @"Major ticks inside",
            @"major-tick-out": @"Major ticks outside", @"minor-tick-in": @"Minor ticks inside",
            @"minor-tick-out": @"Minor ticks outside", @"type": @"Type", @"in-3d": @"3D",
            @"vary-style-by-element": @"Vary style by element", @"compass": @"Position", @"alignment": @"Alignment",
            @"justification": @"Justification", @"allow-markup": @"Allow markup", @"allow-wrap": @"Wrap text",
            @"rotate-frame": @"Rotate frame with text", @"rotate-bg": @"Rotate background with text",
            @"gap-percentage": @"Gap (%)", @"overlap-percentage": @"Overlap (%)", @"horizontal": @"Horizontal",
            @"has-legend": @"Show in legend", @"interpolation": @"Interpolation",
            @"interpolation-skip-invalid": @"Skip invalid data", @"invalid-as-zero": @"Invalid as zero",
            @"use-splines": @"Use splines", @"before-grid": @"Draw under grid",
            @"default-style-has-markers": @"Markers by default", @"default-style-has-lines": @"Lines by default",
            @"default-style-has-fill": @"Fill by default", @"show-eq": @"Show equation", @"show-r2": @"Show R²",
            @"affine": @"Affine", @"dims": @"Dimensions", @"skip-invalid": @"Skip invalid",
            @"drawing-bounds": @"Drawing bounds", @"outliers": @"Outliers", @"vertical": @"Vertical",
            @"radius-ratio": @"Radius ratio", @"is-minor": @"Minor", @"clamp0": @"Clamp at start",
            @"clamp1": @"Clamp at end",
        };
    NSString *name = GnmString (spec->name);
    NSString *label = labels[name];
    if (label)
        return label;
    NSString *nick = GnmString (g_param_spec_get_nick (spec));
    if (nick.length == 0)
        nick = [name stringByReplacingOccurrencesOfString:@"-" withString:@" "];
    return [[nick substringToIndex:1].uppercaseString stringByAppendingString:[nick substringFromIndex:1]];
}

/* The string properties the GTK editor shows as combos, with the engine
 * strings and their labels; nil for a free text. */
static BOOL
property_choices (GParamSpec *spec, NSArray<NSString *> **choices, NSArray<NSString *> **labels)
{
    NSString *name = GnmString (spec->name);
    if ([name isEqualToString:@"compass"]) {
        *choices = @[@"top", @"bottom", @"left", @"right", @"top-left", @"top-right", @"bottom-left", @"bottom-right"];
        *labels = @[@"Top", @"Bottom", @"Left", @"Right", @"Top left", @"Top right", @"Bottom left", @"Bottom right"];
    } else if ([name isEqualToString:@"alignment"]) {
        *choices = @[@"fill", @"start", @"end", @"center"];
        *labels = @[@"Fill", @"Start", @"End", @"Center"];
    } else if ([name isEqualToString:@"pos-str"]) {
        *choices = @[@"low", @"high", @"cross"];
        *labels = @[@"Low", @"High", @"At the crossing"];
    } else if ([name isEqualToString:@"map-name"]) {
        *choices = @[@"Linear", @"Log"];
        *labels = @[@"Linear", @"Logarithmic"];
    } else if ([name isEqualToString:@"interpolation"]) {
        NSMutableArray *c = [NSMutableArray array], *l = [NSMutableArray array];
        for (int i = 0; i < GO_LINE_INTERPOLATION_MAX; i++) {
            [c addObject:GnmString (go_line_interpolation_as_str ((GOLineInterpolation) i))];
            [l addObject:GnmString (go_line_interpolation_as_label ((GOLineInterpolation) i))];
        }
        *choices = c;
        *labels = l;
    } else if ([name isEqualToString:@"type"] && g_type_is_a (spec->owner_type, g_type_from_name ("GogPlot1_5d"))) {
        *choices = @[@"normal", @"stacked", @"as_percentage"];
        *labels = @[@"Normal", @"Stacked", @"Percentage"];
    } else if ([name isEqualToString:@"justification"]) {
        *choices = @[@"left", @"right", @"center", @"fill"];
        *labels = @[@"Left", @"Right", @"Center", @"Fill"];
    } else if ([name isEqualToString:@"theme-name"]) {
        NSMutableArray *c = [NSMutableArray array];
        GSList *names = gog_theme_registry_get_theme_names ();
        for (GSList *l = names; l; l = l->next)
            [c addObject:GnmString (l->data)];
        g_slist_free (names);
        *choices = c;
        *labels = c;
    } else if ([name isEqualToString:@"drawing-bounds"]) {
        *choices = @[@"none", @"absolute", @"relative"];
        *labels = @[@"None", @"Absolute", @"Relative"];
    } else
        return NO;
    return YES;
}

- (NSArray<GnmChartProperty *> *)properties
{
    if (_object == NULL)
        return @[];
    guint n = 0;
    GParamSpec **specs = g_object_class_list_properties (G_OBJECT_GET_CLASS (_object), &n);
    /* Most specific class first (the GTK editor's page order), registration
     * order within a class. */
    NSMutableArray<NSValue *> *ordered = [NSMutableArray array];
    for (guint i = 0; i < n; i++)
        [ordered addObject:[NSValue valueWithPointer:specs[i]]];
    [ordered sortUsingComparator:^NSComparisonResult (NSValue *a, NSValue *b) {
        GParamSpec *pa = a.pointerValue, *pb = b.pointerValue;
        guint da = g_type_depth (pa->owner_type), db = g_type_depth (pb->owner_type);
        if (da != db)
            return da > db ? NSOrderedAscending : NSOrderedDescending;
        return pa->param_id < pb->param_id ? NSOrderedAscending : (pa->param_id > pb->param_id ? NSOrderedDescending : NSOrderedSame);
    }];
    BOOL compass = _object->role != NULL && (_object->role->allowable_positions & GOG_POSITION_COMPASS) != 0;
    NSMutableArray *result = [NSMutableArray array];
    for (NSValue *v in ordered) {
        GParamSpec *spec = v.pointerValue;
        if (!(spec->flags & G_PARAM_WRITABLE) || !(spec->flags & G_PARAM_READABLE) || (spec->flags & G_PARAM_CONSTRUCT_ONLY))
            continue;
        if (property_is_hidden (spec))
            continue;
        NSString *name = GnmString (spec->name);
        if (([name isEqualToString:@"compass"] || [name isEqualToString:@"alignment"]) && !compass)
            continue;
        GType type = spec->value_type;
        GValue value = G_VALUE_INIT;
        g_value_init (&value, type);
        g_object_get_property (G_OBJECT (_object), spec->name, &value);
        GnmChartProperty *property = nil;
        NSString *label = property_label (spec);
        if (type == G_TYPE_BOOLEAN) {
            property = [[GnmChartProperty alloc] initWithName:name label:label kind:GnmChartPropertyBoolean
                                                        value:@(g_value_get_boolean (&value) ? YES : NO)
                                                      choices:@[] choiceLabels:@[] minimum:0 maximum:1];
        } else if (type == G_TYPE_INT) {
            GParamSpecInt *p = G_PARAM_SPEC_INT (spec);
            property = [[GnmChartProperty alloc] initWithName:name label:label kind:GnmChartPropertyInteger
                                                        value:@(g_value_get_int (&value)) choices:@[] choiceLabels:@[]
                                                      minimum:p->minimum maximum:p->maximum];
        } else if (type == G_TYPE_UINT) {
            GParamSpecUInt *p = G_PARAM_SPEC_UINT (spec);
            property = [[GnmChartProperty alloc] initWithName:name label:label kind:GnmChartPropertyInteger
                                                        value:@(g_value_get_uint (&value)) choices:@[] choiceLabels:@[]
                                                      minimum:p->minimum maximum:p->maximum];
        } else if (type == G_TYPE_DOUBLE) {
            GParamSpecDouble *p = G_PARAM_SPEC_DOUBLE (spec);
            property = [[GnmChartProperty alloc] initWithName:name label:label kind:GnmChartPropertyNumber
                                                        value:@(g_value_get_double (&value)) choices:@[] choiceLabels:@[]
                                                      minimum:p->minimum maximum:p->maximum];
        } else if (type == G_TYPE_FLOAT) {
            GParamSpecFloat *p = G_PARAM_SPEC_FLOAT (spec);
            property = [[GnmChartProperty alloc] initWithName:name label:label kind:GnmChartPropertyNumber
                                                        value:@(g_value_get_float (&value)) choices:@[] choiceLabels:@[]
                                                      minimum:p->minimum maximum:p->maximum];
        } else if (type == G_TYPE_STRING) {
            NSArray *choices = nil, *labels = nil;
            NSString *current = GnmString (g_value_get_string (&value));
            if (property_choices (spec, &choices, &labels)) {
                if (![choices containsObject:current] && choices.count)
                    current = choices.firstObject;
                property = [[GnmChartProperty alloc] initWithName:name label:label kind:GnmChartPropertyChoice value:current
                                                          choices:choices choiceLabels:labels minimum:0 maximum:0];
            } else
                property = [[GnmChartProperty alloc] initWithName:name label:label kind:GnmChartPropertyText value:current
                                                          choices:@[] choiceLabels:@[] minimum:0 maximum:0];
        } else if (G_TYPE_IS_ENUM (type)) {
            GEnumClass *klass = G_PARAM_SPEC_ENUM (spec)->enum_class;
            NSMutableArray *choices = [NSMutableArray array], *labels = [NSMutableArray array];
            for (guint j = 0; j < klass->n_values; j++) {
                [choices addObject:GnmString (klass->values[j].value_nick)];
                [labels addObject:GnmString (klass->values[j].value_name)];
            }
            GEnumValue *ev = g_enum_get_value (klass, g_value_get_enum (&value));
            property = [[GnmChartProperty alloc] initWithName:name label:label kind:GnmChartPropertyChoice
                                                        value:ev ? GnmString (ev->value_nick) : choices.firstObject
                                                      choices:choices choiceLabels:labels minimum:0 maximum:0];
        }
        g_value_unset (&value);
        if (property)
            [result addObject:property];
    }
    g_free (specs);
    return result;
}

- (NSArray<GnmChartDimension *> *)dimensions
{
    NSMutableArray *result = [NSMutableArray array];
    if (_object == NULL || !GOG_IS_DATASET (_object))
        return result;
    GnmChartEditor *editor = _editor;
    Sheet *sheet = editor.sheet;
    int first = 0, last = -1;
    gog_dataset_dims (GOG_DATASET (_object), &first, &last);
    GogSeriesDesc const *desc = NULL;
    if (GOG_IS_SERIES (_object)) {
        GogPlot *plot = gog_series_get_plot (GOG_SERIES (_object));
        if (plot)
            desc = &gog_plot_description (plot)->series;
    }
    static NSArray *axisLabels;
    if (axisLabels == nil)
        axisLabels = @[@"Minimum", @"Maximum", @"Major ticks", @"Minor ticks", @"Cross at"];
    for (int i = first; i <= last; i++) {
        NSString *label;
        GnmChartDataKind kind = GnmChartDataScalar;
        if (desc) {
            if (i < 0)
                label = @"Name";
            else if ((unsigned) i < desc->num_dim) {
                label = GnmString (desc->dim[i].name);
                kind = desc->dim[i].val_type == GOG_DIM_MATRIX ? GnmChartDataMatrix : GnmChartDataVector;
            } else {
                label = [NSString stringWithFormat:@"Data %d", i];
                kind = GnmChartDataVector;
            }
        } else if (GOG_IS_AXIS (_object) && i >= 0 && (unsigned) i < axisLabels.count)
            label = axisLabels[i];
        else if (GOG_IS_TEXT (_object))
            label = @"Text";
        else if (GOG_IS_SERIES_LABELS (_object)) {
            label = @"Custom labels";
            kind = GnmChartDataVector;
        } else
            label = [NSString stringWithFormat:@"Data %d", i];
        GOData *data = gog_dataset_get_dim (GOG_DATASET (_object), i);
        NSString *text = @"";
        if (data) {
            char *s = go_data_serialize (data, sheet ? sheet->convs : NULL);
            text = GnmString (s);
            g_free (s);
        }
        [result addObject:[[GnmChartDimension alloc] initWithIndex:i label:label kind:kind text:text isSet:data != NULL]];
    }
    return result;
}

- (GnmChartStyle *)style
{
    if (_object == NULL || !GO_IS_STYLED_OBJECT (_object))
        return nil;
    GOStyle *style = go_styled_object_get_style (GO_STYLED_OBJECT (_object));
    return style ? [[GnmChartStyle alloc] initWithStyle:style] : nil;
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"<ChartNode %@ %@ (%@) %lu children>", self.role, self.name, self.typeName,
            _object ? (unsigned long) g_slist_length (_object->children) : 0UL];
}

@end

/* ------------------------------------------------------------------------ */

static NSError *
editor_error (NSString *description)
{
    return [NSError errorWithDomain:GnmErrorDomain code:GnmErrorCommandFailed userInfo:@{ NSLocalizedDescriptionKey: description }];
}

/* The copy's data bind to the sheet the way a sheet object's do
 * (sheet-object-graph.c cb_graph_add_data and cb_graph_remove_data): a
 * duplicated or newly set expression links as a dependent, a removed one
 * unlinks, and the editor unlinks everything before letting the copy go,
 * so no dependent outlives the sheet whatever still holds a node. */
static void
cb_copy_add_data (G_GNUC_UNUSED GogGraph *graph, GOData *data, gpointer owner)
{
    Sheet *sheet = ((__bridge GnmChartEditor *) owner).sheet;
    if (sheet)
        gnm_go_data_set_sheet (data, sheet);
}

static void
cb_copy_remove_data (G_GNUC_UNUSED GogGraph *graph, GOData *data, G_GNUC_UNUSED gpointer owner)
{
    gnm_go_data_set_sheet (data, NULL);
}

@implementation GnmChartEditor {
    GogGraph *_graph;
    gulong _addHandler, _removeHandler;
    NSMutableDictionary<NSValue *, GnmChartNode *> *_nodes;
}

- (instancetype)initWithSheetObject:(GnmSheetObject *)object
{
    SheetObject *so = object.engineObject;
    if (so == NULL || !GNM_IS_SO_GRAPH (so) || !object.isAttached || sheet_object_graph_get_gog (so) == NULL)
        return nil;
    if (!(self = [super init]))
        return nil;
    _sheetObject = object;
    _nodes = [NSMutableDictionary dictionary];
    [self _adoptGraph:gog_graph_dup (sheet_object_graph_get_gog (so))];
    return self;
}

- (void)dealloc
{
    [_nodes removeAllObjects];
    [self _releaseGraph];
}

/* Take a copy (one reference) as the working graph. */
- (void)_adoptGraph:(GogGraph *)graph
{
    _graph = graph;
    _addHandler = g_signal_connect (graph, "add_data", G_CALLBACK (cb_copy_add_data), (__bridge void *) self);
    _removeHandler = g_signal_connect (graph, "remove_data", G_CALLBACK (cb_copy_remove_data), (__bridge void *) self);
}

/* Stop listening and unlink the copy's data; `keep` hands the graph
 * on (the apply command took it), else the reference goes. */
- (void)_disownGraphKeeping:(BOOL)keep
{
    if (_graph == NULL)
        return;
    g_signal_handler_disconnect (_graph, _addHandler);
    g_signal_handler_disconnect (_graph, _removeHandler);
    if (!keep) {
        for (GSList *l = gog_graph_get_data (_graph); l; l = l->next)
            gnm_go_data_set_sheet (l->data, NULL);
        g_object_unref (_graph);
    }
    _graph = NULL;
}

- (void)_releaseGraph
{
    [self _disownGraphKeeping:NO];
}

- (GogGraph *)graph { return _graph; }

- (Sheet *)sheet
{
    SheetObject *so = _sheetObject.engineObject;
    return so ? sheet_object_get_sheet (so) : NULL;
}

- (GnmChartNode *)_nodeForObject:(GogObject *)object
{
    NSValue *key = [NSValue valueWithPointer:object];
    GnmChartNode *node = _nodes[key];
    if (node == nil) {
        node = [[GnmChartNode alloc] initWithObject:object editor:self];
        _nodes[key] = node;
    }
    return node;
}

- (void)_forgetNodeForObject:(GogObject *)object
{
    [_nodes removeObjectForKey:[NSValue valueWithPointer:object]];
}

- (void)_didChange
{
    _changeCount++;
}

- (GnmChartNode *)root
{
    return [self _nodeForObject:GOG_OBJECT (_graph)];
}

- (void)drawPreviewInContext:(CGContextRef)context size:(CGSize)size
{
    if (size.width <= 0 || size.height <= 0)
        return;
    CGAffineTransform text_matrix = CGContextGetTextMatrix (context);
    CGContextSaveGState (context);
    cairo_surface_t *surface;
    cairo_t *cr = gnm_cocoa_cairo_for_context (context, CGRectMake (0, 0, size.width, size.height), &surface);
    gog_graph_render_to_cairo (_graph, cr, size.width, size.height);
    cairo_destroy (cr);
    cairo_surface_flush (surface);
    cairo_surface_destroy (surface);
    CGContextRestoreGState (context);
    CGContextSetTextMatrix (context, text_matrix);
}

- (BOOL)applyWithError:(NSError **)error
{
    SheetObject *so = _sheetObject.engineObject;
    GnmSheet *sheet = _sheetObject._ownerSheet;
    if (so == NULL || !_sheetObject.isAttached || sheet == nil) {
        if (error)
            *error = editor_error (@"The chart is no longer on the sheet.");
        return NO;
    }
    GogGraph *graph = _graph;
    GogGraph *old = sheet_object_graph_get_gog (so);
    /* The command and the sheet object take their own references; the
     * object relinks the data to the sheet as it adopts the graph. */
    BOOL ok = [sheet.workbook _runCommand:^gboolean (WorkbookControl *wbc) {
        return cmd_so_graph_config (wbc, so, G_OBJECT (graph), G_OBJECT (old));
    } description:@"Could not reconfigure the chart." error:error];
    if (!ok)
        return NO;
    /* The sheet object owns the copy now and binds its data itself; keep
     * editing a fresh one. */
    [self _disownGraphKeeping:YES];
    g_object_unref (graph);
    [_nodes removeAllObjects];
    [self _adoptGraph:gog_graph_dup (sheet_object_graph_get_gog (so))];
    _changeCount++;
    [sheet _objectsDidChange];
    return YES;
}

- (GnmChartNode *)addChildWithRole:(NSString *)role toNode:(GnmChartNode *)node
{
    if (!node.isAttached || ![node.addableRoles containsObject:role])
        return nil;
    GogObject *child = gog_object_add_by_name (node.object, role.UTF8String, NULL);
    if (child == NULL)
        return nil;
    [self _didChange];
    return [self _nodeForObject:child];
}

- (BOOL)removeNode:(GnmChartNode *)node
{
    if (!node.isAttached || !node.canDelete)
        return NO;
    GogObject *object = node.object;
    /* The parent's reference comes to us (the GTK guru does the same); it
     * is the last one, so the object and its subtree go now. */
    if (!gog_object_clear_parent (object))
        return NO;
    g_object_unref (object);
    [self _didChange];
    return YES;
}

- (BOOL)moveNode:(GnmChartNode *)node forward:(BOOL)forward
{
    if (!node.isAttached || !(forward ? node.canMoveForward : node.canMoveBackward))
        return NO;
    if (gog_object_reorder (node.object, forward, FALSE) == NULL)
        return NO;
    [self _didChange];
    return YES;
}

- (BOOL)setValue:(id)value forProperty:(GnmChartProperty *)property ofNode:(GnmChartNode *)node
{
    if (!node.isAttached)
        return NO;
    GParamSpec *spec = g_object_class_find_property (G_OBJECT_GET_CLASS (node.object), property.name.UTF8String);
    if (spec == NULL || !(spec->flags & G_PARAM_WRITABLE))
        return NO;
    GType type = spec->value_type;
    GValue v = G_VALUE_INIT;
    g_value_init (&v, type);
    if (type == G_TYPE_BOOLEAN && [value isKindOfClass:NSNumber.class])
        g_value_set_boolean (&v, [value boolValue]);
    else if (type == G_TYPE_INT && [value isKindOfClass:NSNumber.class])
        g_value_set_int (&v, (gint) CLAMP ([value doubleValue], G_PARAM_SPEC_INT (spec)->minimum, G_PARAM_SPEC_INT (spec)->maximum));
    else if (type == G_TYPE_UINT && [value isKindOfClass:NSNumber.class])
        g_value_set_uint (&v, (guint) CLAMP ([value doubleValue], G_PARAM_SPEC_UINT (spec)->minimum, G_PARAM_SPEC_UINT (spec)->maximum));
    else if (type == G_TYPE_DOUBLE && [value isKindOfClass:NSNumber.class])
        g_value_set_double (&v, CLAMP ([value doubleValue], G_PARAM_SPEC_DOUBLE (spec)->minimum, G_PARAM_SPEC_DOUBLE (spec)->maximum));
    else if (type == G_TYPE_FLOAT && [value isKindOfClass:NSNumber.class])
        g_value_set_float (&v, (float) CLAMP ([value doubleValue], G_PARAM_SPEC_FLOAT (spec)->minimum, G_PARAM_SPEC_FLOAT (spec)->maximum));
    else if (type == G_TYPE_STRING && [value isKindOfClass:NSString.class])
        g_value_set_string (&v, [value UTF8String]);
    else if (G_TYPE_IS_ENUM (type) && [value isKindOfClass:NSString.class]) {
        GEnumValue *ev = g_enum_get_value_by_nick (G_PARAM_SPEC_ENUM (spec)->enum_class, [value UTF8String]);
        if (ev == NULL) {
            g_value_unset (&v);
            return NO;
        }
        g_value_set_enum (&v, ev->value);
    } else {
        g_value_unset (&v);
        return NO;
    }
    g_object_set_property (G_OBJECT (node.object), spec->name, &v);
    g_value_unset (&v);
    [self _didChange];
    return YES;
}

- (BOOL)setText:(NSString *)text forDimension:(GnmChartDimension *)dimension ofNode:(GnmChartNode *)node error:(NSError **)error
{
    Sheet *sheet = self.sheet;
    if (!node.isAttached || !GOG_IS_DATASET (node.object) || sheet == NULL)
        return NO;
    GOData *data = NULL;
    NSString *trimmed = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (trimmed.length) {
        /* The GTK data allocator's parse (wbc-gtk.c cb_graph_dim_editor_update):
         * vectors may be lists, unknown names are strings, and a scalar
         * that does not parse is the text itself. */
        GnmParsePos pp;
        parse_pos_init_sheet (&pp, sheet);
        GnmParseError perr;
        parse_error_init (&perr);
        GnmExprParseFlags flags = GNM_EXPR_PARSE_UNKNOWN_NAMES_ARE_STRINGS;
        if (dimension.kind != GnmChartDataScalar)
            flags |= GNM_EXPR_PARSE_PERMIT_MULTIPLE_EXPRESSIONS;
        GnmExprTop const *texpr = gnm_expr_parse_str (trimmed.UTF8String, &pp, flags, sheet->convs, &perr);
        if (texpr == NULL) {
            if (dimension.kind == GnmChartDataScalar)
                texpr = gnm_expr_top_new_constant (value_new_string (trimmed.UTF8String));
            else {
                if (error)
                    *error = editor_error (perr.err ? GnmString (perr.err->message) : @"Invalid expression.");
                parse_error_free (&perr);
                return NO;
            }
        }
        parse_error_free (&perr);
        switch (dimension.kind) {
        case GnmChartDataScalar: data = gnm_go_data_scalar_new_expr (sheet, texpr); break;
        case GnmChartDataVector: data = gnm_go_data_vector_new_expr (sheet, texpr); break;
        case GnmChartDataMatrix: data = gnm_go_data_matrix_new_expr (sheet, texpr); break;
        }
    }
    GError *gerr = NULL;
    gog_dataset_set_dim (GOG_DATASET (node.object), (int) dimension.index, data, &gerr);
    if (gerr) {
        if (error)
            *error = editor_error (GnmString (gerr->message));
        g_error_free (gerr);
        return NO;
    }
    [self _didChange];
    return YES;
}

- (GnmChartNode *)changeType:(GnmPlotType *)type ofPlot:(GnmChartNode *)node
{
    GogObject *old = node.object;
    if (!node.isAttached || !GOG_IS_PLOT (old) || type.engineType == NULL)
        return nil;
    GogObject *chart = gog_object_get_parent (old);
    if (!GOG_IS_CHART (chart))
        return nil;
    GogPlot *plot = gog_plot_new_by_type (type.engineType);
    if (plot == NULL)
        return nil;
    /* The series in the tree's order, by Excel's dimension roles
     * (gog_series_map_XL_dim: -1 is the name, below that the type has no
     * such dimension).  A dimension the new type shares across its series
     * (categories, say) comes from the first series that has one. */
    GogSeriesDesc const *old_desc = &gog_plot_description (GOG_PLOT (old))->series;
    GogSeriesDesc const *new_desc = &gog_plot_description (plot)->series;
    gboolean *shared_done = g_new0 (gboolean, new_desc->num_dim + 1);
    GSList *pairs = NULL;   /* (from, to) for the styles, once the plot is in the graph */
    for (GSList const *l = old->children; l; l = l->next) {
        if (!GOG_IS_SERIES (l->data))
            continue;
        GogSeries *from = l->data;
        GogSeries *to = gog_plot_new_series (plot);
        if (to == NULL)
            break;   /* as many as the type holds */
        pairs = g_slist_append (pairs, from);
        pairs = g_slist_append (pairs, to);
        GOData *name = gog_dataset_get_dim (GOG_DATASET (from), -1);
        if (name)
            gog_dataset_set_dim (GOG_DATASET (to), -1, go_data_dup (name), NULL);
        for (unsigned i = 0; i < old_desc->num_dim; i++) {
            GOData *data = gog_dataset_get_dim (GOG_DATASET (from), (int) i);
            if (data == NULL)
                continue;
            int j = gog_series_map_XL_dim (to, old_desc->dim[i].ms_type);
            if (j < 0 || (unsigned) j >= new_desc->num_dim)
                continue;
            if (new_desc->dim[j].is_shared) {
                if (shared_done[j])
                    continue;
                shared_done[j] = TRUE;
            }
            gog_dataset_set_dim (GOG_DATASET (to), j, go_data_dup (data), NULL);
        }
    }
    g_free (shared_done);
    /* Out with the old plot (the node keeps its reference), the axes the
     * new type wants (gog_chart_axis_set_assign adds the missing ones;
     * the ones outside the set go here), then the new plot and the
     * type's guru hints. */
    gog_object_clear_parent (old);   /* the parent's reference is ours until the styles are copied */
    gog_plot_axis_clear (GOG_PLOT (old), GOG_AXIS_SET_ALL);   /* no stale hold on the chart's axes */
    GogAxisSet set = gog_plot_axis_set_pref (plot);
    gog_chart_axis_set_assign (GOG_CHART (chart), set);
    GSList *stale = NULL;
    for (GSList *l = chart->children; l; l = l->next)
        if (GOG_IS_AXIS (l->data) && !(set & (1 << gog_axis_get_atype (GOG_AXIS (l->data)))))
            stale = g_slist_prepend (stale, l->data);
    for (GSList *l = stale; l; l = l->next)
        if (gog_object_is_deletable (l->data) && gog_object_clear_parent (l->data))
            g_object_unref (l->data);
    g_slist_free (stale);
    gog_object_add_by_name (chart, "Plot", GOG_OBJECT (plot));
    /* The styles, now that the theme has had its say on the new series:
     * what was set by hand on the old ones stays set. */
    for (GSList *l = pairs; l && l->next; l = l->next->next) {
        GOStyle *from_style = go_styled_object_get_style (GO_STYLED_OBJECT (l->data));
        GOStyle *to_style = go_styled_object_get_style (GO_STYLED_OBJECT (l->next->data));
        if (from_style && to_style) {
            GOStyle *copy = go_style_dup (from_style);
            copy->interesting_fields = to_style->interesting_fields;
            go_styled_object_set_style (GO_STYLED_OBJECT (l->next->data), copy);
            g_object_unref (copy);
        }
    }
    g_slist_free (pairs);
    g_object_unref (old);   /* the last reference: the old plot and its series go now */
    NSString *hints = [type propertyNamed:@"guru-hints"];
    if ([hints containsString:@"backplane"] && gog_object_get_child_by_name (chart, "Backplane") == NULL)
        gog_object_add_by_name (chart, "Backplane", NULL);
    if ([hints containsString:@"major-grid"]) {
        GSList *axes = gog_chart_get_axes (GOG_CHART (chart), GOG_AXIS_Y);
        if (axes && gog_object_get_child_by_name (GOG_OBJECT (axes->data), "MajorGrid") == NULL)
            gog_object_add_by_name (GOG_OBJECT (axes->data), "MajorGrid", NULL);
        g_slist_free (axes);
    }
    [self _didChange];
    return [self _nodeForObject:GOG_OBJECT (plot)];
}

- (BOOL)applyStyle:(GnmChartStyle *)style toNode:(GnmChartNode *)node
{
    if (!node.isAttached || !GO_IS_STYLED_OBJECT (node.object))
        return NO;
    GOStyle *current = go_styled_object_get_style (GO_STYLED_OBJECT (node.object));
    if (current == NULL)
        return NO;
    GOStyle *copy = go_style_dup (current);
    [style writeToStyle:copy];
    go_styled_object_set_style (GO_STYLED_OBJECT (node.object), copy);
    g_object_unref (copy);
    [self _didChange];
    return YES;
}

@end
