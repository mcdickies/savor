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
    @State private var searchFilter: SearchView.SortFilter = .trending
    @State private var selectedTab: Tab = .feed
    @State private var feedViewID = UUID()
    @State private var searchViewID = UUID()
    @State private var createViewID = UUID()
    @State private var savedViewID = UUID()
    @State private var profileViewID = UUID()

    var body: some View {
        Group {
            if auth.currentUser != nil {
                TabView(selection: Binding(
                    get: { selectedTab },
                    set: { newValue in
                        if selectedTab == newValue {
                            resetView(for: newValue)
                        }
                        selectedTab = newValue
                    }
                )) {
                    FeedView()
                        .id(feedViewID)
                        .tabItem { Label("Feed",    systemImage: "list.bullet") }
                        .tag(Tab.feed)

                    SearchView(selectedFilter: $searchFilter)
                        .id(searchViewID)
                        .tabItem { Label("Search",  systemImage: "magnifyingglass") }
                        .tag(Tab.search)

                    CreatePostView()
                        .id(createViewID)
                        .tabItem { Label("Create",  systemImage: "plus.circle") }
                        .tag(Tab.create)

                    SavedCollectionsView()
                        .id(savedViewID)
                        .tabItem { Label("Saved", systemImage: "bookmark") }
                        .tag(Tab.saved)

                    ProfileView()
                        .id(profileViewID)
                        .tabItem { Label("Profile", systemImage: "person.crop.circle") }
                        .tag(Tab.profile)
                }
            } else {
                AuthView()
            }
        }
        .environmentObject(auth)
    }

    private func resetView(for tab: Tab) {
        switch tab {
        case .feed:
            feedViewID = UUID()
        case .search:
            searchViewID = UUID()
        case .create:
            createViewID = UUID()
        case .saved:
            savedViewID = UUID()
        case .profile:
            profileViewID = UUID()
        }
    }
}
