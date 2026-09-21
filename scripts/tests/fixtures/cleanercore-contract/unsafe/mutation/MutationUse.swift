struct MutationUseFixture {
    func mutate(fileManager: FileManager) throws {
        try fileManager.removeItem(atPath: "/tmp/example")
    }
}
