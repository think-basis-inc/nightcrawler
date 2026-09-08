import Foundation
import Testing
@testable import NightCrawler

@Test
func claudeUsageScreenSeparatesAllModelsFromFable() throws {
    let output = """
    Current session
    0% 0% used
    Resets 9:50pm (America/Toronto)
    Current week (all models)
    54% 54% used
    Resets Sep 11 at 3pm (America/Toronto)
    Current week (Fable)
    85% 85% used
    Resets Sep 11 at 3pm (America/Toronto)
    """

    let windows = ClaudeCLIUsageParser.windows(from: Data(output.utf8))

    #expect(windows.map(\.id) == ["session", "weekly_all", "fable"])
    #expect(windows.first { $0.id == "weekly_all" }?.usedPercent == 54)
    #expect(windows.first { $0.id == "fable" }?.usedPercent == 85)
}

@Test
func claudeUsageScreenParserToleratesTerminalControlSequencesAndDuplicatePercentages() {
    let output = "\u{001B}[2KCurrent week (all models)\r\n\u{001B}[G54% 54% used\r\n"
    let windows = ClaudeCLIUsageParser.windows(from: Data(output.utf8))
    #expect(windows.count == 1)
    #expect(windows[0].id == "weekly_all")
    #expect(windows[0].usedPercent == 54)
}

@Test
func claudeCLIUsageClientSendsUsageOnPromptWithoutLiteralAutoMode() async throws {
    let script = """
    printf 'Claude Code v2.1.263\\nyou: '
    read -r cmd
    case "$cmd" in
        */usage*)
            printf 'Current session\\n0%% 0%% used\\nResets 9:50pm\\nCurrent week (all models)\\n54%% 54%% used\\nResets Sep 11\\nCurrent week (Fable)\\n85%% 85%% used\\nResets Sep 11\\n'
            ;;
    esac
    sleep 3
    """
    let client = ClaudeCLIUsageClient(command: ["/bin/sh", "-c", script], timeout: 4)
    let windows = await client.readWindows()
    #expect(windows.map(\.id) == ["session", "weekly_all", "fable"])
}

@Test
func claudeCLIUsageClientReturnsPromptlyWhenFableIsLegitimatelyAbsent() async throws {
    let script = """
    printf 'Current session\\n0%% 0%% used\\nResets 9:50pm\\nCurrent week (all models)\\n54%% 54%% used\\nResets Sep 11\\nUsage credits\\n'
    sleep 5
    """
    let client = ClaudeCLIUsageClient(command: ["/bin/sh", "-c", script], timeout: 10)
    let start = Date()
    let windows = await client.readWindows()
    let elapsed = Date().timeIntervalSince(start)

    #expect(windows.map(\.id) == ["session", "weekly_all"])
    #expect(!windows.contains { $0.id == "fable" })
    #expect(elapsed < 2.0)
}

@Test
func claudeCLIUsageClientDoesNotWaitForASignalIgnoringChild() async throws {
    let script = """
    trap '' HUP INT TERM
    printf 'Current session\n0%% 0%% used\nResets 9:50pm\nCurrent week (all models)\n54%% 54%% used\nResets Sep 11\nUsage credits\n'
    sleep 5
    """
    let client = ClaudeCLIUsageClient(command: ["/bin/sh", "-c", script], timeout: 10)
    let start = Date()
    let windows = await client.readWindows()
    let elapsed = Date().timeIntervalSince(start)

    #expect(windows.map(\.id) == ["session", "weekly_all"])
    #expect(elapsed < 2.0)
}

@Test
func claudeCLIUsageClientIgnoresEarlyScreenReaderBannerAndWaitsForInteractivePrompt() async throws {
    let script = """
    printf 'Screen Reader mode enabled\\nClaude Code v2.1.263\\n'
    read -t 1 early_input || true
    printf 'you: '
    read -r cmd
    case "$cmd" in
        */usage*)
            printf 'Current session\\n0%% 0%% used\\nResets 9:50pm\\nCurrent week (all models)\\n54%% 54%% used\\nResets Sep 11\\nCurrent week (Fable)\\n85%% 85%% used\\nResets Sep 11\\n'
            ;;
    esac
    sleep 3
    """
    let client = ClaudeCLIUsageClient(command: ["/bin/sh", "-c", script], timeout: 4)
    let windows = await client.readWindows()
    #expect(windows.map(\.id) == ["session", "weekly_all", "fable"])
}
