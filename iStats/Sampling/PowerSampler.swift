import Foundation
import Darwin
import IOKit
import IOKit.ps
import iStatsCore

/// Raw snapshot of an internal power source (e.g. battery / AC power) from `IOPowerSources`.
public struct RawPowerSourceSnapshot: Sendable, Equatable {
    public let hasBattery: Bool
    public let isPresent: Bool
    public let powerSourceState: String?       // "AC Power", "Battery Power", etc.
    public let currentCapacity: Int?          // 0...100
    public let maxCapacity: Int?              // 0...100
    public let isCharging: Bool?
    public let isCharged: Bool?
    public let timeToEmpty: Int?              // in minutes, -1 if calculating / unknown
    public let timeToFullCharge: Int?         // in minutes, -1 if calculating / unknown
    public let timeRemainingEstimate: Double? // in seconds, -1.0 if calculating, -2.0 if unlimited/AC, >0 if on battery
    public let transportType: String?         // "Internal"
    public let type: String?                  // "InternalBattery"

    public init(
        hasBattery: Bool,
        isPresent: Bool = true,
        powerSourceState: String? = nil,
        currentCapacity: Int? = nil,
        maxCapacity: Int? = nil,
        isCharging: Bool? = nil,
        isCharged: Bool? = nil,
        timeToEmpty: Int? = nil,
        timeToFullCharge: Int? = nil,
        timeRemainingEstimate: Double? = nil,
        transportType: String? = nil,
        type: String? = nil
    ) {
        self.hasBattery = hasBattery
        self.isPresent = isPresent
        self.powerSourceState = powerSourceState
        self.currentCapacity = currentCapacity
        self.maxCapacity = maxCapacity
        self.isCharging = isCharging
        self.isCharged = isCharged
        self.timeToEmpty = timeToEmpty
        self.timeToFullCharge = timeToFullCharge
        self.timeRemainingEstimate = timeRemainingEstimate
        self.transportType = transportType
        self.type = type
    }
}

/// Raw battery health and wattage data from the `AppleSmartBattery` IOKit registry.
public struct RawSmartBatteryData: Sendable, Equatable {
    public let cycleCount: Int?
    public let condition: String?
    public let designCapacity: Int?
    public let currentMaxCapacity: Int?
    public let adapterWatts: Double?
    public let powerDrawWatts: Double?

    public init(
        cycleCount: Int? = nil,
        condition: String? = nil,
        designCapacity: Int? = nil,
        currentMaxCapacity: Int? = nil,
        adapterWatts: Double? = nil,
        powerDrawWatts: Double? = nil
    ) {
        self.cycleCount = cycleCount
        self.condition = condition
        self.designCapacity = designCapacity
        self.currentMaxCapacity = currentMaxCapacity
        self.adapterWatts = adapterWatts
        self.powerDrawWatts = powerDrawWatts
    }
}

/// Abstract provider for reading power source and battery health/telemetry.
public protocol PowerInfoProvider: Sendable {
    /// Returns snapshot of power sources via `IOPowerSources`.
    func powerSourceSnapshot() throws -> RawPowerSourceSnapshot

    /// Returns smart battery data from IOKit `AppleSmartBattery` service, or nil if unavailable.
    func smartBatteryData() throws -> RawSmartBatteryData?
}

public extension PowerInfoProvider {
    func smartBatteryData() throws -> RawSmartBatteryData? { nil }
}

/// Darwin `IOPowerSources` and `AppleSmartBattery` implementation of `PowerInfoProvider`.
public struct HostPowerInfoProvider: PowerInfoProvider {
    public init() {}

    public func powerSourceSnapshot() throws -> RawPowerSourceSnapshot {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else {
            return RawPowerSourceSnapshot(hasBattery: false, isPresent: false)
        }

        guard let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef], !sources.isEmpty else {
            return RawPowerSourceSnapshot(hasBattery: false, isPresent: false)
        }

        let estimate = Double(IOPSGetTimeRemainingEstimate())

        var batteryDesc: [String: Any]? = nil
        for source in sources {
            guard let desc = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any] else {
                continue
            }
            let type = desc[kIOPSTypeKey as String] as? String
            let transport = desc[kIOPSTransportTypeKey as String] as? String
            if type == (kIOPSInternalBatteryType as String) || transport == "Internal" {
                batteryDesc = desc
                break
            }
        }

        guard let desc = batteryDesc else {
            return RawPowerSourceSnapshot(hasBattery: false, isPresent: false, timeRemainingEstimate: estimate)
        }

        let isPresent = (desc[kIOPSIsPresentKey as String] as? Bool) ?? ((desc[kIOPSIsPresentKey as String] as? NSNumber)?.boolValue ?? true)
        let state = desc[kIOPSPowerSourceStateKey as String] as? String
        let currentCap = (desc[kIOPSCurrentCapacityKey as String] as? NSNumber)?.intValue
        let maxCap = (desc[kIOPSMaxCapacityKey as String] as? NSNumber)?.intValue
        let isCharging = (desc[kIOPSIsChargingKey as String] as? Bool) ?? ((desc[kIOPSIsChargingKey as String] as? NSNumber)?.boolValue)
        let isCharged = (desc[kIOPSIsChargedKey as String] as? Bool) ?? ((desc[kIOPSIsChargedKey as String] as? NSNumber)?.boolValue)
        let timeToEmpty = (desc[kIOPSTimeToEmptyKey as String] as? NSNumber)?.intValue
        let timeToFull = (desc[kIOPSTimeToFullChargeKey as String] as? NSNumber)?.intValue
        let transportType = desc[kIOPSTransportTypeKey as String] as? String
        let type = desc[kIOPSTypeKey as String] as? String

        return RawPowerSourceSnapshot(
            hasBattery: true,
            isPresent: isPresent,
            powerSourceState: state,
            currentCapacity: currentCap,
            maxCapacity: maxCap,
            isCharging: isCharging,
            isCharged: isCharged,
            timeToEmpty: timeToEmpty,
            timeToFullCharge: timeToFull,
            timeRemainingEstimate: estimate,
            transportType: transportType,
            type: type
        )
    }

    public func smartBatteryData() throws -> RawSmartBatteryData? {
        var iterator: io_iterator_t = 0
        let matchingDict = IOServiceMatching("AppleSmartBattery")
        guard let matchingDict = matchingDict else {
            return nil
        }

        let result = IOServiceGetMatchingServices(kIOMainPortDefault, matchingDict, &iterator)
        guard result == KERN_SUCCESS, iterator != 0 else {
            return nil
        }
        defer { IOObjectRelease(iterator) }

        guard case let entry = IOIteratorNext(iterator), entry != 0 else {
            return nil
        }
        defer { IOObjectRelease(entry) }

        var propsRef: Unmanaged<CFMutableDictionary>?
        let propResult = IORegistryEntryCreateCFProperties(entry, &propsRef, kCFAllocatorDefault, 0)
        guard propResult == KERN_SUCCESS, let props = propsRef?.takeRetainedValue() as? [String: Any] else {
            return nil
        }

        let batteryData = props["BatteryData"] as? [String: Any]

        // 1. Cycle Count
        let cycleCount = (props["CycleCount"] as? NSNumber)?.intValue
            ?? (batteryData?["CycleCount"] as? NSNumber)?.intValue

        // 2. Condition
        var condition: String? = props["Condition"] as? String
        if condition == nil {
            let permFail = (props["PermanentFailureStatus"] as? NSNumber)?.intValue
                ?? (batteryData?["PermanentFailureStatus"] as? NSNumber)?.intValue
            if let permFail = permFail {
                condition = permFail == 0 ? "Normal" : "Service Battery"
            } else if props["BatteryInstalled"] != nil || batteryData != nil {
                condition = "Normal"
            }
        }

        // 3. Design Capacity
        let designCapacity = (batteryData?["DesignCapacity"] as? NSNumber)?.intValue
            ?? (props["DesignCapacity"] as? NSNumber)?.intValue

        // 4. Current Maximum Capacity (mAh)
        let currentMaxCapacity = (batteryData?["NominalChargeCapacity"] as? NSNumber)?.intValue
            ?? (batteryData?["FullChargeCapacity"] as? NSNumber)?.intValue
            ?? (batteryData?["AppleRawMaxCapacity"] as? NSNumber)?.intValue
            ?? (props["AppleRawMaxCapacity"] as? NSNumber)?.intValue

        // 5. Adapter Watts
        var adapterWatts: Double? = nil
        let isConnected = (props["ExternalConnected"] as? NSNumber)?.boolValue
            ?? (props["AppleRawExternalConnected"] as? NSNumber)?.boolValue
            ?? (props["AdapterDetails"] != nil)

        if isConnected {
            if let adapterDetails = props["AdapterDetails"] as? [String: Any],
               let watts = (adapterDetails["Watts"] as? NSNumber)?.doubleValue, watts > 0 {
                adapterWatts = watts
            } else if let powerDist = props["PowerDistribution"] as? [String: Any],
                      let ipdPowerMW = (powerDist["IPDInputPower"] as? NSNumber)?.doubleValue, ipdPowerMW > 0 {
                adapterWatts = ipdPowerMW / 1000.0
            } else if let rawWatts = (props["Watts"] as? NSNumber)?.doubleValue, rawWatts > 0 {
                adapterWatts = rawWatts
            }
        }

        // 6. Power Draw Watts
        var powerDrawWatts: Double? = nil
        if let telemetry = props["PowerTelemetryData"] as? [String: Any] {
            if let systemLoadMW = (telemetry["SystemLoad"] as? NSNumber)?.doubleValue, systemLoadMW > 0 {
                powerDrawWatts = systemLoadMW / 1000.0
            } else if let systemPowerInMW = (telemetry["SystemPowerIn"] as? NSNumber)?.doubleValue, systemPowerInMW > 0 {
                powerDrawWatts = systemPowerInMW / 1000.0
            } else if let systemEnergyMW = (telemetry["SystemEnergyConsumed"] as? NSNumber)?.doubleValue, systemEnergyMW > 0 {
                powerDrawWatts = systemEnergyMW / 1000.0
            }
        }

        if powerDrawWatts == nil {
            let amperage = (props["InstantAmperage"] as? NSNumber)?.doubleValue
                ?? (props["Amperage"] as? NSNumber)?.doubleValue
                ?? (batteryData?["Amperage"] as? NSNumber)?.doubleValue
                ?? (batteryData?["InstantAmperage"] as? NSNumber)?.doubleValue
            let voltage = (props["Voltage"] as? NSNumber)?.doubleValue
                ?? (props["AppleRawBatteryVoltage"] as? NSNumber)?.doubleValue
                ?? (batteryData?["Voltage"] as? NSNumber)?.doubleValue

            if let amp = amperage, let volt = voltage, amp != 0, volt > 0 {
                let watts = abs(amp * volt) / 1_000_000.0
                if watts > 0 {
                    powerDrawWatts = watts
                }
            }
        }

        return RawSmartBatteryData(
            cycleCount: cycleCount,
            condition: condition,
            designCapacity: designCapacity,
            currentMaxCapacity: currentMaxCapacity,
            adapterWatts: adapterWatts,
            powerDrawWatts: powerDrawWatts
        )
    }
}

/// Concrete sampler for battery and power metrics.
///
/// Conforms to `Sampler` (Requirements 8.1, 8.2, 8.3, 8.4). Reads `IOPowerSources` for charge/state/time,
/// `AppleSmartBattery` for health and wattage, running all IOKit calls in background work.
public final class PowerSampler: Sampler, @unchecked Sendable {
    public let category: MetricCategory = .power

    private let provider: any PowerInfoProvider

    public init(provider: any PowerInfoProvider = HostPowerInfoProvider()) {
        self.provider = provider
    }

    /// Samples battery and power metrics. Runs off the main thread.
    public func sample() throws -> PowerSample {
        let powerSource = try provider.powerSourceSnapshot()
        let smartBattery = try? provider.smartBatteryData()

        return Self.calculateSample(
            powerSource: powerSource,
            smartBattery: smartBattery
        )
    }

    /// Pure calculation function deriving `PowerSample` from raw power source and smart battery data.
    public static func calculateSample(
        powerSource: RawPowerSourceSnapshot,
        smartBattery: RawSmartBatteryData? = nil
    ) -> PowerSample {
        guard powerSource.hasBattery && powerSource.isPresent else {
            return PowerSample(
                hasBattery: false,
                charge: nil,
                state: nil,
                timeRemaining: nil,
                cycleCount: nil,
                condition: nil,
                designCapacity: nil,
                currentMaxCapacity: nil,
                powerDrawWatts: smartBattery?.powerDrawWatts,
                adapterWatts: smartBattery?.adapterWatts
            )
        }

        // 1. Charge percentage (0...100)
        var charge: Double? = nil
        if let cur = powerSource.currentCapacity, let maxCap = powerSource.maxCapacity, maxCap > 0 {
            charge = min(100.0, Swift.max(0.0, (Double(cur) / Double(maxCap)) * 100.0))
        } else if let cur = powerSource.currentCapacity {
            charge = min(100.0, Swift.max(0.0, Double(cur)))
        }

        // 2. Battery State
        let isCharging = powerSource.isCharging ?? false
        let isAC = powerSource.powerSourceState == (kIOPSACPowerValue as String)
        let isChargedExplicit = powerSource.isCharged ?? false
        let isFullyCharged = (isChargedExplicit || (charge != nil && charge! >= 99.0)) && isAC && !isCharging

        let state: BatteryState
        if isCharging {
            state = .charging
        } else if isFullyCharged && (charge == nil || charge! >= 99.0) {
            state = .charged
        } else if isAC {
            state = .acConnected
        } else if powerSource.powerSourceState == (kIOPSBatteryPowerValue as String) {
            state = .discharging
        } else {
            state = .unknown
        }

        // 3. Time remaining in seconds
        var timeRemaining: TimeInterval? = nil
        switch state {
        case .discharging:
            if let est = powerSource.timeRemainingEstimate, est > 0 {
                timeRemaining = est
            } else if let toEmpty = powerSource.timeToEmpty, toEmpty > 0 {
                timeRemaining = TimeInterval(toEmpty * 60)
            } else {
                timeRemaining = nil
            }
        case .charging:
            if let toFull = powerSource.timeToFullCharge, toFull > 0 {
                timeRemaining = TimeInterval(toFull * 60)
            } else {
                timeRemaining = nil
            }
        case .charged, .acConnected, .unknown:
            timeRemaining = nil
        }

        return PowerSample(
            hasBattery: true,
            charge: charge,
            state: state,
            timeRemaining: timeRemaining,
            cycleCount: smartBattery?.cycleCount,
            condition: smartBattery?.condition,
            designCapacity: smartBattery?.designCapacity,
            currentMaxCapacity: smartBattery?.currentMaxCapacity,
            powerDrawWatts: smartBattery?.powerDrawWatts,
            adapterWatts: smartBattery?.adapterWatts
        )
    }
}
