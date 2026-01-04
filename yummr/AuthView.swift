//
//  AuthView.swift
//  yummr
//
//  Created by kuba woahz on 6/27/25.
//

import SwiftUI
import UIKit


struct AuthView: View {
    @State private var email = ""
    @State private var password = ""
    @State private var displayName = ""
    @State private var isSignup = false
    @State private var errorMessage = ""
    @State private var showImagePicker = false
    @State private var selectedProfileImage: UIImage?

    @EnvironmentObject var auth: AuthService

    var body: some View {
        VStack(spacing: 16) {
            Text(isSignup ? "Create Account" : "Log In")
                .font(.largeTitle)

            TextField("Email", text: $email)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .autocapitalization(.none)

            SecureField("Password", text: $password)
                .textFieldStyle(RoundedBorderTextFieldStyle())

            if isSignup {
                TextField("Display Name", text: $displayName)
                    .textFieldStyle(RoundedBorderTextFieldStyle())

                Button {
                    showImagePicker = true
                } label: {
                    HStack(spacing: 12) {
                        if let image = selectedProfileImage {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 48, height: 48)
                                .clipShape(Circle())
                        } else {
                            Image(systemName: "person.crop.circle.badge.plus")
                                .font(.system(size: 32))
                                .foregroundColor(.secondary)
                        }

                        Text(selectedProfileImage == nil ? "Add Profile Photo" : "Change Profile Photo")
                            .font(.subheadline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(12)
                    .background(Color(UIColor.systemGray6))
                    .cornerRadius(12)
                }
                .buttonStyle(.plain)
            }

            if !errorMessage.isEmpty {
                Text(errorMessage)
                    .foregroundColor(.red)
            }

            Button(action: {
                errorMessage = ""
                if isSignup {
                    let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmedName.isEmpty else {
                        errorMessage = "Please enter your name."
                        return
                    }
                    guard selectedProfileImage != nil else {
                        errorMessage = "Please add a profile photo."
                        return
                    }
                    auth.register(
                        email: email,
                        password: password,
                        displayName: trimmedName,
                        profileImage: selectedProfileImage
                    ) { success, error in
                        if !success {
                            errorMessage = error ?? "Sign-up failed"
                        }
                    }
                } else {
                    auth.login(email: email, password: password) { success, error in
                        if !success {
                            errorMessage = error ?? "Login failed"
                        }
                    }
                }
            }) {
                Text(isSignup ? "Sign Up" : "Log In")
                    .bold()
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.red)
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }

            Button(action: {
                isSignup.toggle()
                errorMessage = ""
                if !isSignup {
                    displayName = ""
                    selectedProfileImage = nil
                }
            }) {
                Text(isSignup
                        ? "Already have an account? Log in"
                        : "Need an account? Sign up")
                    .font(.footnote)
            }
        }
        .padding()
        .sheet(isPresented: $showImagePicker) {
            ImagePicker(image: $selectedProfileImage)
        }
    }
}
