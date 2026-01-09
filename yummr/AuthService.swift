//
//  AuthService.swift
//  yummr
//
//  Created by kuba woahz on 6/27/25.
//

import FirebaseAuth
import Combine
import UIKit

class AuthService: ObservableObject {
    @Published var currentUser: User?

    init() {
        self.currentUser = Auth.auth().currentUser

        if let user = self.currentUser {
            UserService.shared.ensureUserDocument(for: user)
        }

        Auth.auth().addStateDidChangeListener { _, user in
            self.currentUser = user
            if let user = user {
                UserService.shared.ensureUserDocument(for: user)
            }
        }
    }

    func login(email: String,
               password: String,
               completion: @escaping (Bool, String?) -> Void) {
        Auth.auth().signIn(withEmail: email, password: password) { result, error in
            if let error = error {
                completion(false, error.localizedDescription)
            } else {
                if let user = result?.user {
                    UserService.shared.ensureUserDocument(for: user)
                }
                self.currentUser = result?.user
                completion(true, nil)
            }
        }
    }

    func register(email: String,
                  password: String,
                  displayName: String,
                  profileImage: UIImage? = nil,
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
                        let resolvedUser = self.currentUser ?? user
                        UserService.shared.ensureUserDocument(for: resolvedUser, displayName: displayName)

                        guard let profileImage = profileImage else {
                            completion(true, nil)
                            return
                        }

                        StorageService.shared.uploadImage(profileImage) { result in
                            switch result {
                            case .success(let urlString):
                                let updateReq = resolvedUser.createProfileChangeRequest()
                                updateReq.photoURL = URL(string: urlString)
                                updateReq.commitChanges { photoError in
                                    if let photoError = photoError {
                                        completion(false, photoError.localizedDescription)
                                        return
                                    }
                                    UserService.shared.updateProfileImage(uid: resolvedUser.uid, url: urlString)
                                    completion(true, nil)
                                }
                            case .failure(let error):
                                completion(false, error.localizedDescription)
                            }
                        }
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
