import SwiftUI
import UIKit

struct AIDraftWorkshopView: View {
    @Binding var title: String
    @Binding var description: String
    @Binding var recipe: String
    @Binding var selectedImages: [UIImage]
    @Binding var audioTranscript: String

    @State private var ideaPrompt: String = ""
    @State private var capturedIdeas: [String] = []

    @StateObject private var audioRecorder = AudioRecorderService()

    private let promptPlaceholder = "Describe the meal, ingredients, or vibe you want the AI to build on..."

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                promptSection
                audioCaptureSection
                if !capturedIdeas.isEmpty {
                    capturedIdeasSection
                }
                draftSection
                recipeSection
                photosSection
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
                    .buttonStyle(audioRecorder.isRecording ? .borderedProminent : .bordered)
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
                ForEach(Array(capturedIdeas.enumerated()), id: \.offset) { index, idea in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(idea)
                            .font(.body)
                        HStack(spacing: 12) {
                            Button("Apply to Title") {
                                title = idea
                            }
                            Button("Apply to Description") {
                                description = idea
                            }
                            Button("Append to Recipe") {
                                if recipe.isEmpty {
                                    recipe = idea
                                } else {
                                    recipe += "\n\n" + idea
                                }
                            }
                        }
                        .font(.footnote)
                    }
                    .padding()
                    .background(Color(UIColor.secondarySystemBackground))
                    .cornerRadius(12)
                    .contextMenu {
                        Button(role: .destructive) {
                            withAnimation {
                                capturedIdeas.remove(at: index)
                            }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
        }
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
            TextEditor(text: $recipe)
                .frame(minHeight: 180)
                .padding(4)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                )
            HStack {
                Button("Clear Recipe") {
                    recipe = ""
                }
                .buttonStyle(.bordered)
                Spacer()
            }
        }
    }

    private var photosSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Attached Photos")
                .font(.headline)
            if selectedImages.isEmpty {
                Text("No photos attached yet. Add some from the composer to give the AI more context.")
                    .font(.callout)
                    .foregroundColor(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        ForEach(Array(selectedImages.enumerated()), id: \.offset) { index, image in
                            ZStack(alignment: .topTrailing) {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 180, height: 180)
                                    .clipped()
                                    .cornerRadius(16)
                                Button {
                                    withAnimation {
                                        selectedImages.remove(at: index)
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
                recipe: .constant("1. Roast vegetables\n2. Toss with sauce"),
                selectedImages: .constant([]),
                audioTranscript: .constant("Toast bread. Layer greens. Finish with lemon zest.")
            )
        }
    }
}
