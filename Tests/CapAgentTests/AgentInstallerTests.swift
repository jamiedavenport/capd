import Foundation
import Testing

@testable import CapAgent

@Suite("AgentInstaller")
struct AgentInstallerTests {
    @Test("The rendered plist points launchd at the executable and keeps the agent alive")
    func renderedPlistIsComplete() throws {
        let rendered = try AgentInstaller.renderedPlist(executablePath: "/opt/cap/bin/cap-agent")
        let plist = try parse(rendered)

        #expect(plist["Label"] as? String == AgentInstaller.label)
        #expect(plist["ProgramArguments"] as? [String] == ["/opt/cap/bin/cap-agent"])
        #expect(plist["RunAtLoad"] as? Bool == true)
        #expect(plist["KeepAlive"] as? Bool == true)
    }

    @Test("A path needing XML escaping still renders a valid plist")
    func escapedPathRoundTrips() throws {
        let path = "/Users/j/dev & <test>/cap-agent"
        let rendered = try AgentInstaller.renderedPlist(executablePath: path)

        #expect(try parse(rendered)["ProgramArguments"] as? [String] == [path])
    }

    @Test("The plist installs under the user's LaunchAgents, named by label")
    func installsUnderLaunchAgents() {
        let destination = AgentInstaller.installedPlistURL
        #expect(destination.lastPathComponent == "\(AgentInstaller.label).plist")
        #expect(destination.path.hasSuffix("Library/LaunchAgents/dev.jxd.cap.agent.plist"))
    }
}

private func parse(_ rendered: String) throws -> [String: Any] {
    let plist = try PropertyListSerialization.propertyList(
        from: Data(rendered.utf8), options: [], format: nil)
    return try #require(plist as? [String: Any])
}
