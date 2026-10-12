// The function catalog (`func.h`): the groups and functions the engine
// and its plugins register, with the help the GTK function selector
// shows (dialog-function-select.c).
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class GnmEngine;

NS_SWIFT_UI_ACTOR NS_SWIFT_NAME(FunctionInfo)
@interface GnmFunctionInfo : NSObject
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
/// "SUM".
@property (nonatomic, readonly, copy) NSString *name;
/// The group's name ("Mathematics").
@property (nonatomic, readonly, copy) NSString *groupName;
/// The one-sentence description from the help's NAME entry.
@property (nonatomic, readonly, copy) NSString *summary;
/// The longer description, paragraphs joined by blank lines.
@property (nonatomic, readonly, copy) NSString *descriptionText;
/// The arguments' names and their descriptions, in order.
@property (nonatomic, readonly, copy) NSArray<NSString *> *argumentNames;
@property (nonatomic, readonly, copy) NSArray<NSString *> *argumentDescriptions;
/// The help's examples.
@property (nonatomic, readonly, copy) NSArray<NSString *> *examples;
@property (nonatomic, readonly) NSInteger minimumArguments;
/// -1 for any number.
@property (nonatomic, readonly) NSInteger maximumArguments;
@end

NS_SWIFT_UI_ACTOR NS_SWIFT_NAME(FunctionGroup)
@interface GnmFunctionGroup : NSObject
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@property (nonatomic, readonly, copy) NSString *name;
/// By name.
@property (nonatomic, readonly, copy) NSArray<GnmFunctionInfo *> *functions;
@end

@interface GnmEngine (Functions)
/// The groups by name, each with its functions; placeholders left out.
@property (nonatomic, readonly) NSArray<GnmFunctionGroup *> *functionGroups;
/// A function by name (either case), or nil.
- (nullable GnmFunctionInfo *)functionNamed:(NSString *)name NS_SWIFT_NAME(function(named:));
@end

NS_ASSUME_NONNULL_END
