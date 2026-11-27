import Foundation

func collectOutput(of process: Process, from output: Pipe) -> Data {
    process.waitUntilExit()
    return output.fileHandleForReading.readDataToEndOfFile()
}
