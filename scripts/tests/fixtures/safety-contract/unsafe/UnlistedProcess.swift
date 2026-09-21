import Foundation

func launchUnreviewedProcess() throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    try process.run()
}
