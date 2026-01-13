import SwiftUI
import PhotosUI
import UIKit

struct AutoLogSheetView: View {
    @Binding var title: String
    @Binding var description: String
    @Binding var recipe: AttributedString
    @Binding var ingredients: [String]
    @Binding var selectedImages: [UIImage]
    @Binding var aiReferenceImages: [UIImage]
    @Binding var audioTranscript: String
    @Binding var youtubeURL: String
    @Binding var youtubeTranscript: String
    @Binding var cookTime: String
    @Binding var calorieEstimate: String
    @Binding var aiNotes: [String]

    @Environment(\.dismiss) private var dismiss
    @StateObject private var audioRecorder = AudioRecorderService()

    @State private var referencePhotoItems: [PhotosPickerItem] = []
    @State private var showReferenceCamera = false
    @State private var capturedReferenceImage: UIImage?
    @State private var isDrafting = false
    @State private var errorMessage: String?
    @State private var isFetchingYouTube = false
    @State private var youtubeErrorMessage: String?
    @State private var draftState: AutoLogDraftState?
    @State private var showDraftReview = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Auto-log with AI")
                        .font(.title2)
                        .fontWeight(.semibold)

                    Text("Capture a voice memo and optional reference photos. We'll draft a recipe you can review.")
                        .font(.callout)
                        .foregroundColor(.secondary)

                    voiceSection
                    youtubeSection
                    referencePhotosSection

                    Button {
                        requestAIDraft()
                    } label: {
                        Label(isDrafting ? "Drafting..." : "Draft with AI", systemImage: "wand.and.stars")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isDrafting)

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundColor(.red)
                    }
                }
                .padding()
            }
            .contentShape(Rectangle())
            .onTapGesture {
                dismissKeyboard()
            }
            .navigationTitle("Auto Log")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .onAppear { audioRecorder.requestPermissions() }
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
        .sheet(isPresented: $showDraftReview) {
            if let draftState {
                AutoLogDraftReviewView(draft: draftState) { reviewed in
                    applyDraft(reviewed)
                    dismiss()
                }
            }
        }
    }

    private var voiceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Voice Memo")
                .font(.headline)

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

            TextEditor(text: $audioTranscript)
                .frame(minHeight: 120)
                .padding(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                )
        }
        .padding()
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(12)
    }

    private var referencePhotosSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Reference Photos")
                .font(.headline)
            Text("Optional images to guide the AI. These won't post publicly.")
                .font(.footnote)
                .foregroundColor(.secondary)

            HStack(spacing: 16) {
                PhotosPicker(
                    selection: $referencePhotoItems,
                    maxSelectionCount: 4,
                    matching: .images,
                    photoLibrary: .shared()
                ) {
                    Label("Add Photos", systemImage: "photo.on.rectangle")
                }

                Button {
                    showReferenceCamera = true
                } label: {
                    Label("Capture", systemImage: "camera")
                }
                .disabled(!UIImagePickerController.isSourceTypeAvailable(.camera))
            }

            if aiReferenceImages.isEmpty {
                Text("No reference photos yet.")
                    .font(.callout)
                    .foregroundColor(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(Array(aiReferenceImages.enumerated()), id: \.offset) { pair in
                            let i = pair.offset
                            let img = pair.element
                            ZStack(alignment: .topTrailing) {
                                Image(uiImage: img)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 120, height: 120)
                                    .clipped()
                                    .cornerRadius(12)

                                Button {
                                    withAnimation {
                                        if i < aiReferenceImages.count {
                                            aiReferenceImages.remove(at: i)
                                        }
                                    }
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.title3)
                                        .symbolRenderingMode(.multicolor)
                                }
                                .offset(x: 6, y: -6)
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(12)
    }

    private var youtubeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("YouTube Transcript")
                .font(.headline)

            TextField("Paste a YouTube link", text: $youtubeURL)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            Button {
                fetchYouTubeTranscript()
            } label: {
                HStack {
                    if isFetchingYouTube {
                        ProgressView()
                    }
                    Text(isFetchingYouTube ? "Fetching transcript..." : "Fetch transcript")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(isFetchingYouTube || youtubeURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            if !youtubeTranscript.isEmpty {
                Text("Transcript ready (\(youtubeTranscript.split(separator: " ").count) words)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if let youtubeErrorMessage {
                Text(youtubeErrorMessage)
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
        .padding()
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(12)
    }

    private func requestAIDraft() {
        Task {
            await performDraftRequest()
        }
    }

    @MainActor
    private func performDraftRequest() async {
        guard !isDrafting else { return }
        isDrafting = true
        errorMessage = nil

        do {
            let combinedTranscript = [audioTranscript, youtubeTranscript]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
            let trimmedYouTubeURL = youtubeURL.trimmingCharacters(in: .whitespacesAndNewlines)
            let customPrompt = trimmedYouTubeURL.isEmpty ? "" : "Source video: \(trimmedYouTubeURL)"
            let draft = try await AIRecipeService.shared.generateDraft(
                currentTitle: title,
                currentDescription: description,
                currentRecipe: recipe.plainText,
                transcript: combinedTranscript,
                capturedIdeas: [],
                customPrompt: customPrompt,
                ingredients: ingredients,
                images: selectedImages,
                referenceImages: aiReferenceImages
            )
            draftState = AutoLogDraftState(from: draft)
            showDraftReview = true
        } catch {
            if let localized = error as? LocalizedError, let description = localized.errorDescription {
                errorMessage = description
            } else {
                errorMessage = error.localizedDescription
            }
        }

        isDrafting = false
    }

    private func fetchYouTubeTranscript() {
        guard !isFetchingYouTube else { return }
        let trimmed = youtubeURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isFetchingYouTube = true
        youtubeErrorMessage = nil

        Task {
            defer { isFetchingYouTube = false }
            do {
                let transcript = try await YouTubeTranscriptService.fetchTranscript(for: trimmed)
                await MainActor.run {
                    youtubeTranscript = transcript
                }
            } catch {
                await MainActor.run {
                    youtubeErrorMessage = error.localizedDescription
                }
            }
        }
    }

    private func applyDraft(_ draft: AutoLogDraftState) {
        title = draft.title
        description = draft.description
        cookTime = draft.cookTime
        calorieEstimate = draft.calorieEstimate
        ingredients = draft.ingredients
        aiNotes = draft.notes
        recipe = AttributedString(draft.recipeText)
    }

    private func formattedTime(_ interval: TimeInterval) -> String {
        let totalSeconds = max(0, Int(interval))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%01d:%02d", minutes, seconds)
    }
}

private enum YouTubeTranscriptService {
    struct TranscriptLine: Decodable {
        let text: String
    }

    static func fetchTranscript(for urlString: String) async throws -> String {
        guard let encoded = urlString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://youtubetranscript.com/?format=json&url=\(encoded)") else {
            throw AIRecipeService.ServiceError.invalidURL
        }

        let (data, response) = try await URLSession.shared.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw AIRecipeService.ServiceError.invalidResponse
        }

        if let lines = try? JSONDecoder().decode([TranscriptLine].self, from: data) {
            let combined = lines.map(\.text).joined(separator: " ")
            let trimmed = combined.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { throw AIRecipeService.ServiceError.emptyResponse }
            return trimmed
        }

        if let fallback = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !fallback.isEmpty {
            return fallback
        }

        throw AIRecipeService.ServiceError.emptyResponse
    }
}

struct AutoLogDraftState {
    var title: String
    var description: String
    var recipeText: String
    var cookTime: String
    var calorieEstimate: String
    var ingredients: [String]
    var notes: [String]

    init(title: String,
         description: String,
         recipeText: String,
         cookTime: String,
         calorieEstimate: String,
         ingredients: [String],
         notes: [String]) {
        self.title = title
        self.description = description
        self.recipeText = recipeText
        self.cookTime = cookTime
        self.calorieEstimate = calorieEstimate
        self.ingredients = ingredients
        self.notes = notes
    }

    init(from draft: AIRecipeDraft) {
        let recipeText: String
        if let steps = draft.instructions, !steps.isEmpty {
            recipeText = steps.joined(separator: "\n")
        } else {
            recipeText = draft.recipe ?? ""
        }

        let cleanedIngredients = (draft.ingredients ?? [])
            .map { Self.stripCreativeTags($0) }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let cleanedNotes = (draft.notes ?? [])
            .map { Self.stripCreativeTags($0) }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        self.title = Self.stripCreativeTags(draft.title ?? "")
        self.description = Self.stripCreativeTags(draft.description ?? "")
        self.recipeText = Self.stripCreativeTags(recipeText)
        self.cookTime = Self.stripCreativeTags(draft.cookTime ?? "")
        if let calories = draft.calorieEstimate, calories > 0 {
            self.calorieEstimate = "\(calories)"
        } else {
            self.calorieEstimate = ""
        }
        self.ingredients = cleanedIngredients
        self.notes = cleanedNotes
    }

    private static func stripCreativeTags(_ text: String) -> String {
        text
            .replacingOccurrences(of: "<creative>", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "</creative>", with: "", options: .caseInsensitive)
    }
}

struct AutoLogDraftReviewView: View {
    let onConfirm: (AutoLogDraftState) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var description: String
    @State private var recipeText: String
    @State private var cookTime: String
    @State private var calorieEstimate: String
    @State private var ingredientsText: String
    @State private var notesText: String

    init(draft: AutoLogDraftState, onConfirm: @escaping (AutoLogDraftState) -> Void) {
        self.onConfirm = onConfirm
        _title = State(initialValue: draft.title)
        _description = State(initialValue: draft.description)
        _recipeText = State(initialValue: draft.recipeText)
        _cookTime = State(initialValue: draft.cookTime)
        _calorieEstimate = State(initialValue: draft.calorieEstimate)
        _ingredientsText = State(initialValue: draft.ingredients.joined(separator: "\n"))
        _notesText = State(initialValue: draft.notes.joined(separator: "\n"))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    TextField("Title", text: $title)
                        .textFieldStyle(.roundedBorder)

                    TextEditor(text: $description)
                        .frame(minHeight: 120)
                        .padding(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                        )

                    TextField("Cook Time", text: $cookTime)
                        .textFieldStyle(.roundedBorder)

                    TextField("Calories", text: $calorieEstimate)
                        .keyboardType(.numberPad)
                        .textFieldStyle(.roundedBorder)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Ingredients")
                            .font(.headline)
                        TextEditor(text: $ingredientsText)
                            .frame(minHeight: 120)
                            .padding(6)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                            )
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Recipe")
                            .font(.headline)
                        TextEditor(text: $recipeText)
                            .frame(minHeight: 200)
                            .padding(6)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                            )
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Notes")
                            .font(.headline)
                        TextEditor(text: $notesText)
                            .frame(minHeight: 100)
                            .padding(6)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                            )
                    }

                    Button("Confirm Draft") {
                        let ingredients = splitLines(from: ingredientsText)
                        let notes = splitLines(from: notesText)
                        let confirmed = AutoLogDraftState(
                            title: stripCreativeTags(title),
                            description: stripCreativeTags(description),
                            recipeText: stripCreativeTags(recipeText),
                            cookTime: stripCreativeTags(cookTime),
                            calorieEstimate: stripCreativeTags(calorieEstimate),
                            ingredients: ingredients,
                            notes: notes
                        )
                        onConfirm(confirmed)
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
            }
            .navigationTitle("Review Draft")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Back") { dismiss() }
                }
            }
        }
    }

    private func splitLines(from text: String) -> [String] {
        text
            .components(separatedBy: CharacterSet.newlines.union([","]))
            .map { stripCreativeTags($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func stripCreativeTags(_ text: String) -> String {
        text
            .replacingOccurrences(of: "<creative>", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "</creative>", with: "", options: .caseInsensitive)
    }
}
