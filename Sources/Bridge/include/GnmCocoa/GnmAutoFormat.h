// Format → AutoFormat (dialog-autoformat.c, format-template.h): the
// template categories shipped with the engine, each template's name,
// author, and description, a 5 × 5 preview of its styles, the parts of
// it to apply, and the undoable application to the selection.
#import <Foundation/Foundation.h>
#import <GnmCocoa/GnmCellFormat.h>
#import <GnmCocoa/GnmEngine.h>
#import <GnmCocoa/GnmSheet.h>

NS_ASSUME_NONNULL_BEGIN

/// A side of a preview cell.
typedef NS_ENUM(NSInteger, GnmAutoFormatEdge) {
    GnmAutoFormatEdgeTop = 0,
    GnmAutoFormatEdgeBottom,
    GnmAutoFormatEdgeLeft,
    GnmAutoFormatEdgeRight,
} NS_SWIFT_NAME(AutoFormatTemplate.Edge);

NS_SWIFT_UI_ACTOR NS_SWIFT_NAME(AutoFormatTemplate)
@interface GnmAutoFormatTemplate : NSObject
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@property (nonatomic, readonly, copy) NSString *name;
@property (nonatomic, readonly, copy) NSString *author;
@property (nonatomic, readonly, copy) NSString *summary;
@property (nonatomic, readonly, copy) NSString *categoryName;
// The dialog's Settings menu: which parts of the template apply (all on
// to start) and which outer edges get borders.
@property (nonatomic) BOOL appliesNumberFormat;
@property (nonatomic) BOOL appliesBorders;
@property (nonatomic) BOOL appliesFont;
@property (nonatomic) BOOL appliesPatterns;
@property (nonatomic) BOOL appliesAlignment;
@property (nonatomic) BOOL bordersLeftEdge;
@property (nonatomic) BOOL bordersRightEdge;
@property (nonatomic) BOOL bordersTopEdge;
@property (nonatomic) BOOL bordersBottomEdge;
/// The preview's size (5 rows by 5 columns, the GTK's demo table).
@property (class, nonatomic, readonly) NSInteger previewRows;
@property (class, nonatomic, readonly) NSInteger previewColumns;
/// The style a preview cell gets (`gnm_ft_get_style`), as a format.
- (GnmCellFormat *)previewFormatAtRow:(NSInteger)row column:(NSInteger)column NS_SWIFT_NAME(previewFormat(atRow:column:));
/// A preview cell's border on one side: `GnmStyleBorderType` (0 none, 1
/// thin, 2 medium, 5 thick, 6 double, …).
- (NSInteger)previewBorderAtRow:(NSInteger)row column:(NSInteger)column edge:(GnmAutoFormatEdge)edge NS_SWIFT_NAME(previewBorder(atRow:column:edge:));
- (nullable CGColorRef)copyPreviewBorderColorAtRow:(NSInteger)row column:(NSInteger)column edge:(GnmAutoFormatEdge)edge CF_RETURNS_RETAINED
    NS_SWIFT_NAME(previewBorderColor(atRow:column:edge:));
@end

NS_SWIFT_UI_ACTOR NS_SWIFT_NAME(AutoFormatCategory)
@interface GnmAutoFormatCategory : NSObject
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
/// "General", "Financial", …
@property (nonatomic, readonly, copy) NSString *name;
@property (nonatomic, readonly, copy) NSString *summary;
/// The category's templates by name, read from their files on the first
/// call (a template that fails to read is reported through the engine's
/// messages and left out).
@property (nonatomic, readonly, copy) NSArray<GnmAutoFormatTemplate *> *templates;
@end

@interface GnmEngine (AutoFormat)
/// The categories found in the engine's and the user's template
/// directories (`gnm_ft_category_group_list_get`), "General" first as the
/// GTK dialog selects it.
@property (nonatomic, readonly, copy) NSArray<GnmAutoFormatCategory *> *autoFormatCategories;
@end

@interface GnmSheet (AutoFormat)
/// Apply a template to the selection ("Autoformat", undoable;
/// `cmd_selection_autoformat` on a copy with the template's settings).
/// NO with the engine's message when a selected range is too small for
/// the template.
- (BOOL)applyAutoFormat:(GnmAutoFormatTemplate *)template error:(NSError **)error NS_SWIFT_NAME(applyAutoFormat(_:));
@end

NS_ASSUME_NONNULL_END
