//
//  RootView.swift
//  yummr
//
//  Created by kuba woahz on 6/27/25.
//

import SwiftUI


struct RootView: View {
    private enum Tab: Hashable {
        case feed, search, create, saved, profile
    }

    @StateObject var auth = AuthService()
    @State private var selectedTab: Tab = .feed

    var body: some View {
        Group {
            if auth.currentUser != nil {
                TabView(selection: $selectedTab) {
                    FeedView()
                        .tabItem { Label("Feed",    systemImage: "list.bullet") }
                        .tag(Tab.feed)

                    SearchView()
                        .tabItem { Label("Search",  systemImage: "magnifyingglass") }
                        .tag(Tab.search)

                    CreatePostView()
                        .tabItem { Label("Create",  systemImage: "plus.circle") }
                        .tag(Tab.create)

                    SavedCollectionsView()
                        .tabItem { Label("Saved", systemImage: "bookmark") }
                        .tag(Tab.saved)

                    ProfileView()
                        .tabItem { Label("Profile", systemImage: "person.crop.circle") }
                        .tag(Tab.profile)
                }
            } else {
                AuthView()
            }
        }
        .environmentObject(auth)
    }
}
