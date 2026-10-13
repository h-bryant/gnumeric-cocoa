// The Solver (`tools/gnm-solver.h`): a sheet's optimization problem (the
// target cell, the cells to change, the constraints, the algorithm and
// its options) as the GTK Tools → Solver dialog (dialog-solver.c)
// records and runs it.
#import <Foundation/Foundation.h>
#import <GnmCocoa/GnmGeometry.h>
#import <GnmCocoa/GnmSheet.h>

NS_ASSUME_NONNULL_BEGIN

@class GnmEngine;

/// `GnmSolverProblemType`.
typedef NS_ENUM(NSInteger, GnmSolverGoal) {
    GnmSolverGoalMinimize = 0,
    GnmSolverGoalMaximize,
} NS_SWIFT_NAME(SolverSettings.Goal);

/// `GnmSolverModelType`: linear (LP/MILP), quadratic (QP/MIQP), non-linear.
typedef NS_ENUM(NSInteger, GnmSolverModel) {
    GnmSolverModelLinear = 0,
    GnmSolverModelQuadratic,
    GnmSolverModelNonlinear,
} NS_SWIFT_NAME(SolverSettings.Model);

/// `GnmSolverConstraintType`, in the dialog's order (≤, ≥, =, Int, Bool).
typedef NS_ENUM(NSInteger, GnmSolverRuleKind) {
    GnmSolverRuleLessOrEqual = 0,
    GnmSolverRuleGreaterOrEqual,
    GnmSolverRuleEqual,
    GnmSolverRuleInteger,
    GnmSolverRuleBoolean,
} NS_SWIFT_NAME(SolverRule.Kind);

/// `GnmSolverResultQuality`.
typedef NS_ENUM(NSInteger, GnmSolverQuality) {
    GnmSolverQualityNone = 0,
    GnmSolverQualityFeasible,
    GnmSolverQualityOptimal,
    GnmSolverQualityInfeasible,
    GnmSolverQualityUnbounded,
} NS_SWIFT_NAME(SolverOutcome.Quality);

/// A solver the plugins provide (`GnmSolverFactory`): Gnumeric's own
/// non-linear one, and GLPK and lp_solve when their programs are found.
NS_SWIFT_UI_ACTOR NS_SWIFT_NAME(SolverAlgorithm)
@interface GnmSolverAlgorithm : NSObject
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
/// "nlsolve", "glpk", "lpsolve".
@property (nonatomic, readonly, copy) NSString *identifier;
@property (nonatomic, readonly, copy) NSString *name;
/// The model it solves; the dialog offers it for that model.
@property (nonatomic, readonly) GnmSolverModel model;
/// Whether it can run here (an external program may be missing).
@property (nonatomic, readonly) BOOL isFunctional;
@end

/// One constraint: a left side (cells), a kind, and for ≤, ≥, and = a
/// right side (a number or cells).
NS_SWIFT_UI_ACTOR NS_SWIFT_NAME(SolverRule)
@interface GnmSolverRule : NSObject <NSCopying>
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
- (instancetype)initWithKind:(GnmSolverRuleKind)kind leftSide:(NSString *)leftSide rightSide:(NSString *)rightSide NS_DESIGNATED_INITIALIZER;
@property (nonatomic, readonly) GnmSolverRuleKind kind;
@property (nonatomic, readonly, copy) NSString *leftSide;
@property (nonatomic, readonly, copy) NSString *rightSide;
/// Int and Bool take none.
@property (nonatomic, readonly) BOOL takesRightSide;
/// The dialog's symbol for a kind ("≤", "≥", "=", "Int", "Bool").
+ (NSString *)symbolForKind:(GnmSolverRuleKind)kind NS_SWIFT_NAME(symbol(for:));
@end

/// A sheet's solver parameters (`GnmSolverParameters`, saved with the
/// file), as the dialog's pages set them.
NS_SWIFT_UI_ACTOR NS_SWIFT_NAME(SolverSettings)
@interface GnmSolverSettings : NSObject <NSCopying>
/// The engine's defaults.
- (instancetype)init;
/// The cell to optimize ("B1"; a formula that evaluates to a number).
@property (nonatomic, copy) NSString *targetCell;
@property (nonatomic) GnmSolverGoal goal;
/// The cells to change ("A1:A3").
@property (nonatomic, copy) NSString *inputCells;
@property (nonatomic, copy) NSArray<GnmSolverRule *> *rules;
/// An algorithm's identifier, or nil for none chosen.
@property (nonatomic, copy, nullable) NSString *algorithmIdentifier;
@property (nonatomic) GnmSolverModel model;
@property (nonatomic) NSInteger maxIterations;
@property (nonatomic) NSInteger maxTimeSeconds;
@property (nonatomic) BOOL assumesNonNegative;
@property (nonatomic) BOOL assumesDiscrete;
@property (nonatomic) BOOL automaticScaling;
/// Data points on each side for numerical differentiation.
@property (nonatomic) NSInteger gradientOrder;
/// The reports as new sheets ("<sheet> Program Report", "… Sensitivity Report").
@property (nonatomic) BOOL programReport;
@property (nonatomic) BOOL sensitivityReport;
@end

/// What a run came to.
NS_SWIFT_UI_ACTOR NS_SWIFT_NAME(SolverOutcome)
@interface GnmSolverOutcome : NSObject
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
/// The dialog's Solver Status ("Done", "Error", "Cancelled").
@property (nonatomic, readonly, copy) NSString *status;
/// The solver's own words on a failure, or nil.
@property (nonatomic, readonly, copy, nullable) NSString *reason;
/// The dialog's Problem Status.
@property (nonatomic, readonly) GnmSolverQuality quality;
/// A feasible or optimal solution was stored in the cells.
@property (nonatomic, readonly) BOOL hasSolution;
/// The objective value, when there is a solution.
@property (nonatomic, readonly) double objectiveValue;
@property (nonatomic, readonly) double elapsedSeconds;
@end

/// A run in progress (the dialog's run page: cb_notify_status,
/// cb_timer_tick, the Stop button): the engine's solver works through
/// the GLib main context, which the app's run loop pumps.  Read its
/// state, stop it, and once it finished, `finish` to store the solution.
NS_SWIFT_UI_ACTOR NS_SWIFT_NAME(SolverRun)
@interface GnmSolverRun : NSObject
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
/// The dialog's Solver Status so far ("Running", "Done (Timeout)").
@property (nonatomic, readonly, copy) NSString *status;
@property (nonatomic, readonly) BOOL isFinished;
/// The objective value the solver reported so far, or nil.
@property (nonatomic, readonly, copy, nullable) NSNumber *objectiveValue;
@property (nonatomic, readonly) double elapsedSeconds;
/// The dialog's timer tick: stop the solver past its time limit; YES
/// when that just happened.
- (BOOL)checkTimeout;
/// The dialog's Stop button; NO when the solver would not stop.
- (BOOL)stop;
/// Once finished: store a solution in the cells, with the reports, as
/// one undoable command ("Running solver"), and say what the run came
/// to.  Nil before the run finished, and on a second call.
- (nullable GnmSolverOutcome *)finish;
@end

@interface GnmEngine (Solver)
/// The algorithms the plugins registered, by name.
@property (nonatomic, readonly) NSArray<GnmSolverAlgorithm *> *solverAlgorithms;
@end

@interface GnmSheet (Solver)
/// The sheet's solver parameters.
@property (nonatomic, readonly, copy) GnmSolverSettings *solverSettings;
/// Record settings on the sheet after the engine's checks
/// (`gnm_solver_param_valid`: the target, the input, each constraint),
/// as "Changing solver parameters" when they differ; NO with the
/// engine's message otherwise, the sheet's settings unchanged.
- (BOOL)setSolverSettings:(GnmSolverSettings *)settings error:(NSError **)error NS_SWIFT_NAME(setSolverSettings(_:));
/// Start a run with the sheet's parameters (run_solver): the parameters
/// checked, the chosen algorithm's solver created and started.  Nil with
/// the dialog's message when it cannot start; a run that failed at once
/// comes back finished with its reason.
- (nullable GnmSolverRun *)startSolverWithError:(NSError **)error NS_SWIFT_NAME(startSolver());
/// Run the sheet's settings to the end (the dialog's Solve, waiting as
/// its nested main loop does; the time limit holds), store a solution
/// in the cells with the reports asked for as one command ("Running
/// solver").  The outcome, which may say the problem is infeasible; nil
/// with the message when the settings are invalid, the algorithm
/// cannot run, or the solver failed to start.
- (nullable GnmSolverOutcome *)runSolverWithError:(NSError **)error NS_SWIFT_NAME(runSolver());
@end

@interface GnmSheet (SolverRules)
/// A rule as the dialog lists it ("A1:A3 ≤ 10"), or nil when its sides
/// do not parse (`gnm_solver_constraint_as_str`).
- (nullable NSString *)descriptionOfSolverRule:(GnmSolverRule *)rule NS_SWIFT_NAME(description(of:));
@end

NS_ASSUME_NONNULL_END
