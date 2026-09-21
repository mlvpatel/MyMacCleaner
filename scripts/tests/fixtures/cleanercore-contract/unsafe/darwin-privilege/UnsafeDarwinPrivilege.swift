import Darwin

func unsafePrivilege() {
    _ = setuid(0)
}
