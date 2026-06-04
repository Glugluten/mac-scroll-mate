import ApplicationServices
import CoreFoundation
import Darwin
import Foundation
import IOKit.hid

@_silgen_name("setSwipeScrollDirection")
private func setSwipeScrollDirection(_ direction: Bool)

final class MacScrollMate {
    private let hidManager: IOHIDManager
    private let mouseRulesPath: String
    private let logPath: String
    private let syncQueue = DispatchQueue(label: "MacScrollMate.sync")
    private let stateLock = NSLock()
    private var targetMouseConnected = false
    private var cachedRules: [MouseRule] = []
    private var cachedRulesModifiedAt: Date?
    private var pendingFastSync: DispatchWorkItem?
    private var pendingSettledSync: DispatchWorkItem?
    private var pendingEventTapRetry: DispatchWorkItem?
    private var didScheduleEventTapRetry = false
    private var didLogEventTapFailure = false
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    init(mouseRulesPath: String) {
        self.mouseRulesPath = mouseRulesPath
        logPath = NSHomeDirectory() + "/Library/Application Support/Mac Scroll Mate/MacScrollMate.log"
        hidManager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))

        let matching: [String: Any] = [
            kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop,
            kIOHIDDeviceUsageKey: kHIDUsage_GD_Mouse
        ]

        IOHIDManagerSetDeviceMatching(hidManager, matching as CFDictionary)
        IOHIDManagerRegisterDeviceMatchingCallback(hidManager, deviceChanged, Unmanaged.passUnretained(self).toOpaque())
        IOHIDManagerRegisterDeviceRemovalCallback(hidManager, deviceChanged, Unmanaged.passUnretained(self).toOpaque())
        IOHIDManagerScheduleWithRunLoop(hidManager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerOpen(hidManager, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    func start() -> Never {
        log("Starting Mac Scroll Mate. accessibility=\(AXIsProcessTrusted()) inputMonitoring=\(CGPreflightListenEventAccess())")
        ensureNaturalScrollingEnabled()
        scheduleTargetRefresh(delay: 0)
        installEventTapOrScheduleOneRetry()

        CFRunLoopRun()
        fatalError("CFRunLoopRun returned unexpectedly")
    }

    func check() -> Int32 {
        refreshTargetMouseState()
        print("Config: \(mouseRulesPath)")
        print("Target mouse connected: \(isTargetMouseConnected())")
        print("Natural Scrolling preference: \(currentNaturalScrolling().map(String.init(describing:)) ?? "unset")")
        print("Accessibility trusted: \(AXIsProcessTrusted())")
        print("Input monitoring/listen access: \(CGPreflightListenEventAccess())")

        guard installEventTap() else {
            print("Failed to create CGEventTap. Grant Accessibility/Input Monitoring permission to Mac Scroll Mate.")
            return 2
        }

        print("CGEventTap created successfully.")
        invalidateEventTap()
        return 0
    }

    func requestPermissions() -> Int32 {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        _ = CGRequestListenEventAccess()

        print("Accessibility trusted: \(AXIsProcessTrusted())")
        print("Input monitoring/listen access: \(CGPreflightListenEventAccess())")

        return 0
    }

    fileprivate func handleDeviceChanged() {
        scheduleTargetRefresh()
    }

    fileprivate func handleEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }

            return nil
        }

        guard type == .scrollWheel, isTargetMouseConnected() else {
            return Unmanaged.passUnretained(event)
        }

        let isContinuous = event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0

        guard !isContinuous else {
            return Unmanaged.passUnretained(event)
        }

        guard let replacement = invertedReplacementEvent(from: event) else {
            return Unmanaged.passUnretained(event)
        }

        return Unmanaged.passRetained(replacement)
    }

    private func installEventTap() -> Bool {
        if eventTap != nil {
            return true
        }

        guard AXIsProcessTrusted(), CGPreflightListenEventAccess() else {
            return false
        }

        let eventMask = CGEventMask(1 << CGEventType.scrollWheel.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: eventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return false
        }

        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            CFMachPortInvalidate(tap)
            return false
        }

        eventTap = tap
        runLoopSource = source
        didLogEventTapFailure = false
        pendingEventTapRetry?.cancel()
        pendingEventTapRetry = nil
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        log("CGEventTap created successfully.")

        return true
    }

    private func installEventTapOrScheduleOneRetry() {
        if installEventTap() {
            return
        }

        if !didLogEventTapFailure {
            let message = "Failed to create CGEventTap. Grant Accessibility/Input Monitoring permission to Mac Scroll Mate."
            print(message)
            log(message)
            didLogEventTapFailure = true
        }

        guard !didScheduleEventTapRetry else {
            return
        }

        didScheduleEventTapRetry = true
        pendingEventTapRetry?.cancel()

        let retry = DispatchWorkItem { [weak self] in
            self?.pendingEventTapRetry = nil
            if self?.installEventTap() != true {
                let message = "CGEventTap retry failed. Grant permissions, then restart the LaunchAgent."
                print(message)
                self?.log(message)
            }
        }
        pendingEventTapRetry = retry

        DispatchQueue.main.asyncAfter(deadline: .now() + 30.0, execute: retry)
    }

    private func invalidateEventTap() {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }

        if let eventTap {
            CFMachPortInvalidate(eventTap)
        }

        runLoopSource = nil
        eventTap = nil
    }

    private func scheduleTargetRefresh(delay: TimeInterval = 0.2) {
        pendingFastSync?.cancel()
        pendingSettledSync?.cancel()

        let fastSync = DispatchWorkItem { [weak self] in
            self?.syncQueue.async {
                self?.refreshTargetMouseState()
            }
        }
        pendingFastSync = fastSync

        let settledSync = DispatchWorkItem { [weak self] in
            self?.syncQueue.async {
                self?.refreshTargetMouseState()
            }
        }
        pendingSettledSync = settledSync

        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: fastSync)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: settledSync)
    }

    private func refreshTargetMouseState() {
        let connected = detectTargetMouse()
        stateLock.lock()
        let changed = targetMouseConnected != connected
        targetMouseConnected = connected
        stateLock.unlock()

        if changed {
            print("Target mouse connected: \(connected)")
            log("Target mouse connected: \(connected)")
        }

        ensureNaturalScrollingEnabled()
    }

    private func isTargetMouseConnected() -> Bool {
        stateLock.lock()
        let connected = targetMouseConnected
        stateLock.unlock()
        return connected
    }

    private func ensureNaturalScrollingEnabled() {
        if currentNaturalScrolling() != true {
            setNaturalScrolling(true)
            return
        }

        setSwipeScrollDirection(true)
    }

    private func setNaturalScrolling(_ enabled: Bool) {
        var globalDomain = UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain) ?? [:]
        globalDomain["com.apple.swipescrolldirection"] = enabled
        UserDefaults.standard.setPersistentDomain(globalDomain, forName: UserDefaults.globalDomain)
        UserDefaults.standard.synchronize()

        DistributedNotificationCenter.default().postNotificationName(
            Notification.Name("SwipeScrollDirectionDidChangeNotification"),
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )

        setSwipeScrollDirection(enabled)
    }

    private func currentNaturalScrolling() -> Bool? {
        guard let value = UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)?["com.apple.swipescrolldirection"] else {
            return nil
        }

        if let boolValue = value as? Bool {
            return boolValue
        }

        if let intValue = value as? Int {
            return intValue != 0
        }

        return nil
    }

    private func detectTargetMouse() -> Bool {
        let output = run("/usr/bin/hidutil", ["list", "--ndjson", "--matching", "{\"PrimaryUsagePage\":1,\"PrimaryUsage\":2}"])
        let rules = configuredMouseRules()

        guard !rules.isEmpty else {
            return false
        }

        for line in output.split(separator: "\n") {
            guard let device = HIDDevice(jsonLine: String(line)),
                  device.isExternalMouse,
                  rules.contains(where: { $0.matches(device) }) else {
                continue
            }

            return true
        }

        return false
    }

    private func configuredMouseRules() -> [MouseRule] {
        let modifiedAt = (try? FileManager.default.attributesOfItem(atPath: mouseRulesPath)[.modificationDate]) as? Date

        if modifiedAt == cachedRulesModifiedAt {
            return cachedRules
        }

        guard let contents = try? String(contentsOfFile: mouseRulesPath, encoding: .utf8) else {
            cachedRules = []
            cachedRulesModifiedAt = modifiedAt
            return []
        }

        cachedRules = contents
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
            .compactMap(MouseRule.init)
        cachedRulesModifiedAt = modifiedAt

        return cachedRules
    }

    private func invertedReplacementEvent(from event: CGEvent) -> CGEvent? {
        let pointAxis1 = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1)
        let pointAxis2 = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2)
        let pointAxis3 = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis3)
        let lineAxis1 = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
        let lineAxis2 = event.getIntegerValueField(.scrollWheelEventDeltaAxis2)
        let lineAxis3 = event.getIntegerValueField(.scrollWheelEventDeltaAxis3)
        let source = CGEventSource(event: event) ?? CGEventSource(stateID: .combinedSessionState)

        let replacement: CGEvent?

        if pointAxis1 != 0 || pointAxis2 != 0 || pointAxis3 != 0 {
            replacement = CGEvent(
                scrollWheelEvent2Source: source,
                units: .pixel,
                wheelCount: 3,
                wheel1: Int32(clamping: -pointAxis1),
                wheel2: Int32(clamping: -pointAxis2),
                wheel3: Int32(clamping: -pointAxis3)
            )
        } else {
            replacement = CGEvent(
                scrollWheelEvent2Source: source,
                units: .line,
                wheelCount: 3,
                wheel1: Int32(clamping: -lineAxis1),
                wheel2: Int32(clamping: -lineAxis2),
                wheel3: Int32(clamping: -lineAxis3)
            )
        }

        guard let replacement else {
            return nil
        }

        replacement.flags = event.flags
        replacement.location = event.location
        replacement.setIntegerValueField(.scrollWheelEventIsContinuous, value: event.getIntegerValueField(.scrollWheelEventIsContinuous))
        replacement.setIntegerValueField(.scrollWheelEventScrollPhase, value: event.getIntegerValueField(.scrollWheelEventScrollPhase))
        replacement.setIntegerValueField(.scrollWheelEventMomentumPhase, value: event.getIntegerValueField(.scrollWheelEventMomentumPhase))
        replacement.setIntegerValueField(.eventSourceUserData, value: event.getIntegerValueField(.eventSourceUserData))

        return replacement
    }

    private func log(_ message: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "\(timestamp) \(message)\n"

        guard let data = line.data(using: .utf8) else {
            return
        }

        if !FileManager.default.fileExists(atPath: logPath) {
            FileManager.default.createFile(atPath: logPath, contents: nil)
        }

        guard let handle = try? FileHandle(forWritingTo: URL(fileURLWithPath: logPath)) else {
            return
        }

        defer {
            try? handle.close()
        }

        _ = try? handle.seekToEnd()
        _ = try? handle.write(contentsOf: data)
    }

    private func run(_ executable: String, _ arguments: [String]) -> String {
        let process = Process()
        let output = Pipe()

        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return ""
        }

        let data = output.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }
}

private struct HIDDevice {
    let vendorID: Int?
    let productID: Int?
    let product: String?
    let primaryUsagePage: Int
    let primaryUsage: Int
    let builtIn: Bool

    var isExternalMouse: Bool {
        primaryUsagePage == 1 && primaryUsage == 2 && !builtIn
    }

    init?(jsonLine: String) {
        guard let data = jsonLine.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let dict = object as? [String: Any] else {
            return nil
        }

        vendorID = dict["VendorID"] as? Int
        productID = dict["ProductID"] as? Int
        product = dict["Product"] as? String
        primaryUsagePage = dict["PrimaryUsagePage"] as? Int ?? 0
        primaryUsage = dict["PrimaryUsage"] as? Int ?? 0
        builtIn = dict["Built-In"] as? Bool ?? false
    }
}

private enum MouseRule {
    case productName(String)
    case vendorProduct(vendorID: Int, productID: Int)

    init?(_ rawValue: String) {
        if let ids = MouseRule.parseVendorProduct(rawValue) {
            self = .vendorProduct(vendorID: ids.vendorID, productID: ids.productID)
            return
        }

        self = .productName(rawValue)
    }

    func matches(_ device: HIDDevice) -> Bool {
        switch self {
        case .productName(let name):
            return device.product == name
        case .vendorProduct(let vendorID, let productID):
            return device.vendorID == vendorID && device.productID == productID
        }
    }

    private static func parseVendorProduct(_ value: String) -> (vendorID: Int, productID: Int)? {
        let parts = value.split(separator: ":", omittingEmptySubsequences: false)

        guard parts.count == 2,
              let vendorID = parseHexID(String(parts[0])),
              let productID = parseHexID(String(parts[1])) else {
            return nil
        }

        return (vendorID, productID)
    }

    private static func parseHexID(_ value: String) -> Int? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let hex = trimmed.hasPrefix("0x") ? String(trimmed.dropFirst(2)) : trimmed

        guard hex.count == 4 else {
            return nil
        }

        return Int(hex, radix: 16)
    }
}

private let deviceChanged: IOHIDDeviceCallback = { context, _, _, _ in
    guard let context else { return }
    let app = Unmanaged<MacScrollMate>.fromOpaque(context).takeUnretainedValue()
    app.handleDeviceChanged()
}

private let eventTapCallback: CGEventTapCallBack = { _, type, event, userInfo in
    guard let userInfo else {
        return Unmanaged.passUnretained(event)
    }

    let app = Unmanaged<MacScrollMate>.fromOpaque(userInfo).takeUnretainedValue()
    return app.handleEvent(type: type, event: event)
}

private func defaultMouseRulesPath() -> String {
    NSHomeDirectory() + "/Library/Application Support/Mac Scroll Mate/mouse-names.txt"
}

private func argumentValue(after option: String) -> String? {
    let args = CommandLine.arguments

    guard let index = args.firstIndex(of: option), args.indices.contains(index + 1) else {
        return nil
    }

    return args[index + 1]
}

let mouseRulesPath = argumentValue(after: "--config") ?? defaultMouseRulesPath()
let app = MacScrollMate(mouseRulesPath: mouseRulesPath)

if CommandLine.arguments.contains("--check") {
    exit(app.check())
}

if CommandLine.arguments.contains("--request-permissions") {
    exit(app.requestPermissions())
}

app.start()
