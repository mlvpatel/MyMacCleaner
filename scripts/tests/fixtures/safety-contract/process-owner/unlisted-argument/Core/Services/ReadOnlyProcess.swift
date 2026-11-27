import Foundation

enum ReadOnlyCommand {
    case backgroundItems, launchServices, tcpPorts, rootDiskInfo, openFiles

    var invocation: (executable: String, arguments: [String]) {
        switch self {
        case .backgroundItems: ("/usr/bin/sfltool", ["dumpbtm"])
        case .launchServices: ("/bin/launchctl", ["list"])
        case .tcpPorts: ("/usr/sbin/lsof", ["-iTCP", "-sTCP:LISTEN,ESTABLISHED", "-n", "-P"])
        case .rootDiskInfo: ("/usr/sbin/diskutil", ["info", "/"])
        // Dropping -b lets lsof block on a stalled network mount.
        case .openFiles: ("/usr/sbin/lsof", ["-Fn", "-n", "-P", "-w"])
        }
    }
}

func launch(_ command: ReadOnlyCommand) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: command.invocation.executable)
    process.arguments = command.invocation.arguments
}
