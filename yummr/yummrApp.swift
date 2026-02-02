//
//  yummrApp.swift
//  yummr
//
//  Created by kuba woahz on 6/27/25.
//
import SwiftUI
import FirebaseCore
import UIKit

@main
struct YummrApp: App {
    @UIApplicationDelegateAdaptor(OrientationAppDelegate.self) private var orientationDelegate

    init() {
        Self.configureFirebaseIfNeeded()
    }

    var body: some Scene {
        WindowGroup {
            AppRootView()
        }
    }

    private static func configureFirebaseIfNeeded() {
        guard FirebaseApp.app() == nil else { return }

        FirebaseBootstrapState.resolvedBundleMismatch = false
        FirebaseBootstrapState.warning = nil

        if let filePath = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
           let options = FirebaseOptions(contentsOfFile: filePath) {
            if let actualBundleID = Bundle.main.bundleIdentifier {
                if options.bundleID != actualBundleID {
                    options.bundleID = actualBundleID
                    FirebaseBootstrapState.resolvedBundleMismatch = true
                }
                FirebaseApp.configure(options: options)
            } else {
                FirebaseBootstrapState.warning = "Phone verification is unavailable because the bundle identifier is missing."
                FirebaseApp.configure(options: options)
            }
        } else {
            FirebaseBootstrapState.warning = "Phone verification is unavailable because GoogleService-Info.plist is missing."
            FirebaseApp.configure()
        }
    }
}

private struct AppRootView: View {
    @State private var showSplash = true

    var body: some View {
        ZStack {
            RootView()
                .opacity(showSplash ? 0 : 1)

            if showSplash {
                SplashScreenView()
                    .transition(.opacity)
            }
        }
        .onAppear {
            let start = Date()
            let minDuration: TimeInterval = 1.0
            let maxDuration: TimeInterval = 3.0
            var didFinish = false

            func finishSplash(after delay: TimeInterval) {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    guard !didFinish else { return }
                    didFinish = true
                    withAnimation(.easeInOut(duration: 0.6)) {
                        showSplash = false
                    }
                }
            }

            finishSplash(after: maxDuration)

            PostService.shared.preloadTopPostsAndImages(limit: 8) {
                let elapsed = Date().timeIntervalSince(start)
                let remaining = max(0, minDuration - elapsed)
                finishSplash(after: remaining)
            }
        }
    }
}

enum FirebaseBootstrapState {
    static var resolvedBundleMismatch = false
    static var warning: String?
}

final class OrientationAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        .portrait
    }
}
