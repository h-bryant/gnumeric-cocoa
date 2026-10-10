// Entry point.  There is no nib: the delegate builds the menu bar and the
// engine starts before any document opens.
import AppKit

let application = NSApplication.shared
let appDelegate = AppDelegate()
application.delegate = appDelegate
_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
