/// UI-test selection only. A delivered tap is not proof that a native segment selected.
enum FixtureSelection {
    enum Failure: Error { case notActionable, notSelected }

    static func requireSelected(isSelected: () -> Bool,
                                waitUntilActionable: () -> Bool,
                                tap: () -> Void,
                                waitUntilSelected: () -> Bool) throws {
        for _ in 0..<2 {
            if isSelected() { return }
            guard waitUntilActionable() else { throw Failure.notActionable }
            if isSelected() { return }
            tap()
            _ = waitUntilSelected()
            if isSelected() { return }
        }
        throw Failure.notSelected
    }
}
