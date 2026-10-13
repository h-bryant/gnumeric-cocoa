// Scenarios (tools/scenarios.h, dialog-scenarios.c): named sets of
// values for changing cells, added as an undoable command, shown and
// managed through a session that commits or restores on its way out,
// and summarized on a new sheet; and the risk simulation tool
// (tools/simulation.h, dialog-simulation.c).
#import <Foundation/Foundation.h>
#import <GnmCocoa/GnmAnalysis.h>
#import <GnmCocoa/GnmSheet.h>

NS_ASSUME_NONNULL_BEGIN

NS_SWIFT_UI_ACTOR NS_SWIFT_NAME(Scenario)
@interface GnmSheetScenario : NSObject
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@property (nonatomic, readonly, copy) NSString *name;
@property (nonatomic, readonly, copy) NSString *comment;
/// The changing cells as the GTK dialog shows them ("A1:A3,C2").
@property (nonatomic, readonly, copy) NSString *changingCellsText;
/// "A1 = 5" for each saved cell value.
@property (nonatomic, readonly, copy) NSArray<NSString *> *valueDescriptions;
@end

/// The GTK scenario manager's session: Show applies a scenario (the
/// previous one restored first), Delete marks one, Summary writes a
/// report sheet; `finish` makes the shown scenario the undoable "Scenario
/// Show" command and removes the marked ones, `cancel` restores the
/// values, deletes the report sheets, and unmarks.
NS_SWIFT_UI_ACTOR NS_SWIFT_NAME(ScenarioManager)
@interface GnmScenarioManager : NSObject
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@property (nonatomic, readonly) GnmSheet *sheet;
/// The sheet's scenarios not marked for deletion.
@property (nonatomic, readonly, copy) NSArray<GnmSheetScenario *> *scenarios;
@property (nonatomic, readonly, nullable) GnmSheetScenario *shownScenario;
- (BOOL)showScenario:(GnmSheetScenario *)scenario error:(NSError **)error NS_SWIFT_NAME(show(_:));
- (void)deleteScenario:(GnmSheetScenario *)scenario NS_SWIFT_NAME(delete(_:));
/// "Scenario Summary" on a new sheet: each changing cell's current value
/// and its value in every scenario, then each result cell's value under
/// every scenario (`results`: a list of cells or ranges, may be empty).
/// Returns the new sheet; nil with the message when `results` does not
/// parse.
- (nullable GnmSheet *)createSummaryWithResultCells:(NSString *)results error:(NSError **)error NS_SWIFT_NAME(createSummary(resultCells:));
- (BOOL)finishWithError:(NSError **)error NS_SWIFT_NAME(finish());
- (void)cancel;
@end

@interface GnmSheet (Scenarios)
@property (nonatomic, readonly, copy) NSArray<GnmSheetScenario *> *scenarios;
/// The Add Scenario dialog's OK: the changing cells must be on this
/// sheet, the name unused and not blank ("Add scenario", undoable).
- (BOOL)addScenarioNamed:(NSString *)name comment:(NSString *)comment changingCells:(NSString *)cells error:(NSError **)error
    NS_SWIFT_NAME(addScenario(named:comment:changingCells:));
- (GnmScenarioManager *)scenarioManager;
@end

/// One variable's statistics over a simulation round (`simstats_t`).
NS_SWIFT_UI_ACTOR NS_SWIFT_NAME(SimulationStatistics)
@interface GnmSimulationStatistics : NSObject
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
/// The cell's name, inputs prefixed "(Input) ".
@property (nonatomic, readonly, copy) NSString *variableName;
@property (nonatomic, readonly) double minimum;
@property (nonatomic, readonly) double mean;
@property (nonatomic, readonly) double maximum;
@property (nonatomic, readonly) double median;
@property (nonatomic, readonly) double mode;
@property (nonatomic, readonly) double standardDeviation;
@property (nonatomic, readonly) double variance;
@property (nonatomic, readonly) double skewness;
@property (nonatomic, readonly) double kurtosis;
@property (nonatomic, readonly) double range;
@property (nonatomic, readonly) double confidence;
@property (nonatomic, readonly) double lowerLimit;
@property (nonatomic, readonly) double upperLimit;
@end

NS_SWIFT_UI_ACTOR NS_SWIFT_NAME(SimulationResult)
@interface GnmSimulationResult : NSObject
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
/// The rounds run, 1-based as the dialog counts them.
@property (nonatomic, readonly) NSInteger firstRound;
@property (nonatomic, readonly) NSInteger lastRound;
@property (nonatomic, readonly) NSInteger iterations;
@property (nonatomic, readonly) NSInteger inputCount;
@property (nonatomic, readonly) NSInteger outputCount;
@property (nonatomic, readonly) NSTimeInterval runtime;
/// Outputs first, then inputs, as the report lists them.
- (NSArray<GnmSimulationStatistics *> *)statisticsForRound:(NSInteger)round NS_SWIFT_NAME(statistics(forRound:));
/// The GTK results pane for one round: Variable, Min, Average, Max.
- (NSString *)textForRound:(NSInteger)round NS_SWIFT_NAME(text(forRound:));
/// The GTK log: Simulations, Iterations, # Input variables, # Output
/// variables, Runtime, Run on.
@property (nonatomic, readonly, copy) NSArray<NSString *> *logLines;
@end

@interface GnmSheet (Simulation)
/// The Risk Simulation dialog's OK (`simulation_tool`): the input cells
/// recomputed `iterations` times for rounds `firstRound`…`lastRound`
/// (1-based), the outputs' statistics written as the "Simulation Report"
/// to `output` (not undoable, as in the GTK) and returned.  Nil with the
/// tool's message: a bad range, rounds out of order, a non-numeric
/// variable, or the time limit.
- (nullable GnmSimulationResult *)runSimulationWithInputs:(NSString *)inputs outputs:(NSString *)outputs iterations:(NSInteger)iterations
                                               firstRound:(NSInteger)firstRound lastRound:(NSInteger)lastRound maximumSeconds:(NSInteger)seconds
                                                   output:(GnmAnalysisOutput *)output error:(NSError **)error
    NS_SWIFT_NAME(runSimulation(inputs:outputs:iterations:firstRound:lastRound:maximumSeconds:output:));
@end

NS_ASSUME_NONNULL_END
