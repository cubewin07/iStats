# Stage 2 Technical Design & TDD Plan: Persistent IOKit & Hardware Caching

**Branch:** `perf/energy-optimization`  
**Target:** `iStats/Sampling/` (`AppleSMCClient.swift`, `FanSampler.swift`, `ThermalSampler.swift`, `GPUSampler.swift`, `NetworkSampler.swift`)  
**Test Suite:** `Tests/iStatsTests/PersistentSMCAndHardwareCachingTests.swift`  
**Status:** In Progress (TDD Phase: Tests & Design First)

---

## 1. Problem Statement & Objectives

### Identified Overheads in Stage 2
1. **AppleSMC Connection Churn:**
   Every 2-second tick, three separate samplers independently connect to `AppleSMC`:
   - [`FanSampler.swift`](/iStats/Sampling/FanSampler.swift#L43-L48): `openSMCConnection()` $\to$ read $\to$ `IOServiceClose`
   - [`ThermalSampler.swift`](/iStats/Sampling/ThermalSampler.swift#L364-L376): `readAppleSMCThermals()` $\to$ `IOServiceOpen` $\to$ read $\to$ `IOServiceClose`
   - [`GPUSampler.swift`](/iStats/Sampling/GPUSampler.swift#L289-L298): `readSMCGPUTemperature()` $\to$ `IOServiceOpen` $\to$ read $\to$ `IOServiceClose`
   
   Every `IOServiceOpen` invokes Mach IPC to allocate a new kernel user-client instance, create Mach ports, and map structures, only to discard them milliseconds later.
2. **Redundant Metal Framework Instantiation:**
   In [`GPUSampler.swift:227`](/iStats/Sampling/GPUSampler.swift#L227), `MTLCopyAllDevices()` is invoked on every single sample tick. This allocates Metal runtime objects for a hardware configuration that never changes during runtime.
3. **Display Subsystem Polling:**
   In [`GPUSampler.swift:237`](/iStats/Sampling/GPUSampler.swift#L237), `NSScreen.screens` and `CGDisplayCopyDisplayMode` query CoreGraphics display modes every 2 seconds.
4. **SystemConfiguration IPC Overhead:**
   In [`NetworkSampler.swift:187`](/iStats/Sampling/NetworkSampler.swift#L187), `SCDynamicStoreCreate` establishes a new session with `configd` on every sample.
5. **Continuous Active Wi-Fi Hardware Polling:**
   In [`NetworkSampler.swift:220`](/iStats/Sampling/NetworkSampler.swift#L220), `CWWiFiClient` polls RSSI, noise, and transmission rate every 2s, forcing the wireless driver and `airportd` daemon to stay active.

### Stage 2 Goals
1. **Persistent `AppleSMCClient`:** Maintain a single, persistent, thread-safe `io_connect_t` to `AppleSMC` shared across `FanSampler`, `ThermalSampler`, and `GPUSampler`.
2. **Self-Healing Reconnection:** Automatically detect stale connections (e.g. after system wake from sleep) and reconnect transparently.
3. **Static Hardware Metadata Caching:** Cache `MTLDevice` reference, GPU device name, and display resolution string. Refresh display modes only on change or throttled cadence.
4. **Network IPC Caching & Wi-Fi Throttling:** Persist the `SCDynamicStore` reference; throttle Wi-Fi signal/noise polling to every ~10s while retaining real-time byte counters at 2s.

---

## 2. Technical Architecture

### 2.1 Shared `AppleSMCClient`
A centralized, thread-safe client manages the IOKit `AppleSMC` user client:
```swift
public final class AppleSMCClient: @unchecked Sendable {
    public static let shared = AppleSMCClient()

    private let lock = NSLock()
    private var connection: io_connect_t = 0
    ...
}
```
- **Connection Reuse:** Once opened, the connection is held open across sampling ticks.
- **Unified Key Decoding:** Centralizes four-character key conversion and data format parsing (`flt`, `sp78`, `fpe2`, `ui8`, `ui16`, `ui32`, `ch8*`).
- **Resilience:** If `IOConnectCallStructMethod` returns `kIOReturnNotResponding` or `kIOReturnNoDevice`, the client invalidates the handle and automatically re-opens the user client on the next query.

### 2.2 Hardware & Display Caching in `GPUSampler`
- Cache `MTLCopyAllDevices().first` in a static/lazy property.
- Cache `queryConnectedDisplays()` with a 30-second TTL (Time-To-Live) or refresh on screen parameter notifications.

### 2.3 Throttled Telemetry in `NetworkSampler`
- Keep `interfaceCounters()` running at full sampling frequency (real-time byte rates).
- Cache `networkConnectivity()` (primary interface, router IP, Wi-Fi RSSI/noise) with a 5-tick cooldown (~10s) or refresh on dynamic store notification, preventing `airportd` driver wakeups on every tick.

---

## 3. Test-Driven Development (TDD) Specification

The following tests will be implemented in `Tests/iStatsTests/PersistentSMCAndHardwareCachingTests.swift`:

| Test Name | Specification |
| :--- | :--- |
| `testAppleSMCClientMaintainsSinglePersistentConnection` | Perform multiple consecutive key reads. Assert that the underlying `io_connect_t` remains open and unchanged between reads. |
| `testAppleSMCClientInvalidateAndReconnect` | Explicitly invalidate the active connection. Assert that the subsequent read cleanly reopens a valid connection and returns data. |
| `testFanSamplerReusesPersistentSMC` | Multiple calls to `FanSampler.sample()` execute successfully without opening and closing IOKit connections per call. |
| `testGPUSamplerCachesMetalDeviceAndDisplays` | Execute consecutive GPU samples. Verify that static device name and display descriptions remain stable and cached without re-invoking `MTLCopyAllDevices`. |
| `testNetworkSamplerThrottlesWiFiTelemetry` | Execute 5 consecutive `NetworkSampler` reads. Verify byte counters update every tick while Wi-Fi telemetry is throttled across ticks. |
