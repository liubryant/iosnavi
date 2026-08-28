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

enum NavigationVoiceSelectionKind: String {
    case automatic
    case systemVoice
    case personalPack
}

enum NavigationVoicePreference {
    static let selectionKindKey = "navi.tts.voice.selectionKind.v1"
    static let systemVoiceIdentifierKey = "navi.tts.voice.identifier"

    static var selectionKind: NavigationVoiceSelectionKind? {
        get {
            UserDefaults.standard.string(forKey: selectionKindKey)
                .flatMap(NavigationVoiceSelectionKind.init(rawValue:))
        }
        set {
            if let newValue {
                UserDefaults.standard.set(newValue.rawValue, forKey: selectionKindKey)
            } else {
                UserDefaults.standard.removeObject(forKey: selectionKindKey)
            }
        }
    }
}

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
    private let personalAudioEngine = AVAudioEngine()
    private let personalPlayerNode = AVAudioPlayerNode()
    private let personalGainNode = AVAudioUnitEQ(numberOfBands: 0)
    private var personalAudioQueue: [URL] = []
    private var isPersonalAudioScheduled = false
    private var personalPlaybackGeneration = 0
    private var isPersonalAudioEngineConfigured = false
    private var isAudioSessionConfigured = false
    private let selectedVoiceIdentifierKey = NavigationVoicePreference.systemVoiceIdentifierKey
    private let personalVoiceGainDecibels: Float = 5.0

    private override init() {
        super.init()
        restorePersistedVoiceSelection()
    }

    /// 恢复上次在导航设置中选择的语音。旧版本没有保存选择类型时，
    /// 根据已有的系统语音 ID / 个人语音包 ID 自动迁移一次。
    private func restorePersistedVoiceSelection() {
        let defaults = UserDefaults.standard
        let store = PersonalVoicePackStore.shared
        let validPersonalPackID = store.activePackID.flatMap { id in
            store.packs().contains(where: { $0.id == id }) && store.generatedCount(for: id) > 0 ? id : nil
        }
        let validSystemVoiceIdentifier: String? = defaults.string(forKey: selectedVoiceIdentifierKey).flatMap { identifier -> String? in
            guard let voice = AVSpeechSynthesisVoice(identifier: identifier),
                  isChineseVoice(voice), !isExcludedVoice(voice) else { return nil }
            return identifier
        }

        let selectionKind = NavigationVoicePreference.selectionKind
            ?? (validPersonalPackID != nil ? .personalPack : (validSystemVoiceIdentifier != nil ? .systemVoice : .automatic))

        switch selectionKind {
        case .personalPack:
            if let validPersonalPackID {
                store.activePackID = validPersonalPackID
                NavigationVoicePreference.selectionKind = .personalPack
            } else if let validSystemVoiceIdentifier {
                store.activePackID = nil
                defaults.set(validSystemVoiceIdentifier, forKey: selectedVoiceIdentifierKey)
                NavigationVoicePreference.selectionKind = .systemVoice
            } else {
                store.activePackID = nil
                defaults.removeObject(forKey: selectedVoiceIdentifierKey)
                NavigationVoicePreference.selectionKind = .automatic
            }
        case .systemVoice:
            store.activePackID = nil
            if validSystemVoiceIdentifier != nil {
                NavigationVoicePreference.selectionKind = .systemVoice
            } else {
                defaults.removeObject(forKey: selectedVoiceIdentifierKey)
                NavigationVoicePreference.selectionKind = .automatic
            }
        case .automatic:
            store.activePackID = nil
            defaults.removeObject(forKey: selectedVoiceIdentifierKey)
            NavigationVoicePreference.selectionKind = .automatic
        }
    }

    /// 播报一段文字 (按队列顺序播放，对应 Android wordList.addLast)
    func speak(_ text: String) {
        speak(text, voice: resolvedVoice())
    }

    private func speak(_ text: String, voice: AVSpeechSynthesisVoice?) {
        guard !text.isEmpty else { return }
        configureAudioSessionIfNeeded()
        if isPersonalAudioScheduled {
            personalAudioQueue.removeAll()
            stopPersonalAudio()
        }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.pitchMultiplier = 1.0
        synthesizer.speak(utterance)
    }

    /// 驾车导航优先使用已生成的个人语音；未命中时立即回退系统 TTS。
    func speakDrive(_ text: String) {
        let playbackText = PersonalVoicePhrase.personalizedPlaybackText(text)
        let store = PersonalVoicePackStore.shared
        let isExactHit = store.hasExactAudio(for: playbackText)
        let audioURLs = store.audioURLs(for: playbackText)
        guard !audioURLs.isEmpty else {
            // 先立即播报，后台生成不参与本次播放，避免错过转向时机。
            speak(playbackText, voice: personalVoiceFallback())
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                DynamicPersonalVoiceCache.shared.collectAndGenerate(playbackText)
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
                DynamicPersonalVoiceCache.shared.collectAndGenerate(playbackText)
            }
        }
    }

    /// 退出驾车导航时使用完整收尾语，避免只播放“导航结束”显得突然。
    func speakDriveClosing() {
        // 收尾播报独占当前音频队列，避免 SDK 的“退出导航”短提示插队或截断。
        stop()
        speakDrive(PersonalVoicePhrase.closingAnnouncement)
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
        stopPersonalAudio()
    }

    var isSpeaking: Bool {
        synthesizer.isSpeaking || isPersonalAudioScheduled
    }

    private func playNextPersonalAudioIfNeeded() {
        guard !isPersonalAudioScheduled, !personalAudioQueue.isEmpty else { return }
        let url = personalAudioQueue.removeFirst()
        do {
            configurePersonalAudioEngineIfNeeded()
            let audioFile = try AVAudioFile(forReading: url)
            if !personalAudioEngine.isRunning {
                personalAudioEngine.prepare()
                try personalAudioEngine.start()
            }

            personalPlaybackGeneration &+= 1
            let playbackGeneration = personalPlaybackGeneration
            isPersonalAudioScheduled = true
            personalPlayerNode.scheduleFile(
                audioFile,
                at: nil,
                completionCallbackType: .dataPlayedBack
            ) { [weak self] _ in
                DispatchQueue.main.async {
                    self?.personalAudioDidFinishPlaying(generation: playbackGeneration)
                }
            }
            personalPlayerNode.play()
        } catch {
            isPersonalAudioScheduled = false
            playNextPersonalAudioIfNeeded()
        }
    }

    private func configurePersonalAudioEngineIfNeeded() {
        guard !isPersonalAudioEngineConfigured else { return }
        personalGainNode.globalGain = personalVoiceGainDecibels
        personalAudioEngine.attach(personalPlayerNode)
        personalAudioEngine.attach(personalGainNode)
        personalAudioEngine.connect(personalPlayerNode, to: personalGainNode, format: nil)
        personalAudioEngine.connect(personalGainNode, to: personalAudioEngine.mainMixerNode, format: nil)
        isPersonalAudioEngineConfigured = true
    }

    private func personalAudioDidFinishPlaying(generation: Int) {
        guard generation == personalPlaybackGeneration, isPersonalAudioScheduled else { return }
        personalPlayerNode.stop()
        isPersonalAudioScheduled = false
        playNextPersonalAudioIfNeeded()
    }

    private func stopPersonalAudio() {
        personalPlaybackGeneration &+= 1
        personalPlayerNode.stop()
        personalAudioEngine.pause()
        isPersonalAudioScheduled = false
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
        guard !isUsingPersonalVoice else { return nil }
        return resolvedVoice()?.identifier
    }

    var currentVoiceName: String {
        if let pack = PersonalVoicePackStore.shared.activePack {
            return pack.name
        }
        return resolvedVoice()?.name ?? "系统默认"
    }

    var isUsingPersonalVoice: Bool {
        PersonalVoicePackStore.shared.activePack != nil
    }

    var currentPersonalVoicePackID: String? {
        PersonalVoicePackStore.shared.activePackID
    }

    var availablePersonalVoicePacks: [PersonalVoicePackStore.PackInfo] {
        let store = PersonalVoicePackStore.shared
        return store.packs().filter { store.generatedCount(for: $0.id) > 0 }
    }

    var isUsingAutomaticVoice: Bool {
        guard !isUsingPersonalVoice else { return false }
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
        PersonalVoicePackStore.shared.activatePack(nil)
        UserDefaults.standard.set(identifier, forKey: selectedVoiceIdentifierKey)
        NavigationVoicePreference.selectionKind = .systemVoice
    }

    func useAutomaticVoice() {
        stop()
        PersonalVoicePackStore.shared.activatePack(nil)
        UserDefaults.standard.removeObject(forKey: selectedVoiceIdentifierKey)
        NavigationVoicePreference.selectionKind = .automatic
    }

    @discardableResult
    func selectPersonalVoicePack(id: String) -> Bool {
        let store = PersonalVoicePackStore.shared
        guard store.packs().contains(where: { $0.id == id }),
              store.generatedCount(for: id) > 0 else { return false }
        stop()
        store.selectPack(id)
        store.activatePack(id)
        NavigationVoicePreference.selectionKind = .personalPack
        return store.activePackID == id
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
