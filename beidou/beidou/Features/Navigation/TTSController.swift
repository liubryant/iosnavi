//
//  TTSController.swift
//  beidou
//  Author: Liuzheng <bryant_liu24@126.com>
//
//  导航语音播报。对应 Android navi/TTSController.java 的队列播报模式
//  (LinkedList<String> wordList + Handler 轮询)，iOS 用 AVSpeechSynthesizer
//  内置队列(QUEUE_ADD语义)实现，封装为单例供 NaviViewController 使用。
//

import Foundation
import AVFoundation

final class TTSController: NSObject {

    struct VoiceOption: Identifiable {
        let identifier: String
        let name: String
        let language: String
        let quality: AVSpeechSynthesisVoiceQuality

        var id: String { identifier }

        var displayName: String {
            let qualityText = quality == .enhanced ? "（增强）" : ""
            return "\(name)（中文）\(qualityText)"
        }
    }

    static let shared = TTSController()

    private let synthesizer = AVSpeechSynthesizer()
    private var isAudioSessionConfigured = false
    private let selectedVoiceIdentifierKey = "navi.tts.voice.identifier"

    private override init() {
        super.init()
    }

    /// 播报一段文字 (按队列顺序播放，对应 Android wordList.addLast)
    func speak(_ text: String) {
        guard !text.isEmpty else { return }
        configureAudioSessionIfNeeded()
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = resolvedVoice()
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.pitchMultiplier = 1.0
        synthesizer.speak(utterance)
    }

    /// 停止播报并清空队列 (对应 Android stopSpeaking)
    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }

    var isSpeaking: Bool {
        synthesizer.isSpeaking
    }

    var availableChineseVoices: [VoiceOption] {
        let installedVoices = AVSpeechSynthesisVoice.speechVoices()
        // Keep every installed Chinese-region voice (including voices such as
        // “美佳”, which some iOS versions classify as zh-TW), while still
        // excluding the novelty voices explicitly removed from the picker.
        let candidates = installedVoices.filter { isChineseVoice($0) && !isExcludedVoice($0) }

        return candidates
            .sorted { lhs, rhs in
                let lhsLiLian = isLiLianVoice(lhs)
                let rhsLiLian = isLiLianVoice(rhs)
                if lhsLiLian != rhsLiLian { return lhsLiLian }
                let lhsMainland = isMainlandChineseVoice(lhs)
                let rhsMainland = isMainlandChineseVoice(rhs)
                if lhsMainland != rhsMainland { return lhsMainland }
                if lhs.quality != rhs.quality { return lhs.quality.rawValue > rhs.quality.rawValue }
                if lhs.name != rhs.name { return lhs.name.localizedCompare(rhs.name) == .orderedAscending }
                return lhs.identifier < rhs.identifier
            }
            .map {
                VoiceOption(
                    identifier: $0.identifier,
                    name: $0.name,
                    language: $0.language,
                    quality: $0.quality
                )
            }
    }

    var currentVoiceIdentifier: String? {
        resolvedVoice()?.identifier
    }

    var currentVoiceName: String {
        resolvedVoice()?.name ?? "系统默认"
    }

    var isUsingAutomaticVoice: Bool {
        guard let identifier = UserDefaults.standard.string(forKey: selectedVoiceIdentifierKey),
              let voice = AVSpeechSynthesisVoice(identifier: identifier) else {
            return true
        }
        return !isChineseVoice(voice) || isExcludedVoice(voice)
    }

    func selectVoice(identifier: String) {
        guard let voice = AVSpeechSynthesisVoice(identifier: identifier),
              isChineseVoice(voice), !isExcludedVoice(voice) else { return }
        stop()
        UserDefaults.standard.set(identifier, forKey: selectedVoiceIdentifierKey)
    }

    func useAutomaticVoice() {
        stop()
        UserDefaults.standard.removeObject(forKey: selectedVoiceIdentifierKey)
    }

    private func resolvedVoice() -> AVSpeechSynthesisVoice? {
        if let identifier = UserDefaults.standard.string(forKey: selectedVoiceIdentifierKey),
           let selectedVoice = AVSpeechSynthesisVoice(identifier: identifier),
           isChineseVoice(selectedVoice), !isExcludedVoice(selectedVoice) {
            return selectedVoice
        }

        let voices = AVSpeechSynthesisVoice.speechVoices()
        if let liLianVoice = voices.first(where: { isChineseVoice($0) && isLiLianVoice($0) }) {
            return liLianVoice
        }

        if let systemMandarin = AVSpeechSynthesisVoice(language: "zh-CN"),
           !isExcludedVoice(systemMandarin) {
            return systemMandarin
        }
        return voices.first(where: { isMainlandChineseVoice($0) && !isExcludedVoice($0) })
            ?? voices.first(where: { isChineseVoice($0) && !isExcludedVoice($0) })
    }

    private func isChineseVoice(_ voice: AVSpeechSynthesisVoice) -> Bool {
        let language = voice.language.lowercased().replacingOccurrences(of: "_", with: "-")
        return language == "zh" || language.hasPrefix("zh-")
    }

    private func isMainlandChineseVoice(_ voice: AVSpeechSynthesisVoice) -> Bool {
        voice.language.lowercased().replacingOccurrences(of: "_", with: "-") == "zh-cn"
    }

    private func isLiLianVoice(_ voice: AVSpeechSynthesisVoice) -> Bool {
        let searchable = "\(voice.name) \(voice.identifier)".lowercased()
        let aliases = ["黎潋", "li-lian", "li_lian", "li lian", "lilian"]
        return aliases.contains { searchable.contains($0) }
    }

    private func isExcludedVoice(_ voice: AVSpeechSynthesisVoice) -> Bool {
        let searchable = "\(voice.name) \(voice.identifier)".lowercased()
        let excludedNames = ["eddy", "flo", "grandma", "grandpa", "reed"]
        return excludedNames.contains { searchable.contains($0) }
    }

    private func configureAudioSessionIfNeeded() {
        guard !isAudioSessionConfigured else { return }
        do {
            try AVAudioSession.sharedInstance().setCategory(
                .playback,
                mode: .default,
                options: [.mixWithOthers]
            )
            try AVAudioSession.sharedInstance().setActive(true)
            isAudioSessionConfigured = true
        } catch {
            #if DEBUG
            print("TTS audio session configure failed: \(error)")
            #endif
        }
    }
}
