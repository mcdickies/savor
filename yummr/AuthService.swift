//
//  AuthService.swift
//  yummr
//
//  Created by kuba woahz on 6/27/25.
//

import FirebaseAuth
import Combine

class AuthService: ObservableObject {
    @Published var currentUser: User?

    init() {
        self.currentUser = Auth.auth().currentUser

        Auth.auth().addStateDidChangeListener { _, user in
            self.currentUser = user
        }
    }

    func login(email: String,
               password: String,
               completion: @escaping (Bool, String?) -> Void) {
        Auth.auth().signIn(withEmail: email, password: password) { result, error in
            if let error = error {
                completion(false, error.localizedDescription)
            } else {
                self.currentUser = result?.user
                completion(true, nil)
            }
        }
    }

    func register(email: String,
                  password: String,
                  displayName: String,
                  completion: @escaping (Bool, String?) -> Void) {
        Auth.auth().createUser(withEmail: email, password: password) { result, error in
            if let error = error {
                completion(false, error.localizedDescription)
            } else if let user = result?.user {
                let changeReq = user.createProfileChangeRequest()
                changeReq.displayName = displayName
                changeReq.commitChanges { err in
                    if let err = err {
                        completion(false, err.localizedDescription)
                    } else {
                        // Refresh currentUser so displayName is populated
                        self.currentUser = Auth.auth().currentUser
                        completion(true, nil)
                    }
                }
            }
        }
    }
//push
    func signOut() {
        try? Auth.auth().signOut()
        self.currentUser = nil
    }
}
