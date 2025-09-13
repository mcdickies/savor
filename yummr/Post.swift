//
//  Post.swift
//  yummr
//
//  Created by kuba woahz on 6/28/25.
//import Foundation
import FirebaseFirestore

struct Post: Identifiable, Codable {
    @DocumentID var id: String?
    var title: String
    var description: String
    var imageURLs: [String]
    var timestamp: Date
    var authorID: String
    var authorName: String
    var likedBy: [String]
    var likeCount: Int
//push
    init(id: String? = nil, title: String, description: String, imageURLs: [String], timestamp: Date, authorID: String, authorName: String, likedBy: [String] = [], likeCount: Int = 0) {
        self.id = id
        self.title = title
        self.description = description
        self.imageURLs = imageURLs
        self.timestamp = timestamp
        self.authorID = authorID
        self.authorName = authorName
        self.likedBy = likedBy
        self.likeCount = likeCount
    }
}
