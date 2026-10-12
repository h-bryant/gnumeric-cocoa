// GnmSheetObject: a wrapper per engine SheetObject (GnmSheetObject.h).
#import "GnmPrivate.h"

static void
cb_object_changed (G_GNUC_UNUSED SheetObject *so, gpointer owner)
{
    [(__bridge GnmSheetObject *) owner _engineObjectDidChange];
}

@implementation GnmSheetObject {
    SheetObject *_so;
    Sheet *_sheet;
    __weak GnmSheet *_owner;
    gulong _boundsHandler;
    gulong _unrealizedHandler;
}

- (instancetype)initWithObject:(SheetObject *)so sheet:(GnmSheet *)sheet
{
    if (!(self = [super init]))
        return nil;
    _so = g_object_ref (so);
    _sheet = sheet.engineSheet;
    _owner = sheet;
    /* sheet_object_update_bounds emits the first after any anchor change
     * (moves, resizes, their undo); sheet_object_clear_sheet the second. */
    _boundsHandler = g_signal_connect (so, "bounds-changed", G_CALLBACK (cb_object_changed), (__bridge void *) self);
    _unrealizedHandler = g_signal_connect (so, "unrealized", G_CALLBACK (cb_object_changed), (__bridge void *) self);
    return self;
}

- (void)dealloc
{
    [self _detachFromEngine];
}

- (void)_detachFromEngine
{
    if (_so == NULL)
        return;
    g_signal_handler_disconnect (_so, _boundsHandler);
    g_signal_handler_disconnect (_so, _unrealizedHandler);
    g_object_unref (_so);
    _so = NULL;
}

- (SheetObject *)engineObject { return _so; }
- (GnmSheet *)_ownerSheet { return _owner; }

- (void)_engineObjectDidChange
{
    [_owner _objectsDidChange];
}

- (NSString *)typeName
{
    return _so ? GnmString (G_OBJECT_TYPE_NAME (_so)) : @"";
}

- (NSString *)name
{
    if (_so == NULL)
        return @"";
    char *name = NULL;
    g_object_get (_so, "name", &name, NULL);
    NSString *s = GnmString (name);
    g_free (name);
    return s;
}

- (BOOL)isAttached
{
    return _so != NULL && _so->sheet == _sheet;
}

- (CGRect)frame
{
    if (!self.isAttached)
        return CGRectZero;
    double c[4];
    gnm_cocoa_object_pixel_frame (_sheet, _so, c);
    return CGRectMake (c[0], c[1], c[2] - c[0], c[3] - c[1]);
}

- (BOOL)isVisible
{
    return self.isAttached && (_so->flags & SHEET_OBJECT_IS_VISIBLE) != 0;
}

- (BOOL)canResize { return _so != NULL && sheet_object_can_resize (_so); }
- (BOOL)canEdit { return _so != NULL && sheet_object_can_edit (_so); }

- (BOOL)isSelectable
{
    if (_so == NULL || GNM_IS_CELL_COMMENT (_so) || GNM_IS_FILTER_COMBO (_so))
        return NO;
    /* The validation combo (its header is not installed) and the other
     * widget-like objects have no renderer either. */
    return GNM_SO_CLASS (G_OBJECT_GET_CLASS (_so))->draw_cairo != NULL;
}

- (BOOL)isEqual:(id)object
{
    return [object isKindOfClass:GnmSheetObject.class] && ((GnmSheetObject *) object)->_so == _so;
}

- (NSUInteger)hash
{
    return (NSUInteger) _so;
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"<%@ %@ %@>", self.typeName, self.name, NSStringFromRect (self.frame)];
}

@end
