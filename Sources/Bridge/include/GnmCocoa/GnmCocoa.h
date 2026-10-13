// GnmCocoa: Objective-C bridge between the Gnumeric engine and the Cocoa app.
//
// Rules (HANDOFF.md §6):
//   - this directory is the only public surface; Swift never sees a GObject
//     pointer, and no header here includes GLib, goffice, or Gnumeric headers;
//   - every class is main-thread only (NS_SWIFT_UI_ACTOR), because the engine
//     is not thread-safe;
//   - failures come back as NSError out-parameters so Swift gets `throws`.
#import <Foundation/Foundation.h>

#import <GnmCocoa/GnmGeometry.h>
#import <GnmCocoa/GnmError.h>
#import <GnmCocoa/GnmPreferences.h>
#import <GnmCocoa/GnmEngine.h>
#import <GnmCocoa/GnmWorkbook.h>
#import <GnmCocoa/GnmCellFormat.h>
#import <GnmCocoa/GnmFilter.h>
#import <GnmCocoa/GnmSheetObject.h>
#import <GnmCocoa/GnmPlotType.h>
#import <GnmCocoa/GnmChartEditor.h>
#import <GnmCocoa/GnmSheet.h>
#import <GnmCocoa/GnmConditionalFormat.h>
#import <GnmCocoa/GnmAnalysis.h>
#import <GnmCocoa/GnmValidation.h>
#import <GnmCocoa/GnmHyperlink.h>
#import <GnmCocoa/GnmSolver.h>
#import <GnmCocoa/GnmPrinting.h>
#import <GnmCocoa/GnmFormulaEditing.h>
#import <GnmCocoa/GnmFunctions.h>
#import <GnmCocoa/GnmWhatIf.h>
#import <GnmCocoa/GnmOutline.h>
#import <GnmCocoa/GnmPlugins.h>
#import <GnmCocoa/GnmScenarios.h>
#import <GnmCocoa/GnmAutoFormat.h>
#import <GnmCocoa/GnmWidgets.h>
#import <GnmCocoa/GnmNumberFormats.h>
#import <GnmCocoa/GnmDragging.h>
#import <GnmCocoa/GnmWorkbookProperties.h>
#import <GnmCocoa/GnmMerge.h>
#import <GnmCocoa/GnmSearch.h>
#import <GnmCocoa/GnmTextExport.h>
#import <GnmCocoa/GnmTextImport.h>
#import <GnmCocoa/GnmNames.h>
#import <GnmCocoa/GnmRunLoopBridge.h>
