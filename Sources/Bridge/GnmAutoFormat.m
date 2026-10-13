// AutoFormat templates as dialog-autoformat.c reads, previews, and
// applies them.
#import "GnmPrivate.h"
#include <format-template.h>
#include <file-autoft.h>
#include <commands.h>
#include <mstyle.h>
#include <style-border.h>
#include <style-color.h>
#include <ranges.h>

enum { PREVIEW_ROWS = 5, PREVIEW_COLS = 5 };

static CGColorRef
cg_color_from_gnm (GnmColor const *color) CF_RETURNS_RETAINED
{
    return color ? gnm_cocoa_cgcolor_from_go (color->go_color) : NULL;
}

@interface GnmAutoFormatTemplate ()
- (instancetype)initWithTemplate:(GnmFT *)ft NS_DESIGNATED_INITIALIZER;   /* takes the reference */
@property (nonatomic, readonly) GnmFT *engineTemplate;
@end

@implementation GnmAutoFormatTemplate {
    GnmFT *_ft;
}

- (instancetype)initWithTemplate:(GnmFT *)ft
{
    if (!(self = [super init]))
        return nil;
    _ft = ft;
    /* templates_load: the preview's dimension */
    range_init (&_ft->dimension, 0, 0, PREVIEW_COLS - 1, PREVIEW_ROWS - 1);
    _ft->invalidate_hash = TRUE;
    return self;
}

- (void)dealloc
{
    if (_ft)
        g_object_unref (_ft);
}

- (GnmFT *)engineTemplate { return _ft; }
- (NSString *)name { return GnmString (_ft->name); }
- (NSString *)author { return GnmString (_ft->author); }
- (NSString *)summary { return GnmString (_ft->description); }
- (NSString *)categoryName { return _ft->category ? GnmString (_ft->category->name) : @""; }

+ (NSInteger)previewRows { return PREVIEW_ROWS; }
+ (NSInteger)previewColumns { return PREVIEW_COLS; }

#define SETTING(getter, setter, field) \
    - (BOOL)getter { return _ft->field; } \
    - (void)setter:(BOOL)value { _ft->field = value ? TRUE : FALSE; _ft->invalidate_hash = TRUE; }

SETTING (appliesNumberFormat, setAppliesNumberFormat, number)
SETTING (appliesBorders, setAppliesBorders, border)
SETTING (appliesFont, setAppliesFont, font)
SETTING (appliesPatterns, setAppliesPatterns, patterns)
SETTING (appliesAlignment, setAppliesAlignment, alignment)
SETTING (bordersLeftEdge, setBordersLeftEdge, edges.left)
SETTING (bordersRightEdge, setBordersRightEdge, edges.right)
SETTING (bordersTopEdge, setBordersTopEdge, edges.top)
SETTING (bordersBottomEdge, setBordersBottomEdge, edges.bottom)

#undef SETTING

- (GnmStyle *)previewStyleAtRow:(NSInteger)row column:(NSInteger)column
{
    if (row < 0 || row >= PREVIEW_ROWS || column < 0 || column >= PREVIEW_COLS)
        return NULL;
    return gnm_ft_get_style (_ft, (int) row, (int) column);
}

- (GnmCellFormat *)previewFormatAtRow:(NSInteger)row column:(NSInteger)column
{
    NSAssert (NSThread.isMainThread, @"engine access off the main thread");
    GnmStyle *style = [self previewStyleAtRow:row column:column];
    return style ? gnm_cocoa_format_from_style (style) : [[GnmCellFormat alloc] init];
}

static GnmStyleElement
element_for_edge (GnmAutoFormatEdge edge)
{
    switch (edge) {
    case GnmAutoFormatEdgeTop: return MSTYLE_BORDER_TOP;
    case GnmAutoFormatEdgeBottom: return MSTYLE_BORDER_BOTTOM;
    case GnmAutoFormatEdgeLeft: return MSTYLE_BORDER_LEFT;
    default: return MSTYLE_BORDER_RIGHT;
    }
}

- (GnmBorder *)previewBorderObjectAtRow:(NSInteger)row column:(NSInteger)column edge:(GnmAutoFormatEdge)edge
{
    GnmStyle *style = [self previewStyleAtRow:row column:column];
    GnmStyleElement element = element_for_edge (edge);
    if (!style || !gnm_style_is_element_set (style, element))
        return NULL;
    return gnm_style_get_border (style, element);
}

- (NSInteger)previewBorderAtRow:(NSInteger)row column:(NSInteger)column edge:(GnmAutoFormatEdge)edge
{
    NSAssert (NSThread.isMainThread, @"engine access off the main thread");
    GnmBorder *border = [self previewBorderObjectAtRow:row column:column edge:edge];
    return border ? border->line_type : GNM_STYLE_BORDER_NONE;
}

- (CGColorRef)copyPreviewBorderColorAtRow:(NSInteger)row column:(NSInteger)column edge:(GnmAutoFormatEdge)edge
{
    NSAssert (NSThread.isMainThread, @"engine access off the main thread");
    GnmBorder *border = [self previewBorderObjectAtRow:row column:column edge:edge];
    return border && border->line_type != GNM_STYLE_BORDER_NONE ? cg_color_from_gnm (border->color) : NULL;
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"<%@ %@ (%@)>", self.class, self.name, self.categoryName];
}

@end

@interface GnmAutoFormatCategory ()
- (instancetype)initWithGroup:(GnmFTCategoryGroup *)group engine:(GnmEngine *)engine NS_DESIGNATED_INITIALIZER;
@end

@implementation GnmAutoFormatCategory {
    GnmFTCategoryGroup *_group;
    __weak GnmEngine *_engine;
    NSArray<GnmAutoFormatTemplate *> *_templates;
}

- (instancetype)initWithGroup:(GnmFTCategoryGroup *)group engine:(GnmEngine *)engine
{
    if (!(self = [super init]))
        return nil;
    _group = g_object_ref (group);
    _engine = engine;
    return self;
}

- (void)dealloc
{
    if (_group)
        g_object_unref (_group);
}

- (NSString *)name { return GnmString (_group->name); }
- (NSString *)summary { return GnmString (_group->description); }

- (NSArray<GnmAutoFormatTemplate *> *)templates
{
    NSAssert (NSThread.isMainThread, @"engine access off the main thread");
    if (_templates)
        return _templates;
    GnmEngine *engine = _engine;
    /* templates_load; the list's references pass to the wrappers */
    GSList *list = gnm_ft_category_group_get_templates_list (_group, engine.commandContext);
    NSMutableArray *result = [NSMutableArray array];
    for (GSList *l = list; l; l = l->next)
        [result addObject:[[GnmAutoFormatTemplate alloc] initWithTemplate:l->data]];
    g_slist_free (list);
    _templates = result;
    return result;
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"<%@ %@>", self.class, self.name];
}

@end

@implementation GnmEngine (AutoFormat)

- (NSArray<GnmAutoFormatCategory *> *)autoFormatCategories
{
    NSAssert (NSThread.isMainThread, @"engine access off the main thread");
    GList *groups = gnm_ft_category_group_list_get ();
    NSMutableArray *result = [NSMutableArray array];
    GnmAutoFormatCategory *general = nil;
    for (GList *l = groups; l; l = l->next) {
        GnmAutoFormatCategory *category = [[GnmAutoFormatCategory alloc] initWithGroup:l->data engine:self];
        if (!general && [category.name isEqualToString:@"General"])
            general = category;
        else
            [result addObject:category];
    }
    gnm_ft_category_group_list_free (groups);
    if (general)
        [result insertObject:general atIndex:0];
    return result;
}

@end

@implementation GnmSheet (AutoFormat)

- (BOOL)applyAutoFormat:(GnmAutoFormatTemplate *)template error:(NSError **)error
{
    NSAssert (NSThread.isMainThread, @"engine access off the main thread");
    GnmWorkbook *workbook = self.workbook;
    if (!workbook || !self.engineSheet)
        return NO;
    [workbook selectSheet:self];
    /* cb_ok_clicked: the command owns the copy */
    return [workbook _runCommand:^gboolean (WorkbookControl *wbc) {
        return cmd_selection_autoformat (wbc, gnm_ft_clone (template.engineTemplate));
    } description:@"Could not apply the autoformat template." error:error];
}

@end
