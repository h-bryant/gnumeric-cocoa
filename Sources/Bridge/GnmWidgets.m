// Widget configuration as the dialogs in sheet-object-widget.c and
// dialog-so-list.c read and apply it.
#import "GnmPrivate.h"
#include <sheet-object-widget.h>
#include <commands.h>
#include <expr.h>
#include <value.h>
#include <parse-util.h>
#include <workbook.h>
#include <gnm-format.h>

@interface GnmWidgetSettings ()
- (instancetype)initWithKind:(GnmWidgetKind)kind NS_DESIGNATED_INITIALIZER;
@end

@implementation GnmWidgetSettings

- (instancetype)initWithKind:(GnmWidgetKind)kind
{
    if (!(self = [super init]))
        return nil;
    _kind = kind;
    _label = @"";
    _linkText = @"";
    _valueText = @"";
    _contentText = @"";
    _maximum = 100;
    _increment = 1;
    _pageIncrement = 10;
    return self;
}

- (id)copyWithZone:(NSZone *)zone
{
    GnmWidgetSettings *copy = [[GnmWidgetSettings allocWithZone:zone] initWithKind:_kind];
    copy.label = _label;
    copy.linkText = _linkText;
    copy.valueText = _valueText;
    copy.minimum = _minimum;
    copy.maximum = _maximum;
    copy.increment = _increment;
    copy.pageIncrement = _pageIncrement;
    copy.horizontal = _horizontal;
    copy.contentText = _contentText;
    copy.outputsIndex = _outputsIndex;
    return copy;
}

- (NSString *)title
{
    switch (_kind) {
    case GnmWidgetKindFrame: return @"Frame Properties";
    case GnmWidgetKindButton: return @"Button Properties";
    case GnmWidgetKindCheckbox: return @"Checkbox Properties";
    case GnmWidgetKindRadioButton: return @"Radio Button Properties";
    case GnmWidgetKindScrollbar: return @"Scrollbar Properties";
    case GnmWidgetKindSpinButton: return @"Spinbutton Properties";
    case GnmWidgetKindSlider: return @"Slider Properties";
    case GnmWidgetKindList: return @"List Properties";
    case GnmWidgetKindCombo: return @"Combo Box Properties";
    default: return @"Properties";
    }
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"<%@ kind %ld label '%@' link '%@' value '%@' %ld..%ld by %ld/%ld %@ content '%@' index %d>", self.class,
            (long) _kind, _label, _linkText, _valueText, (long) _minimum, (long) _maximum, (long) _increment, (long) _pageIncrement,
            _horizontal ? @"horizontal" : @"vertical", _contentText, _outputsIndex];
}

@end

static GnmWidgetKind
widget_kind (SheetObject *so)
{
    if (!so)
        return GnmWidgetKindNone;
    if (GNM_IS_SOW_FRAME (so)) return GnmWidgetKindFrame;
    if (GNM_IS_SOW_BUTTON (so)) return GnmWidgetKindButton;
    if (GNM_IS_SOW_CHECKBOX (so)) return GnmWidgetKindCheckbox;
    if (GNM_IS_SOW_RADIO_BUTTON (so)) return GnmWidgetKindRadioButton;
    if (GNM_IS_SOW_SCROLLBAR (so)) return GnmWidgetKindScrollbar;
    if (GNM_IS_SOW_SPINBUTTON (so)) return GnmWidgetKindSpinButton;
    if (GNM_IS_SOW_SLIDER (so)) return GnmWidgetKindSlider;
    if (GNM_IS_SOW_LIST (so)) return GnmWidgetKindList;
    if (GNM_IS_SOW_COMBO (so)) return GnmWidgetKindCombo;
    return GnmWidgetKindNone;
}

@implementation GnmSheetObject (Widgets)

- (GnmWidgetKind)widgetKind
{
    NSAssert (NSThread.isMainThread, @"engine access off the main thread");
    return widget_kind (self.engineObject);
}

@end

/* The text of a link the widget getters hand over with a reference
 * (sheet_widget_*_get_link ref the expression); released here. */
static NSString *
link_text (GnmExprTop const *texpr, Sheet *sheet)
{
    if (!texpr)
        return @"";
    GnmParsePos pp;
    parse_pos_init_sheet (&pp, sheet);
    char *text = gnm_expr_top_as_string (texpr, &pp, sheet_get_conventions (sheet));
    NSString *result = GnmString (text);
    g_free (text);
    gnm_expr_top_unref (texpr);
    return result;
}

static NSString *
object_text (SheetObject *so)
{
    char *text = NULL;
    g_object_get (G_OBJECT (so), "text", &text, NULL);
    NSString *result = GnmString (text);
    g_free (text);
    return result;
}

/* A link as the GTK entries parse it (gnm_expr_entry_parse with
 * GNM_EXPR_PARSE_DEFAULT); NULL for empty text, and NO when it fails. */
static BOOL
parse_link (NSString *text, Sheet *sheet, GnmExprTop const **out, GnmEngine *engine, NSError **error)
{
    *out = NULL;
    NSString *trimmed = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (trimmed.length == 0)
        return YES;
    GnmParsePos pp;
    parse_pos_init_sheet (&pp, sheet);
    GnmParseError perr;
    GnmExprTop const *texpr = gnm_expr_parse_str (trimmed.UTF8String, &pp, GNM_EXPR_PARSE_DEFAULT, NULL, parse_error_init (&perr));
    if (!texpr) {
        NSString *message = perr.err ? GnmString (perr.err->message) : @"The reference could not be read.";
        parse_error_free (&perr);
        if (error)
            *error = [engine _errorWithCode:GnmErrorCommandFailed
                                description:[NSString stringWithFormat:@"“%@” is not a valid reference: %@", trimmed, message] collected:@[]];
        return NO;
    }
    parse_error_free (&perr);
    *out = texpr;
    return YES;
}

@implementation GnmSheet (Widgets)

+ (NSString *)nameOfWidgetKind:(GnmWidgetKind)kind
{
    switch (kind) {
    case GnmWidgetKindFrame: return @"Frame";
    case GnmWidgetKindButton: return @"Button";
    case GnmWidgetKindCheckbox: return @"Checkbox";
    case GnmWidgetKindRadioButton: return @"Radio Button";
    case GnmWidgetKindScrollbar: return @"Scrollbar";
    case GnmWidgetKindSpinButton: return @"Spin Button";
    case GnmWidgetKindSlider: return @"Slider";
    case GnmWidgetKindList: return @"List";
    case GnmWidgetKindCombo: return @"Combo Box";
    default: return @"";
    }
}

- (GnmWidgetSettings *)widgetSettingsOfSheetObject:(GnmSheetObject *)object
{
    NSAssert (NSThread.isMainThread, @"engine access off the main thread");
    SheetObject *so = object.engineObject;
    Sheet *sheet = self.engineSheet;
    GnmWidgetKind kind = widget_kind (so);
    if (kind == GnmWidgetKindNone || !sheet)
        return nil;
    GnmWidgetSettings *settings = [[GnmWidgetSettings alloc] initWithKind:kind];
    switch (kind) {
    case GnmWidgetKindFrame:
        settings.label = object_text (so);
        break;
    case GnmWidgetKindButton:
        settings.label = object_text (so);
        settings.linkText = link_text (sheet_widget_button_get_link (so), sheet);
        break;
    case GnmWidgetKindCheckbox:
        settings.label = object_text (so);
        settings.linkText = link_text (sheet_widget_checkbox_get_link (so), sheet);
        break;
    case GnmWidgetKindRadioButton: {
        settings.label = object_text (so);
        settings.linkText = link_text (sheet_widget_radio_button_get_link (so), sheet);
        GnmValue const *value = sheet_widget_radio_button_get_value (so);
        if (value) {
            char *text = value_get_as_string (value);
            settings.valueText = GnmString (text);
            g_free (text);
        }
        break;
    }
    case GnmWidgetKindScrollbar:
    case GnmWidgetKindSpinButton:
    case GnmWidgetKindSlider: {
        settings.linkText = link_text (sheet_widget_adjustment_get_link (so), sheet);
        GtkAdjustment *adjustment = sheet_widget_adjustment_get_adjustment (so);
        if (adjustment) {
            settings.minimum = (NSInteger) gtk_adjustment_get_lower (adjustment);
            settings.maximum = (NSInteger) gtk_adjustment_get_upper (adjustment);
            settings.increment = (NSInteger) gtk_adjustment_get_step_increment (adjustment);
            settings.pageIncrement = (NSInteger) gtk_adjustment_get_page_increment (adjustment);
        }
        settings.horizontal = sheet_widget_adjustment_get_horizontal (so);
        break;
    }
    case GnmWidgetKindList:
    case GnmWidgetKindCombo:
        settings.linkText = link_text (sheet_widget_list_base_get_result_link (so), sheet);
        settings.contentText = link_text (sheet_widget_list_base_get_content_link (so), sheet);
        settings.outputsIndex = sheet_widget_list_base_result_type_is_index (so);
        break;
    default:
        break;
    }
    return settings;
}

- (BOOL)applyWidgetSettings:(GnmWidgetSettings *)settings toSheetObject:(GnmSheetObject *)object error:(NSError **)error
{
    NSAssert (NSThread.isMainThread, @"engine access off the main thread");
    SheetObject *so = object.engineObject;
    Sheet *sheet = self.engineSheet;
    GnmWorkbook *workbook = self.workbook;
    GnmWidgetKind kind = widget_kind (so);
    if (kind == GnmWidgetKindNone || kind != settings.kind || !sheet || !workbook)
        return NO;
    GnmEngine *engine = workbook.engine;
    GnmExprTop const *link = NULL;
    if (kind != GnmWidgetKindFrame && !parse_link (settings.linkText, sheet, &link, engine, error))
        return NO;
    const char *label = settings.label.UTF8String;
    switch (kind) {
    case GnmWidgetKindFrame:
        return [workbook _runCommand:^gboolean (WorkbookControl *wbc) {
            return cmd_so_set_frame_label (wbc, so, g_strdup (object_text (so).UTF8String), g_strdup (label));
        } description:@"Could not configure the frame." error:error];
    case GnmWidgetKindButton:
        return [workbook _runCommand:^gboolean (WorkbookControl *wbc) {
            return cmd_so_set_button (wbc, so, link, g_strdup (object_text (so).UTF8String), g_strdup (label));
        } description:@"Could not configure the button." error:error];
    case GnmWidgetKindCheckbox:
        return [workbook _runCommand:^gboolean (WorkbookControl *wbc) {
            return cmd_so_set_checkbox (wbc, so, link, g_strdup (object_text (so).UTF8String), g_strdup (label));
        } description:@"Could not configure the checkbox." error:error];
    case GnmWidgetKindRadioButton: {
        /* so_parse_value */
        GnmValue *value = format_match (settings.valueText.UTF8String, NULL, sheet_date_conv (sheet));
        if (!value)
            value = value_new_string (settings.valueText.UTF8String);
        GnmValue const *old = sheet_widget_radio_button_get_value (so);
        GnmValue *oldValue = old ? value_dup (old) : value_new_empty ();
        return [workbook _runCommand:^gboolean (WorkbookControl *wbc) {
            return cmd_so_set_radio_button (wbc, so, link, g_strdup (object_text (so).UTF8String), g_strdup (label), oldValue, value);
        } description:@"Could not configure the radio button." error:error];
    }
    case GnmWidgetKindScrollbar:
    case GnmWidgetKindSpinButton:
    case GnmWidgetKindSlider: {
        const char *undoLabel = kind == GnmWidgetKindScrollbar ? "Configure Scrollbar"
            : kind == GnmWidgetKindSpinButton ? "Configure Spinbutton" : "Configure Slider";
        gboolean horizontal = settings.horizontal ? TRUE : FALSE;
        int lower = (int) settings.minimum, upper = (int) settings.maximum, step = (int) settings.increment, page = (int) settings.pageIncrement;
        return [workbook _runCommand:^gboolean (WorkbookControl *wbc) {
            return cmd_so_set_adjustment (wbc, so, link, horizontal, lower, upper, step, page, undoLabel);
        } description:@"Could not configure the adjustment." error:error];
    }
    case GnmWidgetKindList:
    case GnmWidgetKindCombo: {
        GnmExprTop const *content = NULL;
        if (!parse_link (settings.contentText, sheet, &content, engine, error)) {
            if (link)
                gnm_expr_top_unref (link);
            return NO;
        }
        gboolean asIndex = settings.outputsIndex ? TRUE : FALSE;
        return [workbook _runCommand:^gboolean (WorkbookControl *wbc) {
            return cmd_so_set_links (wbc, so, link, content, asIndex);
        } description:@"Could not configure the list." error:error];
    }
    default:
        if (link)
            gnm_expr_top_unref (link);
        return NO;
    }
}

- (GnmSheetObject *)insertWidgetOfKind:(GnmWidgetKind)kind frame:(CGRect)frame error:(NSError **)error
{
    NSAssert (NSThread.isMainThread, @"engine access off the main thread");
    GType type;
    switch (kind) {
    case GnmWidgetKindFrame: type = GNM_SOW_FRAME_TYPE; break;
    case GnmWidgetKindButton: type = GNM_SOW_BUTTON_TYPE; break;
    case GnmWidgetKindCheckbox: type = GNM_SOW_CHECKBOX_TYPE; break;
    case GnmWidgetKindRadioButton: type = GNM_SOW_RADIO_BUTTON_TYPE; break;
    case GnmWidgetKindScrollbar: type = GNM_SOW_SCROLLBAR_TYPE; break;
    case GnmWidgetKindSpinButton: type = GNM_SOW_SPIN_BUTTON_TYPE; break;
    case GnmWidgetKindSlider: type = GNM_SOW_SLIDER_TYPE; break;
    case GnmWidgetKindList: type = GNM_SOW_LIST_TYPE; break;
    case GnmWidgetKindCombo: type = GNM_SOW_COMBO_TYPE; break;
    default: return nil;
    }
    /* create_object in wbc-gtk-actions.c, placed as a creation drag would */
    SheetObject *so = g_object_new (type, NULL);
    GnmSheetObject *wrapper = [self _insertCreatedObject:so frame:frame anchorMode:GNM_SO_ANCHOR_TWO_CELLS
                                             description:@"Could not insert the widget." error:error];
    g_object_unref (so);   /* the sheet and the command hold theirs */
    return wrapper;
}

@end
