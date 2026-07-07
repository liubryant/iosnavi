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

    static let shared = TTSController()

    private let synthesizer = AVSpeechSynthesizer()
    private let voice = AVSpeechSynthesisVoice(language: "zh-CN")
    private var isAudioSessionConfigured = false

    private override init() {
        super.init()
    }

    /// 播报一段文字 (按队列顺序播放，对应 Android wordList.addLast)
    func speak(_ text: String) {
        guard !text.isEmpty else { return }
        configureAudioSessionIfNeeded()
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
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
