import Darwin

func unsafeSettings() {
    var value: Int32 = 1
    var size = MemoryLayout<Int32>.size
    _ = sysctlbyname("kern.example", nil, &size, &value, size)
}
