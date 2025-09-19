import Foundation
import AVFoundation
import Speech

class AudioRecorderService: NSObject, ObservableObject {
    enum RecorderError: LocalizedError {
        case microphonePermissionDenied
        case speechPermissionDenied
        case recognizerUnavailable
        case unableToCreateRecorder
        case unknown

        var errorDescription: String? {
            switch self {
            case .microphonePermissionDenied:
                return "Microphone access is denied. Enable it in Settings to record audio."
            case .speechPermissionDenied:
                return "Speech recognition access is denied. Enable it in Settings to transcribe audio."
            case .recognizerUnavailable:
                return "Speech recognizer is currently unavailable."
            case .unableToCreateRecorder:
                return "Unable to start audio recorder."
            case .unknown:
                return "An unexpected recording error occurred."
            }
        }
    }

    @Published private(set) var isRecording: Bool = false
    @Published private(set) var elapsedTime: TimeInterval = 0
    @Published private(set) var transcript: String = ""
    @Published var errorMessage: String?
    @Published private(set) var hasMicrophonePermission: Bool = false
    @Published private(set) var speechAuthorizationStatus: SFSpeechRecognizerAuthorizationStatus = .notDetermined

    private let audioSession = AVAudioSession.sharedInstance()
    private var audioRecorder: AVAudioRecorder?
    private let speechRecognizer: SFSpeechRecognizer?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var timer: Timer?
    private var audioFileURL: URL?

    private let maxDuration: TimeInterval = 60

    override init() {
        speechRecognizer = SFSpeechRecognizer()
        super.init()
        requestPermissions()
    }

    deinit {
        timer?.invalidate()
        audioRecorder?.stop()
        recognitionTask?.cancel()
        try? audioSession.setActive(false, options: [.notifyOthersOnDeactivation])
    }

    func requestPermissions() {
        audioSession.requestRecordPermission { [weak self] granted in
            DispatchQueue.main.async {
                self?.hasMicrophonePermission = granted
                self?.updatePermissionErrorState()
            }
        }

        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            DispatchQueue.main.async {
                self?.speechAuthorizationStatus = status
                self?.updatePermissionErrorState()
            }
        }
    }

    func startRecording() {
        updatePermissionErrorState()
        guard hasMicrophonePermission else {
            errorMessage = RecorderError.microphonePermissionDenied.errorDescription
            requestPermissions()
            return
        }

        guard speechAuthorizationStatus == .authorized else {
            errorMessage = RecorderError.speechPermissionDenied.errorDescription
            requestPermissions()
            return
        }

        guard speechRecognizer?.isAvailable == true else {
            errorMessage = RecorderError.recognizerUnavailable.errorDescription
            return
        }

        do {
            try configureAudioSession()
            let url = try makeRecordingURL()
            audioFileURL = url

            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 44100,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ]

            audioRecorder = try AVAudioRecorder(url: url, settings: settings)
            audioRecorder?.delegate = self
            audioRecorder?.isMeteringEnabled = true
            audioRecorder?.prepareToRecord()

            if audioRecorder?.record(forDuration: maxDuration) == true {
                DispatchQueue.main.async {
                    self.transcript = ""
                    self.elapsedTime = 0
                    self.isRecording = true
                    self.errorMessage = nil
                    self.startTimer()
                }
            } else {
                throw RecorderError.unableToCreateRecorder
            }
        } catch {
            DispatchQueue.main.async {
                if let recorderError = error as? RecorderError {
                    self.errorMessage = recorderError.errorDescription
                } else {
                    self.errorMessage = RecorderError.unknown.errorDescription
                }
                self.isRecording = false
                self.stopTimer()
            }
        }
    }

    func stopRecording() {
        guard isRecording else { return }
        audioRecorder?.stop()
        stopTimer()
    }

    func resetTranscript() {
        transcript = ""
    }

    private func updatePermissionErrorState() {
        if !hasMicrophonePermission {
            errorMessage = RecorderError.microphonePermissionDenied.errorDescription
        } else if speechAuthorizationStatus != .authorized {
            errorMessage = RecorderError.speechPermissionDenied.errorDescription
        } else if let message = errorMessage,
                  message == RecorderError.microphonePermissionDenied.errorDescription ||
                    message == RecorderError.speechPermissionDenied.errorDescription {
            errorMessage = nil
        }
    }

    private func configureAudioSession() throws {
        try audioSession.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker])
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
    }

    private func makeRecordingURL() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
        let filename = UUID().uuidString.appending(".m4a")
        return directory.appendingPathComponent(filename)
    }

    private func startTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.elapsedTime += 0.2
            if self.elapsedTime >= self.maxDuration {
                self.stopRecording()
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func handleFinishRecording(successfully flag: Bool) {
        DispatchQueue.main.async {
            self.isRecording = false
            self.stopTimer()
            self.audioRecorder = nil
            try? self.audioSession.setActive(false, options: [.notifyOthersOnDeactivation])
        }

        guard flag, let url = audioFileURL else {
            DispatchQueue.main.async {
                self.errorMessage = RecorderError.unknown.errorDescription
            }
            cleanupRecordingFile()
            return
        }

        transcribeAudio(at: url)
    }

    private func transcribeAudio(at url: URL) {
        recognitionTask?.cancel()
        recognitionTask = nil

        let request = SFSpeechURLRecognitionRequest(url: url)
        request.shouldReportPartialResults = false

        recognitionTask = speechRecognizer?.recognitionTask(with: request) { [weak self] result, error in
            guard let self = self else { return }
            DispatchQueue.main.async {
                if let result = result {
                    self.transcript = result.bestTranscription.formattedString
                    if result.isFinal {
                        self.recognitionTask = nil
                        self.cleanupRecordingFile()
                    }
                }
                if let error = error {
                    self.errorMessage = error.localizedDescription
                    self.recognitionTask = nil
                    self.cleanupRecordingFile()
                }
            }
        }
    }

    private func cleanupRecordingFile() {
        if let url = audioFileURL {
            try? FileManager.default.removeItem(at: url)
            audioFileURL = nil
        }
    }
}

extension AudioRecorderService: AVAudioRecorderDelegate {
    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        handleFinishRecording(successfully: flag)
    }

    func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        DispatchQueue.main.async {
            self.errorMessage = error?.localizedDescription ?? RecorderError.unknown.errorDescription
            self.isRecording = false
            self.stopTimer()
        }
    }
}
