import Foundation

/// A copyable, telemetry-free description of the app and machine for bug reports (ADR 0006).
///
/// Contains the Mac model, macOS version, app version and each sampler's `Availability`.
/// It never contains a metric value (no temperatures, usage, network or process data).
public struct DiagnosticsReport: Sendable, Equatable {
    public var appVersion: String
    public var build: String
    public var hardwareModel: String
    public var architecture: String
    public var osVersion: String
    public var samplers: [(category: MetricCategory, availability: Availability?)]

    public init(
        appVersion: String,
        build: String,
        hardwareModel: String,
        architecture: String,
        osVersion: String,
        availability: [MetricCategory: Availability]
    ) {
        self.appVersion = appVersion
        self.build = build
        self.hardwareModel = hardwareModel
        self.architecture = architecture
        self.osVersion = osVersion
        self.samplers = MetricCategory.allCases.map { ($0, availability[$0]) }
    }

    public static func == (lhs: DiagnosticsReport, rhs: DiagnosticsReport) -> Bool {
        lhs.appVersion == rhs.appVersion && lhs.build == rhs.build
            && lhs.hardwareModel == rhs.hardwareModel && lhs.architecture == rhs.architecture
            && lhs.osVersion == rhs.osVersion
            && lhs.samplers.count == rhs.samplers.count
            && zip(lhs.samplers, rhs.samplers).allSatisfy { $0.category == $1.category && $0.availability == $1.availability }
    }

    public func render() -> String {
        var lines = [
            "iStats Diagnostics",
            "App: \(appVersion) (\(build))",
            "Mac: \(hardwareModel) (\(architecture))",
            "macOS: \(osVersion)",
            "Samplers:"
        ]
        for sampler in samplers {
            let state: String
            switch sampler.availability {
            case .some(.available): state = "available"
            case .some(.unavailable(let reason)): state = "unavailable (\(reason))"
            case .none: state = "no reading yet"
            }
            lines.append("  \(sampler.category.rawValue): \(state)")
        }
        return lines.joined(separator: "\n")
    }

    /// Builds the report for this process. Reads `sysctl hw.model`, so call it off the main thread.
    public static func current(
        availability: [MetricCategory: Availability],
        bundle: Bundle = .main
    ) -> DiagnosticsReport {
        let info = bundle.infoDictionary
        return DiagnosticsReport(
            appVersion: info?["CFBundleShortVersionString"] as? String ?? "unknown",
            build: info?["CFBundleVersion"] as? String ?? "unknown",
            hardwareModel: readHardwareModel(),
            architecture: currentArchitecture,
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            availability: availability
        )
    }

    public static var currentArchitecture: String {
        #if arch(arm64)
        return "arm64"
        #elseif arch(x86_64)
        return "x86_64"
        #else
        return "unknown"
        #endif
    }

    /// `hw.model` such as "Mac14,2", or "unknown" when the read is denied.
    public static func readHardwareModel() -> String {
        var size = 0
        guard sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 1 else { return "unknown" }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname("hw.model", &buffer, &size, nil, 0) == 0 else { return "unknown" }
        let bytes = buffer.prefix { $0 != 0 }.map(UInt8.init(bitPattern:))
        return bytes.isEmpty ? "unknown" : String(decoding: bytes, as: UTF8.self)
    }
}
