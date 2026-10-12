// The function catalog read from the engine's groups and each function's
// help entries, as the GTK selector reads them.
#import "GnmPrivate.h"

@implementation GnmFunctionInfo

- (instancetype)initWithFunction:(GnmFunc *)func
{
    if (!(self = [super init]))
        return nil;
    gnm_func_load_if_stub (func);   /* a plugin's function has no help until loaded */
    /* the engine keeps names in lower case; the UI shows them upper case */
    _name = GnmString (gnm_func_get_name (func, FALSE)).uppercaseString;
    GnmFuncGroup *group = gnm_func_get_function_group (func);
    _groupName = group && group->display_name ? GnmString (group->display_name->str) : @"";
    NSMutableArray *names = [NSMutableArray array], *argDescriptions = [NSMutableArray array], *examples = [NSMutableArray array];
    NSMutableArray *paragraphs = [NSMutableArray array];
    NSString *summary = @"";
    int n = 0;
    GnmFuncHelp const *help = gnm_func_get_help (func, &n);
    for (int i = 0; help && i < n && help[i].type != GNM_FUNC_HELP_END; i++) {
        const char *raw = help[i].text;
        if (!raw)
            continue;
        NSString *text = GnmString (gnm_func_gettext (func, raw));
        switch (help[i].type) {
        case GNM_FUNC_HELP_NAME: {
            NSRange colon = [text rangeOfString:@":"];
            summary = colon.location == NSNotFound ? text : [text substringFromIndex:colon.location + 1];
            break;
        }
        case GNM_FUNC_HELP_ARG: {
            NSRange colon = [text rangeOfString:@":"];
            [names addObject:colon.location == NSNotFound ? text : [text substringToIndex:colon.location]];
            [argDescriptions addObject:colon.location == NSNotFound ? @"" : [text substringFromIndex:colon.location + 1]];
            break;
        }
        case GNM_FUNC_HELP_DESCRIPTION:
        case GNM_FUNC_HELP_NOTE:
            [paragraphs addObject:text];
            break;
        case GNM_FUNC_HELP_EXAMPLES:
            [examples addObject:text];
            break;
        default:
            break;
        }
    }
    _summary = summary;
    _descriptionText = [paragraphs componentsJoinedByString:@"\n\n"];
    _argumentNames = names;
    _argumentDescriptions = argDescriptions;
    _examples = examples;
    int min = 0, max = 0;
    gnm_func_count_args (func, &min, &max);
    _minimumArguments = min;
    _maximumArguments = max >= G_MAXINT / 2 ? -1 : max;
    return self;
}

@end

@implementation GnmFunctionGroup

- (instancetype)initWithName:(NSString *)name functions:(NSArray<GnmFunctionInfo *> *)functions
{
    if (!(self = [super init]))
        return nil;
    _name = [name copy];
    _functions = [functions copy];
    return self;
}

@end

@implementation GnmEngine (Functions)

- (NSArray<GnmFunctionGroup *> *)functionGroups
{
    NSAssert (NSThread.isMainThread, @"engine access off the main thread");
    NSMutableArray *groups = [NSMutableArray array];
    for (int i = 0; ; i++) {
        GnmFuncGroup *group = gnm_func_group_get_nth (i);
        if (!group)
            break;
        NSMutableArray *functions = [NSMutableArray array];
        for (GSList *l = group->functions; l; l = l->next) {
            GnmFunc *func = l->data;
            if (gnm_func_get_flags (func) & GNM_FUNC_IS_PLACEHOLDER)
                continue;
            [functions addObject:[[GnmFunctionInfo alloc] initWithFunction:func]];
        }
        [functions sortUsingComparator:^NSComparisonResult (GnmFunctionInfo *a, GnmFunctionInfo *b) { return [a.name compare:b.name]; }];
        [groups addObject:[[GnmFunctionGroup alloc] initWithName:group->display_name ? GnmString (group->display_name->str) : @"" functions:functions]];
    }
    [groups sortUsingComparator:^NSComparisonResult (GnmFunctionGroup *a, GnmFunctionGroup *b) { return [a.name localizedCaseInsensitiveCompare:b.name]; }];
    return groups;
}

- (GnmFunctionInfo *)functionNamed:(NSString *)name
{
    NSAssert (NSThread.isMainThread, @"engine access off the main thread");
    if (name.length == 0)
        return nil;
    GnmFunc *func = gnm_func_lookup (name.UTF8String, NULL);
    if (!func || (gnm_func_get_flags (func) & GNM_FUNC_IS_PLACEHOLDER))
        return nil;
    return [[GnmFunctionInfo alloc] initWithFunction:func];
}

@end
