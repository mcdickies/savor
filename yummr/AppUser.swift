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

    init(id: String? = nil,
         handle: String = "",
         displayName: String = "",
         profileImageURL: String? = nil,
         bannerImageURL: String? = nil,
         bio: String? = nil,
         followerCount: Int? = nil,
         followingCount: Int? = nil,
         topFoods: [String]? = nil,
         healthMetrics: [String: String]? = nil) {
        self.id = id
        self.handle = handle
        self.displayName = displayName
        self.profileImageURL = profileImageURL
        self.bannerImageURL = bannerImageURL
        self.bio = bio
        self.followerCount = followerCount
        self.followingCount = followingCount
        self.topFoods = topFoods
        self.healthMetrics = healthMetrics
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.handle = try container.decodeIfPresent(String.self, forKey: .handle) ?? ""
        self.displayName = try container.decodeIfPresent(String.self, forKey: .displayName) ?? ""
        self.profileImageURL = try container.decodeIfPresent(String.self, forKey: .profileImageURL)
        self.bannerImageURL = try container.decodeIfPresent(String.self, forKey: .bannerImageURL)
        self.bio = try container.decodeIfPresent(String.self, forKey: .bio)
        self.followerCount = try container.decodeIfPresent(Int.self, forKey: .followerCount)
        self.followingCount = try container.decodeIfPresent(Int.self, forKey: .followingCount)
        self.topFoods = try container.decodeIfPresent([String].self, forKey: .topFoods)
        self.healthMetrics = try container.decodeIfPresent([String: String].self, forKey: .healthMetrics)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(handle, forKey: .handle)
        try container.encode(displayName, forKey: .displayName)
        try container.encodeIfPresent(profileImageURL, forKey: .profileImageURL)
        try container.encodeIfPresent(bannerImageURL, forKey: .bannerImageURL)
        try container.encodeIfPresent(bio, forKey: .bio)
        try container.encodeIfPresent(followerCount, forKey: .followerCount)
        try container.encodeIfPresent(followingCount, forKey: .followingCount)
        try container.encodeIfPresent(topFoods, forKey: .topFoods)
        try container.encodeIfPresent(healthMetrics, forKey: .healthMetrics)
    }
}
