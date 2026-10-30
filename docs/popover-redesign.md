# Popover redesign notes

The menu bar studio presents recommended widgets while retaining already-enabled
legacy widgets. Popover destinations are independent of widget appearance.
Legacy popover identifiers remain decodable; at presentation time, duplicate
visual treatments route to their purpose-based replacement. Component-specific
temperature choices open the shared Sensor Explorer in the corresponding group.

History charts in redesigned views use sample timestamps, split at missing
readings or long gaps, and display the actual recorded time range. Samples are
kept in the existing bounded session buffer, not persisted long-term. A thermal
peak can represent a different sensor at each point.

Hardware-dependent fields are optional. A missing value is not a zero, an
adapter rating is not measured delivery, and swap used is not a paging rate.
Disk I/O is aggregate across reported block devices; storage volumes may share
capacity. Network throughput sums monitored interfaces and can include VPNs.

## Remaining follow-up

* Allow selecting a specific volume, fan, or temperature sensor for a menu bar
  widget and persist the selection independently of its visual style.
* Add navigation between purpose-based destinations from within a popover.
* Complete keyboard, VoiceOver, reduced-motion and contrast validation, and
  exercise the UI on Intel, Apple Silicon, fanless and desktop Macs.
* Audit remaining legacy renderers and unavailable-state behavior, including
  old widgets kept for backwards compatibility.

## Validation on macOS

Run `swift test` from the repository root and build the Xcode app target. Check
preferences migration, live menu bar rendering, hardware availability states,
preview interactions, and visual layout in light and dark appearances. The
Swift package includes the new `HistoryTimelineTests` and existing app/UI test
suites; tests that exercise real hardware may vary by machine.
