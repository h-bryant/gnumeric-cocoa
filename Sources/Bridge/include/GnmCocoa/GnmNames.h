// Defined names (`expr-name.h`): what the GTK Define Names dialog lists
// (the workbook's names and the current sheet's), and its commands
// (`cmd_define_name`, `cmd_remove_name`, `cmd_rescope_name`).
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class GnmSheet, GnmWorkbook;

/// One name: its scope (a sheet, or the workbook), and its expression
/// as the sheet writes it.
NS_SWIFT_UI_ACTOR NS_SWIFT_NAME(DefinedName)
@interface GnmDefinedName : NSObject
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@property (nonatomic, readonly, copy) NSString *name;
/// The sheet the name belongs to; nil for a workbook name.
@property (nonatomic, readonly, nullable) GnmSheet *scope;
/// The expression in the sheet's syntax, relative to the edit position
/// of the sheet the list was made for (as the GTK dialog shows it).
@property (nonatomic, readonly, copy) NSString *expressionText;
/// The engine's permanent names (print areas and the like) cannot be
/// changed or removed.
@property (nonatomic, readonly, getter=isEditable) BOOL editable;
/// Whether cells or other names refer to it (the dialog asks before
/// removing one that is).
@property (nonatomic, readonly, getter=isInUse) BOOL inUse;
@end

@interface GnmWorkbook (Names)
/// The workbook's names and `sheet`'s own, sorted by name, hidden and
/// placeholder names left out; expressions written relative to the
/// sheet's edit position.
- (NSArray<GnmDefinedName *> *)definedNamesForSheet:(GnmSheet *)sheet NS_SWIFT_NAME(definedNames(for:));
/// Define a name, or change the definition of an existing one with
/// this scope ("Define Name", undoable).  `text` is an expression in the
/// sheet's syntax, parsed relative to `sheet`'s edit position with
/// unknown names invalid; `scope` nil is the workbook.  NO with the
/// engine's message for a bad name or expression.
- (BOOL)defineName:(NSString *)name expression:(NSString *)text scope:(nullable GnmSheet *)scope
          inSheet:(GnmSheet *)sheet error:(NSError **)error NS_SWIFT_NAME(defineName(_:expression:scope:in:));
/// Remove a name ("Remove Name", undoable).
- (BOOL)removeName:(GnmDefinedName *)name error:(NSError **)error NS_SWIFT_NAME(remove(_:));
/// Move a name between the workbook and a sheet ("Change Scope of
/// Name", undoable); `scope` nil is the workbook.
- (BOOL)changeScopeOfName:(GnmDefinedName *)name toSheet:(nullable GnmSheet *)scope
                    error:(NSError **)error NS_SWIFT_NAME(changeScope(of:to:));
@end

NS_ASSUME_NONNULL_END
