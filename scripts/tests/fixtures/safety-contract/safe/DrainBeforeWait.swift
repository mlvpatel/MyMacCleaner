import Foundation

func collectOutput(of process: Process, from output: Pipe) -> Data {
    // Never call waitUntilExit before draining: the child blocks once the pipe buffer is full.
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return data
}
