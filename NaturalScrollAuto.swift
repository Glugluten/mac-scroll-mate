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
    private var cachedRules: [MouseRule] = []
    private var cachedRulesModifiedAt: Date?
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
        let output = run("/usr/bin/hidutil", ["list", "--ndjson", "--matching", "{\"PrimaryUsagePage\":1,\"PrimaryUsage\":2}"])
        let rules = configuredMouseRules()

        if rules.isEmpty {
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
        let modifiedAt = (try? FileManager.default.attributesOfItem(atPath: mouseNamesPath)[.modificationDate]) as? Date

        if modifiedAt == cachedRulesModifiedAt {
            return cachedRules
        }

        guard let contents = try? String(contentsOfFile: mouseNamesPath, encoding: .utf8) else {
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
