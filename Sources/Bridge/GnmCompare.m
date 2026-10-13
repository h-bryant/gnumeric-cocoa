// The GTK compare dialog's GnmDiffActions (dialog-sheet-compare.c
// dsc_*), building the tree the dialog shows.
#import "GnmPrivate.h"
#include <sheet-diff.h>
#include <cell.h>
#include <ranges.h>
#include <parse-util.h>
#include <sheet-style.h>
#include <mstyle.h>
#include <style-color.h>
#include <gtk/gtk.h>
#include <goffice/gtk/go-color-palette.h>

@interface GnmSheetDifference ()
@property (nonatomic, readwrite) GnmDifferenceSection section;
@property (nonatomic, readwrite) GnmDifferenceDirection direction;
@property (nonatomic, readwrite, copy) NSString *text;
@property (nonatomic, readwrite, copy) NSString *location;
@property (nonatomic, readwrite, copy) NSString *beforeText;
@property (nonatomic, readwrite, copy) NSString *afterText;
@property (nonatomic, readwrite, nullable, weak) GnmSheet *beforeSheet;
@property (nonatomic, readwrite, nullable, weak) GnmSheet *afterSheet;
@property (nonatomic, readwrite) GnmCellRange beforeRange;
@property (nonatomic, readwrite) GnmCellRange afterRange;
@property (nonatomic, readonly) NSMutableArray<GnmSheetDifference *> *mutableChildren;
- (instancetype)initPrivate;
@end

@implementation GnmSheetDifference {
    NSMutableArray<GnmSheetDifference *> *_mutableChildren;
}

- (instancetype)initPrivate
{
    if (!(self = [super init]))
        return nil;
    _text = @"";
    _location = @"";
    _beforeText = @"";
    _afterText = @"";
    _mutableChildren = [NSMutableArray array];
    return self;
}

- (NSMutableArray<GnmSheetDifference *> *)mutableChildren { return _mutableChildren; }
- (NSArray<GnmSheetDifference *> *)children { return [_mutableChildren copy]; }

- (NSString *)description
{
    return [NSString stringWithFormat:@"<%@ %ld/%ld '%@' %@ '%@'→'%@' %lu>", self.class, (long) _section, (long) _direction,
            _text, _location, _beforeText, _afterText, (unsigned long) _mutableChildren.count];
}

@end

/* The dialog's renderers */

static NSString *
mstyle_name (int e)
{
    switch (e) {
    case MSTYLE_COLOR_BACK: return @"Background color";
    case MSTYLE_COLOR_PATTERN: return @"Pattern color";
    case MSTYLE_BORDER_TOP: return @"Top border";
    case MSTYLE_BORDER_BOTTOM: return @"Bottom border";
    case MSTYLE_BORDER_LEFT: return @"Left border";
    case MSTYLE_BORDER_RIGHT: return @"Right border";
    case MSTYLE_BORDER_REV_DIAGONAL: return @"Reverse diagonal border";
    case MSTYLE_BORDER_DIAGONAL: return @"Diagonal border";
    case MSTYLE_PATTERN: return @"Pattern";
    case MSTYLE_FONT_COLOR: return @"Font color";
    case MSTYLE_FONT_NAME: return @"Font";
    case MSTYLE_FONT_BOLD: return @"Bold";
    case MSTYLE_FONT_ITALIC: return @"Italic";
    case MSTYLE_FONT_UNDERLINE: return @"Underline";
    case MSTYLE_FONT_STRIKETHROUGH: return @"Strikethrough";
    case MSTYLE_FONT_SCRIPT: return @"Script";
    case MSTYLE_FONT_SIZE: return @"Size";
    case MSTYLE_FORMAT: return @"Format";
    case MSTYLE_ALIGN_V: return @"Vertical alignment";
    case MSTYLE_ALIGN_H: return @"Horizontal alignment";
    case MSTYLE_INDENT: return @"Indentation";
    case MSTYLE_ROTATION: return @"Rotation";
    case MSTYLE_TEXT_DIR: return @"Direction";
    case MSTYLE_WRAP_TEXT: return @"Wrap";
    case MSTYLE_SHRINK_TO_FIT: return @"Shrink-to-fit";
    case MSTYLE_CONTENTS_LOCKED: return @"Locked";
    case MSTYLE_CONTENTS_HIDDEN: return @"Hidden";
    case MSTYLE_VALIDATION: return @"Validation";
    case MSTYLE_HLINK: return @"Hyperlink";
    case MSTYLE_INPUT_MSG: return @"Input message";
    case MSTYLE_CONDITIONS: return @"Conditional format";
    default: return @"?";
    }
}

static NSString *
color_text (GnmColor const *gcolor)
{
    GOColor color = gcolor->go_color;
    unsigned r, g, b, a;
    GO_COLOR_TO_RGBA (color, &r, &g, &b, &a);
    NSString *hex = a == 0xff ? [NSString stringWithFormat:@"#%02X%02X%02X", r, g, b]
                              : [NSString stringWithFormat:@"#%02X%02X%02X%02X", r, g, b, a];
    const char *name = NULL;
    GONamedColor nc;
    for (int n = 0; go_color_palette_query (n, &nc); n++)
        if (nc.color == color) {
            name = nc.name;
            break;
        }
    return [NSString stringWithFormat:@"%@%@%@", gcolor->is_auto ? @"Auto " : @"", name ? [NSString stringWithUTF8String:name] : hex,
            name ? [NSString stringWithFormat:@" (%@)", hex] : @""];
}

static NSString *
halign_text (GnmHAlign h)
{
    switch (h) {
    case GNM_HALIGN_GENERAL: return @"General";
    case GNM_HALIGN_LEFT: return @"Left";
    case GNM_HALIGN_RIGHT: return @"Right";
    case GNM_HALIGN_CENTER: return @"Center";
    case GNM_HALIGN_FILL: return @"Fill";
    case GNM_HALIGN_JUSTIFY: return @"Justify";
    case GNM_HALIGN_CENTER_ACROSS_SELECTION: return @"Center across selection";
    case GNM_HALIGN_DISTRIBUTED: return @"Distributed";
    default: return @"?";
    }
}

static NSString *
valign_text (GnmVAlign v)
{
    switch (v) {
    case GNM_VALIGN_TOP: return @"Top";
    case GNM_VALIGN_BOTTOM: return @"Bottom";
    case GNM_VALIGN_CENTER: return @"Center";
    case GNM_VALIGN_JUSTIFY: return @"Justify";
    case GNM_VALIGN_DISTRIBUTED: return @"Distributed";
    default: return @"?";
    }
}

static NSString *
bool_text (gboolean b)
{
    return b ? @"Yes" : @"No";
}

/* oldnew_renderer_func for a style element */
static NSString *
style_element_text (GnmStyle const *style, int e)
{
    static NSString *const underlines[] = { @"None", @"Single", @"Double", @"Single low", @"Double low" };
    static NSString *const textdirs[] = { @"Right-to-left", @"Auto", @"Left-to-right" };
    switch (e) {
    case MSTYLE_COLOR_BACK: return color_text (gnm_style_get_back_color (style));
    case MSTYLE_COLOR_PATTERN: return color_text (gnm_style_get_pattern_color (style));
    case MSTYLE_FONT_COLOR: return color_text (gnm_style_get_font_color (style));
    case MSTYLE_PATTERN: return [NSString stringWithFormat:@"%d", gnm_style_get_pattern (style)];
    case MSTYLE_FONT_NAME: return [NSString stringWithUTF8String:gnm_style_get_font_name (style)];
    case MSTYLE_FONT_BOLD: return bool_text (gnm_style_get_font_bold (style));
    case MSTYLE_FONT_ITALIC: return bool_text (gnm_style_get_font_italic (style));
    case MSTYLE_FONT_UNDERLINE: {
        int u = gnm_style_get_font_uline (style);
        return u >= 0 && u < 5 ? underlines[u] : @"?";
    }
    case MSTYLE_FONT_STRIKETHROUGH: return bool_text (gnm_style_get_font_strike (style));
    case MSTYLE_FONT_SCRIPT: return [NSString stringWithFormat:@"%d", gnm_style_get_font_script (style)];
    case MSTYLE_FONT_SIZE: return [NSString stringWithFormat:@"%g", gnm_style_get_font_size (style)];
    case MSTYLE_ROTATION: return [NSString stringWithFormat:@"%d", gnm_style_get_rotation (style)];
    case MSTYLE_INDENT: return [NSString stringWithFormat:@"%d", gnm_style_get_indent (style)];
    case MSTYLE_FORMAT: return [NSString stringWithUTF8String:go_format_as_XL (gnm_style_get_format (style))];
    case MSTYLE_TEXT_DIR: {
        int d = 1 + gnm_style_get_text_dir (style);
        return d >= 0 && d < 3 ? textdirs[d] : @"?";
    }
    case MSTYLE_ALIGN_H: return halign_text (gnm_style_get_align_h (style));
    case MSTYLE_ALIGN_V: return valign_text (gnm_style_get_align_v (style));
    case MSTYLE_CONTENTS_LOCKED: return bool_text (gnm_style_get_contents_locked (style));
    case MSTYLE_CONTENTS_HIDDEN: return bool_text (gnm_style_get_contents_hidden (style));
    default: return @"Unavailable";
    }
}

/* location_renderer_func */
static NSString *
location_text (Sheet const *sheet, GnmRange const *r)
{
    if (range_is_full (r, sheet, TRUE) && r->start.row == r->end.row)
        return [NSString stringWithFormat:@"Row %s", row_name (r->start.row)];
    if (range_is_full (r, sheet, FALSE) && r->start.col == r->end.col)
        return [NSString stringWithFormat:@"Column %s", col_name (r->start.col)];
    return GnmString (range_as_string (r));
}

static GnmCellRange
cell_range_of (GnmRange const *r)
{
    return GnmCellRangeMake (r->start.col, r->start.row, r->end.col, r->end.row);
}

/* The diff's state (SheetCompare) */
typedef struct {
    void *result;    /* NSMutableArray<GnmSheetDifference *> * */
    void *sections[3];   /* GnmSheetDifference * or NULL */
    Sheet *old_sheet, *new_sheet;
    void *old_wrapper, *new_wrapper;   /* GnmSheet * */
} CompareState;

static GnmSheetDifference *
section_head (CompareState *state, GnmDifferenceSection section)
{
    if (!state->sections[section]) {
        GnmSheetDifference *head = [[GnmSheetDifference alloc] initPrivate];
        head.section = section;
        head.direction = GnmDifferenceDirectionNone;
        head.text = section == GnmDifferenceSectionCells ? @"Cells" : section == GnmDifferenceSectionFormatting ? @"Formatting" : @"Columns/Rows";
        [(__bridge NSMutableArray *) state->result addObject:head];
        state->sections[section] = (__bridge_retained void *) head;
    }
    return (__bridge GnmSheetDifference *) state->sections[section];
}

static void
dsc_sheet_start (gpointer user, Sheet const *os, Sheet const *ns)
{
    CompareState *state = user;
    state->old_sheet = (Sheet *) os;
    state->new_sheet = (Sheet *) ns;
}

static void
dsc_sheet_end (gpointer user)
{
    CompareState *state = user;
    state->old_sheet = NULL;
    state->new_sheet = NULL;
}

static void
dsc_cell_changed (gpointer user, GnmCell const *oc, GnmCell const *nc)
{
    CompareState *state = user;
    GnmSheetDifference *head = section_head (state, GnmDifferenceSectionCells);
    GnmSheetDifference *d = [[GnmSheetDifference alloc] initPrivate];
    d.section = GnmDifferenceSectionCells;
    d.direction = oc ? (nc ? GnmDifferenceDirectionChanged : GnmDifferenceDirectionRemoved) : GnmDifferenceDirectionAdded;
    d.text = d.direction == GnmDifferenceDirectionChanged ? @"Changed" : d.direction == GnmDifferenceDirectionRemoved ? @"Removed" : @"Added";
    GnmCell const *where = oc ? oc : nc;
    GnmRange r;
    range_init (&r, where->pos.col, where->pos.row, where->pos.col, where->pos.row);
    d.location = location_text (where->base.sheet, &r);
    if (oc) {
        char *text = gnm_cell_get_entered_text (oc);
        d.beforeText = GnmString (text);
        d.beforeSheet = (__bridge GnmSheet *) state->old_wrapper;
        d.beforeRange = cell_range_of (&r);
    }
    if (nc) {
        char *text = gnm_cell_get_entered_text (nc);
        d.afterText = GnmString (text);
        d.afterSheet = (__bridge GnmSheet *) state->new_wrapper;
        d.afterRange = cell_range_of (&r);
    }
    [head.mutableChildren addObject:d];
}

static void
dsc_style_changed (gpointer user, GnmRange const *r, GnmStyle const *os, GnmStyle const *ns)
{
    CompareState *state = user;
    GnmSheetDifference *head = section_head (state, GnmDifferenceSectionFormatting);
    unsigned int conflicts = gnm_style_find_differences (os, ns, TRUE);
    GnmSheetDifference *parent = head;
    int estart = (conflicts & (conflicts - 1)) == 0 ? 0 : -1;
    for (int e = estart; e < MSTYLE_ELEMENT_MAX; e++) {
        gboolean qhead = e == -1;
        if (!qhead && (conflicts & (1u << e)) == 0)
            continue;
        GnmSheetDifference *d = [[GnmSheetDifference alloc] initPrivate];
        d.section = GnmDifferenceSectionFormatting;
        d.direction = GnmDifferenceDirectionQuiet;
        d.text = qhead ? @"Various" : mstyle_name (e);
        d.location = location_text (state->new_sheet, r);
        d.beforeSheet = (__bridge GnmSheet *) state->old_wrapper;
        d.afterSheet = (__bridge GnmSheet *) state->new_wrapper;
        d.beforeRange = cell_range_of (r);
        d.afterRange = cell_range_of (r);
        if (!qhead) {
            d.beforeText = style_element_text (os, e);
            d.afterText = style_element_text (ns, e);
        }
        [parent.mutableChildren addObject:d];
        if (qhead)
            parent = d;
    }
}

static void
dsc_colrow_changed (gpointer user, ColRowInfo const *oc, ColRowInfo const *nc, gboolean is_cols, int i)
{
    CompareState *state = user;
    GnmSheetDifference *head = section_head (state, GnmDifferenceSectionColumnsRows);
    GnmSheetDifference *d = [[GnmSheetDifference alloc] initPrivate];
    d.section = GnmDifferenceSectionColumnsRows;
    d.direction = GnmDifferenceDirectionQuiet;
    d.text = @"Size";
    GnmRange rold, rnew;
    (is_cols ? range_init_cols : range_init_rows) (&rold, state->old_sheet, i, i);
    (is_cols ? range_init_cols : range_init_rows) (&rnew, state->new_sheet, i, i);
    d.location = location_text (state->new_sheet, &rnew);
    d.beforeSheet = (__bridge GnmSheet *) state->old_wrapper;
    d.afterSheet = (__bridge GnmSheet *) state->new_wrapper;
    d.beforeRange = cell_range_of (&rold);
    d.afterRange = cell_range_of (&rnew);
    d.beforeText = [NSString stringWithFormat:@"%.2f pt", oc->size_pts];
    d.afterText = [NSString stringWithFormat:@"%.2f pt", nc->size_pts];
    [head.mutableChildren addObject:d];
}

static const GnmDiffActions dsc_actions = {
    .sheet_start = dsc_sheet_start,
    .sheet_end = dsc_sheet_end,
    .cell_changed = dsc_cell_changed,
    .style_changed = dsc_style_changed,
    .colrow_changed = dsc_colrow_changed,
};

@implementation GnmSheet (Compare)

- (NSArray<GnmSheetDifference *> *)differencesFromSheet:(GnmSheet *)beforeSheet
{
    NSAssert (NSThread.isMainThread, @"engine access off the main thread");
    NSMutableArray *result = [NSMutableArray array];
    Sheet *new_sheet = self.engineSheet, *old_sheet = beforeSheet.engineSheet;
    if (!new_sheet || !old_sheet)
        return result;
    CompareState state = { 0 };
    state.result = (__bridge void *) result;
    state.old_wrapper = (__bridge void *) beforeSheet;
    state.new_wrapper = (__bridge void *) self;
    gnm_diff_sheets (&dsc_actions, &state, old_sheet, new_sheet);
    for (int i = 0; i < 3; i++)
        if (state.sections[i])
            CFRelease (state.sections[i]);
    return result;
}

@end
