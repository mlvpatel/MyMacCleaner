import Darwin

func readLocalFile() {
    _ = open("/tmp/value", O_RDONLY)
}
