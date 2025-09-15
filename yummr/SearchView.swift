//
//  SearchView.swift
//  yummr
//
//  Created by kuba woahz on 9/15/25.
//


import SwiftUI

struct SearchView: View {
    enum SortFilter: String, CaseIterable, Identifiable {
        case trending = "Trending"
        case newest = "New"

        var id: String { rawValue }
    }

    @State private var searchText: String = ""
    @Binding var selectedFilter: SortFilter
    @State private var recommendedPosts: [Post] = []
    @State private var userResults: [AppUser] = []
    @State private var postResults: [Post] = []

    private let badges = ["Something new to try", "Something you might like", "Celebrity"]

    init(selectedFilter: Binding<SortFilter>) {
        self._selectedFilter = selectedFilter
    }

    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 16) {
                searchBar
                Picker("Sort", selection: $selectedFilter) {
                    ForEach(SortFilter.allCases) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                if searchText.isEmpty {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                            ForEach(recommendedPosts) { post in
                                NavigationLink(destination: PostDetailView(post: post)) {
                                    ZStack(alignment: .topTrailing) {
                                        CachedWebImage(url: URL(string: post.imageURLs.first ?? "")) {
                                            ProgressView()
                                        }
                                        .aspectRatio(contentMode: .fill)
                                        .frame(height: 160)
                                        .clipped()
                                        .cornerRadius(12)

                                        Text(badge(for: post))
                                            .font(.caption2)
                                            .padding(6)
                                            .background(Color.black.opacity(0.6))
                                            .foregroundColor(.white)
                                            .cornerRadius(10)
                                            .padding(6)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal)
                    }
                } else {
                    List {
                        if !userResults.isEmpty {
                            Section("Users") {
                                ForEach(userResults, id: \.handle) { user in
                                    NavigationLink(destination: ProfileView(userID: user.id ?? "")) {
                                        HStack {
                                            CachedWebImage(url: URL(string: user.profileImageURL ?? "")) {
                                                Circle().fill(Color.gray.opacity(0.3))
                                                    .frame(width: 44, height: 44)
                                            }
                                            .aspectRatio(contentMode: .fill)
                                            .frame(width: 44, height: 44)
                                            .clipShape(Circle())

                                            VStack(alignment: .leading) {
                                                Text(user.displayName)
                                                Text("@\(user.handle)")
                                                    .font(.caption)
                                                    .foregroundColor(.gray)
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        if !postResults.isEmpty {
                            Section("Recipes") {
                                ForEach(postResults) { post in
                                    NavigationLink(destination: PostDetailView(post: post)) {
                                        VStack(alignment: .leading) {
                                            Text(post.title)
                                                .font(.headline)
                                            if let recipe = post.recipe, !recipe.isEmpty {
                                                Text(recipe)
                                                    .font(.caption)
                                                    .lineLimit(2)
                                            } else {
                                                Text(post.description)
                                                    .font(.caption)
                                                    .lineLimit(2)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }

                Spacer()
            }
            .navigationTitle("Search")
        }
        .onAppear(perform: loadRecommendations)
        .onChange(of: searchText) { newValue in
            performSearch(query: newValue)
        }
        .onChange(of: selectedFilter) { _ in
            sortPostResults()
        }
    }

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
            TextField("Search users, recipes, and ingredients", text: $searchText)
                .textFieldStyle(PlainTextFieldStyle())
        }
        .padding(12)
        .background(Color(UIColor.systemGray6))
        .cornerRadius(12)
        .padding(.horizontal)
    }

    private func badge(for post: Post) -> String {
        let identifier = post.id ?? post.title
        let index = abs(identifier.hashValue) % badges.count
        return badges[index]
    }

    private func loadRecommendations() {
        if !PostService.shared.cachedTopPosts.isEmpty {
            recommendedPosts = PostService.shared.cachedTopPosts
            return
        }
        PostService.shared.preloadTopPosts(limit: 6) {
            recommendedPosts = PostService.shared.cachedTopPosts
        }
    }

    private func performSearch(query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            userResults = []
            postResults = []
            return
        }

        UserService.shared.searchUsers(matching: trimmed) { users in
            DispatchQueue.main.async {
                self.userResults = users
            }
        }

        PostService.shared.searchPosts(matching: trimmed) { posts in
            DispatchQueue.main.async {
                self.postResults = posts
                self.sortPostResults()
            }
        }
    }

    private func sortPostResults() {
        switch selectedFilter {
        case .trending:
            postResults.sort { $0.likeCount > $1.likeCount }
        case .newest:
            postResults.sort { $0.timestamp > $1.timestamp }
        }
    }
}
