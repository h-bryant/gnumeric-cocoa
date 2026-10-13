// Form widgets (sheet-object-widget.c): the kinds the GTK Insert → Object
// menu creates, each one's configuration as its dialog edits it (label,
// linked cell, value, range, direction, content, output), applied as the
// engine's undoable cmd_so_set_* commands.
#import <Foundation/Foundation.h>
#import <GnmCocoa/GnmSheet.h>
#import <GnmCocoa/GnmSheetObject.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, GnmWidgetKind) {
    GnmWidgetKindNone = 0,
    GnmWidgetKindFrame,
    GnmWidgetKindButton,
    GnmWidgetKindCheckbox,
    GnmWidgetKindRadioButton,
    GnmWidgetKindScrollbar,
    GnmWidgetKindSpinButton,
    GnmWidgetKindSlider,
    GnmWidgetKindList,
    GnmWidgetKindCombo,
} NS_SWIFT_NAME(WidgetSettings.Kind);

/// What a widget's configuration dialog shows and sets; the parts that
/// apply depend on the kind.
NS_SWIFT_UI_ACTOR NS_SWIFT_NAME(WidgetSettings)
@interface GnmWidgetSettings : NSObject <NSCopying>
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@property (nonatomic, readonly) GnmWidgetKind kind;
/// Frame, button, checkbox, radio button.
@property (nonatomic, copy) NSString *label;
/// The linked cell, in the sheet's syntax; empty for none.  Button,
/// checkbox, radio button, scrollbar, spin button, slider, list, combo
/// (the output).
@property (nonatomic, copy) NSString *linkText;
/// A radio button's value, as typed in a cell.
@property (nonatomic, copy) NSString *valueText;
/// Scrollbar, spin button, slider.
@property (nonatomic) NSInteger minimum;
@property (nonatomic) NSInteger maximum;
@property (nonatomic) NSInteger increment;
@property (nonatomic) NSInteger pageIncrement;
@property (nonatomic) BOOL horizontal;
/// List, combo: the range of entries, and whether the output cell gets
/// the chosen entry's index rather than its content.
@property (nonatomic, copy) NSString *contentText;
@property (nonatomic) BOOL outputsIndex;
/// The GTK dialog's title for the kind ("Configure Scrollbar").
@property (nonatomic, readonly, copy) NSString *title;
@end

@interface GnmSheetObject (Widgets)
/// The kind for a "GnmSOW…" object, None for anything else.
@property (nonatomic, readonly) GnmWidgetKind widgetKind;
@end

@interface GnmSheet (Widgets)
/// The Insert → Object menu's names ("Button", "Scrollbar", …).
+ (NSString *)nameOfWidgetKind:(GnmWidgetKind)kind NS_SWIFT_NAME(nameOfWidgetKind(_:));
/// A widget's configuration as its dialog would show it; nil for a
/// non-widget.
- (nullable GnmWidgetSettings *)widgetSettingsOfSheetObject:(GnmSheetObject *)object NS_SWIFT_NAME(widgetSettings(of:));
/// The dialog's OK: the engine's command for the kind ("Configure
/// Scrollbar" and so on, undoable).  NO with the parser's message when
/// a link or content range does not parse.
- (BOOL)applyWidgetSettings:(GnmWidgetSettings *)settings toSheetObject:(GnmSheetObject *)object error:(NSError **)error
    NS_SWIFT_NAME(applyWidgetSettings(_:to:));
/// Insert → Object: a new widget of `kind` at `frame` (sheet pixels),
/// "Insert 1 Object", undoable.
- (nullable GnmSheetObject *)insertWidgetOfKind:(GnmWidgetKind)kind frame:(CGRect)frame error:(NSError **)error NS_SWIFT_NAME(insertWidget(ofKind:frame:));
@end

NS_ASSUME_NONNULL_END
