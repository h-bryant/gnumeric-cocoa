// GnmPlotType: goffice's plot type registry (GnmPlotType.h).
#import "GnmPrivate.h"

@implementation GnmPlotType {
    GogPlotType const *_type;
}

- (instancetype)initWithEngineType:(GogPlotType const *)type
{
    if (!(self = [super init]))
        return nil;
    _type = type;
    _family = GnmString (type->family ? type->family->name : NULL);
    _familyPriority = type->family ? type->family->priority : 0;
    _name = GnmString (type->name);
    _summary = GnmString (type->description);
    _engine = GnmString (type->engine);
    _row = type->row;
    _column = type->col;
    return self;
}

- (GogPlotType const *)engineType { return _type; }

- (NSString *)propertyNamed:(NSString *)name
{
    char const *value = _type->properties ? g_hash_table_lookup (_type->properties, name.UTF8String) : NULL;
    return value ? GnmString (value) : nil;
}

static void
cb_collect_family (G_GNUC_UNUSED gpointer key, gpointer value, gpointer accum)
{
    g_ptr_array_add (accum, value);
}

static void
cb_collect_type (G_GNUC_UNUSED gpointer key, gpointer value, gpointer accum)
{
    g_ptr_array_add (accum, value);
}

static gint
family_cmp (gconstpointer a, gconstpointer b)
{
    GogPlotFamily const *fa = *(GogPlotFamily const **) a, *fb = *(GogPlotFamily const **) b;
    if (fa->priority != fb->priority)
        return fb->priority - fa->priority;
    return g_strcmp0 (fa->name, fb->name);
}

static gint
type_cmp (gconstpointer a, gconstpointer b)
{
    GogPlotType const *ta = *(GogPlotType const **) a, *tb = *(GogPlotType const **) b;
    if (ta->row != tb->row)
        return ta->row - tb->row;
    return ta->col - tb->col;
}

+ (NSArray<GnmPlotType *> *)allTypes
{
    NSMutableArray *result = [NSMutableArray array];
    GHashTable const *families = gog_plot_families ();
    if (families == NULL)
        return result;
    GPtrArray *sorted_families = g_ptr_array_new ();
    g_hash_table_foreach ((GHashTable *) families, cb_collect_family, sorted_families);
    g_ptr_array_sort (sorted_families, family_cmp);
    for (unsigned i = 0; i < sorted_families->len; i++) {
        GogPlotFamily const *family = g_ptr_array_index (sorted_families, i);
        if (family->types == NULL)
            continue;
        GPtrArray *types = g_ptr_array_new ();
        g_hash_table_foreach (family->types, cb_collect_type, types);
        g_ptr_array_sort (types, type_cmp);
        for (unsigned j = 0; j < types->len; j++)
            [result addObject:[[GnmPlotType alloc] initWithEngineType:g_ptr_array_index (types, j)]];
        g_ptr_array_free (types, TRUE);
    }
    g_ptr_array_free (sorted_families, TRUE);
    return result;
}

- (NSData *)sampleImageData
{
    /* "res:go:plot_barcol/chart_line_1_1.png": a goffice resource */
    char const *file = _type->sample_image_file;
    if (file == NULL)
        return nil;
    if (g_str_has_prefix (file, "res:")) {
        size_t len = 0;
        gconstpointer bytes = go_rsm_lookup (file + 4, &len);
        return bytes && len ? [NSData dataWithBytes:bytes length:len] : nil;
    }
    return [NSData dataWithContentsOfFile:GnmString (file)];
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"<PlotType %@ / %@ (%@)>", _family, _name, _engine];
}

@end
