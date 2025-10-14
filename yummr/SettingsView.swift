import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var auth: AuthService

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

    var body: some View {
        NavigationStack {
            Form {
                profileSection
                phoneSection
                notificationsSection
                privacySection
                destructiveSection
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear(perform: loadUser)
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
            TextField("Phone number", text: $phoneNumber)
                .keyboardType(.phonePad)

            Button {
                sendVerificationCode()
            } label: {
                if isSendingCode {
                    ProgressView()
                } else {
                    Text("Send verification code")
                }
            }
            .disabled(phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSendingCode)

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
                .disabled(verificationCode.count < 4 || isVerifyingCode)
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

    private var destructiveSection: some View {
        Section {
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

    private func sendVerificationCode() {
        guard !phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        isSendingCode = true
        phoneStatusMessage = "Sending…"
        PhoneAuthProvider.provider().verifyPhoneNumber(phoneNumber, uiDelegate: nil) { verificationID, error in
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
