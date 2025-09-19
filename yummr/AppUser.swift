//
//  AppUser 2.swift
//  yummr
//
//  Created by kuba woahz on 9/16/25.
//


import Foundation
import FirebaseFirestore


struct AppUser: Identifiable, Codable {
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
    }
