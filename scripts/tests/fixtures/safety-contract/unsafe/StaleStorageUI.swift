import SwiftUI

struct StaleStorageUI: View {
    @State private var showCleanConfirmation = false

    var body: some View {
        Button("Move to Trash") {
            prepareClean()
        }
        .alert("Confirm", isPresented: $showCleanConfirmation) {
            Button("Delete", role: .destructive) {
                confirmClean()
            }
        }
    }

    func prepareClean() {
        showCleanConfirmation = true
    }

    func confirmClean() {}
}
