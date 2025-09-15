import Foundation
import FirebaseFirestore

struct Comment: Identifiable, Codable {
    @DocumentID var id: String?
    var text: String
    var authorID: String
    var authorName: String
    var parentCommentID: String?
    var taggedUserIDs: [String]
    @ServerTimestamp var timestamp: Date?

    init(id: String? = nil,
         text: String,
         authorID: String,
         authorName: String,
         parentCommentID: String? = nil,
         taggedUserIDs: [String] = [],
         timestamp: Date? = nil) {
        self.id = id
        self.text = text
        self.authorID = authorID
        self.authorName = authorName
        self.parentCommentID = parentCommentID
        self.taggedUserIDs = taggedUserIDs
        self.timestamp = timestamp
    }
}
