import Foundation
import SwordRPC

final class PlaySettings {
    static let shared = PlaySettings()
    let discordActivity = DiscordActivity()
}

@main enum DiscordSessionTest {
    static func main() async throws {
        let mode = CommandLine.arguments[1]
        PlaySettings.shared.discordActivity.image = "local-test-image"
        PlaySettings.shared.discordActivity.enable = mode != "disabled"
        DiscordIPC.shared.initialize()
        if mode == "standalone" {
            for _ in 0..<100 where SwordRPC.calls != [1, 1, 1] { try await Task.sleep(nanoseconds: 10_000_000) }
            precondition(SwordRPC.calls == [1, 1, 1], "Standalone PlayCover must keep its configured Discord integration")
        } else {
            try await Task.sleep(nanoseconds: 100_000_000)
            precondition(SwordRPC.calls == [0, 0, 0], "Touchstone or disabled sessions must never construct, connect or publish Discord presence")
        }
        print("Discord session isolation passed: \(mode)")
    }
}
