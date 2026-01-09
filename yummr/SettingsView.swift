import SwiftUI
import FirebaseAuth
import FirebaseCore
import UIKit

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var auth: AuthService

    private let authUIDelegate = SettingsAuthUIDelegate.shared

    @State private var appUser: AppUser?
    @State private var displayName: String = ""
    @State private var handle: String = ""
    @State private var bio: String = ""
    @State private var phoneNumber: String = ""
    @State private var verificationCode: String = ""
    @State private var verificationID: String?
    @State private var isSendingCode = false
    @State private var isVerifyingCode = false
    @State private var profileStatusMessage: String?
    @State private var phoneStatusMessage: String?
    @State private var showDeleteConfirmation = false

    @State private var notificationSettings = AppUser.NotificationSettings.default
    @State private var privacySettings = AppUser.PrivacySettings.default
    @State private var geminiAPIKey: String = ""
    @State private var geminiStatusMessage: String?
    @State private var isLoadingGeminiKey = false

    var body: some View {
        NavigationStack {
            Form {
                profileSection
                phoneSection
                notificationsSection
                privacySection
                aiSection
                destructiveSection
            }
            .navigationTitle("Settings")
            .contentShape(Rectangle())
            .onTapGesture {
                dismissKeyboard()
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                loadUser()
                loadGeminiKey()
            }
        }
    }

    private var profileSection: some View {
        Section("Profile") {
            TextField("Display name", text: $displayName)
            TextField("Username", text: $handle)
                .autocapitalization(.none)
                .textInputAutocapitalization(.never)
            TextField("Bio", text: $bio, axis: .vertical)

            if let message = profileStatusMessage {
                Text(message)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Button {
                saveProfile()
            } label: {
                Text("Save profile")
            }
            .disabled(appUser == nil)
        }
    }

    private var phoneSection: some View {
        Section("Phone") {
            if FirebaseBootstrapState.resolvedBundleMismatch {
                Text("Firebase was configured with an adjusted bundle identifier to match this build. Download a matching GoogleService-Info.plist when you publish to avoid using the fallback.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            TextField("Phone number", text: $phoneNumber)
                .keyboardType(.phonePad)

            if let warning = phoneVerificationWarning {
                Text(warning)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Button {
                sendVerificationCode()
            } label: {
                if isSendingCode {
                    ProgressView()
                } else {
                    Text("Send verification code")
                }
            }
            .disabled(phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSendingCode || phoneVerificationWarning != nil)

            if verificationID != nil {
                TextField("Verification code", text: $verificationCode)
                    .keyboardType(.numberPad)

                Button {
                    verifyCode()
                } label: {
                    if isVerifyingCode {
                        ProgressView()
                    } else {
                        Text("Verify & save")
                    }
                }
                .disabled(verificationCode.count < 4 || isVerifyingCode || phoneVerificationWarning != nil)
            }

            if let phoneStatusMessage {
                Text(phoneStatusMessage)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var notificationsSection: some View {
        Section("Notifications") {
            Toggle("Likes", isOn: Binding(
                get: { notificationSettings.likes ?? true },
                set: { value in
                    notificationSettings.likes = value
                    persistNotificationSettings()
                }
            ))

            Toggle("Comments", isOn: Binding(
                get: { notificationSettings.comments ?? true },
                set: { value in
                    notificationSettings.comments = value
                    persistNotificationSettings()
                }
            ))

            Toggle("Friend requests", isOn: Binding(
                get: { notificationSettings.friendRequests ?? true },
                set: { value in
                    notificationSettings.friendRequests = value
                    persistNotificationSettings()
                }
            ))

            Toggle("Friend posts", isOn: Binding(
                get: { notificationSettings.friendPosts ?? true },
                set: { value in
                    notificationSettings.friendPosts = value
                    persistNotificationSettings()
                }
            ))
        }
    }

    private var privacySection: some View {
        Section("Privacy") {
            Toggle("Private account", isOn: Binding(
                get: { privacySettings.isPrivateAccount ?? false },
                set: { value in
                    privacySettings.isPrivateAccount = value
                    persistPrivacySettings()
                }
            ))

            Toggle("Allow contact discovery", isOn: Binding(
                get: { privacySettings.allowContactDiscovery ?? true },
                set: { value in
                    privacySettings.allowContactDiscovery = value
                    persistPrivacySettings()
                }
            ))
        }
    }

    private var aiSection: some View {
        Section("AI Drafting") {
            if isLoadingGeminiKey {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                LabeledContent("Shared Gemini key") {
                    Text(maskedGeminiKey)
                        .monospaced()
                        .foregroundColor(geminiAPIKey.isEmpty ? .secondary : .primary)
                }
            }

            if let message = geminiStatusMessage {
                Text(message)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Button("Reload shared key") {
                loadGeminiKey(force: true)
            }
            .disabled(isLoadingGeminiKey)

            Text("The Gemini API key is managed centrally for all users. Update it in Firestore if you need to rotate the shared credential.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var destructiveSection: some View {
        Section {
            Button {
                auth.signOut()
                dismiss()
            } label: {
                Text("Log out")
            }

            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                Text("Delete account")
            }
        }
        .alert("Delete account?", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                deleteAccount()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This removes your profile, posts, friends, and saved data.")
        }
    }

    private func loadUser() {
        guard let uid = auth.currentUser?.uid else { return }
        UserService.shared.fetchUser(withID: uid) { user in
            DispatchQueue.main.async {
                self.appUser = user
                self.displayName = user?.displayName ?? ""
                self.handle = user?.handle ?? ""
                self.bio = user?.bio ?? ""
                self.phoneNumber = user?.phoneNumber ?? ""
                self.notificationSettings = user?.resolvedNotificationSettings ?? .default
                self.privacySettings = user?.resolvedPrivacySettings ?? .default
            }
        }
    }

    private func saveProfile() {
        guard let uid = auth.currentUser?.uid else { return }
        profileStatusMessage = "Saving…"
        UserService.shared.updateProfile(for: uid,
                                         displayName: displayName,
                                         handle: handle,
                                         bio: bio.isEmpty ? nil : bio) { error in
            DispatchQueue.main.async {
                if let error = error {
                    self.profileStatusMessage = "Failed: \(error.localizedDescription)"
                } else {
                    self.profileStatusMessage = "Saved"
                    self.appUser?.displayName = displayName
                    self.appUser?.handle = handle
                    self.appUser?.bio = bio
                }
            }
        }
    }

    private func loadGeminiKey(force: Bool = false) {
        if !force, let cached = SecretsService.shared.cachedGeminiAPIKey() {
            geminiAPIKey = cached
            geminiStatusMessage = "Using cached Gemini API key."
            return
        }

        isLoadingGeminiKey = true
        geminiStatusMessage = nil

        Task {
            do {
                if let remote = try await SecretsService.shared.resolveSharedGeminiAPIKey() {
                    await MainActor.run {
                        geminiAPIKey = remote
                        geminiStatusMessage = "Loaded the shared Gemini API key."
                        isLoadingGeminiKey = false
                    }
                } else {
                    let fallback = fallbackGeminiKey()
                    await MainActor.run {
                        if let fallback = fallback {
                            geminiAPIKey = fallback
                            geminiStatusMessage = "Using a fallback Gemini key until the shared key is configured."
                        } else {
                            geminiAPIKey = ""
                            geminiStatusMessage = "No shared Gemini API key is configured yet."
                        }
                        isLoadingGeminiKey = false
                    }
                }
            } catch {
                let fallback = fallbackGeminiKey()
                await MainActor.run {
                    if let fallback = fallback {
                        geminiAPIKey = fallback
                        geminiStatusMessage = "Using a fallback Gemini key. Couldn't refresh the shared key: \(error.localizedDescription)"
                    } else {
                        geminiAPIKey = ""
                        geminiStatusMessage = "Couldn't refresh the shared key: \(error.localizedDescription)"
                    }
                    isLoadingGeminiKey = false
                }
            }
        }
    }

    private func fallbackGeminiKey() -> String? {
        if let cached = SecretsService.shared.cachedGeminiAPIKey() {
            return cached
        }

        if let secretsURL = Bundle.main.url(forResource: "GeminiSecrets", withExtension: "plist"),
           let secrets = NSDictionary(contentsOf: secretsURL),
           let bundledKey = secrets["GeminiAPIKey"] as? String,
           let sanitized = sanitizedGeminiKey(from: bundledKey) {
            return sanitized
        }

        if let environmentKey = ProcessInfo.processInfo.environment["GEMINI_API_KEY"],
           let sanitized = sanitizedGeminiKey(from: environmentKey) {
            return sanitized
        }

        return nil
    }

    private func sanitizedGeminiKey(from raw: String?) -> String? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }

        SecretsService.shared.cacheGeminiAPIKey(trimmed)
        return trimmed
    }

    private var maskedGeminiKey: String {
        guard !geminiAPIKey.isEmpty else { return "Not configured" }
        let prefixCount = min(4, geminiAPIKey.count)
        let prefix = String(geminiAPIKey.prefix(prefixCount))
        let maskCount = max(4, geminiAPIKey.count - prefixCount)
        let mask = String(repeating: "•", count: maskCount)
        return prefixCount == geminiAPIKey.count ? mask : prefix + mask
    }

    private var phoneVerificationWarning: String? {
        if let bootstrapWarning = FirebaseBootstrapState.warning {
            return bootstrapWarning
        }

        guard let firebaseApp = FirebaseApp.app() else {
            return "Phone verification is unavailable because Firebase isn't configured."
        }

        guard let bundleID = Bundle.main.bundleIdentifier else {
            return "Phone verification is unavailable in this build."
        }

        let configuredBundleID = firebaseApp.options.bundleID
        if configuredBundleID != bundleID {
            return "Phone verification is disabled in this build. Update GoogleService-Info.plist to match the app's bundle identifier."
        }

        return nil
    }

    private func sendVerificationCode() {
        guard !phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        if let warning = phoneVerificationWarning {
            phoneStatusMessage = warning
            return
        }

        guard Auth.auth().currentUser != nil else {
            phoneStatusMessage = "You need to be signed in to verify a phone number."
            return
        }

        isSendingCode = true
        phoneStatusMessage = "Sending…"
        PhoneAuthProvider.provider().verifyPhoneNumber(phoneNumber, uiDelegate: authUIDelegate) { verificationID, error in
            DispatchQueue.main.async {
                self.isSendingCode = false
                if let error = error {
                    self.phoneStatusMessage = "Failed: \(error.localizedDescription)"
                } else {
                    self.verificationID = verificationID
                    self.phoneStatusMessage = "Code sent"
                }
            }
        }
    }

    private func verifyCode() {
        guard let verificationID else { return }

        if let warning = phoneVerificationWarning {
            phoneStatusMessage = warning
            return
        }

        guard Auth.auth().currentUser != nil else {
            phoneStatusMessage = "You need to be signed in to verify a phone number."
            return
        }

        isVerifyingCode = true
        phoneStatusMessage = "Verifying…"
        let credential = PhoneAuthProvider.provider().credential(withVerificationID: verificationID,
                                                                  verificationCode: verificationCode)
        Auth.auth().currentUser?.updatePhoneNumber(credential) { error in
            DispatchQueue.main.async {
                self.isVerifyingCode = false
                if let error = error {
                    self.phoneStatusMessage = "Failed: \(error.localizedDescription)"
                    return
                }

                self.phoneStatusMessage = "Verified"
                self.verificationID = nil
                self.verificationCode = ""
                if let uid = self.auth.currentUser?.uid {
                    UserService.shared.updatePhoneNumber(for: uid, phoneNumber: self.phoneNumber)
                }
            }
        }
    }

    private func persistNotificationSettings() {
        guard let uid = auth.currentUser?.uid else { return }
        UserService.shared.updateNotificationSettings(for: uid, settings: notificationSettings)
    }

    private func persistPrivacySettings() {
        guard let uid = auth.currentUser?.uid else { return }
        UserService.shared.updatePrivacySettings(for: uid, settings: privacySettings)
    }

    private func deleteAccount() {
        guard let uid = auth.currentUser?.uid else { return }
        UserService.shared.deleteAccount(uid: uid) { error in
            DispatchQueue.main.async {
                if let error = error {
                    self.profileStatusMessage = "Delete failed: \(error.localizedDescription)"
                } else {
                    auth.signOut()
                    dismiss()
                }
            }
        }
    }
}

private final class SettingsAuthUIDelegate: NSObject, AuthUIDelegate {
    static let shared = SettingsAuthUIDelegate()

    func presentationAnchor(for authUI: AuthUI, in scene: UIScene) -> UIWindow {
        guard let windowScene = scene as? UIWindowScene,
              let window = windowScene.windows.first(where: { $0.isKeyWindow }) else {
            return UIWindow()
        }
        return window
    }

    func presentationAnchor(for authUI: AuthUI) -> UIWindow {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first(where: { $0.isKeyWindow }) else {
            return UIWindow()
        }
        return window
    }
}
