import Darwin

func unsafeSensitive(_ pid: Int32) {
    var bytes = [CChar](repeating: 0, count: 1_024)
    _ = proc_pidpath(pid, &bytes, UInt32(bytes.count))
}
