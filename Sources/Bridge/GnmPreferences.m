// The engine's preferences as properties over `gnm_conf_get_*` and
// `gnm_conf_set_*`.  The setters clamp to the schema's ranges themselves
// (gnumeric-conf.c), so the values round-trip within them.
#import "GnmPrivate.h"

@implementation GnmPreferences

- (instancetype)initPrivate
{
    return [super init];
}

static NSString *
string_from (const char *s)
{
    return s ? [NSString stringWithUTF8String:s] : @"";
}

#define GNM_PREF_INT(getter, setter, key) \
    - (NSInteger)getter { return gnm_conf_get_##key (); } \
    - (void)setter:(NSInteger)value { gnm_conf_set_##key ((int) value); }
#define GNM_PREF_BOOL(getter, setter, key) \
    - (BOOL)getter { return gnm_conf_get_##key (); } \
    - (void)setter:(BOOL)value { gnm_conf_set_##key (value); }
#define GNM_PREF_DOUBLE(getter, setter, key) \
    - (double)getter { return gnm_conf_get_##key (); } \
    - (void)setter:(double)value { gnm_conf_set_##key (value); }

GNM_PREF_INT (xmlCompressionLevel, setXmlCompressionLevel, core_xml_compression_level)

GNM_PREF_INT (newWorkbookSheetCount, setNewWorkbookSheetCount, core_workbook_n_sheet)
GNM_PREF_INT (newWorkbookRowCount, setNewWorkbookRowCount, core_workbook_n_rows)
GNM_PREF_INT (newWorkbookColumnCount, setNewWorkbookColumnCount, core_workbook_n_cols)
GNM_PREF_DOUBLE (defaultZoom, setDefaultZoom, core_gui_window_zoom)
GNM_PREF_INT (autosaveTime, setAutosaveTime, core_workbook_autosave_time)

- (NSString *)defaultFontName { return string_from (gnm_conf_get_core_defaultfont_name ()); }
- (void)setDefaultFontName:(NSString *)name { gnm_conf_set_core_defaultfont_name (name.UTF8String ?: ""); }
GNM_PREF_DOUBLE (defaultFontSize, setDefaultFontSize, core_defaultfont_size)
GNM_PREF_BOOL (defaultFontBold, setDefaultFontBold, core_defaultfont_bold)
GNM_PREF_BOOL (defaultFontItalic, setDefaultFontItalic, core_defaultfont_italic)

- (GnmEnterDirection)enterMovesDirection
{
    switch (gnm_conf_get_core_gui_editing_enter_moves_dir ()) {
    case GO_DIRECTION_UP: return GnmEnterDirectionUp;
    case GO_DIRECTION_LEFT: return GnmEnterDirectionLeft;
    case GO_DIRECTION_RIGHT: return GnmEnterDirectionRight;
    case GO_DIRECTION_DOWN:
    default: return GnmEnterDirectionDown;
    }
}

- (void)setEnterMovesDirection:(GnmEnterDirection)direction
{
    GODirection d;
    switch (direction) {
    case GnmEnterDirectionUp: d = GO_DIRECTION_UP; break;
    case GnmEnterDirectionLeft: d = GO_DIRECTION_LEFT; break;
    case GnmEnterDirectionRight: d = GO_DIRECTION_RIGHT; break;
    case GnmEnterDirectionDown:
    default: d = GO_DIRECTION_DOWN; break;
    }
    gnm_conf_set_core_gui_editing_enter_moves_dir (d);
}

GNM_PREF_BOOL (autocorrectsInitialCapitals, setAutocorrectsInitialCapitals, autocorrect_init_caps)
GNM_PREF_BOOL (autocorrectsFirstLetter, setAutocorrectsFirstLetter, autocorrect_first_letter)
GNM_PREF_BOOL (autocorrectsNamesOfDays, setAutocorrectsNamesOfDays, autocorrect_names_of_days)
GNM_PREF_BOOL (autocorrectsReplacements, setAutocorrectsReplacements, autocorrect_replace)

GNM_PREF_INT (undoMaximumSteps, setUndoMaximumSteps, undo_maxnum)
GNM_PREF_INT (undoMaximumSize, setUndoMaximumSize, undo_size)
GNM_PREF_BOOL (undoShowsSheetName, setUndoShowsSheetName, undo_show_sheet_name)
GNM_PREF_INT (undoMaximumDescriptorWidth, setUndoMaximumDescriptorWidth, undo_max_descriptor_width)

GNM_PREF_BOOL (sortRetainsFormats, setSortRetainsFormats, core_sort_default_retain_formats)
GNM_PREF_BOOL (sortIsCaseSensitive, setSortIsCaseSensitive, core_sort_default_by_case)
GNM_PREF_BOOL (sortAscending, setSortAscending, core_sort_default_ascending)
GNM_PREF_INT (sortInitialClauseCount, setSortInitialClauseCount, core_sort_dialog_max_initial_clauses)

@end
