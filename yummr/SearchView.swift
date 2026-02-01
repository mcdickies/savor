//
//  SearchView.swift
//  yummr
//
//  Created by kuba woahz on 9/15/25.
//


import SwiftUI
import FirebaseFirestore

struct SearchView: View {
    @State private var searchText: String = ""
    @State private var recommendedPosts: [Post] = []
    @State private var userResults: [AppUser] = []
    @State private var postResults: [Post] = []
    @State private var contactSuggestions: [AppUser] = []
    @State private var selectedProfileID: String?
    @EnvironmentObject var auth: AuthService

    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 16) {
                searchBar

                if searchText.isEmpty {
                    ScrollView {
                        if !contactSuggestions.isEmpty {
                            suggestionSection
                        }
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                            ForEach(recommendedPosts) { post in
                                NavigationLink(destination: PostDetailView(post: post)) {
                                    CachedWebImage(url: URL(string: post.imageURLs.first ?? "")) {
                                        ProgressView()
                                    }
                                    .aspectRatio(contentMode: .fill)
                                    .frame(height: 160)
                                    .clipped()
                                    .cornerRadius(12)
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
                                    HStack {
                                        userRowButton(for: user)
                                        Spacer()
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
            .background(
                NavigationLink(
                    destination: Group {
                        if let selected = selectedProfileID {
                            ProfileView(userID: selected)
                        } else {
                            EmptyView()
                        }
                    },
                    isActive: Binding(
                        get: { selectedProfileID != nil },
                        set: { isActive in
                            if !isActive {
                                selectedProfileID = nil
                            }
                        }
                    )
                ) {
                    EmptyView()
                }
                .hidden()
            )
        }
        .onAppear(perform: loadRecommendations)
        .onAppear(perform: startFriendListeners)
        .onChange(of: searchText) { newValue in
            performSearch(query: newValue)
        }
    }

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
            TextField("Search users, recipes, and ingredients", text: $searchText)
                .textFieldStyle(PlainTextFieldStyle())
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(Color(UIColor.systemGray6))
        .cornerRadius(12)
        .padding(.horizontal)
        .frame(height: 56)
    }

    private var suggestionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("People you may know")
                .font(.headline)
                .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(contactSuggestions, id: \.handle) { user in
                        suggestionCard(for: user)
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    private func loadRecommendations() {
        if !PostService.shared.cachedTopPosts.isEmpty {
            recommendedPosts = Array(PostService.shared.cachedTopPosts.prefix(8))
            return
        }
        PostService.shared.preloadTopPosts(limit: 8) {
            recommendedPosts = Array(PostService.shared.cachedTopPosts.prefix(8))
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

        PostService.shared.searchPosts(matching: trimmed, limit: 8) { posts in
            DispatchQueue.main.async {
                self.postResults = posts
                    .sorted { $0.likeCount > $1.likeCount }
                    .prefix(8)
                    .map { $0 }
            }
        }
    }

    private func startFriendListeners() {
        guard let uid = auth.currentUser?.uid else { return }
        UserService.shared.fetchContactSuggestions(for: uid) { users in
            DispatchQueue.main.async {
                contactSuggestions = users
            }
        }
    }

    private func userRowButton(for user: AppUser) -> some View {
        let isEnabled = (user.id?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
        return Button {
            if let id = user.id, !id.isEmpty {
                selectedProfileID = id
            }
        } label: {
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
            .opacity(isEnabled ? 1 : 0.6)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }

    private func suggestionCard(for user: AppUser) -> some View {
        let isEnabled = (user.id?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
        return Button {
            if let id = user.id, !id.isEmpty {
                selectedProfileID = id
            }
        } label: {
            VStack {
                CachedWebImage(url: URL(string: user.profileImageURL ?? "")) {
                    Circle().fill(Color.gray.opacity(0.3))
                        .frame(width: 64, height: 64)
                }
                .aspectRatio(contentMode: .fill)
                .frame(width: 64, height: 64)
                .clipShape(Circle())

                Text(user.displayName)
                    .font(.caption)
            }
            .opacity(isEnabled ? 1 : 0.6)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }
}
