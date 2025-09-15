//
//  Post.swift
//  yummr
//
//  Created by kuba woahz on 6/28/25.
//

import FirebaseFirestore
import CoreGraphics

struct Post: Identifiable, Codable {
    struct PhotoTag: Identifiable, Codable, Hashable {
        var id: String
        var userID: String
        var imageIndex: Int?
        var x: Double?
        var y: Double?
        var label: String?

        init(id: String = UUID().uuidString,
             userID: String,
             imageIndex: Int? = nil,
             x: Double? = nil,
             y: Double? = nil,
             label: String? = nil) {
            self.id = id
            self.userID = userID
            self.imageIndex = imageIndex
            self.x = x
            self.y = y
            self.label = label
        }
    }

    @DocumentID var id: String?
    var title: String
    var description: String
    var recipe: String?
    var cookTime: String?
    var imageURLs: [String]
    var detailImages: [String]?
    var extraFields: [String: String]?
    var timestamp: Date
    var authorID: String
    var authorName: String
    var likedBy: [String]
    var likeCount: Int
    var taggedUserIDs: [String]
    var photoTags: [PhotoTag]

    init(id: String? = nil,
         title: String,
         description: String,
         recipe: String? = nil,
         cookTime: String? = nil,
         imageURLs: [String],
         detailImages: [String]? = nil,
         extraFields: [String: String]? = nil,
         timestamp: Date,
         authorID: String,
         authorName: String,
         likedBy: [String] = [],
         likeCount: Int = 0,
         taggedUserIDs: [String] = [],
         photoTags: [PhotoTag] = []) {
        self.id = id
        self.title = title
        self.description = description
        self.recipe = recipe
        self.cookTime = cookTime
        self.imageURLs = imageURLs
        self.detailImages = detailImages
        self.extraFields = extraFields
        self.timestamp = timestamp
        self.authorID = authorID
        self.authorName = authorName
        self.likedBy = likedBy
        self.likeCount = likeCount
        self.taggedUserIDs = taggedUserIDs
        self.photoTags = photoTags
    }
}
