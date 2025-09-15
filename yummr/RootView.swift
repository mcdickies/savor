//
//  RootView.swift
//  yummr
//
//  Created by kuba woahz on 6/27/25.
//

import SwiftUI


struct RootView: View {
    @StateObject var auth = AuthService()
    @State private var searchFilter: SearchView.SortFilter = .trending

    var body: some View {
        Group {
            if auth.currentUser != nil {
                TabView {
                    FeedView()
                        .tabItem { Label("Feed",    systemImage: "list.bullet") }

                    SearchView(selectedFilter: $searchFilter)
                        .tabItem { Label("Search",  systemImage: "magnifyingglass") }

                    CreatePostView()
                        .tabItem { Label("Create",  systemImage: "plus.circle") }

                    ProfileView()
                        .tabItem { Label("Profile", systemImage: "person.crop.circle") }
                }
            } else {
                AuthView()
            }
        }
        .environmentObject(auth)
    }
}
