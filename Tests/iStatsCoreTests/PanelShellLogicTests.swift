import XCTest
@testable import iStatsCore

final class PanelShellLogicTests: XCTestCase {
    private func key(
        _ code: UInt16,
        _ chars: String = "",
        cmd: Bool = false,
        ctrl: Bool = false,
        shift: Bool = false,
        opt: Bool = false
    ) -> PanelKeyInput {
        PanelKeyInput(keyCode: code, characters: chars, command: cmd, control: ctrl, shift: shift, option: opt)
    }

    // MARK: - Keyboard map

    func testSpaceIsNoLongerMapped() {
        XCTAssertNil(PanelKeyMap.action(for: key(49, " "), isPinned: false))
        XCTAssertNil(PanelKeyMap.action(for: key(49, " "), isPinned: true))
    }

    func testEscapeClosesButIsNoOpWhenPinned() {
        XCTAssertEqual(PanelKeyMap.action(for: key(53), isPinned: false), .close)
        XCTAssertEqual(PanelKeyMap.action(for: key(53), isPinned: true), .noOp)
    }

    func testCommandDigitsSelectStripPositions() {
        for digit in 1...9 {
            XCTAssertEqual(
                PanelKeyMap.action(for: key(0, String(digit), cmd: true), isPinned: false),
                .selectDestination(digit - 1)
            )
        }
        XCTAssertNil(PanelKeyMap.action(for: key(0, "0", cmd: true), isPinned: false))
        XCTAssertNil(PanelKeyMap.action(for: key(0, "1"), isPinned: false), "Plain digits are not shortcuts")
    }

    func testControlTabCyclesDestinations() {
        XCTAssertEqual(PanelKeyMap.action(for: key(48, "\t", ctrl: true), isPinned: false), .nextDestination)
        XCTAssertEqual(PanelKeyMap.action(for: key(48, "\t", ctrl: true, shift: true), isPinned: false), .previousDestination)
        XCTAssertNil(PanelKeyMap.action(for: key(48, "\t"), isPinned: false), "Plain Tab stays with the responder chain")
    }

    func testArrowsChangePageOnlyWithoutCommandOrControl() {
        XCTAssertEqual(PanelKeyMap.action(for: key(123), isPinned: false), .previousPage)
        XCTAssertEqual(PanelKeyMap.action(for: key(124), isPinned: false), .nextPage)
        XCTAssertNil(PanelKeyMap.action(for: key(123, cmd: true), isPinned: false))
        XCTAssertNil(PanelKeyMap.action(for: key(124, ctrl: true), isPinned: false))
    }

    func testCommandLettersPinCloseSettingsQuitCopy() {
        XCTAssertEqual(PanelKeyMap.action(for: key(0, "p", cmd: true), isPinned: false), .togglePin)
        XCTAssertEqual(PanelKeyMap.action(for: key(0, "P", cmd: true), isPinned: true), .togglePin)
        XCTAssertEqual(PanelKeyMap.action(for: key(0, "w", cmd: true), isPinned: false), .close)
        XCTAssertEqual(PanelKeyMap.action(for: key(0, "w", cmd: true), isPinned: true), .unpin)
        XCTAssertEqual(PanelKeyMap.action(for: key(0, ",", cmd: true), isPinned: false), .openSettings)
        XCTAssertEqual(PanelKeyMap.action(for: key(0, "q", cmd: true), isPinned: false), .quit)
        XCTAssertEqual(PanelKeyMap.action(for: key(0, "c", cmd: true), isPinned: false), .copy)
        XCTAssertNil(PanelKeyMap.action(for: key(0, "z", cmd: true), isPinned: false))
    }

    func testQuestionMarkOpensGlossaryHook() {
        XCTAssertEqual(PanelKeyMap.action(for: key(44, "?", shift: true), isPinned: false), .showGlossary)
        XCTAssertEqual(PanelKeyMap.action(for: key(44, "/", shift: true), isPinned: false), .showGlossary)
        XCTAssertNil(PanelKeyMap.action(for: key(44, "/"), isPinned: false))
    }

    // MARK: - Quick actions

    func testFooterQuickActionsPerDestination() {
        XCTAssertEqual(PanelQuickAction.footer(for: .overview).title, "Activity Monitor ↗")
        for category in [MetricCategory.cpu, .memory, .gpu, .thermal, .fan] {
            let action = PanelQuickAction.footer(for: .category(category))
            XCTAssertEqual(action.title, "Activity Monitor ↗")
            XCTAssertEqual(action.target, .activityMonitor)
        }
        XCTAssertEqual(PanelQuickAction.footer(for: .category(.network)).title, "Network Settings ↗")
        XCTAssertEqual(PanelQuickAction.footer(for: .category(.disk)).title, "Storage ↗")
        XCTAssertEqual(PanelQuickAction.footer(for: .category(.power)).title, "Battery Settings ↗")
        XCTAssertEqual(PanelQuickAction.footer(for: .category(.power), hasBattery: false).systemImage, "powerplug")
    }

    func testRibbonActionsAreAlwaysRealActions() {
        XCTAssertEqual(PanelQuickAction.ribbon(for: .power).title, "Battery Settings…")
        XCTAssertEqual(PanelQuickAction.ribbon(for: .disk).title, "Manage Storage…")
        XCTAssertEqual(PanelQuickAction.ribbon(for: .network).title, "Wi-Fi Settings…")
        XCTAssertEqual(PanelQuickAction.ribbon(for: .cpu).title, "Open Activity Monitor")
        for category in MetricCategory.allCases {
            let action = PanelQuickAction.ribbon(for: category)
            XCTAssertFalse(action.title.isEmpty)
            if case .systemSettings(let url) = action.target {
                XCTAssertTrue(url.hasPrefix("x-apple.systempreferences:"))
            }
        }
    }

    func testMenuQuickActionTitles() {
        XCTAssertEqual(PanelQuickAction.menu(for: .category(.cpu)).title, "Open Activity Monitor")
        XCTAssertEqual(PanelQuickAction.menu(for: .category(.network)).title, "Open Network Settings")
        XCTAssertEqual(PanelQuickAction.menu(for: .category(.disk)).title, "Open Storage Settings")
        XCTAssertEqual(PanelQuickAction.menu(for: .category(.power)).title, "Open Battery Settings")
    }

    // MARK: - Footer caption and Settings link

    func testFooterCaption() {
        XCTAssertEqual(PanelFooterCaption.text(isPaused: false, refreshInterval: 2), "Updated · every 2 s")
        XCTAssertEqual(PanelFooterCaption.text(isPaused: false, refreshInterval: 0.5), "Updated · every 0.5 s")
        XCTAssertEqual(PanelFooterCaption.text(isPaused: true, refreshInterval: 2), "Paused")
    }

    func testSettingsDeepLinkSection() {
        XCTAssertEqual(PanelSettingsLink.notificationName, "iStats.openSettingsSection")
        XCTAssertEqual(PanelSettingsLink.section(for: .overview), "general")
        XCTAssertEqual(PanelSettingsLink.section(for: .category(.network)), "network")
        for category in MetricCategory.allCases {
            XCTAssertEqual(PanelSettingsLink.section(for: .category(category)), category.rawValue)
        }
    }
}
