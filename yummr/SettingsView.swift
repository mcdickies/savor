import SwiftUI
import FirebaseFirestore
import FirebaseAuth

struct SettingsView: View {
    @State private var hideLikeCounts = false
    private let db = Firestore.firestore()

    var body: some View {
        NavigationView {
            Form {
                Toggle("Hide my like counts", isOn: $hideLikeCounts)
                    .onChange(of: hideLikeCounts) { newValue in
                        updateSetting(newValue)
                    }
            }
            .navigationTitle("Settings")
            .onAppear { loadSetting() }
        }
    }

    private func loadSetting() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        db.collection("users").document(uid).getDocument { snap, _ in
            hideLikeCounts = snap?.data()?["hideLikeCounts"] as? Bool ?? false
        }
    }

    private func updateSetting(_ value: Bool) {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        db.collection("users").document(uid).updateData(["hideLikeCounts": value])
    }
}
