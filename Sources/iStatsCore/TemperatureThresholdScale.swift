import Foundation

/// Slider geometry for the temperature alert threshold, in the user's display unit.
///
/// The threshold is stored in Celsius (60...105). Stepping a slider in raw Celsius while showing
/// Fahrenheit gives uneven, non-round labels, so the slider works in display units and converts back.
public enum TemperatureThresholdScale {
    /// Display-unit slider bounds: 60...105 °C or 140...220 °F.
    public static func range(unit: Units.TemperatureUnit) -> ClosedRange<Double> {
        switch unit {
        case .celsius: return 60.0...105.0
        case .fahrenheit: return 140.0...220.0
        }
    }

    /// Display-unit step: 5 °C or 10 °F.
    public static func step(unit: Units.TemperatureUnit) -> Double {
        unit == .celsius ? 5.0 : 10.0
    }

    public static func displayValue(celsius: Double, unit: Units.TemperatureUnit) -> Double {
        let value = unit == .fahrenheit ? Units.celsiusToFahrenheit(celsius) : celsius
        let bounds = range(unit: unit)
        return min(max(value, bounds.lowerBound), bounds.upperBound)
    }

    /// Converts a slider value to the stored Celsius threshold, clamped to the rule's valid range.
    public static func celsius(fromDisplay value: Double, unit: Units.TemperatureUnit) -> Double {
        let bounds = range(unit: unit)
        let clamped = min(max(value, bounds.lowerBound), bounds.upperBound)
        let celsius = unit == .fahrenheit ? Units.fahrenheitToCelsius(clamped) : clamped
        let valid = AlertKind.temperature.thresholdRange
        return min(max(celsius, valid.lowerBound), valid.upperBound)
    }
}
