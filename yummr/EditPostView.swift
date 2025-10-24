import SwiftUI

struct EditPostView: View {
    @Binding var post: Post
    @Environment(\.dismiss) private var dismiss

    @State private var description: String
    @State private var newIngredient: String = ""
    @State private var ingredients: [String]
    @State private var instructions: [String]
    @State private var aiNotes: String
    @State private var starRating: Double
    @State private var isFavorite: Bool
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(post: Binding<Post>) {
        self._post = post
        _description = State(initialValue: post.wrappedValue.description)
        _ingredients = State(initialValue: post.wrappedValue.ingredientList)
        _instructions = State(initialValue: post.wrappedValue.instructionsList)
        _aiNotes = State(initialValue: post.wrappedValue.extraFields?["aiNotes"] ?? "")
        _starRating = State(initialValue: min(max(post.wrappedValue.starRating ?? 0, 0), 5))
        _isFavorite = State(initialValue: post.wrappedValue.isFavorited)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Caption") {
                    TextField("What did you make?", text: $description, axis: .vertical)
                }

                Section("Ingredients") {
                    HStack {
                        TextField("Add ingredient", text: $newIngredient)
                        Button("Add") {
                            addIngredient()
                        }
                        .disabled(newIngredient.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }

                    ForEach(ingredients, id: \.self) { ingredient in
                        Text(ingredient)
                    }
                    .onDelete { indexSet in
                        ingredients.remove(atOffsets: indexSet)
                    }
                }

                Section("Instructions") {
                    ForEach(instructions.indices, id: \.self) { index in
                        TextField("Step \(index + 1)", text: Binding(
                            get: { instructions[index] },
                            set: { instructions[index] = $0 }
                        ), axis: .vertical)
                    }
                    .onDelete { indexSet in
                        instructions.remove(atOffsets: indexSet)
                    }

                    Button("Add step") {
                        instructions.append("")
                    }
                }

                Section("AI Notes") {
                    TextField("Optional notes", text: $aiNotes, axis: .vertical)
                }

                Section("Rating & Favorites") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 12) {
                            Slider(value: $starRating, in: 0...5, step: 0.5) {
                                Text("Star rating")
                            }
                            Text(String(format: "%.1f ★", starRating))
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .frame(width: 72, alignment: .trailing)
                                .accessibilityHidden(true)
                        }

                        Toggle("Mark as favorite", isOn: $isFavorite)
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("Edit Post")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Save") { saveChanges() }
                    }
                }
            }
        }
    }

    private func addIngredient() {
        let trimmed = newIngredient.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        ingredients.append(trimmed)
        newIngredient = ""
    }

    private func saveChanges() {
        guard let postID = post.id else { return }
        isSaving = true
        errorMessage = nil

        var extras = post.extraFields ?? [:]
        extras["ingredients"] = ingredients.joined(separator: "\n")
        extras["aiNotes"] = aiNotes

        let roundedRating = (starRating * 10).rounded() / 10
        if roundedRating > 0 {
            extras["starRating"] = String(format: "%.1f", roundedRating)
        } else {
            extras.removeValue(forKey: "starRating")
            extras.removeValue(forKey: "rating")
            extras.removeValue(forKey: "stars")
        }

        if isFavorite {
            extras["isFavorite"] = "true"
        } else {
            extras.removeValue(forKey: "isFavorite")
            extras.removeValue(forKey: "favorite")
        }

        PostService.shared.updatePost(postID: postID,
                                      title: post.title,
                                      description: description,
                                      recipeSteps: instructions,
                                      extraFields: extras) { result in
            DispatchQueue.main.async {
                isSaving = false
                switch result {
                case .success:
                    post.description = description
                    post.extraFields = extras
                    post.recipe = instructions.joined(separator: "\n")
                    dismiss()
                case .failure(let error):
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}
