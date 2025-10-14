//
//  AppUser 2.swift
//  yummr
//
//  Created by kuba woahz on 9/16/25.
//


import Foundation
import FirebaseFirestore


struct AppUser: Identifiable, Codable {
    struct NotificationSettings: Codable {
        var likes: Bool?
        var comments: Bool?
        var friendRequests: Bool?
        var friendPosts: Bool?
        var mutedUserIDs: [String]?

        static let `default` = NotificationSettings(
            likes: true,
            comments: true,
            friendRequests: true,
            friendPosts: true,
            mutedUserIDs: []
        )
    }

    struct PrivacySettings: Codable {
        var isPrivateAccount: Bool?
        var allowContactDiscovery: Bool?

        static let `default` = PrivacySettings(
            isPrivateAccount: false,
            allowContactDiscovery: true
        )
    }

    struct SavedCollection: Identifiable, Codable, Hashable {
        @DocumentID var id: String?
        var title: String
        var postIDs: [String]
        @ServerTimestamp var createdAt: Date?

        var resolvedID: String { id ?? title }

        init(id: String? = nil, title: String, postIDs: [String] = [], createdAt: Date? = nil) {
            self.id = id
            self.title = title
            self.postIDs = postIDs
            self.createdAt = createdAt
        }
    }

    @DocumentID var id: String?
    var handle: String
    var displayName: String
    var profileImageURL: String?
    var bannerImageURL: String?
    var bio: String?
    var followerCount: Int?
    var followingCount: Int?
    var topFoods: [String]?
    var healthMetrics: [String: String]?
    var phoneNumber: String?
    var notificationSettings: NotificationSettings?
    var privacySettings: PrivacySettings?
    var friendIDs: [String]?
    var pendingFriendRequestIDs: [String]?
    var savedCollections: [SavedCollection]?

    enum CodingKeys: String, CodingKey {
        case handle
        case displayName
        case profileImageURL
        case bannerImageURL
        case bio
        case followerCount
        case followingCount
        case topFoods
        case healthMetrics
        case phoneNumber
        case notificationSettings
        case privacySettings
        case friendIDs
        case pendingFriendRequestIDs
        case savedCollections
    }
}

extension AppUser {
    var resolvedNotificationSettings: NotificationSettings {
        notificationSettings ?? .default
    }

    var resolvedPrivacySettings: PrivacySettings {
        privacySettings ?? .default
    }

    var resolvedFriendIDs: [String] {
        friendIDs ?? []
    }

    var resolvedPendingFriendRequestIDs: [String] {
        pendingFriendRequestIDs ?? []
    }

    var resolvedSavedCollections: [SavedCollection] {
        if let collections = savedCollections, !collections.isEmpty {
            return collections
        }
        return [SavedCollection(id: "all", title: "All Saves", postIDs: [])]
    }
}
