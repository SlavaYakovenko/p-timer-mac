import AppKit

// p-timer-mac: menu-bar-only work/break timer: no windows, no Dock icon.
// Work (25 min by default, 15-60 via the menu slider) starts only manually;
// break (5 min, 15 min after every 4th work session of the day) starts automatically after work.
// The menu shows how many work sessions were completed today (resets at local midnight,
// which also clears the red shown for an idle timer after a break).

let breakDuration: TimeInterval = 5 * 60
let longBreakDuration: TimeInterval = 15 * 60

enum Phase { case work, rest }

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let startItem = NSMenuItem(title: "Start", action: #selector(start), keyEquivalent: "s")
    private let stopItem = NSMenuItem(title: "Stop", action: #selector(stop), keyEquivalent: "p")
    private let resetItem = NSMenuItem(title: "Reset", action: #selector(reset), keyEquivalent: "r")
    private let doneItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let lengthLabel = NSTextField(labelWithString: "")
    private let lengthSlider = NSSlider(value: 25, minValue: 15, maxValue: 60, target: nil, action: nil)

    // Chosen work length in minutes; a work session keeps the length it started with.
    // Clamped and snapped to the slider's 5-minute steps, so a hand-edited default can't give a 0-minute session.
    private var workMinutes = (min(max(UserDefaults.standard.object(forKey: "workMinutes") as? Int ?? 25, 15), 60) + 2) / 5 * 5
    private lazy var duration = TimeInterval(workMinutes * 60)   // full length of the current phase
    private var phase: Phase = .work
    private lazy var remaining: TimeInterval = duration
    private var endDate: Date?          // non-nil while running
    private var breakOver = false       // a break ended and work hasn't been started yet: shown in red
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
        menu.addItem(lengthMenuItem())
        menu.addItem(.separator())
        doneItem.isEnabled = false
        menu.addItem(doneItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        menu.delegate = self
        statusItem.menu = menu
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(willSleep), name: NSWorkspace.willSleepNotification, object: nil)
        // Refresh the status bar on a new day even if the menu is never opened.
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(dayMayHaveChanged), name: NSWorkspace.didWakeNotification, object: nil)
        NotificationCenter.default.addObserver(forName: .NSCalendarDayChanged, object: nil, queue: .main) {
            [weak self] _ in self?.dayMayHaveChanged()   // may be posted off the main thread
        }

        rollDay()
        render()
    }

    @objc private func start() {
        guard endDate == nil else { return }
        breakOver = false
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
        idle()
        render()
    }

    @objc private func lengthChanged() {
        guard lengthSlider.integerValue != workMinutes else { return }   // a drag fires many actions per step
        let wasFresh = fresh
        workMinutes = lengthSlider.integerValue
        lengthLabel.stringValue = "Work length: \(workMinutes) min"
        UserDefaults.standard.set(workMinutes, forKey: "workMinutes")
        if wasFresh { idle() }   // an untouched work timer is the next session, so it takes the new length now
        render()
    }

    private func lengthMenuItem() -> NSMenuItem {
        lengthSlider.numberOfTickMarks = 10   // 5-minute steps
        lengthSlider.allowsTickMarkValuesOnly = true
        lengthSlider.integerValue = workMinutes
        lengthSlider.target = self
        lengthSlider.action = #selector(lengthChanged)
        lengthSlider.setAccessibilityLabel("Work length in minutes")
        lengthSlider.frame = NSRect(x: 12, y: 4, width: 176, height: 24)
        lengthLabel.font = .menuFont(ofSize: 0)
        lengthLabel.stringValue = "Work length: \(workMinutes) min"
        lengthLabel.frame = NSRect(x: 14, y: 30, width: 172, height: 17)
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 50))
        view.addSubview(lengthLabel)
        view.addSubview(lengthSlider)
        let item = NSMenuItem()
        item.view = view
        return item
    }

    private func idle() {
        phase = .work
        duration = TimeInterval(workMinutes * 60)
        remaining = duration
    }

    // Untouched work timer: not running and still showing the full length.
    private var fresh: Bool {
        phase == .work && endDate == nil && Int(remaining.rounded(.up)) == Int(duration)
    }

    // Closing the lid pauses an unfinished work session; a running break just keeps counting.
    @objc private func willSleep() {
        if phase == .work { stop() }
    }

    func menuWillOpen(_ menu: NSMenu) {
        dayMayHaveChanged()
    }

    @objc private func dayMayHaveChanged() {
        rollDay()
        render()
    }

    private func rollDay() {
        // A calendar-day number, not an instant, so a time-zone change doesn't reset the count.
        let c = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        let today = c.year! * 10000 + c.month! * 100 + c.day!
        guard doneDay != today else { return }
        doneDay = today
        doneCount = 0
        breakOver = false   // yesterday's finished break is no longer worth flagging
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
            duration = doneCount % 4 == 0 ? longBreakDuration : breakDuration
            remaining = duration
            run()
        case .rest:
            rollDay()   // before flagging, so a later day-change check can't clear today's red
            idle()
            breakOver = true
            render()
        }
    }

    private func render() {
        let secs = Int(remaining.rounded(.up))
        let running = endDate != nil
        // Compare whole displayed seconds, so stopping right after Start (25:00 on screen) isn't "paused".
        let paused = !running && secs < Int(duration)
        // No icon to save menu-bar space; the break is shown in green to catch the eye, and a timer waiting
        // to be started in red: idle after a break, or a work session paused by Stop or by closing the lid.
        statusItem.button?.attributedTitle = NSAttributedString(
            string: String(format: "%02d:%02d", secs / 60, secs % 60),
            attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 0, weight: .regular),
                .foregroundColor: breakOver || (paused && phase == .work) ? NSColor.systemRed
                    : phase == .work ? NSColor.labelColor : NSColor.systemGreen,
            ])

        startItem.isEnabled = !running
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
