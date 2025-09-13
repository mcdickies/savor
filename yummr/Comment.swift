import Foundation
import FirebaseFirestore


struct Comment: Identifiable, Codable {
    @DocumentID var id: String?
    var text: String
    var authorID: String
    var authorName: String
    @ServerTimestamp var timestamp: Date?
}
