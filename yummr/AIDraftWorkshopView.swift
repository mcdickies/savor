import SwiftUI
import UIKit
import PhotosUI

struct AIDraftWorkshopView: View {
    @Binding var title: String
    @Binding var description: String
    @Binding var recipe: AttributedString
    @Binding var ingredients: [String]
    @Binding var selectedImages: [UIImage]
    @Binding var aiReferenceImages: [UIImage]
    @Binding var audioTranscript: String

    @State private var ideaPrompt: String = ""
    @State private var capturedIdeas: [String] = []

    @StateObject private var audioRecorder = AudioRecorderService()

    @State private var customGuidance: String = ""
    @State private var aiErrorMessage: String?
    @State private var isDraftingWithAI: Bool = false
    @State private var lastGeneratedDate: Date?
    @State private var newIngredientDraft: String = ""
    @State private var aiNotes: [String] = []
    @State private var referencePhotoItems: [PhotosPickerItem] = []
    @State private var showReferenceCamera: Bool = false
    @State private var capturedReferenceImage: UIImage?

    private let promptPlaceholder = "Describe the meal, ingredients, or vibe you want the AI to build on..."

    private var aiButtonTitle: String {
        lastGeneratedDate == nil ? "Draft with AI" : "Regenerate with AI"
    }

    private let ingredientColumns: [GridItem] = [GridItem(.adaptive(minimum: 120), spacing: 8)]
    private let creativeHighlightColor = UIColor.systemBlue.withAlphaComponent(0.2)

    private var contextImagesMessage: String? {
        let publishedCount = min(selectedImages.count, 4)
        let referenceCount = min(aiReferenceImages.count, 4)

        switch (publishedCount, referenceCount) {
        case (0, 0):
            return nil
        case (let post, 0):
            let suffix = post == 1 ? "" : "s"
            return "We'll send up to \(post) post photo\(suffix) for visual context."
        case (0, let reference):
            let suffix = reference == 1 ? "" : "s"
            return "We'll send up to \(reference) private reference photo\(suffix) for visual context."
        case (let post, let reference):
            let postSuffix = post == 1 ? "" : "s"
            let referenceSuffix = reference == 1 ? "" : "s"
            return "We'll send up to \(post) post photo\(postSuffix) and \(reference) private reference photo\(referenceSuffix) for visual context."
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                aiDraftingControls
                promptSection
                audioCaptureSection
                if !capturedIdeas.isEmpty {
                    capturedIdeasSection
                }
                ingredientsTuningSection
                draftSection
                recipeSection
                if !aiNotes.isEmpty {
                    aiNotesSection
                }
                photosSection
                referencePhotosSection
            }
            .padding()
        }
        .navigationTitle("AI Draft")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            audioRecorder.requestPermissions()
        }
        .onReceive(audioRecorder.$transcript) { transcript in
            guard !transcript.isEmpty else { return }
            audioTranscript = transcript
        }
        .sheet(isPresented: $showReferenceCamera) {
            ImagePicker(image: $capturedReferenceImage, sourceType: .camera)
        }
        .onChange(of: referencePhotoItems) { items in
            Task {
                var loadedImages: [UIImage] = []
                for item in items {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        loadedImages.append(image)
                    }
                }
                if !loadedImages.isEmpty {
                    aiReferenceImages.append(contentsOf: loadedImages)
                }
                referencePhotoItems = []
            }
        }
        .onChange(of: capturedReferenceImage) { image in
            guard let image = image else { return }
            aiReferenceImages.append(image)
            capturedReferenceImage = nil
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Workshop your post with AI")
                .font(.title2)
                .fontWeight(.semibold)
            Text("Use this space to capture prompts, iterate on AI generated suggestions, and fine‑tune the draft before heading back to the manual composer.")
                .font(.callout)
                .foregroundColor(.secondary)
        }
    }

    private var aiDraftingControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("AI Drafting")
                .font(.headline)
            Text("Combine your transcript, photos, and notes to draft a recipe. Tweak the guidance below to regenerate as needed.")
                .font(.callout)
                .foregroundColor(.secondary)

            ZStack(alignment: .topLeading) {
                if customGuidance.isEmpty {
                    Text("Optional: tell the AI about serving size, dietary notes, or the vibe you want.")
                        .foregroundColor(.secondary)
                        .padding(.top, 8)
                        .padding(.horizontal, 4)
                }
                TextEditor(text: $customGuidance)
                    .frame(minHeight: 100)
                    .padding(4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                    )
            }

            Button {
                requestAIDraft()
            } label: {
                Label(aiButtonTitle, systemImage: "wand.and.stars")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isDraftingWithAI)

            if isDraftingWithAI {
                ProgressView("Drafting with Gemini…")
                    .progressViewStyle(.circular)
            }

            if let message = aiErrorMessage {
                Text(message)
                    .font(.footnote)
                    .foregroundColor(.red)
            }

            if let message = contextImagesMessage {
                Text(message)
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }

            if let generatedDate = lastGeneratedDate {
                Text("Last generated \(relativeTimeString(for: generatedDate)).")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(12)
    }

    private var audioCaptureSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Voice Capture")
                .font(.headline)
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 16) {
                    Button {
                        if audioRecorder.isRecording {
                            audioRecorder.stopRecording()
                        } else {
                            audioRecorder.startRecording()
                        }
                    } label: {
                        Label(audioRecorder.isRecording ? "Stop Recording" : "Record Idea",
                              systemImage: audioRecorder.isRecording ? "stop.circle.fill" : "mic.circle.fill")
                            .font(.headline)
                            .labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(.bordered)
                    .tint(audioRecorder.isRecording ? .red : .accentColor)
                    .tint(audioRecorder.isRecording ? .red : .accentColor)
                    .disabled(!audioRecorder.hasMicrophonePermission || audioRecorder.speechAuthorizationStatus != .authorized)

                    Text(formattedTime(audioRecorder.elapsedTime))
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(audioRecorder.isRecording ? .primary : .secondary)
                    Spacer()
                    Text("Max 60s")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if let errorMessage = audioRecorder.errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundColor(.red)
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Transcript")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Spacer()
                        if !audioTranscript.isEmpty {
                            Button("Clear") {
                                audioTranscript = ""
                                audioRecorder.resetTranscript()
                            }
                            .font(.caption)
                        }
                    }
                    ZStack(alignment: .topLeading) {
                        if audioTranscript.isEmpty {
                            Text("Tap record and describe your dish to see a transcript here.")
                                .foregroundColor(.secondary)
                                .padding(.top, 8)
                                .padding(.horizontal, 8)
                        }
                        TextEditor(text: $audioTranscript)
                            .frame(minHeight: 120)
                            .padding(4)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                            )
                    }
                }
                Text("Review and edit the transcript before sending it with your AI request.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color(UIColor.secondarySystemBackground))
            .cornerRadius(12)
        }
    }

    private func formattedTime(_ interval: TimeInterval) -> String {
        let totalSeconds = max(0, Int(interval))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%01d:%02d", minutes, seconds)
    }

    private func requestAIDraft() {
        Task {
            await performDraftRequest()
        }
    }

    @MainActor
    private func performDraftRequest() async {
        guard !isDraftingWithAI else { return }
        isDraftingWithAI = true
        aiErrorMessage = nil

        do {
            let draft = try await AIRecipeService.shared.generateDraft(
                currentTitle: title,
                currentDescription: description,
                currentRecipe: recipe.plainText,
                transcript: audioTranscript,
                capturedIdeas: capturedIdeas,
                customPrompt: customGuidance,
                ingredients: ingredients,
                images: selectedImages,
                referenceImages: aiReferenceImages
            )
            applyAIDraft(draft)
            lastGeneratedDate = Date()
            aiErrorMessage = nil
        } catch {
            if let localized = error as? LocalizedError, let description = localized.errorDescription {
                aiErrorMessage = description
            } else {
                aiErrorMessage = error.localizedDescription
            }
        }

        isDraftingWithAI = false
    }

    @MainActor
    private func applyAIDraft(_ draft: AIRecipeDraft) {
        if let newTitle = draft.title?.trimmingCharacters(in: .whitespacesAndNewlines), !newTitle.isEmpty {
            title = newTitle
        }

        let summarySource = draft.summary ?? draft.description
        if let newSummary = summarySource?.trimmingCharacters(in: .whitespacesAndNewlines), !newSummary.isEmpty {
            description = newSummary
        }

        if let newIngredients = draft.ingredients?.map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) }).filter({ !$0.isEmpty }),
           !newIngredients.isEmpty {
            ingredients = newIngredients
        }

        if let steps = draft.instructions, !steps.isEmpty {
            var combined = AttributedString()
            for (index, step) in steps.enumerated() {
                var line = AttributedString("\(index + 1). ")
                let ranges = index < draft.instructionCreativeRanges.count ? draft.instructionCreativeRanges[index] : []
                let highlighted = makeAttributedRecipe(text: step, ranges: ranges)
                line.append(highlighted)
                if index < steps.count - 1 {
                    line.append(AttributedString("\n"))
                }
                combined.append(line)
            }
            recipe = combined
        } else if let recipeText = draft.recipe, !recipeText.isEmpty {
            recipe = makeAttributedRecipe(text: recipeText, ranges: draft.recipeCreativeRanges)
        }

        if let notes = draft.notes?.map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) }).filter({ !$0.isEmpty }),
           !notes.isEmpty {
            aiNotes = notes
        } else {
            aiNotes = []
        }
    }

    private func makeAttributedRecipe(text: String, ranges: [AIRecipeDraft.CreativeRange]) -> AttributedString {
        let mutable = NSMutableAttributedString(string: text)
        let highlight = creativeHighlightColor

        for range in ranges {
            let nsRange = NSRange(location: range.location, length: range.length)
            guard nsRange.location >= 0, NSMaxRange(nsRange) <= mutable.length else { continue }
            mutable.addAttribute(.backgroundColor, value: highlight, range: nsRange)
        }

        return AttributedString(mutable)
    }

    private func appendRecipeText(_ text: String) {
        var updated = recipe
        let addition = AttributedString(text)
        if recipe.characters.isEmpty {
            recipe = addition
        } else {
            updated.append(AttributedString("\n\n"))
            updated.append(addition)
            recipe = updated
        }
    }

    private func addIngredientToken() {
        let trimmed = newIngredientDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if !ingredients.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            ingredients.append(trimmed)
        }

        newIngredientDraft = ""
    }

    private func removeIngredientToken(_ ingredient: String) {
        ingredients.removeAll { $0.caseInsensitiveCompare(ingredient) == .orderedSame }
    }

    private func relativeTimeString(for date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private var promptSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Prompt Scratchpad")
                .font(.headline)
            ZStack(alignment: .topLeading) {
                if ideaPrompt.isEmpty {
                    Text(promptPlaceholder)
                        .foregroundColor(.secondary)
                        .padding(.top, 8)
                }
                TextEditor(text: $ideaPrompt)
                    .frame(minHeight: 140)
                    .padding(4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                    )
            }
            Button {
                let trimmed = ideaPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                withAnimation {
                    capturedIdeas.insert(trimmed, at: 0)
                }
                ideaPrompt = ""
            } label: {
                Label("Save Idea", systemImage: "plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }

   
    private var capturedIdeasSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Captured Ideas")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                // Simple: iterate the strings directly (no indices, no enumerated)
                ForEach(capturedIdeas, id: \.self) { idea in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(idea).font(.body)

                        HStack(spacing: 12) {
                            Button("Apply to Title") { title = idea }
                            Button("Apply to Description") { description = idea }
                            Button("Append to Recipe") { appendRecipeText(idea) }
                        }
                        .font(.footnote)
                    }
                    .padding()
                    .background(Color(uiColor: .secondarySystemBackground)) // avoids UIKit import ambiguity
                    .cornerRadius(12)
                    .contextMenu {
                        Button(role: .destructive) {
                            withAnimation {
                                if let i = capturedIdeas.firstIndex(of: idea) {
                                    capturedIdeas.remove(at: i)
                                }
                            }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
        }
    }


    private var ingredientsTuningSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Ingredients & Keywords for AI")
                .font(.headline)
            Text("Edit the list the model will emphasize. Add shorthand notes or pantry staples that matter for this dish.")
                .font(.caption)
                .foregroundColor(.secondary)

            HStack {
                TextField("Add ingredient or descriptor", text: $newIngredientDraft)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addIngredientToken)
                Button("Add") {
                    addIngredientToken()
                }
                .disabled(newIngredientDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if ingredients.isEmpty {
                Text("No ingredients listed yet. Add a few to anchor the AI's suggestions.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            } else {
                LazyVGrid(columns: ingredientColumns, spacing: 8) {
                    ForEach(ingredients, id: \.self) { ingredient in
                        HStack {
                            Text(ingredient)
                                .font(.footnote)
                                .foregroundColor(.primary)
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: 4)
                            Button(action: { removeIngredientToken(ingredient) }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.caption)
                            }
                        }
                        .padding(8)
                        .background(Color.accentColor.opacity(0.12))
                        .cornerRadius(10)
                    }
                }
            }
        }
        .padding()
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(12)
    }

    private var draftSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Draft Details")
                .font(.headline)
            VStack(alignment: .leading, spacing: 8) {
                Text("Title")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                TextField("Give your dish a name", text: $title)
                    .textFieldStyle(.roundedBorder)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Description")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                TextEditor(text: $description)
                    .frame(minHeight: 140)
                    .padding(4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                    )
            }
        }
    }

    private var recipeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recipe")
                .font(.headline)
            ZStack(alignment: .topLeading) {
                if recipe.characters.isEmpty {
                    Text("Write step-by-step instructions...")
                        .foregroundColor(.secondary)
                        .padding(.top, 8)
                        .padding(.horizontal, 8)
                }
                RichTextEditor(text: $recipe)
                    .frame(minHeight: 180)
                    .padding(4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                    )
            }
            HStack {
                Button("Clear Recipe") {
                    recipe = AttributedString()
                }
                .buttonStyle(.bordered)
                Spacer()
            }
        }
    }

    private var aiNotesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("AI Notes")
                .font(.headline)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(aiNotes, id: \.self) { note in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "lightbulb.fill")
                            .foregroundColor(.accentColor)
                            .font(.subheadline)
                        Text(note)
                            .font(.body)
                            .multilineTextAlignment(.leading)
                    }
                }
            }
        }
        .padding()
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(12)
    }


    private var photosSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Attached Photos").font(.headline)
            Text("These are the images that will publish with your post.")
                .font(.footnote).foregroundColor(.secondary)

            if selectedImages.isEmpty {
                Text("No photos attached yet. Add some from the composer to give the AI more context.")
                    .font(.callout).foregroundColor(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        // Use enumerated() so we can capture a stable pair (i, img) for this render pass.
                        ForEach(Array(selectedImages.enumerated()), id: \.offset) { pair in
                            let i = pair.offset
                            // If selectedImages is [UIImage], this is just `let img = pair.element`.
                            // If it's [UIImage?], we unwrap and skip nils.
                            if let img = (pair.element as AnyObject?) as? UIImage ?? (pair.element as? UIImage) {
                                ZStack(alignment: .topTrailing) {
                                    Image(uiImage: img)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 180, height: 180)
                                        .clipped()
                                        .cornerRadius(16)

                                    Button {
                                        withAnimation {
                                            // Safe: we remove using the captured index from this render pass.
                                            if i < selectedImages.count {
                                                selectedImages.remove(at: i)
                                            }
                                        }
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.title2)
                                            .symbolRenderingMode(.multicolor)
                                    }
                                    .offset(x: 8, y: -8)
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("Remove photo")
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }



    private var referencePhotosSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Reference Photos for Gemini").font(.headline)
            Text("Use these only to guide the AI. They will not appear in your published post.")
                .font(.footnote)
                .foregroundColor(.secondary)

            HStack(spacing: 16) {
                PhotosPicker(
                    selection: $referencePhotoItems,
                    maxSelectionCount: 4,
                    matching: .images,
                    photoLibrary: .shared()
                ) {
                    Label("Add Reference Photos", systemImage: "photo.on.rectangle")
                }

                Button {
                    showReferenceCamera = true
                } label: {
                    Label("Capture Reference", systemImage: "camera")
                }
                .disabled(!UIImagePickerController.isSourceTypeAvailable(.camera))
            }

            if aiReferenceImages.isEmpty {
                Text("No private reference photos yet. Add a few to give Gemini extra context.")
                    .font(.callout)
                    .foregroundColor(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        // Capture a stable (index, image) pair per render.
                        ForEach(Array(aiReferenceImages.enumerated()), id: \.offset) { pair in
                            let i = pair.offset
                            let img = pair.element

                            ZStack(alignment: .topTrailing) {
                                Image(uiImage: img) // or SwiftUI.Image(uiImage:) if disambiguation needed
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 180, height: 180)
                                    .clipped()
                                    .cornerRadius(16)

                                Button {
                                    withAnimation {
                                        if i < aiReferenceImages.count {
                                            aiReferenceImages.remove(at: i)
                                        }
                                    }
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.title2)
                                        .symbolRenderingMode(.multicolor)
                                }
                                .offset(x: 8, y: -8)
                                .buttonStyle(.plain)
                                .accessibilityLabel("Remove reference photo")
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }


}

struct AIDraftWorkshopView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            AIDraftWorkshopView(
                title: .constant("Weekend Brunch Bowl"),
                description: .constant("A cozy bowl stacked with roasted veggies and a bright herb sauce."),
                recipe: .constant(AttributedString("1. Roast vegetables\n2. Toss with sauce")),
                ingredients: .constant(["sweet potatoes", "poached eggs", "chimichurri"]),
                selectedImages: .constant([]),
                aiReferenceImages: .constant([]),
                audioTranscript: .constant("Toast bread. Layer greens. Finish with lemon zest.")
            )
        }
    }
}
