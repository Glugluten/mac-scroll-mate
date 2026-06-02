import CoreFoundation
import Foundation
import IOKit.hid

@_silgen_name("setSwipeScrollDirection")
private func setSwipeScrollDirection(_ direction: Bool)

final class NaturalScrollAuto {
    private let manager: IOHIDManager
    private let syncQueue = DispatchQueue(label: "NaturalScrollAuto.sync")
    private var lastDesiredValue: Bool?
    private var pendingFastSync: DispatchWorkItem?
    private var pendingSettledSync: DispatchWorkItem?
    private let mouseNamesPath: String

    init() {
        manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        mouseNamesPath = NSHomeDirectory() + "/Library/Application Support/NaturalScrollAuto/mouse-names.txt"

        let matching: [String: Any] = [
            kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop,
            kIOHIDDeviceUsageKey: kHIDUsage_GD_Mouse
        ]

        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)
        IOHIDManagerRegisterDeviceMatchingCallback(manager, deviceMatched, Unmanaged.passUnretained(self).toOpaque())
        IOHIDManagerRegisterDeviceRemovalCallback(manager, deviceRemoved, Unmanaged.passUnretained(self).toOpaque())
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    func start() {
        scheduleSync(delay: 0)
        CFRunLoopRun()
    }

    fileprivate func handleMatched() {
        scheduleSync()
    }

    fileprivate func handleRemoved() {
        scheduleSync()
    }

    private func scheduleSync(delay: TimeInterval = 0.2) {
        pendingFastSync?.cancel()
        pendingSettledSync?.cancel()

        let fastSync = DispatchWorkItem { [weak self] in
            self?.syncQueue.async {
                self?.syncNaturalScrolling()
            }
        }
        pendingFastSync = fastSync

        let settledSync = DispatchWorkItem { [weak self] in
            self?.syncQueue.async {
                self?.syncNaturalScrolling()
            }
        }
        pendingSettledSync = settledSync

        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: fastSync)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: settledSync)
    }

    private func syncNaturalScrolling() {
        let shouldEnableNaturalScrolling = !externalMouseConnected()

        if lastDesiredValue == shouldEnableNaturalScrolling {
            return
        }

        lastDesiredValue = shouldEnableNaturalScrolling
        setNaturalScrolling(shouldEnableNaturalScrolling)
    }

    private func setNaturalScrolling(_ enabled: Bool) {
        if currentNaturalScrolling() != enabled {
            var globalDomain = UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain) ?? [:]
            globalDomain["com.apple.swipescrolldirection"] = enabled
            UserDefaults.standard.setPersistentDomain(globalDomain, forName: UserDefaults.globalDomain)
            UserDefaults.standard.synchronize()
        }

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

    private func externalMouseConnected() -> Bool {
        let output = run("/usr/bin/hidutil", ["list"])
        let allowedNames = configuredMouseNames()

        if allowedNames.isEmpty {
            return false
        }

        for line in output.split(separator: "\n") {
            let fields = line.split(separator: " ")

            guard fields.count >= 6 else {
                continue
            }

            let usagePage = fields[3]
            let usage = fields[4]
            let builtIn = fields.last ?? ""

            if usagePage == "1" && usage == "2" && builtIn == "0" && matchesConfiguredMouse(String(line), allowedNames) {
                return true
            }
        }

        return false
    }

    private func configuredMouseNames() -> [String] {
        guard let contents = try? String(contentsOfFile: mouseNamesPath, encoding: .utf8) else {
            return []
        }

        return contents
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
    }

    private func matchesConfiguredMouse(_ line: String, _ mouseNames: [String]) -> Bool {
        mouseNames.contains { line.contains($0) }
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

private let deviceMatched: IOHIDDeviceCallback = { context, _, _, _ in
    guard let context else { return }
    let app = Unmanaged<NaturalScrollAuto>.fromOpaque(context).takeUnretainedValue()
    app.handleMatched()
}

private let deviceRemoved: IOHIDDeviceCallback = { context, _, _, _ in
    guard let context else { return }
    let app = Unmanaged<NaturalScrollAuto>.fromOpaque(context).takeUnretainedValue()
    app.handleRemoved()
}

let app = NaturalScrollAuto()
app.start()
