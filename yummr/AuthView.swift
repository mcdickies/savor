//
//  AuthView.swift
//  yummr
//
//  Created by kuba woahz on 6/27/25.
//

import SwiftUI


struct AuthView: View {
    @State private var email = ""
    @State private var password = ""
    @State private var displayName = ""
    @State private var isSignup = false
    @State private var errorMessage = ""

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
            }

            if !errorMessage.isEmpty {
                Text(errorMessage)
                    .foregroundColor(.red)
            }

            Button(action: {
                errorMessage = ""
                if isSignup {
                    auth.register(
                        email: email,
                        password: password,
                        displayName: displayName
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
            }) {
                Text(isSignup
                        ? "Already have an account? Log in"
                        : "Need an account? Sign up")
                    .font(.footnote)
            }
        }
        .padding()
    }
}
