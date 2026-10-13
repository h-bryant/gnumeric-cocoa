import AppKit
import GnmCocoa

/// The GTK Solver dialog's run page (dialog-solver.c cb_notify_status,
/// cb_timer_tick, the Stop button) as a sheet: the status, the objective
/// value so far, the elapsed time, polled every 100 ms while the engine's
/// solver works through the run loop; closes itself when the run ends
/// and hands the outcome on.
@MainActor
final class SolverProgress {
    let run: SolverRun
    let window: NSWindow
    let completion: (SolverOutcome) -> Void
    let alert = NSAlert()
    let statusLabel = NSTextField(labelWithString: "")
    let objectiveLabel = NSTextField(labelWithString: "")
    let elapsedLabel = NSTextField(labelWithString: "")
    private var timer: Timer?
    private var presented = false

    init(run: SolverRun, in window: NSWindow, completion: @escaping (SolverOutcome) -> Void) {
        self.run = run
        self.window = window
        self.completion = completion
        alert.messageText = "Solver"
        alert.informativeText = "Solving…"
        alert.addButton(withTitle: Localization.title("Stop"))
        func label(_ text: String) -> NSTextField {
            let field = NSTextField(labelWithString: text)
            field.alignment = .right
            return field
        }
        for field in [statusLabel, objectiveLabel, elapsedLabel] {
            field.widthAnchor.constraint(greaterThanOrEqualToConstant: 180).isActive = true
        }
        let grid = NSGridView(views: [[label("Solver status:"), statusLabel], [label("Objective value:"), objectiveLabel],
                                      [label("Elapsed time:"), elapsedLabel]])
        grid.rowSpacing = 6
        grid.columnSpacing = 8
        grid.column(at: 0).xPlacement = .trailing
        let size = grid.fittingSize
        grid.frame = NSRect(x: 0, y: 0, width: max(size.width, 300), height: size.height)
        alert.accessoryView = grid
    }

    /// Show the sheet (not under GNM_SNAPSHOT) and start polling; a run
    /// that already ended is finished at once.
    func begin() {
        update()
        if run.isFinished {
            finish()
            return
        }
        if ProcessInfo.processInfo.environment["GNM_SNAPSHOT"] == nil {
            presented = true
            alert.beginSheetModal(for: window) { [self] _ in
                presented = false
                if !run.isFinished { _ = run.stop() }
            }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    private func tick() {
        _ = run.checkTimeout()
        update()
        if run.isFinished { finish() }
    }

    private func update() {
        statusLabel.stringValue = run.status
        objectiveLabel.stringValue = run.objectiveValue.map { String(format: "%.10g", $0.doubleValue) } ?? ""
        let seconds = max(0, Int(run.elapsedSeconds))
        elapsedLabel.stringValue = seconds >= 3600
            ? String(format: "%02d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
            : String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    private func finish() {
        timer?.invalidate()
        timer = nil
        if presented {
            presented = false
            window.endSheet(alert.window)
        }
        if let outcome = run.finish() { completion(outcome) }
    }
}
