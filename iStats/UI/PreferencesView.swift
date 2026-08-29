import SwiftUI
import iStatsCore

/// A macOS preferences window view allowing configuration of sampling intervals,
/// per-category menu bar widgets, display units, and system behavior (Requirements 11.1-11.4, ADR 0007).
public struct PreferencesView: View {
    @ObservedObject public var store: PreferencesStore
    @ObservedObject public var coordinator: MetricsCoordinator

    private let presetIntervals: [TimeInterval] = [0.5, 1.0, 2.0, 5.0, 10.0, 30.0, 60.0]

    public init(
        store: PreferencesStore = .shared,
        coordinator: MetricsCoordinator = .shared
    ) {
        self.store = store
        self.coordinator = coordinator
    }

    public var body: some View {
        TabView {
            generalTab
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }
                .tag(0)

            menuBarTab
                .tabItem {
                    Label("Menu Bar", systemImage: "menubar.rectangle")
                }
                .tag(1)

            unitsTab
                .tabItem {
                    Label("Units", systemImage: "ruler")
                }
                .tag(2)

            aboutTab
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
                .tag(3)
        }
        .frame(width: 560, height: 480)
        .padding(16)
    }

    // MARK: - General Tab

    private var generalTab: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Sampling Refresh Interval:")
                            .font(.headline)
                        Spacer()
                        Text(String(format: "%.1f s", store.refreshInterval))
                            .font(.system(.body, design: .monospaced))
                            .fontWeight(.semibold)
                            .foregroundColor(.accentColor)
                    }

                    // Continuous Slider bounded to [minRefreshInterval, maxRefreshInterval]
                    Slider(
                        value: $store.refreshInterval,
                        in: PreferencesStore.minRefreshInterval...PreferencesStore.maxRefreshInterval,
                        step: 0.5
                    ) {
                        Text("Refresh Interval")
                    } minimumValueLabel: {
                        Text("0.5s")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    } maximumValueLabel: {
                        Text("60s")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                    // Preset Buttons
                    HStack(spacing: 6) {
                        Text("Presets:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        ForEach(presetIntervals, id: \.self) { preset in
                            Button(action: {
                                store.refreshInterval = preset
                            }) {
                                Text(preset < 1.0 ? "\(preset, specifier: "%.1f")s" : "\(Int(preset))s")
                                    .font(.caption)
                            }
                            .buttonStyle(.bordered)
                            .tint(store.refreshInterval == preset ? .accentColor : nil)
                        }
                    }

                    Text("Higher refresh intervals reduce CPU overhead and power consumption (Requirement 12.4).")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
            } header: {
                Text("Performance & Scheduling")
            }

            Divider()
                .padding(.vertical, 6)

            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("Show Dock Icon", isOn: $store.showDockIcon)
                        .onChange(of: store.showDockIcon) { newValue in
                            DockIconManager.shared.setDockIconVisible(newValue)
                        }

                    Text("When disabled, iStats runs as a lightweight menu bar accessory app without a Dock icon.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Toggle("Launch at Login", isOn: $store.launchAtLogin)
                        .onChange(of: store.launchAtLogin) { newValue in
                            LaunchAtLoginManager.shared.setLaunchAtLogin(enabled: newValue)
                        }

                    Text("Automatically start iStats in the background when logging into macOS.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
            } header: {
                Text("App Behavior")
            }

            Divider()
                .padding(.vertical, 6)

            HStack {
                Spacer()
                Button("Reset to Defaults", role: .destructive) {
                    store.resetToDefaults()
                    DockIconManager.shared.setDockIconVisible(store.showDockIcon)
                    LaunchAtLoginManager.shared.setLaunchAtLogin(enabled: store.launchAtLogin)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Menu Bar Tab (ADR 0007)

    private var menuBarTab: some View {
        Form {
            Section {
                List {
                    ForEach(MetricCategory.allCases, id: \.self) { category in
                        VStack(alignment: .leading, spacing: 10) {
                            // Category Row & Master Toggle
                            HStack(spacing: 12) {
                                Image(systemName: iconName(for: category))
                                    .frame(width: 24)
                                    .foregroundColor(.accentColor)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(category.displayName)
                                        .font(.body)
                                        .fontWeight(.semibold)
                                    Text(categoryDescription(for: category))
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                Toggle("", isOn: Binding(
                                    get: { store.isCategoryEnabled(category) },
                                    set: { store.setCategory(category, isEnabled: $0) }
                                ))
                                .labelsHidden()
                            }

                            // Available Widget Styles with Live Previews
                            if store.isCategoryEnabled(category) {
                                let hasBattery = coordinator.latestPower?.value.hasBattery ?? true
                                VStack(spacing: 8) {
                                    ForEach(MetricDisplayStyle.supportedStyles(for: category, hasBattery: hasBattery)) { style in
                                        widgetStyleRow(category: category, style: style)
                                    }
                                }
                                .padding(.leading, 36)
                            }
                        }
                        .padding(.vertical, 6)
                    }
                }
            } header: {
                Text("Customizable Menu Bar Icons & Widgets")
            } footer: {
                Text("Live previews reflect real-time telemetry. Toggle any widget style to show it in your macOS menu bar. Clicking any item opens its popover.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func widgetStyleRow(category: MetricCategory, style: MetricDisplayStyle) -> some View {
        let renderResult = MenuBarIconRenderer.render(
            config: MenuBarItemConfig(category: category, style: style),
            coordinator: coordinator,
            preferences: store
        )

        return HStack(spacing: 12) {
            // Live Preview Badge
            HStack(spacing: 5) {
                if let img = renderResult.image {
                    Image(nsImage: img)
                        .renderingMode(img.isTemplate ? .template : .original)
                }
                if !renderResult.title.isEmpty {
                    Text(renderResult.title)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .frame(minWidth: 48, minHeight: 22)
            .background(Color.secondary.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 2) {
                Text(style.displayName(for: category))
                    .font(.subheadline)
                    .fontWeight(.medium)
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { store.isItemEnabled(category: category, style: style) },
                set: { store.setItemEnabled(category: category, style: style, isEnabled: $0) }
            ))
            .toggleStyle(.switch)
            .controlSize(.small)
            .labelsHidden()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(8)
    }

    // MARK: - Units Tab

    private var unitsTab: some View {
        Form {
            Section {
                Picker("Temperature Unit", selection: $store.temperatureUnit) {
                    ForEach(Units.TemperatureUnit.allCases) { unit in
                        Text(unit.displayName).tag(unit)
                    }
                }
                .pickerStyle(.menu)

                Picker("Network Rate Unit", selection: $store.networkUnit) {
                    ForEach(Units.NetworkUnit.allCases) { unit in
                        Text(unit.displayName).tag(unit)
                    }
                }
                .pickerStyle(.menu)

                Picker("Data Size Standard", selection: $store.byteUnitStandard) {
                    ForEach(Units.ByteUnitStandard.allCases) { standard in
                        Text(standard.displayName).tag(standard)
                    }
                }
                .pickerStyle(.menu)
            } header: {
                Text("Display Formatting")
            } footer: {
                Text("Applies globally across all menu bar items and popovers.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - About Tab

    private var aboutTab: some View {
        VStack(spacing: 16) {
            Image(systemName: "gauge.with.dots.needle.bottom.50percent")
                .font(.system(size: 48))
                .foregroundColor(.accentColor)

            VStack(spacing: 4) {
                Text("iStats")
                    .font(.title2)
                    .fontWeight(.bold)
                Text("Version 0.1.0")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Divider()
                .frame(width: 300)

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "lock.shield")
                        .foregroundColor(.green)
                    Text("Privacy First: All telemetry stays on-device in memory only. No data is ever persisted to disk or transmitted across the network (ADR 0006).")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "bolt.badge.clock")
                        .foregroundColor(.orange)
                    Text("Resource Conscious: All OS samplers run on dedicated background queues and respect configured refresh intervals.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: 400)
            .padding(.vertical, 8)

            Spacer()
        }
        .padding(.top, 24)
    }

    // MARK: - Category Helpers

    private func iconName(for category: MetricCategory) -> String {
        switch category {
        case .cpu: return "cpu"
        case .memory: return "memorychip"
        case .thermal: return "thermometer.medium"
        case .fan: return "fan"
        case .gpu: return "display"
        case .network: return "network"
        case .disk: return "internaldrive"
        case .power: return "bolt.fill"
        }
    }

    private func styleIcon(for style: MetricDisplayStyle) -> String {
        switch style {
        case .symbol: return "star"
        case .gauge: return "gauge.medium"
        case .bar: return "chart.bar.fill"
        case .sparkline: return "chart.xyaxis.line"
        case .text: return "textformat.123"
        case .throughput: return "arrow.up.arrow.down"
        }
    }

    private func categoryDescription(for category: MetricCategory) -> String {
        switch category {
        case .cpu: return "Processor utilization, load averages, and core usage."
        case .memory: return "RAM breakdown (active, wired, compressed) and pressure."
        case .thermal: return "SoC temperatures and thermal pressure level."
        case .fan: return "Fan speeds and cooling system status."
        case .gpu: return "GPU core utilization and renderer metrics."
        case .network: return "Real-time interface throughput and bandwidth."
        case .disk: return "Disk I/O operations and volume space capacity."
        case .power: return "Battery status, health, and power consumption."
        }
    }
}
