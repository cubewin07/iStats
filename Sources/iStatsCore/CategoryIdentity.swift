import Foundation

/// Runtime state that refines a category's identity symbol (battery level, interface kind, ...).
/// A `nil` field means "unknown", and `CategoryIdentity.liveSymbol` falls back to the identity symbol.
public struct LiveSymbolState: Sendable, Equatable {
    /// Battery charge 0...100.
    public var batteryChargePercent: Double?
    public var isCharging: Bool
    /// Active primary network interface kind.
    public var connectionType: NetworkConnectionType?
    /// True for an external volume, false for the boot/internal one.
    public var isExternalVolume: Bool?
    /// Hottest sensor in Celsius.
    public var thermalPeakCelsius: Double?
    /// True when the Mac has no fans.
    public var isFanless: Bool?

    public init(
        batteryChargePercent: Double? = nil,
        isCharging: Bool = false,
        connectionType: NetworkConnectionType? = nil,
        isExternalVolume: Bool? = nil,
        thermalPeakCelsius: Double? = nil,
        isFanless: Bool? = nil
    ) {
        self.batteryChargePercent = batteryChargePercent
        self.isCharging = isCharging
        self.connectionType = connectionType
        self.isExternalVolume = isExternalVolume
        self.thermalPeakCelsius = thermalPeakCelsius
        self.isFanless = isFanless
    }
}

/// Single source of a category's display name, short label, identity symbol and live symbol (ADR 0011).
public struct CategoryIdentity: Sendable, Equatable {
    public let category: MetricCategory

    public init(_ category: MetricCategory) {
        self.category = category
    }

    public func displayName(hasBattery: Bool = true) -> String {
        switch category {
        case .cpu: return "CPU"
        case .memory: return "Memory"
        case .thermal: return "Temperature"
        case .fan: return "Fans"
        case .gpu: return "GPU"
        case .network: return "Network"
        case .disk: return "Disk"
        case .power: return hasBattery ? "Battery" : "Power"
        }
    }

    /// 3-letter widget label.
    public func shortLabel(hasBattery: Bool = true) -> String {
        switch category {
        case .cpu: return "CPU"
        case .memory: return "MEM"
        case .thermal: return "TMP"
        case .fan: return "FAN"
        case .gpu: return "GPU"
        case .network: return "NET"
        case .disk: return "SSD"
        case .power: return hasBattery ? "BAT" : "PWR"
        }
    }

    /// Stable identity symbol used by the strip, Settings and alerts.
    public func symbol(hasBattery: Bool = true) -> String {
        switch category {
        case .cpu: return "cpu"
        case .memory: return "memorychip"
        case .thermal: return "thermometer.medium"
        case .fan: return "fan"
        case .gpu: return "cube.transparent"
        case .network: return "network"
        case .disk: return "internaldrive"
        case .power: return hasBattery ? "battery.100percent" : "powerplug"
        }
    }

    /// State-dependent symbol; falls back to `symbol(hasBattery:)` when the relevant state is unknown.
    public func liveSymbol(_ state: LiveSymbolState, hasBattery: Bool = true) -> String {
        switch category {
        case .power:
            guard hasBattery, let charge = state.batteryChargePercent else {
                return symbol(hasBattery: hasBattery)
            }
            if state.isCharging { return "battery.100percent.bolt" }
            switch charge {
            case ..<12.5: return "battery.0percent"
            case ..<37.5: return "battery.25percent"
            case ..<62.5: return "battery.50percent"
            case ..<87.5: return "battery.75percent"
            default: return "battery.100percent"
            }
        case .thermal:
            guard let peak = state.thermalPeakCelsius else { return symbol() }
            if peak >= 75 { return "thermometer.high" }
            if peak >= 55 { return "thermometer.medium" }
            return "thermometer.low"
        case .fan:
            return state.isFanless == true ? "fan.slash" : symbol()
        case .network:
            guard let type = state.connectionType else { return symbol() }
            return type.iconName
        case .disk:
            guard let external = state.isExternalVolume else { return symbol() }
            return external ? "externaldrive.fill" : "internaldrive.fill"
        case .cpu, .memory, .gpu:
            return symbol()
        }
    }

    /// Every symbol this identity can produce (used by the symbol-availability test).
    public var allSymbols: [String] {
        switch category {
        case .power:
            return ["battery.100percent", "powerplug", "battery.0percent", "battery.25percent",
                    "battery.50percent", "battery.75percent", "battery.100percent.bolt"]
        case .thermal: return ["thermometer.low", "thermometer.medium", "thermometer.high"]
        case .fan: return ["fan", "fan.slash"]
        case .network: return NetworkConnectionType.allCases.map(\.iconName) + [symbol()]
        case .disk: return ["internaldrive", "internaldrive.fill", "externaldrive.fill"]
        case .cpu, .memory, .gpu: return [symbol()]
        }
    }
}

extension MetricCategory {
    public var identity: CategoryIdentity { CategoryIdentity(self) }
}

extension StatusLevel {
    /// Filled variant for chips and ribbons; `symbolName` is the plain variant.
    public var symbolNameFilled: String { symbolName + ".fill" }
}
