# PR #11 review: perf: reduce idle energy impact

`perf/energy-optimization` → `main` · 12 commits · +2764 / −294 · 20 files

**Verdict: request changes.** The scheduler coalescing, the persistent SMC connection and the caching are reasonable. But the new menu-bar shortcut (it skips redrawing when a short "visual key" summary of the item hasn't changed) leaves some items showing stale values, and the scheduler change breaks ADR 0002 without updating it.

## Tests I ran on the PR head (`5d83a02`)

| Command | Result |
|---|---|
| `swift build --scratch-path /tmp/istats-build` | ✅ Builds (only warnings that were already there) |
| `swift test --scratch-path /tmp/istats-build` | ✅ 142 passed, 0 failed |
| `xcodebuild test -scheme iStatsApp -destination platform=macOS` | ✅ 276 passed, 0 failed (the PR description says 269) |

`docs/progress.md` and the PR description name the scheme `iStats`, but only `iStatsApp` has a test bundle.

---

## 🔴 Must fix

### 1. The redraw shortcut freezes visible values
In [MenuBarController.swift:304](file:///Users/letanthang/learning_software/OS_Project/iStats/iStats/App/MenuBarController.swift#L304), if the visual key matches the previous one, the controller returns before rendering. That skips the image, title, tooltip and accessibility label. The key is too coarse for several styles in [MenuBarIconRenderer.swift](file:///Users/letanthang/learning_software/OS_Project/iStats/iStats/UI/MenuBarIconRenderer.swift):

| Style | Key contains | What the item actually draws | Result |
|---|---|---|---|
| **Power `.text`** ([L288](file:///Users/letanthang/learning_software/OS_Project/iStats/iStats/UI/MenuBarIconRenderer.swift#L288)) | charge %, state | Second line shows **time remaining (`h:mm`) or watts** | Second line freezes until charge % changes |
| **CPU `.bar`** ([L93](file:///Users/letanthang/learning_software/OS_Project/iStats/iStats/UI/MenuBarIconRenderer.swift#L93)) | rounded total % | Per-core bars whenever there are ≥2 cores (every Apple Silicon Mac) | Core bars go stale while the total stays the same |
| **Fan `.bar` / `.throughput`** ([L220-L224](file:///Users/letanthang/learning_software/OS_Project/iStats/iStats/UI/MenuBarIconRenderer.swift#L220-L224)) | busiest fan only | Both fans (L/R RPM) | Second fan freezes |
| **Disk `.gauge` / `.bar`** ([L267](file:///Users/letanthang/learning_software/OS_Project/iStats/iStats/UI/MenuBarIconRenderer.swift#L267)) | volume used % | Tooltip shows `Disk I/O: Read…, Write…` | Tooltip can be stale for hours |
| **Network `.symbol`** | in/out active flags | Tooltip shows live ↓/↑ rates | Tooltip frozen while activity state is unchanged |
| **CPU / GPU / Thermal** | whole % / °C | Tooltip uses one decimal place | Small tooltip and VoiceOver staleness |

**Fix:** Either include every value that reaches the image, title, tooltip or accessibility label in the key, or limit the shortcut to the image. The tooltip and label strings are cheap to rebuild and compare, so the second option is safer. Add a regression test for each row above. The current tests only check unchanged → bypass and changed total → redraw, so none of these cases are caught.

### 2. A slow sampler delays every metric in its batch
[SampleScheduler.swift:460-475](file:///Users/letanthang/learning_software/OS_Project/iStats/Sources/iStatsCore/SampleScheduler.swift#L460-L475) waits for the whole batch before publishing anything. One slow SMC or IOKit read (time limit 2s by default) now holds back CPU, memory and every other category on the same interval. Before, each category had its own loop.

- [ADR 0002](file:///Users/letanthang/learning_software/OS_Project/iStats/docs/architecture/adr/0002-threading-and-scheduling-model.md) still says *"one timer per metric category"* and *"a failure in one sensor must not affect others."* The code no longer matches it, which breaks AGENTS.md rule 7 ("Docs stay true").
- The test `testTimeoutIsolationInBatchedTick` only checks that both readings eventually arrive, not that the fast one arrives quickly.
- **Fix:** Either publish each reading as it finishes (keep the shared timer, drop the shared barrier), or accept the trade-off and update ADR 0002 with the reasoning. Thermal, Fan and GPU now also share one `NSLock` on a single connection, so one stalled SMC call blocks all three.

---

## 🟠 Should fix

3. **SMC decoding behaves differently from before** ([AppleSMCClient.swift](file:///Users/letanthang/learning_software/OS_Project/iStats/iStats/Sampling/AppleSMCClient.swift)):
   - The `default:` branch ([L291](file:///Users/letanthang/learning_software/OS_Project/iStats/iStats/Sampling/AppleSMCClient.swift#L291)) now decodes **unknown** 4-byte types as floats and 2-byte types as `sp78`. The old readers returned `nil`. Sensor discovery may now accept junk keys; only the 0–150 °C filter stands in the way.
   - `fpe2` ([L266](file:///Users/letanthang/learning_software/OS_Project/iStats/iStats/Sampling/AppleSMCClient.swift#L266)) changed from `UInt16` to `Int16`.
   - `flt ` now drops negative values.
   - Please keep exact parity, or document each change and test the decoders directly with fixed byte inputs.
4. **The old SMC code is still there.** `readSMCKeyNumeric` / `readSMCKeyString` / `openSMCConnection` in FanSampler, `readSMCKeyNumeric` in GPUSampler and `readSMCKeyTemperature` in ThermalSampler are now unused copies. Delete them so there is one decoder.
5. **Display names got worse** ([GPUSampler.swift:355-369](file:///Users/letanthang/learning_software/OS_Project/iStats/iStats/Sampling/GPUSampler.swift#L355-L369)). Moving off `NSScreen` (which must be used on the main thread) is correct. But real monitor names (`localizedName`) became `"External Display N"`. Also, `CGGetOnlineDisplayList` counts mirrored and sleeping displays; `CGGetActiveDisplayList` matches the old `NSScreen.screens` count.
6. **"1 @Published broadcast" is overstated.** [handleReadings](file:///Users/letanthang/learning_software/OS_Project/iStats/iStats/App/MetricsCoordinator.swift#L180) still assigns `categoryAvailability[...]` and `latestX` for every reading, which is about 16 change notifications per batch. `categoryAvailability` is also reassigned even when nothing changed. Fix the PR text, or skip assignments when the value is the same.
7. **Unsynchronized counters in `AppleSMCClient`.** `openConnectionCount` and `reconnectCount` are written under the lock but read without it from an `@unchecked Sendable` type, and `resetPerformanceCounters()` doesn't reset `openConnectionCount`.

## 🟡 Nits

- The memory key uses `round(ratio * 100)` on a value that is already a percentage, so its resolution is 0.01%. The shortcut almost never fires for memory items. (Not wrong, just ineffective.)
- `computeVisualKey` repeats the formatting logic in each `renderX`, so the two will drift apart. That drift is the cause of finding 1. Consider building a small value per category once and using it for both the key and the drawing.
- `CoordinatorBatchingTests` change `receivedBatch` / `receivedReading` from inside a `Task` without synchronization, which Swift 6 strict concurrency may flag.
- The timing checks in `SampleSchedulerCoalescingTests` (spread ≤ 25 ms / 80 ms) will likely be flaky on CI machines under load.
- `clearImageCache()` is never called. Hook it to appearance or low-memory notifications, or remove it.
- Nothing calls `AppleSMCClient.invalidate()` on wake; it relies only on reconnecting after an error. That's fine, but say so in ADR 0003, which still describes opening a connection per read.
- Wi-Fi details refresh at most every 10s, so RSSI in the popover can be up to 10s old. Fine, but document it.

## ✅ Good
- The new interval loop uses `ContinuousClock` with a fixed schedule, tolerance and `.utility` priority. Changes to the set of loops are handled cleanly through `syncCadenceLoops`.
- The persistent SMC connection only reconnects after a real connection error, not when a key is missing, and there's a test for that.
- Moving GPU display queries off AppKit fixes a hidden main-thread rule violation.
- History arrays are only built for sparklines, and history comes from the store on demand.
- Removed status items are correctly cleared from `previousRenderStates`.

## Suggested order before merging
1. Fix the redraw shortcut (finding 1) and add a regression test per category and style.
2. Decide on batch publishing (finding 2), and update ADR 0002 and ADR 0003.
3. Restore decoder parity, delete the old SMC readers, and fix the test scheme name in `docs/progress.md` and the PR description.