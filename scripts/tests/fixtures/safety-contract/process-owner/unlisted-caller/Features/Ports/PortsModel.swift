import Foundation

// A caller that builds its own child instead of asking the owner for a fixed command.
func readPorts() throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
    try process.run()
}
