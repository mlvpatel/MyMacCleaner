struct SilentErrorFixture {
    func parse(_ action: () throws -> Void) {
        do {
            try action()
        } catch {}
    }
}
