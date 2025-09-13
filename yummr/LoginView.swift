
import SwiftUI

struct LoginView: View {
    @State private var email = ""
    @State private var password = ""
    @State private var errorMessage = ""
    //push
    @EnvironmentObject var auth: AuthService

    var body: some View {
        VStack(spacing: 20) {
            Text("Log In")
                .font(.largeTitle)
                .bold()

            TextField("Email", text: $email)
                .autocapitalization(.none)
                .textFieldStyle(RoundedBorderTextFieldStyle())

            SecureField("Password", text: $password)
                .textFieldStyle(RoundedBorderTextFieldStyle())

            if !errorMessage.isEmpty {
                Text(errorMessage)
                    .foregroundColor(.red)
            }

            // MARK: – Login
            Button("Login") {
                auth.login(email: email, password: password) { success, error in
                    if !success {
                        errorMessage = error ?? "Login failed"
                    }
                }
            }
            .padding()
            .background(Color.blue)
            .foregroundColor(.white)
            .cornerRadius(8)

            // MARK: – Sign Up
            Button("Sign Up") {
                // derive a simple displayName from the email prefix
                let username = email
                    .split(separator: "@")
                    .first
                    .map(String.init) ?? ""
                auth.register(
                    email: email,
                    password: password,
                    displayName: username
                ) { success, error in
                    if !success {
                        errorMessage = error ?? "Sign-up failed"
                    }
                }
            }
            .padding()
        }
        .padding()
    }
}
