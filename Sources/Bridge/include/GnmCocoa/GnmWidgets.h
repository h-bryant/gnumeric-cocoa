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

/// What the widgets do when used (sheet-object-widget.c's signal
/// handlers): each change goes to the linked cell as the undoable
/// `cmd_so_set_value`, and the widget follows the cell; a widget without
/// a link changes on its own, without undo.
@interface GnmSheet (WidgetActions)
/// A checkbox's or radio button's state, a button while pressed.
- (BOOL)widgetIsActive:(GnmSheetObject *)object NS_SWIFT_NAME(widgetIsActive(_:));
/// A scrollbar's, spin button's, or slider's value.
- (double)widgetValue:(GnmSheetObject *)object NS_SWIFT_NAME(widgetValue(_:));
/// A list's or combo's entries, as its content range shows them.
- (NSArray<NSString *> *)widgetEntries:(GnmSheetObject *)object NS_SWIFT_NAME(widgetEntries(_:));
/// A list's or combo's chosen entry, 1-based, 0 for none (from the
/// output cell).
- (NSInteger)widgetSelection:(GnmSheetObject *)object NS_SWIFT_NAME(widgetSelection(_:));
/// A click: a checkbox toggles ("Clicking checkbox"), a radio button
/// puts its value in the cell ("Clicking radiobutton"), a button sets
/// the cell TRUE and back ("Pressed Button", "Released Button").
- (BOOL)clickWidget:(GnmSheetObject *)object error:(NSError **)error NS_SWIFT_NAME(clickWidget(_:));
/// A new value for a scrollbar, spin button, or slider, kept within its
/// range and rounded ("Change widget").
- (BOOL)setWidgetValue:(double)value forObject:(GnmSheetObject *)object error:(NSError **)error NS_SWIFT_NAME(setWidgetValue(_:for:));
/// Choose an entry (1-based, 0 for none) in a list or combo with an
/// output cell ("Clicking in list"); the index or the content goes to
/// the cell as the widget's output setting says.
- (BOOL)chooseWidgetEntry:(NSInteger)index forObject:(GnmSheetObject *)object error:(NSError **)error NS_SWIFT_NAME(chooseWidgetEntry(_:for:));
@end

NS_ASSUME_NONNULL_END
