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

final class TTSController: NSObject, AVAudioPlayerDelegate {

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
    private var personalPlayer: AVAudioPlayer?
    private var personalAudioQueue: [URL] = []
    private var isAudioSessionConfigured = false
    private let selectedVoiceIdentifierKey = "navi.tts.voice.identifier"

    private override init() {
        super.init()
    }

    /// 播报一段文字 (按队列顺序播放，对应 Android wordList.addLast)
    func speak(_ text: String) {
        speak(text, voice: resolvedVoice())
    }

    private func speak(_ text: String, voice: AVSpeechSynthesisVoice?) {
        guard !text.isEmpty else { return }
        configureAudioSessionIfNeeded()
        if personalPlayer?.isPlaying == true {
            personalAudioQueue.removeAll()
            personalPlayer?.stop()
            personalPlayer = nil
        }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.pitchMultiplier = 1.0
        synthesizer.speak(utterance)
    }

    /// 驾车导航优先使用已生成的个人语音；未命中时立即回退系统 TTS。
    func speakDrive(_ text: String) {
        let store = PersonalVoicePackStore.shared
        let isExactHit = store.hasExactAudio(for: text)
        let audioURLs = store.audioURLs(for: text)
        guard !audioURLs.isEmpty else {
            // 先立即播报，后台生成不参与本次播放，避免错过转向时机。
            speak(text, voice: personalVoiceFallback())
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                DynamicPersonalVoiceCache.shared.collectAndGenerate(text)
            }
            return
        }
        configureAudioSessionIfNeeded()
        synthesizer.stopSpeaking(at: .immediate)
        personalAudioQueue.append(contentsOf: audioURLs)
        playNextPersonalAudioIfNeeded()
        // 基础片段只能近似覆盖完整文案时，后台继续缓存高德原始整句。
        if !isExactHit {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                DynamicPersonalVoiceCache.shared.collectAndGenerate(text)
            }
        }
    }

    /// 退出驾车导航时使用完整收尾语，避免只播放“导航结束”显得突然。
    func speakDriveClosing() {
        let text = "导航结束，感谢您的使用，请确认车辆已经安全停稳。"
        if let cachedURL = PersonalVoicePackStore.shared.cachedDynamicAudioURL(for: text) {
            configureAudioSessionIfNeeded()
            synthesizer.stopSpeaking(at: .immediate)
            personalAudioQueue.append(cachedURL)
            playNextPersonalAudioIfNeeded()
            return
        }

        // 第一次立即使用系统声音，完整个人声音在后台生成供下次使用。
        speak(text, voice: personalVoiceFallback())
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            DynamicPersonalVoiceCache.shared.collectAndGenerate(text)
        }
    }

    /// 算路完成后后台预热路线文案；不等待、不影响开始导航。
    func prewarmDriveVoice(_ texts: [String]) {
        DispatchQueue.main.async {
            DynamicPersonalVoiceCache.shared.prewarm(texts)
        }
    }

    /// 收集当前播报模式过滤掉的高德文案，不影响本次语音播放。
    func collectDriveVoiceForCache(_ text: String) {
        DispatchQueue.main.async {
            DynamicPersonalVoiceCache.shared.collectForLater(text)
        }
    }

    private func personalVoiceFallback() -> AVSpeechSynthesisVoice? {
        let voices = AVSpeechSynthesisVoice.speechVoices()
        let gender = PersonalVoicePackStore.shared.activeGender
        if gender == .male {
            let aliases = ["彬彬", "binbin", "bin-bin", "bin_bin", "bin bin"]
            if let binbin = voices.first(where: { voice in
                let searchable = "\(voice.name) \(voice.identifier)".lowercased()
                return voice.language.lowercased().hasPrefix("zh") && aliases.contains { searchable.contains($0) }
            }) { return binbin }
            return voices.filter { $0.language.lowercased().hasPrefix("zh") && $0.gender == .male }
                .sorted { $0.quality.rawValue > $1.quality.rawValue }.first
                ?? AVSpeechSynthesisVoice(language: "zh-CN")
        }

        let aliases = ["黎潋", "li-lian", "li_lian", "li lian", "lilian", "tingting", "meijia", "mei-jia"]
        if let preferred = voices.first(where: { voice in
            let searchable = "\(voice.name) \(voice.identifier)".lowercased()
            return voice.language.lowercased().hasPrefix("zh") && aliases.contains { searchable.contains($0) }
        }) { return preferred }
        return voices.filter { $0.language.lowercased().hasPrefix("zh") && $0.gender == .female }
            .sorted { $0.quality.rawValue > $1.quality.rawValue }.first
            ?? AVSpeechSynthesisVoice(language: "zh-CN")
    }

    /// 停止播报并清空队列 (对应 Android stopSpeaking)
    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        personalAudioQueue.removeAll()
        personalPlayer?.stop()
        personalPlayer = nil
    }

    var isSpeaking: Bool {
        synthesizer.isSpeaking || personalPlayer?.isPlaying == true
    }

    private func playNextPersonalAudioIfNeeded() {
        guard personalPlayer?.isPlaying != true, !personalAudioQueue.isEmpty else { return }
        let url = personalAudioQueue.removeFirst()
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.delegate = self
            player.prepareToPlay()
            personalPlayer = player
            player.play()
        } catch {
            personalPlayer = nil
        }
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        personalPlayer = nil
        playNextPersonalAudioIfNeeded()
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
        let excludedNames = [
            "eddy", "flo", "grandma", "grandpa", "reed",
            "rocko", "sandy", "shelly", "shelley"
        ]
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
