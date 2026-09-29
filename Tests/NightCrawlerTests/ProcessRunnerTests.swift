import Foundation
import Testing
@testable import NightCrawler

@Test
func processRunnerTimesOutInsteadOfHangingThePollLoop() async {
    let started = Date()
    let result = await ProcessRunner.run(
        command: "/bin/sleep",
        arguments: ["8"],
        timeout: 0.35
    )
    let elapsed = Date().timeIntervalSince(started)

    #expect(elapsed < 1.5, "a hung child must not freeze later provider polls")
    #expect(result.exitCode != 0)
}

@Test
func processRunnerReapsAFinishedChildWithoutParkingOnWaitUntilExit() async {
    let started = Date()
    let result = await withTaskGroup(of: ProcessRunner.RunResult?.self) { group in
        group.addTask {
            await ProcessRunner.run(
                command: "/bin/echo",
                arguments: ["ok"],
                timeout: 2
            )
        }
        group.addTask {
            try? await Task.sleep(for: .seconds(2))
            return nil
        }
        let first = await group.next()!
        group.cancelAll()
        return first
    }
    let elapsed = Date().timeIntervalSince(started)

    #expect(result != nil, "waitUntilExit after a finished sqlite/echo child must not deadlock the poll loop")
    #expect(elapsed < 1.8)
    #expect(result?.exitCode == 0)
    #expect(String(data: result?.output ?? Data(), encoding: .utf8)?.contains("ok") == true)
}

@Test
func processRunnerDrainRetriesEAGAINUntilStdoutArrives() async throws {
    let pipe = Pipe()
    let writer = pipe.fileHandleForWriting
    let drain = Task.detached {
        ProcessRunner.drain(pipe, timeout: 0.6)
    }
    try await Task.sleep(for: .milliseconds(80))
    try writer.write(contentsOf: Data("cursor-session\n".utf8))
    try writer.close()
    let data = await drain.value

    #expect(
        String(data: data, encoding: .utf8) == "cursor-session\n",
        "a non-blocking drain must retry EAGAIN; treating it as EOF drops the Cursor sqlite session"
    )
}
