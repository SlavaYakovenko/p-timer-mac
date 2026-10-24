import AppKit

// p-timer-mac: menu-bar-only work/break timer: no windows, no Dock icon.
// Work (25 min) starts only manually; break (5 min) starts automatically after work.
// The menu shows how many work sessions were completed today (resets at local midnight).

let workDuration: TimeInterval = 25 * 60
let breakDuration: TimeInterval = 5 * 60

enum Phase { case work, rest }

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let startItem = NSMenuItem(title: "Start", action: #selector(start), keyEquivalent: "s")
    private let stopItem = NSMenuItem(title: "Stop", action: #selector(stop), keyEquivalent: "p")
    private let resetItem = NSMenuItem(title: "Reset", action: #selector(reset), keyEquivalent: "r")
    private let doneItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")

    private var phase: Phase = .work
    private var remaining: TimeInterval = workDuration
    private var endDate: Date?          // non-nil while running
    private var ticker: Timer?

    // Completed work sessions today; persisted so a relaunch within the same day keeps the count.
    private var doneCount = UserDefaults.standard.integer(forKey: "doneCount")
    private var doneDay = UserDefaults.standard.integer(forKey: "doneDay")   // local day as yyyymmdd

    func applicationDidFinishLaunching(_ notification: Notification) {
        let menu = NSMenu()
        menu.autoenablesItems = false
        for item in [startItem, stopItem, resetItem] {
            item.target = self
            menu.addItem(item)
        }
        menu.addItem(.separator())
        doneItem.isEnabled = false
        menu.addItem(doneItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        menu.delegate = self
        statusItem.menu = menu
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(willSleep), name: NSWorkspace.willSleepNotification, object: nil)

        rollDay()
        render()
    }

    @objc private func start() {
        guard endDate == nil else { return }
        run()
    }

    @objc private func stop() {
        guard let end = endDate else { return }
        remaining = max(0, end.timeIntervalSinceNow)
        endDate = nil
        ticker?.invalidate()
        ticker = nil
        render()
    }

    @objc private func reset() {
        stop()
        phase = .work
        remaining = workDuration
        render()
    }

    // Closing the lid pauses an unfinished work session; a running break just keeps counting.
    @objc private func willSleep() {
        if phase == .work { stop() }
    }

    func menuWillOpen(_ menu: NSMenu) {
        rollDay()   // the day may have changed since the last render
        render()
    }

    private func rollDay() {
        // A calendar-day number, not an instant, so a time-zone change doesn't reset the count.
        let c = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        let today = c.year! * 10000 + c.month! * 100 + c.day!
        guard doneDay != today else { return }
        doneDay = today
        doneCount = 0
        saveDone()
    }

    private func saveDone() {
        UserDefaults.standard.set(doneCount, forKey: "doneCount")
        UserDefaults.standard.set(doneDay, forKey: "doneDay")
    }

    private func run() {
        // Track an absolute end date so sleep/menu tracking can't make the timer drift.
        endDate = Date().addingTimeInterval(remaining)
        ticker?.invalidate()
        let t = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in self?.tick() }
        t.tolerance = 0.1
        RunLoop.main.add(t, forMode: .common)   // keep updating while the menu is open
        ticker = t
        render()
    }

    private func tick() {
        guard let end = endDate else { return }
        remaining = max(0, end.timeIntervalSinceNow)
        if remaining > 0 { render(); return }

        NSSound(named: "Glass")?.play()
        endDate = nil
        ticker?.invalidate()
        ticker = nil
        switch phase {
        case .work:
            rollDay()   // a session that ends after midnight counts for the new day
            doneCount += 1
            saveDone()
            phase = .rest
            remaining = breakDuration
            run()
        case .rest:
            phase = .work
            remaining = workDuration
            render()
        }
    }

    private func render() {
        let secs = Int(remaining.rounded(.up))
        // No icon to save menu-bar space; the break is shown in a dimmed color instead.
        statusItem.button?.attributedTitle = NSAttributedString(
            string: String(format: "%02d:%02d", secs / 60, secs % 60),
            attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 0, weight: .regular),
                .foregroundColor: phase == .work ? NSColor.labelColor : NSColor.secondaryLabelColor,
            ])

        let running = endDate != nil
        // Compare whole displayed seconds, so stopping right after Start (25:00 on screen) isn't "paused".
        let fresh = phase == .work && secs == Int(workDuration)
        startItem.isEnabled = !running
        let paused = !running && secs < Int(phase == .work ? workDuration : breakDuration)
        startItem.title = paused ? "Resume" : "Start"
        stopItem.isEnabled = running
        resetItem.isEnabled = running || !fresh
        doneItem.title = "Completed today: \(doneCount)"
    }
}

// Single instance: quit silently if another copy (any install location) is already running.
if let id = Bundle.main.bundleIdentifier,
   NSRunningApplication.runningApplications(withBundleIdentifier: id).contains(where: { $0 != .current }) {
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
