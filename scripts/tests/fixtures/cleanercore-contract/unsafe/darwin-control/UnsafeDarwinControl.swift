import Darwin

func unsafeControl(_ pid: Int32) {
    _ = kill(pid, SIGTERM)
}
