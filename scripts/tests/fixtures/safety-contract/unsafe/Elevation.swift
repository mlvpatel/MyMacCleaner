import Foundation

func requestElevatedMaintenance() {
    let script = NSAppleScript(source: "do shell script \"id\" with administrator privileges")
    _ = script?.executeAndReturnError(nil)
}
