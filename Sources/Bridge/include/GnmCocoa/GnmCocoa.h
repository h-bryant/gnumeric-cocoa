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
#import <GnmCocoa/GnmEngine.h>
#import <GnmCocoa/GnmWorkbook.h>
#import <GnmCocoa/GnmCellFormat.h>
#import <GnmCocoa/GnmFilter.h>
#import <GnmCocoa/GnmSheetObject.h>
#import <GnmCocoa/GnmPlotType.h>
#import <GnmCocoa/GnmChartEditor.h>
#import <GnmCocoa/GnmSheet.h>
#import <GnmCocoa/GnmSearch.h>
#import <GnmCocoa/GnmRunLoopBridge.h>
