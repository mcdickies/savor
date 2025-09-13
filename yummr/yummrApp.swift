//
//  yummrApp.swift
//  yummr
//
//  Created by kuba woahz on 6/27/25.
//
import SwiftUI
import FirebaseCore
import SwiftUI
import FirebaseCore

@main
struct YummrApp: App {
    init() {
        FirebaseApp.configure()
    }

    var body: some Scene {
        WindowGroup {
            RootView() // or FeedView/AuthView if not using RootView
        }
    }
}
