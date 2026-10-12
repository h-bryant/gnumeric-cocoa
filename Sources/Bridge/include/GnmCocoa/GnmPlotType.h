// The plot types goffice registers (the chart guru's catalogue): families
// such as Column, Line, Pie, and the types in each, with the sample
// image the GTK guru shows.  Charts are inserted through the sheet
// (GnmSheet.h, "Charts").
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

NS_SWIFT_UI_ACTOR NS_SWIFT_NAME(PlotType)
@interface GnmPlotType : NSObject
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
/// Every registered type, families by descending priority then name,
/// types by their row and column in the guru's grid.
@property (class, nonatomic, readonly) NSArray<GnmPlotType *> *allTypes;

@property (nonatomic, readonly, copy) NSString *family;
/// The family's rank in the guru (higher first).
@property (nonatomic, readonly) NSInteger familyPriority;
@property (nonatomic, readonly, copy) NSString *name;
/// What the type is for, in a sentence.
@property (nonatomic, readonly, copy) NSString *summary;
/// The goffice plot class ("GogBarColPlot", "GogXYPlot", ...).
@property (nonatomic, readonly, copy) NSString *engine;
@property (nonatomic, readonly) NSInteger row;
@property (nonatomic, readonly) NSInteger column;
/// PNG bytes of the sample image, from goffice's resources; nil when
/// the type has none.
@property (nonatomic, readonly, nullable, copy) NSData *sampleImageData;
@end

/// How `insertChart...` reads the selection into series (the GTK guru's
/// "Series as" choice).
typedef NS_ENUM(NSInteger, GnmChartSeriesLayout) {
    /// Columns when the selection is taller than wide, else rows.
    GnmChartSeriesLayoutAuto = 0,
    GnmChartSeriesLayoutColumns = 1,
    GnmChartSeriesLayoutRows = 2,
} NS_SWIFT_NAME(ChartSeriesLayout);

NS_ASSUME_NONNULL_END
