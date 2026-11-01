import Foundation

/// Calculated node power flow in watts and particle propagation rates (Task 8.8h / ADR 0009).
public struct PowerFlow: Equatable, Sendable {
    /// Watts flowing from the power adapter to the Mac system.
    public let adapterToMac: Double?

    /// Watts flowing from the power adapter into the battery (charging).
    public let adapterToBattery: Double?

    /// Watts flowing from the battery to the Mac system (discharging or deficit assisting).
    public let batteryToMac: Double?

    /// Net battery wattage (positive = charging, negative = discharging).
    public let batteryNetWatts: Double?

    public var speedAdapterToMac: Double {
        PowerFlowMath.particleSpeed(watts: adapterToMac ?? 0)
    }

    public var speedAdapterToBattery: Double {
        PowerFlowMath.particleSpeed(watts: adapterToBattery ?? 0)
    }

    public var speedBatteryToMac: Double {
        PowerFlowMath.particleSpeed(watts: batteryToMac ?? 0)
    }

    public init(
        adapterToMac: Double? = nil,
        adapterToBattery: Double? = nil,
        batteryToMac: Double? = nil,
        batteryNetWatts: Double? = nil
    ) {
        self.adapterToMac = adapterToMac
        self.adapterToBattery = adapterToBattery
        self.batteryToMac = batteryToMac
        self.batteryNetWatts = batteryNetWatts
    }
}

/// Pure mathematical calculation of 3-node power flow.
public enum PowerFlowMath {

    /// Normalizes watt load to particle animation speed clamped to [0.1, 1.0].
    public static func particleSpeed(watts: Double) -> Double {
        guard watts > 0 else { return 0.0 }
        let raw = log1p(watts) / log1p(100.0)
        return min(1.0, max(0.1, raw))
    }

    /// Evaluates the 3-node power topology from raw hardware metrics.
    public static func calculateFlow(
        hasBattery: Bool,
        state: BatteryState?,
        adapterWatts: Double?,
        powerDrawWatts: Double?,
        voltageVolts: Double?,
        amperageMilliAmps: Double?
    ) -> PowerFlow {
        // 1. Desktop Mac (No battery)
        guard hasBattery else {
            let toMac = powerDrawWatts ?? adapterWatts
            return PowerFlow(
                adapterToMac: toMac,
                adapterToBattery: nil,
                batteryToMac: nil,
                batteryNetWatts: nil
            )
        }

        // Calculate battery net wattage if voltage and amperage are present
        let netWatts: Double? = {
            guard let v = voltageVolts, let a = amperageMilliAmps else { return nil }
            return (v * a) / 1000.0
        }()

        let isConnectedToAC = (adapterWatts != nil && adapterWatts! > 0) || state == .charging || state == .acConnected || state == .charged

        // 2. Pure Battery Discharging (no AC connection)
        if !isConnectedToAC || state == .discharging {
            let toMac: Double? = {
                if let draw = powerDrawWatts, draw > 0 { return draw }
                if let net = netWatts, net < 0 { return abs(net) }
                return nil
            }()
            return PowerFlow(
                adapterToMac: nil,
                adapterToBattery: nil,
                batteryToMac: toMac,
                batteryNetWatts: netWatts
            )
        }

        // 3. Power Deficit: Connected to AC, but system power draw exceeds adapter capacity
        let isDeficit: Bool = {
            if let adapter = adapterWatts, adapter > 0, let draw = powerDrawWatts, draw > (adapter + 1.0) {
                return true
            }
            if let a = amperageMilliAmps, a < -200.0 {
                return true
            }
            return false
        }()

        if isDeficit {
            let adapterToMac = adapterWatts ?? powerDrawWatts
            let batteryToMac: Double? = {
                if let net = netWatts, net < 0 { return abs(net) }
                if let draw = powerDrawWatts, let adapter = adapterWatts, draw > adapter {
                    return draw - adapter
                }
                return nil
            }()
            return PowerFlow(
                adapterToMac: adapterToMac,
                adapterToBattery: nil,
                batteryToMac: batteryToMac,
                batteryNetWatts: netWatts
            )
        }

        // 4. Charging / On AC
        let adapterToBattery: Double? = {
            if let net = netWatts, net > 0.05 {
                return net
            }
            if state == .charging, let adapter = adapterWatts, let draw = powerDrawWatts, adapter > draw {
                return adapter - draw
            }
            return nil
        }()

        let adapterToMac: Double? = {
            if let draw = powerDrawWatts, draw > 0 {
                return draw
            }
            if let adapter = adapterWatts {
                if let batt = adapterToBattery, adapter > batt {
                    return adapter - batt
                }
                return adapter
            }
            return nil
        }()

        return PowerFlow(
            adapterToMac: adapterToMac,
            adapterToBattery: adapterToBattery,
            batteryToMac: nil,
            batteryNetWatts: netWatts
        )
    }
}
