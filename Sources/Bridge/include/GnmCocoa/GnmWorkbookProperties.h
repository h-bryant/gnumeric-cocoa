// Workbook-level settings and selections: Edit → Select → Array,
// Depends, Inputs (cmd-edit.c), Format → Workbook… (the view's
// attributes, dialog-workbook-attr.c), and File → Properties… (the
// document's metadata, dialog-doc-metadata.c).
#import <Foundation/Foundation.h>
#import <GnmCocoa/GnmSheet.h>
#import <GnmCocoa/GnmWorkbook.h>

NS_ASSUME_NONNULL_BEGIN

@interface GnmSheet (SelectionTools)
/// Select the array the cursor cell belongs to (`sv_select_cur_array`);
/// NO when the cell is not in one.
- (BOOL)selectCurrentArray;
/// Select the cells whose formulas depend on the cursor cell
/// (`sv_select_cur_depends`); NO when nothing does.
- (BOOL)selectDependents;
/// Select the cells the cursor cell's formula reads
/// (`sv_select_cur_inputs`); NO when it has no formula or inputs.
- (BOOL)selectInputs;
@end

/// The workbook view's attributes (Format → Workbook…), stored in the
/// file; set at once, not undoable, as the GTK dialog sets them.
@interface GnmWorkbook (ViewAttributes)
@property (nonatomic) BOOL showsHorizontalScrollbar;
@property (nonatomic) BOOL showsVerticalScrollbar;
@property (nonatomic) BOOL showsSheetTabs;
@property (nonatomic) BOOL autoCompletes;
@property (nonatomic) BOOL showsFunctionCellMarkers;
@property (nonatomic) BOOL showsExtensionMarkers;
@property (nonatomic, getter=isProtected) BOOL protected;
@end

/// The document's metadata (File → Properties…): the standard
/// string-valued properties by their gsf names ("dc:title").
/// The types the GTK Properties page offers for a custom property.
typedef NS_ENUM(NSInteger, GnmDocumentPropertyType) {
    GnmDocumentPropertyTypeString = 0,
    GnmDocumentPropertyTypeInteger,
    GnmDocumentPropertyTypeNumber,
    GnmDocumentPropertyTypeBoolean,
    GnmDocumentPropertyTypeTimestamp,
    /// A list of strings (keywords) or anything else, shown as text.
    GnmDocumentPropertyTypeOther,
} NS_SWIFT_NAME(DocumentProperty.Kind);

/// One metadata property as the GTK Properties page lists it: the
/// name, the value rendered as text, and the type.
NS_SWIFT_UI_ACTOR NS_SWIFT_NAME(DocumentProperty)
@interface GnmDocumentProperty : NSObject
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@property (nonatomic, readonly, copy) NSString *name;
@property (nonatomic, readonly, copy) NSString *value;
@property (nonatomic, readonly) GnmDocumentPropertyType type;
@end

@interface GnmWorkbook (DocumentProperties)
/// The names the dialog edits, in its order: title, subject,
/// description, keywords, creator, initial creator, manager, company,
/// category.
@property (class, nonatomic, readonly) NSArray<NSString *> *standardDocumentPropertyNames;
/// A label for a name ("Title").
+ (NSString *)labelForDocumentProperty:(NSString *)name NS_SWIFT_NAME(label(forDocumentProperty:));
/// Every string-valued property set on the document.
@property (nonatomic, readonly, copy) NSDictionary<NSString *, NSString *> *documentProperties;
/// Set the given properties (an empty value removes one) as one undoable
/// command ("Changing workbook properties"); nothing when none differ.
- (BOOL)setDocumentProperties:(NSDictionary<NSString *, NSString *> *)changes error:(NSError **)error NS_SWIFT_NAME(setDocumentProperties(_:));

/// Every property of the document's metadata, by name.
@property (nonatomic, readonly, copy) NSArray<GnmDocumentProperty *> *allDocumentProperties;
/// Set (or add) a property of a type from text, as the GTK page's Add
/// does (dialog_doc_metadata_set_gsf_prop_val: numbers through the
/// engine's matcher, booleans from TRUE/FALSE or a number, timestamps
/// as "yyyy-mm-dd hh:mm:ss", else now); one undoable command.  NO with
/// a message for an empty name.
- (BOOL)setDocumentProperty:(NSString *)name type:(GnmDocumentPropertyType)type value:(NSString *)value error:(NSError **)error
    NS_SWIFT_NAME(setDocumentProperty(_:type:value:));
/// Remove a property (the page's Remove); one undoable command.
- (BOOL)removeDocumentProperty:(NSString *)name error:(NSError **)error NS_SWIFT_NAME(removeDocumentProperty(_:));
@end

/// The GTK Properties dialog's Calculation page (dialog-doc-metadata.c):
/// automatic or manual recalculation and the iteration settings, set
/// on the workbook at once (not undoable there either) and saved with
/// the file.  The Statistics page's counts are here too.
@interface GnmWorkbook (Calculation)
/// `workbook_get_recalcmode` / `workbook_set_recalcmode`.
@property (nonatomic) BOOL recalculatesAutomatically;
/// `workbook_iteration_enabled`, `_max_number`, `_tolerance`.
@property (nonatomic) BOOL iterationEnabled;
@property (nonatomic) NSInteger iterationMaximum;
@property (nonatomic) double iterationTolerance;
/// The cells with content over every sheet (the GTK shows "Unknown").
@property (nonatomic, readonly) NSInteger cellCount;
@end

NS_ASSUME_NONNULL_END
