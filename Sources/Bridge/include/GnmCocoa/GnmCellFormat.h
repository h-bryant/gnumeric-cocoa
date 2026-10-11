// A set of cell style changes, or the common style of a selection.
//
// Every property is optional.  When applying, nil means "leave as is"; when
// read back from a selection, nil means "differs across the selection".
// Scalar properties are NSNumbers for that reason; the app wraps them.
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, GnmHorizontalAlignment) {
    GnmHorizontalAlignmentGeneral = 0x01,
    GnmHorizontalAlignmentLeft = 0x02,
    GnmHorizontalAlignmentRight = 0x04,
    GnmHorizontalAlignmentCenter = 0x08,
    GnmHorizontalAlignmentFill = 0x10,
    GnmHorizontalAlignmentJustify = 0x20,
    GnmHorizontalAlignmentCenterAcrossSelection = 0x40,
    GnmHorizontalAlignmentDistributed = 0x80,
} NS_SWIFT_NAME(HorizontalAlignment);

typedef NS_ENUM(NSInteger, GnmVerticalAlignment) {
    GnmVerticalAlignmentTop = 1,
    GnmVerticalAlignmentBottom = 2,
    GnmVerticalAlignmentCenter = 4,
    GnmVerticalAlignmentJustify = 8,
    GnmVerticalAlignmentDistributed = 16,
} NS_SWIFT_NAME(VerticalAlignment);

typedef NS_ENUM(NSInteger, GnmUnderlineStyle) {
    GnmUnderlineStyleNone = 0,
    GnmUnderlineStyleSingle = 1,
    GnmUnderlineStyleDouble = 2,
    GnmUnderlineStyleSingleLow = 3,
    GnmUnderlineStyleDoubleLow = 4,
} NS_SWIFT_NAME(UnderlineStyle);

/// The engine's border line types, in its order.
typedef NS_ENUM(NSInteger, GnmBorderLineStyle) {
    GnmBorderLineStyleNone = 0,
    GnmBorderLineStyleThin = 1,
    GnmBorderLineStyleMedium = 2,
    GnmBorderLineStyleDashed = 3,
    GnmBorderLineStyleDotted = 4,
    GnmBorderLineStyleThick = 5,
    GnmBorderLineStyleDouble = 6,
    GnmBorderLineStyleHair = 7,
    GnmBorderLineStyleMediumDash = 8,
    GnmBorderLineStyleDashDot = 9,
    GnmBorderLineStyleMediumDashDot = 10,
    GnmBorderLineStyleDashDotDot = 11,
    GnmBorderLineStyleMediumDashDotDot = 12,
    GnmBorderLineStyleSlantedDashDot = 13,
} NS_SWIFT_NAME(BorderLineStyle);

/// Border positions, in the engine's order.  The inside edges apply between
/// the cells of a multi-cell selection.
typedef NS_ENUM(NSInteger, GnmBorderEdge) {
    GnmBorderEdgeTop = 0,
    GnmBorderEdgeBottom = 1,
    GnmBorderEdgeLeft = 2,
    GnmBorderEdgeRight = 3,
    GnmBorderEdgeReverseDiagonal = 4,
    GnmBorderEdgeDiagonal = 5,
    GnmBorderEdgeInsideHorizontal = 6,
    GnmBorderEdgeInsideVertical = 7,
} NS_SWIFT_NAME(BorderEdge);

/// Number format families, as goffice classifies format strings.
typedef NS_ENUM(NSInteger, GnmNumberFormatFamily) {
    GnmNumberFormatFamilyUnknown = -1,
    GnmNumberFormatFamilyGeneral = 0,
    GnmNumberFormatFamilyNumber = 1,
    GnmNumberFormatFamilyCurrency = 2,
    GnmNumberFormatFamilyAccounting = 3,
    GnmNumberFormatFamilyDate = 4,
    GnmNumberFormatFamilyTime = 5,
    GnmNumberFormatFamilyPercentage = 6,
    GnmNumberFormatFamilyFraction = 7,
    GnmNumberFormatFamilyScientific = 8,
    GnmNumberFormatFamilyText = 9,
    GnmNumberFormatFamilySpecial = 10,
} NS_SWIFT_NAME(NumberFormatFamily);

NS_SWIFT_UI_ACTOR NS_SWIFT_NAME(CellFormat)
@interface GnmCellFormat : NSObject <NSCopying>

/// Number format in Excel syntax ("General", "0.00", "yyyy-mm-dd", "@").
@property (nonatomic, copy, nullable) NSString *numberFormat;
/// `GnmHorizontalAlignment` / `GnmVerticalAlignment` raw values.
@property (nonatomic, copy, nullable) NSNumber *horizontalAlignment;
@property (nonatomic, copy, nullable) NSNumber *verticalAlignment;
@property (nonatomic, copy, nullable) NSNumber *wrapsText;   // BOOL

@property (nonatomic, copy, nullable) NSString *fontName;    // family name as Pango knows it
@property (nonatomic, copy, nullable) NSNumber *fontSize;    // points
@property (nonatomic, copy, nullable) NSNumber *bold;        // BOOL
@property (nonatomic, copy, nullable) NSNumber *italic;      // BOOL
@property (nonatomic, copy, nullable) NSNumber *underline;   // GnmUnderlineStyle
@property (nonatomic, copy, nullable) NSNumber *strikethrough;   // BOOL
@property (nonatomic, nullable) CGColorRef textColor;

/// NO clears the fill (pattern 0); YES fills solid with `backgroundColor`.
@property (nonatomic, copy, nullable) NSNumber *fillsBackground;
@property (nonatomic, nullable) CGColorRef backgroundColor;

/// Border per edge; nil style means unset.  `GnmBorderLineStyleNone`
/// removes the border.  A nil color with a style means black.
- (nullable NSNumber *)borderStyleForEdge:(GnmBorderEdge)edge NS_SWIFT_NAME(borderStyle(edge:));
- (nullable CGColorRef)borderColorForEdge:(GnmBorderEdge)edge CF_RETURNS_NOT_RETAINED NS_SWIFT_NAME(borderColor(edge:));
- (void)setBorderStyle:(GnmBorderLineStyle)style color:(nullable CGColorRef)color forEdge:(GnmBorderEdge)edge NS_SWIFT_NAME(setBorder(_:color:edge:));
- (void)clearBorderForEdge:(GnmBorderEdge)edge NS_SWIFT_NAME(clearBorder(edge:));

/// Classify a format string the way goffice does.
+ (GnmNumberFormatFamily)familyOfNumberFormat:(NSString *)format NS_SWIFT_NAME(family(ofNumberFormat:));
/// A format string from a family and options, through goffice's generator
/// (decimals and the thousands separator apply to number, currency,
/// percentage, and scientific).
+ (NSString *)numberFormatForFamily:(GnmNumberFormatFamily)family decimals:(NSInteger)decimals
                   thousandsSeparator:(BOOL)thousandsSeparator NS_SWIFT_NAME(numberFormat(family:decimals:thousandsSeparator:));

@end

NS_ASSUME_NONNULL_END
