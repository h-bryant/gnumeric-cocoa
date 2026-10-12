#import "GnmPrivate.h"

@implementation GnmCellFormat {
    NSMutableDictionary<NSNumber *, NSNumber *> *_borderStyles;
    NSMutableDictionary<NSNumber *, id> *_borderColors;   /* CGColorRef boxed, or NSNull */
}

- (instancetype)init
{
    if ((self = [super init])) {
        _borderStyles = [NSMutableDictionary dictionary];
        _borderColors = [NSMutableDictionary dictionary];
    }
    return self;
}

- (void)dealloc
{
    if (_textColor) CGColorRelease (_textColor);
    if (_backgroundColor) CGColorRelease (_backgroundColor);
}

- (void)setTextColor:(CGColorRef)textColor
{
    if (textColor) CGColorRetain (textColor);
    if (_textColor) CGColorRelease (_textColor);
    _textColor = textColor;
}

- (void)setBackgroundColor:(CGColorRef)backgroundColor
{
    if (backgroundColor) CGColorRetain (backgroundColor);
    if (_backgroundColor) CGColorRelease (_backgroundColor);
    _backgroundColor = backgroundColor;
}

- (id)copyWithZone:(NSZone *)zone
{
    GnmCellFormat *c = [[GnmCellFormat allocWithZone:zone] init];
    c.numberFormat = self.numberFormat;
    c.horizontalAlignment = self.horizontalAlignment;
    c.verticalAlignment = self.verticalAlignment;
    c.wrapsText = self.wrapsText;
    c.fontName = self.fontName;
    c.fontSize = self.fontSize;
    c.bold = self.bold;
    c.italic = self.italic;
    c.underline = self.underline;
    c.strikethrough = self.strikethrough;
    c.textColor = self.textColor;
    c.fillsBackground = self.fillsBackground;
    c.backgroundColor = self.backgroundColor;
    for (NSNumber *edge in _borderStyles)
        [c setBorderStyle:_borderStyles[edge].integerValue
                    color:[self borderColorForEdge:edge.integerValue]
                  forEdge:edge.integerValue];
    return c;
}

- (NSNumber *)borderStyleForEdge:(GnmBorderEdge)edge
{
    return _borderStyles[@(edge)];
}

- (CGColorRef)borderColorForEdge:(GnmBorderEdge)edge
{
    id boxed = _borderColors[@(edge)];
    return (boxed == nil || boxed == NSNull.null) ? NULL : (__bridge CGColorRef) boxed;
}

- (void)setBorderStyle:(GnmBorderLineStyle)style color:(CGColorRef)color forEdge:(GnmBorderEdge)edge
{
    _borderStyles[@(edge)] = @(style);
    _borderColors[@(edge)] = color ? (__bridge id) color : NSNull.null;
}

- (void)clearBorderForEdge:(GnmBorderEdge)edge
{
    [_borderStyles removeObjectForKey:@(edge)];
    [_borderColors removeObjectForKey:@(edge)];
}

+ (GnmNumberFormatFamily)familyOfNumberFormat:(NSString *)format
{
    GOFormat *fmt = go_format_new_from_XL (format.UTF8String);
    GnmNumberFormatFamily family = (GnmNumberFormatFamily) go_format_get_family (fmt);
    go_format_unref (fmt);
    return family;
}

+ (NSString *)numberFormatForFamily:(GnmNumberFormatFamily)family decimals:(NSInteger)decimals
                   thousandsSeparator:(BOOL)thousandsSeparator
{
    GOFormatDetails *details = go_format_details_new ((GOFormatFamily) family);
    details->num_decimals = (int) MAX (decimals, 0);
    details->thousands_sep = thousandsSeparator;
    GString *str = g_string_new (NULL);
    go_format_generate_str (str, details);
    NSString *result = GnmString (str->str);
    g_string_free (str, TRUE);
    go_format_details_free (details);
    return result.length ? result : @"General";
}

@end

/* ------------------------------------------------------------------------
 * Engine conversions, used by GnmSheet.
 */

CGColorRef
gnm_cocoa_cgcolor_from_go (GOColor c)
{
    return CGColorCreateSRGB (GO_COLOR_UINT_R (c) / 255.0, GO_COLOR_UINT_G (c) / 255.0,
                              GO_COLOR_UINT_B (c) / 255.0, GO_COLOR_UINT_A (c) / 255.0);
}

GOColor
gnm_cocoa_go_from_cgcolor (CGColorRef color)
{
    GdkRGBA rgba = gnm_cocoa_rgba_from_cgcolor (color);
    return GO_COLOR_FROM_RGBA ((int) lround (rgba.red * 255), (int) lround (rgba.green * 255),
                               (int) lround (rgba.blue * 255), (int) lround (rgba.alpha * 255));
}

static BOOL
conflicts (unsigned mask, GnmStyleElement e)
{
    return (mask & (1u << e)) != 0;
}

GnmCellFormat *
gnm_cocoa_format_from_selection (Sheet const *sheet, GnmRange const *range)
{
    GnmStyle *style = NULL;
    GnmBorder *borders[GNM_STYLE_BORDER_EDGE_MAX];
    unsigned mask = sheet_style_find_conflicts (sheet, range, &style, borders);
    GnmCellFormat *f = [[GnmCellFormat alloc] init];

    if (!conflicts (mask, MSTYLE_FORMAT))
        f.numberFormat = GnmString (go_format_as_XL (gnm_style_get_format (style)));
    if (!conflicts (mask, MSTYLE_ALIGN_H))
        f.horizontalAlignment = @(gnm_style_get_align_h (style));
    if (!conflicts (mask, MSTYLE_ALIGN_V))
        f.verticalAlignment = @(gnm_style_get_align_v (style));
    if (!conflicts (mask, MSTYLE_WRAP_TEXT))
        f.wrapsText = @(gnm_style_get_wrap_text (style));
    if (!conflicts (mask, MSTYLE_FONT_NAME))
        f.fontName = GnmString (gnm_style_get_font_name (style));
    if (!conflicts (mask, MSTYLE_FONT_SIZE))
        f.fontSize = @(gnm_style_get_font_size (style));
    if (!conflicts (mask, MSTYLE_FONT_BOLD))
        f.bold = @(gnm_style_get_font_bold (style));
    if (!conflicts (mask, MSTYLE_FONT_ITALIC))
        f.italic = @(gnm_style_get_font_italic (style));
    if (!conflicts (mask, MSTYLE_FONT_UNDERLINE))
        f.underline = @(gnm_style_get_font_uline (style));
    if (!conflicts (mask, MSTYLE_FONT_STRIKETHROUGH))
        f.strikethrough = @(gnm_style_get_font_strike (style));
    if (!conflicts (mask, MSTYLE_FONT_COLOR)) {
        CGColorRef c = gnm_cocoa_cgcolor_from_go (gnm_style_get_font_color (style)->go_color);
        f.textColor = c;
        CGColorRelease (c);
    }
    if (!conflicts (mask, MSTYLE_PATTERN)) {
        int pattern = gnm_style_get_pattern (style);
        f.fillsBackground = @(pattern != 0);
        if (pattern != 0 && !conflicts (mask, MSTYLE_COLOR_BACK)) {
            CGColorRef c = gnm_cocoa_cgcolor_from_go (gnm_style_get_back_color (style)->go_color);
            f.backgroundColor = c;
            CGColorRelease (c);
        }
    }
    for (int i = 0; i < GNM_STYLE_BORDER_EDGE_MAX; i++) {
        GnmBorder *b = borders[i];
        if (b == NULL)
            continue;   /* differs across the selection */
        CGColorRef c = b->color ? gnm_cocoa_cgcolor_from_go (b->color->go_color) : NULL;
        [f setBorderStyle:(GnmBorderLineStyle) b->line_type color:c forEdge:(GnmBorderEdge) i];
        if (c)
            CGColorRelease (c);
        gnm_style_border_unref (b);
    }
    gnm_style_unref (style);
    return f;
}

/* A partial style's set elements as a format (a conditional overlay). */
GnmCellFormat *
gnm_cocoa_format_from_style (GnmStyle const *style)
{
    GnmCellFormat *f = [[GnmCellFormat alloc] init];
    if (gnm_style_is_element_set (style, MSTYLE_FORMAT))
        f.numberFormat = GnmString (go_format_as_XL (gnm_style_get_format (style)));
    if (gnm_style_is_element_set (style, MSTYLE_ALIGN_H))
        f.horizontalAlignment = @(gnm_style_get_align_h (style));
    if (gnm_style_is_element_set (style, MSTYLE_ALIGN_V))
        f.verticalAlignment = @(gnm_style_get_align_v (style));
    if (gnm_style_is_element_set (style, MSTYLE_WRAP_TEXT))
        f.wrapsText = @(gnm_style_get_wrap_text (style));
    if (gnm_style_is_element_set (style, MSTYLE_FONT_NAME))
        f.fontName = GnmString (gnm_style_get_font_name (style));
    if (gnm_style_is_element_set (style, MSTYLE_FONT_SIZE))
        f.fontSize = @(gnm_style_get_font_size (style));
    if (gnm_style_is_element_set (style, MSTYLE_FONT_BOLD))
        f.bold = @(gnm_style_get_font_bold (style));
    if (gnm_style_is_element_set (style, MSTYLE_FONT_ITALIC))
        f.italic = @(gnm_style_get_font_italic (style));
    if (gnm_style_is_element_set (style, MSTYLE_FONT_UNDERLINE))
        f.underline = @(gnm_style_get_font_uline (style));
    if (gnm_style_is_element_set (style, MSTYLE_FONT_STRIKETHROUGH))
        f.strikethrough = @(gnm_style_get_font_strike (style));
    if (gnm_style_is_element_set (style, MSTYLE_FONT_COLOR)) {
        CGColorRef c = gnm_cocoa_cgcolor_from_go (gnm_style_get_font_color (style)->go_color);
        f.textColor = c;
        CGColorRelease (c);
    }
    if (gnm_style_is_element_set (style, MSTYLE_PATTERN)) {
        int pattern = gnm_style_get_pattern (style);
        f.fillsBackground = @(pattern != 0);
    }
    if (gnm_style_is_element_set (style, MSTYLE_COLOR_BACK)) {
        CGColorRef c = gnm_cocoa_cgcolor_from_go (gnm_style_get_back_color (style)->go_color);
        f.backgroundColor = c;
        CGColorRelease (c);
    }
    return f;
}

/* Builds the partial style and border set cmd_selection_format wants; both
 * are handed over to the command. */
void
gnm_cocoa_format_to_engine (GnmCellFormat *f, GnmStyle **style_out, GnmBorder *borders[GNM_STYLE_BORDER_EDGE_MAX])
{
    GnmStyle *style = gnm_style_new ();
    if (f.numberFormat)
        gnm_style_set_format_text (style, f.numberFormat.UTF8String);
    if (f.horizontalAlignment)
        gnm_style_set_align_h (style, (GnmHAlign) f.horizontalAlignment.integerValue);
    if (f.verticalAlignment)
        gnm_style_set_align_v (style, (GnmVAlign) f.verticalAlignment.integerValue);
    if (f.wrapsText)
        gnm_style_set_wrap_text (style, f.wrapsText.boolValue);
    if (f.fontName)
        gnm_style_set_font_name (style, f.fontName.UTF8String);
    if (f.fontSize)
        gnm_style_set_font_size (style, MAX (f.fontSize.doubleValue, 1.0));
    if (f.bold)
        gnm_style_set_font_bold (style, f.bold.boolValue);
    if (f.italic)
        gnm_style_set_font_italic (style, f.italic.boolValue);
    if (f.underline)
        gnm_style_set_font_uline (style, (GnmUnderline) f.underline.integerValue);
    if (f.strikethrough)
        gnm_style_set_font_strike (style, f.strikethrough.boolValue);
    if (f.textColor)
        gnm_style_set_font_color (style, gnm_color_new_go (gnm_cocoa_go_from_cgcolor (f.textColor)));
    if (f.fillsBackground) {
        if (f.fillsBackground.boolValue) {
            gnm_style_set_pattern (style, 1);
            if (f.backgroundColor)
                gnm_style_set_back_color (style, gnm_color_new_go (gnm_cocoa_go_from_cgcolor (f.backgroundColor)));
        } else
            gnm_style_set_pattern (style, 0);
    } else if (f.backgroundColor) {
        gnm_style_set_pattern (style, 1);
        gnm_style_set_back_color (style, gnm_color_new_go (gnm_cocoa_go_from_cgcolor (f.backgroundColor)));
    }
    for (int i = 0; i < GNM_STYLE_BORDER_EDGE_MAX; i++) {
        NSNumber *line = [f borderStyleForEdge:(GnmBorderEdge) i];
        if (line == nil) {
            borders[i] = NULL;
            continue;
        }
        CGColorRef c = [f borderColorForEdge:(GnmBorderEdge) i];
        GnmColor *color = c ? gnm_color_new_go (gnm_cocoa_go_from_cgcolor (c)) : gnm_color_new_rgb8 (0, 0, 0);
        borders[i] = gnm_style_border_fetch ((GnmStyleBorderType) line.integerValue, color,
                                             gnm_style_border_get_orientation ((GnmStyleBorderLocation) i));
    }
    *style_out = style;
}
