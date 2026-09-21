import Darwin

func unsafeNetwork() {
    _ = socket(AF_INET, SOCK_STREAM, 0)
}
