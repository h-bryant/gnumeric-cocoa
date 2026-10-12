// Sheet objects: charts, images, lines, shapes, and widgets anchored to a
// sheet.  The sheet hands out one wrapper per engine object for as long as
// the sheet lives; moving, resizing, deleting, and restacking go through
// the sheet (GnmSheet.h, "Sheet objects") as undoable commands.
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN

NS_SWIFT_UI_ACTOR NS_SWIFT_NAME(SheetObject)
@interface GnmSheetObject : NSObject
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

/// The engine's type name: "SheetObjectGraph", "SheetObjectImage",
/// "GnmSOLine", "GnmSOFilled", "GnmSOPath", the "GnmSOW..." widgets.
@property (nonatomic, readonly, copy) NSString *typeName;
/// The object's own name, often empty.
@property (nonatomic, readonly, copy) NSString *name;
/// Where it is drawn, in sheet pixels at the current zoom; empty while
/// the object is off the sheet (deleted, until an undo brings it back).
@property (nonatomic, readonly) CGRect frame;
@property (nonatomic, readonly, getter=isAttached) BOOL attached;
/// Hidden objects sit on hidden columns or rows.
@property (nonatomic, readonly, getter=isVisible) BOOL visible;
@property (nonatomic, readonly) BOOL canResize;
@property (nonatomic, readonly) BOOL canEdit;
/// What the user may click and drag: not cell comments, not the filter
/// and validation combos, not objects the engine cannot draw.
@property (nonatomic, readonly, getter=isSelectable) BOOL selectable;
@end

/// A format an object can be written as (`GnmSheet.imageFormatsForSheetObject:`).
NS_SWIFT_UI_ACTOR NS_SWIFT_NAME(ImageFormat)
@interface GnmImageFormat : NSObject
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
/// goffice's name: "png", "svg", "pdf", "jpeg", "ps", "eps".
@property (nonatomic, readonly, copy) NSString *name;
/// What to show ("PNG (raster)", "SVG (vector)").
@property (nonatomic, readonly, copy) NSString *summary;
@property (nonatomic, readonly, copy) NSString *fileExtension;
/// Whether a resolution (dots per inch) applies: raster output of a chart.
@property (nonatomic, readonly) BOOL usesResolution;
@end

/// `restackSheetObject:` directions (`cmd_object_raise`).
typedef NS_ENUM(NSInteger, GnmSheetObjectStacking) {
    GnmSheetObjectPullToFront = 0,
    GnmSheetObjectPullForward,
    GnmSheetObjectPushBackward,
    GnmSheetObjectPushToBack,
} NS_SWIFT_NAME(SheetObject.Stacking);

NS_ASSUME_NONNULL_END
