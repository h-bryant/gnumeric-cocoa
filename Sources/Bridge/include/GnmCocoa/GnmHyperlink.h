// Hyperlinks (`hlink.h`): a cell style's link to a range of this workbook,
// a file, an email address, or a web address, as the GTK Insert →
// Hyperlink dialog (dialog-hyperlink.c) sets them and the grid follows
// them.
#import <Foundation/Foundation.h>
#import <GnmCocoa/GnmGeometry.h>
#import <GnmCocoa/GnmSheet.h>

NS_ASSUME_NONNULL_BEGIN

/// The dialog's link types, in its order.
typedef NS_ENUM(NSInteger, GnmHyperlinkKind) {
    /// A range or a name in this workbook (`GnmHLinkCurWorkbook`).
    GnmHyperlinkInternal = 0,
    /// A file (`GnmHLinkExternal`).
    GnmHyperlinkExternalFile,
    /// A mailto target (`GnmHLinkEMail`).
    GnmHyperlinkEmail,
    /// A web address (`GnmHLinkURL`).
    GnmHyperlinkWeb,
} NS_SWIFT_NAME(Hyperlink.Kind);

NS_SWIFT_UI_ACTOR NS_SWIFT_NAME(Hyperlink)
@interface GnmHyperlink : NSObject <NSCopying>
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
/// A link; the tip is shown over the cell (nil for the engine's default).
- (instancetype)initWithKind:(GnmHyperlinkKind)kind target:(NSString *)target tip:(nullable NSString *)tip NS_DESIGNATED_INITIALIZER;
@property (nonatomic, readonly) GnmHyperlinkKind kind;
/// "Sheet1!A1:B2" or a name, a file path, "mailto:…", or a URL.
@property (nonatomic, readonly, copy) NSString *target;
@property (nonatomic, readonly, copy, nullable) NSString *tip;
/// The mailto target the dialog builds from an address and a subject
/// (`dhl_get_target_email`); empty for an empty address.
+ (NSString *)emailTargetForAddress:(NSString *)address subject:(NSString *)subject NS_SWIFT_NAME(emailTarget(address:subject:));
@end

@interface GnmSheet (Hyperlinks)
/// A cell's link, or nil without one.
- (nullable GnmHyperlink *)hyperlinkAtColumn:(NSInteger)column row:(NSInteger)row NS_SWIFT_NAME(hyperlink(atColumn:row:));
/// Give the selection a link as the dialog's OK does: a new one with the
/// cells underlined in blue and empty cells showing the target ("Add
/// Hyperlink"), a change ("Edit Hyperlink"), or nil to take it away
/// ("Remove Hyperlink"); undoable.
- (BOOL)setHyperlink:(nullable GnmHyperlink *)link error:(NSError **)error NS_SWIFT_NAME(setHyperlink(_:));
/// Whether text names a range or a name of this workbook, as the dialog
/// checks an internal target.
- (BOOL)isValidInternalTarget:(NSString *)text NS_SWIFT_NAME(isValidInternalTarget(_:));
/// Follow a cell's internal link: select its range, bring it into view,
/// and focus its sheet (`gnm_hlink_cur_wb_activate`).  NO with "Link
/// target" when the target no longer resolves, or for the other kinds,
/// whose targets the application opens.
- (BOOL)followInternalHyperlinkAtColumn:(NSInteger)column row:(NSInteger)row error:(NSError **)error NS_SWIFT_NAME(followInternalHyperlink(atColumn:row:));
/// The ranges within a range whose cells carry links, as `GnmCellRange`
/// values (`sheet_style_collect_hlinks`).
- (NSArray<NSValue *> *)hyperlinkRangesInRange:(GnmCellRange)range NS_SWIFT_NAME(hyperlinkRanges(in:));
/// The GTK Edit → Clear → Hyperlinks (cb_edit_delete_links): the links
/// of every selected range taken away as one command named after the
/// count of linked regions ("Remove 2 Links"); the underline and color
/// stay, as there.
- (BOOL)removeHyperlinksOfSelectionWithError:(NSError **)error NS_SWIFT_NAME(removeHyperlinksOfSelection());
@end

NS_ASSUME_NONNULL_END
