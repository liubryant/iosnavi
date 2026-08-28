import UIKit
import AVFoundation
import CryptoKit
import UniformTypeIdentifiers

struct PersonalVoicePhrase: Codable, Hashable {
    let id: String
    let text: String

    private static var isVIPMember: Bool {
        UserDefaults.standard.bool(forKey: "vip_active")
    }

    static var navigationOpeningPhrase: PersonalVoicePhrase {
        isVIPMember
            ? .init(id: "vip_start_v1", text: "尊敬的VIP会员，导航已开始，请注意行车安全，祝您一路顺风。")
            : .init(id: "start", text: "开始导航")
    }

    static var navigationClosingPhrase: PersonalVoicePhrase {
        isVIPMember
            ? .init(id: "vip_navigation_end_v1", text: "尊敬的VIP会员，本次导航已结束，感谢您的使用，请确认车辆已经安全停稳。")
            : .init(id: "navigation_end", text: "导航结束")
    }

    static var closingAnnouncement: String {
        isVIPMember
            ? navigationClosingPhrase.text
            : "导航结束，感谢您的使用，请确认车辆已经安全停稳。"
    }

    static func personalizedPlaybackText(_ text: String) -> String {
        guard isVIPMember,
              isOpeningInstruction(text),
              !text.contains("尊敬的VIP会员") else { return text }
        return navigationOpeningPhrase.text + text
    }

    static func isOpeningInstruction(_ text: String) -> Bool {
        text.contains("准备出发") || text.contains("开始导航") || text.contains("导航已开始")
    }

    static var driveCatalog: [PersonalVoicePhrase] {
        [
            navigationOpeningPhrase,
            navigationClosingPhrase,
            .init(id: "arrived", text: "您已到达目的地"),
        .init(id: "rerouting", text: "路线重新规划"),
        .init(id: "straight", text: "请保持直行"),
        .init(id: "turn_left", text: "前方左转"),
        .init(id: "turn_right", text: "前方右转"),
        .init(id: "uturn", text: "前方掉头"),
        .init(id: "keep_left", text: "请靠左行驶"),
        .init(id: "keep_right", text: "请靠右行驶"),
        .init(id: "enter_ramp", text: "前方进入匝道"),
        .init(id: "exit_ramp", text: "前方驶出匝道"),
        .init(id: "enter_roundabout", text: "前方进入环岛"),
        .init(id: "exit_roundabout", text: "前方驶出环岛"),
        .init(id: "slow_down", text: "前方路段请减速慢行"),
        .init(id: "destination_ahead", text: "目的地就在前方"),
        .init(id: "gps_weak", text: "卫星定位信号弱"),
        .init(id: "100_left", text: "前方100米左转"),
        .init(id: "100_right", text: "前方100米右转"),
        .init(id: "200_left", text: "前方200米左转"),
        .init(id: "200_right", text: "前方200米右转"),
        .init(id: "300_left", text: "前方300米左转"),
        .init(id: "300_right", text: "前方300米右转"),
        .init(id: "500_left", text: "前方500米左转"),
        .init(id: "500_right", text: "前方500米右转"),
        .init(id: "1km_left", text: "前方1公里左转"),
        .init(id: "1km_right", text: "前方1公里右转"),
        .init(id: "100_ramp", text: "前方100米进入匝道"),
        .init(id: "300_ramp", text: "前方300米进入匝道"),
        .init(id: "500_ramp", text: "前方500米进入匝道"),
        .init(id: "100_exit", text: "前方100米驶出匝道"),
        .init(id: "300_exit", text: "前方300米驶出匝道"),
            .init(id: "500_exit", text: "前方500米驶出匝道")
        ]
    }
}

struct DynamicPersonalVoiceEntry: Codable, Hashable {
    let id: String
    var text: String
    var hitCount: Int
    let createdAt: Date
    var lastUsedAt: Date
}

enum PersonalVoiceGender: String, Codable {
    case male
    case female
}

final class PersonalVoicePackStore {
    struct PackInfo: Codable, Equatable {
        let id: String
        var name: String
        var gender: PersonalVoiceGender
        let createdAt: Date
        var allowsDynamicGeneration: Bool? = nil
        var syncsExistingDynamicVoices: Bool? = nil
    }

    static let shared = PersonalVoicePackStore()
    private let packsKey = "navi.personalVoice.packs.v2"
    private let activePackKey = "navi.personalVoice.activePackID.v2"
    private let fileManager = FileManager.default
    private(set) var selectedPackID: String?

    private init() {
        migrateLegacyPackIfNeeded()
        selectedPackID = activePackID ?? packs().first?.id
    }

    private var packsRoot: URL {
        fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PersonalDriveVoicePacks", isDirectory: true)
    }

    private var legacyDirectory: URL {
        fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PersonalDriveVoicePack", isDirectory: true)
    }

    var activePackID: String? {
        get { UserDefaults.standard.string(forKey: activePackKey) }
        set {
            if let newValue { UserDefaults.standard.set(newValue, forKey: activePackKey) }
            else { UserDefaults.standard.removeObject(forKey: activePackKey) }
        }
    }

    var activePack: PackInfo? {
        guard let id = activePackID else { return nil }
        return packs().first { $0.id == id }
    }

    var isEnabled: Bool {
        get { selectedPackID != nil && activePackID == selectedPackID }
        set {
            if newValue, let selectedPackID {
                activatePack(selectedPackID)
            } else if activePackID == selectedPackID {
                activatePack(nil)
            }
        }
    }

    var gender: PersonalVoiceGender {
        get { selectedPack?.gender ?? .male }
        set { updateSelectedPack { $0.gender = newValue } }
    }

    var activeGender: PersonalVoiceGender { activePack?.gender ?? .male }

    var shouldSyncExistingDynamicVoices: Bool {
        selectedPack?.syncsExistingDynamicVoices == true
    }

    func setShouldSyncExistingDynamicVoices(_ enabled: Bool) {
        updateSelectedPack { $0.syncsExistingDynamicVoices = enabled }
    }

    var selectedPack: PackInfo? {
        guard let id = selectedPackID else { return nil }
        return packs().first { $0.id == id }
    }

    func packs() -> [PackInfo] {
        guard let data = UserDefaults.standard.data(forKey: packsKey),
              let values = try? JSONDecoder().decode([PackInfo].self, from: data) else { return [] }
        return values.sorted { $0.createdAt < $1.createdAt }
    }

    @discardableResult
    func createPack(name: String, gender: PersonalVoiceGender) throws -> PackInfo {
        let pack = PackInfo(id: UUID().uuidString, name: name, gender: gender, createdAt: Date())
        var values = packs()
        values.append(pack)
        try save(values)
        selectedPackID = pack.id
        try ensureDirectory()
        return pack
    }

    func selectPack(_ id: String) {
        guard packs().contains(where: { $0.id == id }) else { return }
        selectedPackID = id
    }

    func activatePack(_ id: String?) {
        guard let id else {
            activePackID = nil
            if NavigationVoicePreference.selectionKind == .personalPack {
                NavigationVoicePreference.selectionKind = .automatic
            }
            return
        }
        guard packs().contains(where: { $0.id == id }), generatedCount(for: id) > 0 else { return }
        activePackID = id
        NavigationVoicePreference.selectionKind = .personalPack
    }

    var packDirectory: URL {
        let id = selectedPackID ?? "unselected"
        return packsRoot.appendingPathComponent(id, isDirectory: true)
    }

    var referenceAudioURL: URL {
        existingReferenceAudioURL(in: packDirectory) ?? recordingReferenceAudioURL
    }

    var recordingReferenceAudioURL: URL {
        packDirectory.appendingPathComponent("reference.wav")
    }

    private func existingReferenceAudioURL(in directory: URL) -> URL? {
        for ext in ["mp3", "wav", "m4a"] {
            let url = directory.appendingPathComponent("reference.\(ext)")
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        return nil
    }

    func replaceReferenceAudio(with sourceURL: URL) throws -> URL {
        try ensureDirectory()
        let ext = sourceURL.pathExtension.lowercased()
        guard ["mp3", "wav", "m4a"].contains(ext) else {
            throw CocoaError(.fileReadUnsupportedScheme)
        }
        let destination = packDirectory.appendingPathComponent("reference.\(ext)")
        for oldExt in ["mp3", "wav", "m4a"] {
            let oldURL = packDirectory.appendingPathComponent("reference.\(oldExt)")
            if oldURL != destination, FileManager.default.fileExists(atPath: oldURL.path) {
                try FileManager.default.removeItem(at: oldURL)
            }
        }
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: sourceURL, to: destination)
        return destination
    }

    private var referenceTextURL: URL { packDirectory.appendingPathComponent("reference.txt") }

    private func directory(for packID: String) -> URL {
        packsRoot.appendingPathComponent(packID, isDirectory: true)
    }

    private func dynamicDirectory(for packID: String) -> URL {
        directory(for: packID).appendingPathComponent("dynamic", isDirectory: true)
    }

    private func dynamicManifestURL(for packID: String) -> URL {
        directory(for: packID).appendingPathComponent("dynamic-voices.json")
    }

    func audioURL(for phrase: PersonalVoicePhrase) -> URL {
        packDirectory.appendingPathComponent("\(phrase.id).wav")
    }

    func audioURLs(for text: String) -> [URL] {
        guard let activeID = activePackID else { return [] }
        let directory = packsRoot.appendingPathComponent(activeID, isDirectory: true)
        if let cached = cachedDynamicAudioURL(for: text, packID: activeID) {
            return [cached]
        }
        let normalized = Self.normalize(text)
        if let exact = PersonalVoicePhrase.driveCatalog.first(where: { Self.normalize($0.text) == normalized }),
           let url = existingURL(id: exact.id, directory: directory) {
            return [url]
        }

        var result: [URL] = []
        func append(_ id: String) {
            if let url = existingURL(id: id, directory: directory), !result.contains(url) { result.append(url) }
        }

        // 高德首次播报通常是“准备出发，全程xx米，大约需要xx分钟，右转”。
        // 路程与时间是动态数据，使用本地“开始导航 + 转向动作”代替系统音色朗读整句。
        if PersonalVoicePhrase.isOpeningInstruction(normalized) {
            let openingID = PersonalVoicePhrase.navigationOpeningPhrase.id
            guard let openingURL = existingURL(id: openingID, directory: directory) else {
                // 开场语缺失时整句回退系统 TTS，不能只播后半段转向提示。
                return []
            }
            result.append(openingURL)
        }
        if normalized.contains("到达目的地") || normalized.contains("您已到达") { append("arrived"); return result }
        if normalized.contains("重新规划") { append("rerouting"); return result }
        if normalized.contains("卫星定位信号弱") { append("gps_weak"); return result }

        let clauses = text.components(separatedBy: CharacterSet(charactersIn: "，。,.；;！!"))
            .map { Self.normalize($0) }
            .filter { !$0.isEmpty }
        let instruction = clauses.last ?? normalized

        if instruction.contains("驶出环岛") { append("exit_roundabout") }
        else if instruction.contains("进入环岛") { append("enter_roundabout") }
        else if instruction.contains("驶出匝道") || instruction.contains("驶离匝道") {
            append(Self.distanceID(in: instruction, suffix: "exit") ?? "exit_ramp")
        } else if instruction.contains("进入匝道") || instruction.contains("驶入匝道") {
            append(Self.distanceID(in: instruction, suffix: "ramp") ?? "enter_ramp")
        } else if instruction.contains("掉头") { append("uturn") }
        else if instruction.contains("靠左") { append("keep_left") }
        else if instruction.contains("靠右") { append("keep_right") }
        else if instruction.contains("左转") {
            append(Self.distanceID(in: instruction, suffix: "left") ?? "turn_left")
        } else if instruction.contains("右转") {
            append(Self.distanceID(in: instruction, suffix: "right") ?? "turn_right")
        } else if instruction.contains("直行") { append("straight") }
        else if instruction.contains("减速") { append("slow_down") }
        else if instruction.contains("目的地就在前方") { append("destination_ahead") }

        return result
    }

    func hasExactAudio(for text: String) -> Bool {
        guard let activeID = activePackID else { return false }
        if cachedDynamicAudioURL(for: text, packID: activeID) != nil { return true }
        let normalized = Self.normalize(text)
        guard let phrase = PersonalVoicePhrase.driveCatalog.first(where: { Self.normalize($0.text) == normalized }) else {
            return false
        }
        return existingURL(id: phrase.id, directory: directory(for: activeID)) != nil
    }

    func saveReferenceText(_ text: String) throws {
        try ensureDirectory()
        try text.data(using: .utf8)?.write(to: referenceTextURL, options: .atomic)
        updateSelectedPack { $0.allowsDynamicGeneration = true }
    }

    func selectedReferenceText() -> String? {
        guard let data = try? Data(contentsOf: referenceTextURL) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func activeGenerationContext() -> (packID: String, referenceText: String, referenceAudioURL: URL)? {
        guard let pack = activePack else { return nil }
        return generationContext(for: pack.id)
    }

    func generationContext(for packID: String) -> (packID: String, referenceText: String, referenceAudioURL: URL)? {
        guard let pack = packs().first(where: { $0.id == packID }),
              pack.allowsDynamicGeneration == true else { return nil }
        let directory = directory(for: pack.id)
        guard let audioURL = existingReferenceAudioURL(in: directory) else { return nil }
        let textURL = directory.appendingPathComponent("reference.txt")
        guard isValidAudio(at: audioURL),
              let data = try? Data(contentsOf: textURL),
              let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else { return nil }
        return (pack.id, text, audioURL)
    }

    /// 汇总其他语音包已经成功生成的动态文案。新音色只复用文案，不复用
    /// 旧音频，后续会使用新语音包自己的参考录音重新合成。
    func generatedDynamicEntriesFromOtherPacks(excluding packID: String) -> [DynamicPersonalVoiceEntry] {
        var merged: [String: DynamicPersonalVoiceEntry] = [:]
        for pack in packs() where pack.id != packID {
            for entry in dynamicEntries(for: pack.id, generatedOnly: true) {
                let key = Self.normalize(entry.text)
                guard !key.isEmpty else { continue }
                if var existing = merged[key] {
                    existing.hitCount += entry.hitCount
                    if entry.lastUsedAt > existing.lastUsedAt {
                        existing.lastUsedAt = entry.lastUsedAt
                        existing.text = entry.text
                    }
                    merged[key] = existing
                } else {
                    merged[key] = entry
                }
            }
        }
        return merged.values.sorted {
            if $0.hitCount != $1.hitCount { return $0.hitCount > $1.hitCount }
            return $0.lastUsedAt > $1.lastUsedAt
        }
    }

    @discardableResult
    func recordDynamicRequest(_ text: String, packID: String) -> DynamicPersonalVoiceEntry? {
        let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanText.isEmpty else { return nil }
        let id = Self.dynamicID(for: cleanText)
        var entries = dynamicEntries(for: packID, generatedOnly: false)
        if let index = entries.firstIndex(where: { $0.id == id }) {
            entries[index].hitCount += 1
            entries[index].lastUsedAt = Date()
            try? saveDynamicEntries(entries, packID: packID)
            return entries[index]
        }
        let entry = DynamicPersonalVoiceEntry(id: id, text: cleanText, hitCount: 1, createdAt: Date(), lastUsedAt: Date())
        entries.append(entry)
        try? saveDynamicEntries(entries, packID: packID)
        return entry
    }

    func dynamicEntries(for packID: String? = nil, generatedOnly: Bool = true) -> [DynamicPersonalVoiceEntry] {
        guard let id = packID ?? selectedPackID,
              let data = try? Data(contentsOf: dynamicManifestURL(for: id)),
              let entries = try? JSONDecoder().decode([DynamicPersonalVoiceEntry].self, from: data) else { return [] }
        // 清单和页面统计只做轻量文件检查。逐个创建 AVAudioPlayer 验证数百条
        // WAV 会阻塞主线程；真正播放和刚生成保存时仍会校验音频有效性。
        let filtered = generatedOnly ? entries.filter { hasCachedDynamicAudio(forID: $0.id, packID: id) } : entries
        return filtered.sorted { $0.lastUsedAt > $1.lastUsedAt }
    }

    func cachedDynamicCount(for packID: String? = nil) -> Int {
        dynamicEntries(for: packID, generatedOnly: true).count
    }

    func cachedDynamicAudioURL(for text: String, packID: String? = nil) -> URL? {
        guard let id = packID ?? activePackID else { return nil }
        return cachedDynamicAudioURL(forID: Self.dynamicID(for: text), packID: id)
    }

    func saveDynamicAudio(_ data: Data, text: String, packID: String) throws {
        guard (try? AVAudioPlayer(data: data)) != nil else {
            throw NSError(domain: "PersonalVoicePack", code: 2, userInfo: [NSLocalizedDescriptionKey: "动态语音不是有效音频"])
        }
        let folder = dynamicDirectory(for: packID)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let dynamicID = Self.dynamicID(for: cleanText)
        var entries = dynamicEntries(for: packID, generatedOnly: false)
        if !entries.contains(where: { $0.id == dynamicID }) {
            entries.append(DynamicPersonalVoiceEntry(
                id: dynamicID,
                text: cleanText,
                hitCount: 1,
                createdAt: Date(),
                lastUsedAt: Date()
            ))
            try saveDynamicEntries(entries, packID: packID)
        }
        try data.write(to: folder.appendingPathComponent("\(dynamicID).wav"), options: .atomic)
    }

    private func cachedDynamicAudioURL(forID id: String, packID: String) -> URL? {
        let url = dynamicDirectory(for: packID).appendingPathComponent("\(id).wav")
        return isValidAudio(at: url) ? url : nil
    }

    private func hasCachedDynamicAudio(forID id: String, packID: String) -> Bool {
        let url = dynamicDirectory(for: packID).appendingPathComponent("\(id).wav")
        guard fileManager.fileExists(atPath: url.path),
              let attributes = try? fileManager.attributesOfItem(atPath: url.path),
              let byteCount = attributes[.size] as? NSNumber else { return false }
        return byteCount.intValue > 1_000
    }

    private func saveDynamicEntries(_ entries: [DynamicPersonalVoiceEntry], packID: String) throws {
        try fileManager.createDirectory(at: directory(for: packID), withIntermediateDirectories: true)
        try JSONEncoder().encode(entries).write(to: dynamicManifestURL(for: packID), options: .atomic)
    }

    private static func dynamicID(for text: String) -> String {
        SHA256.hash(data: Data(normalize(text).utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private func existingURL(id: String, directory: URL) -> URL? {
        guard let phrase = PersonalVoicePhrase.driveCatalog.first(where: { $0.id == id }) else { return nil }
        let url = directory.appendingPathComponent("\(phrase.id).wav")
        return isValidAudio(at: url) ? url : nil
    }

    func ensureDirectory() throws {
        try fileManager.createDirectory(at: packDirectory, withIntermediateDirectories: true)
    }

    func generatedCount() -> Int {
        PersonalVoicePhrase.driveCatalog.filter(isGenerated).count
    }

    func isGenerated(_ phrase: PersonalVoicePhrase) -> Bool {
        isValidAudio(at: audioURL(for: phrase))
    }

    func generatedCount(for packID: String) -> Int {
        let directory = packsRoot.appendingPathComponent(packID, isDirectory: true)
        return PersonalVoicePhrase.driveCatalog.filter {
            isValidAudio(at: directory.appendingPathComponent("\($0.id).wav"))
        }.count
    }

    func generatedPhrases(for packID: String? = nil) -> [PersonalVoicePhrase] {
        let id = packID ?? selectedPackID
        guard let id else { return [] }
        let directory = packsRoot.appendingPathComponent(id, isDirectory: true)
        return PersonalVoicePhrase.driveCatalog.filter {
            isValidAudio(at: directory.appendingPathComponent("\($0.id).wav"))
        }
    }

    func generatedAudioURL(for phrase: PersonalVoicePhrase, packID: String? = nil) -> URL? {
        let id = packID ?? selectedPackID
        guard let id else { return nil }
        let url = packsRoot.appendingPathComponent(id, isDirectory: true)
            .appendingPathComponent("\(phrase.id).wav")
        return isValidAudio(at: url) ? url : nil
    }

    private func isValidAudio(at url: URL) -> Bool {
        guard fileManager.fileExists(atPath: url.path),
              let attributes = try? fileManager.attributesOfItem(atPath: url.path),
              let byteCount = attributes[.size] as? NSNumber,
              byteCount.intValue > 1_000,
              let player = try? AVAudioPlayer(contentsOf: url),
              player.duration > 0.05 else {
            return false
        }
        return true
    }

    func removePack() throws {
        guard let id = selectedPackID else { return }
        try removePack(id: id)
    }

    func removePack(id: String) throws {
        let directory = packsRoot.appendingPathComponent(id, isDirectory: true)
        if fileManager.fileExists(atPath: directory.path) { try fileManager.removeItem(at: directory) }
        var values = packs()
        values.removeAll { $0.id == id }
        try save(values)
        if activePackID == id { activatePack(nil) }
        if selectedPackID == id { selectedPackID = values.first?.id }
    }

    private func updateSelectedPack(_ change: (inout PackInfo) -> Void) {
        guard let id = selectedPackID else { return }
        var values = packs()
        guard let index = values.firstIndex(where: { $0.id == id }) else { return }
        change(&values[index])
        try? save(values)
    }

    func renameSelectedPack(to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        updateSelectedPack { $0.name = trimmed }
    }

    private func save(_ values: [PackInfo]) throws {
        let data = try JSONEncoder().encode(values)
        UserDefaults.standard.set(data, forKey: packsKey)
    }

    private func migrateLegacyPackIfNeeded() {
        guard packs().isEmpty, fileManager.fileExists(atPath: legacyDirectory.path) else { return }
        let id = "legacy-voice-pack"
        let target = packsRoot.appendingPathComponent(id, isDirectory: true)
        do {
            try fileManager.createDirectory(at: packsRoot, withIntermediateDirectories: true)
            if !fileManager.fileExists(atPath: target.path) { try fileManager.copyItem(at: legacyDirectory, to: target) }
            let oldGender = PersonalVoiceGender(rawValue: UserDefaults.standard.string(forKey: "navi.personalVoice.gender") ?? "") ?? .male
            try save([PackInfo(id: id, name: "我的语音包", gender: oldGender, createdAt: Date())])
            if UserDefaults.standard.bool(forKey: "navi.personalVoice.enabled") { activePackID = id }
        } catch {
            #if DEBUG
            print("Voice pack migration failed: \(error)")
            #endif
        }
    }

    private static func normalize(_ text: String) -> String {
        var value = text.replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "，", with: "")
            .replacingOccurrences(of: "。", with: "")
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: ".", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let replacements = [
            "一百": "100", "两百": "200", "二百": "200", "三百": "300", "五百": "500",
            "一公里": "1公里", "向左转": "左转", "向右转": "右转", "米处": "米"
        ]
        for (source, target) in replacements {
            value = value.replacingOccurrences(of: source, with: target)
        }
        return value
    }

    private static func distanceID(in text: String, suffix: String) -> String? {
        for (token, id) in [("100米", "100"), ("200米", "200"), ("300米", "300"), ("500米", "500"), ("1公里", "1km")] {
            if text.contains(token) { return "\(id)_\(suffix)" }
        }
        return nil
    }
}

final class Audio8VoiceClient {
    enum ClientError: LocalizedError {
        case invalidResponse
        case server(Int, String)
        case unsupportedResponse

        var errorDescription: String? {
            switch self {
            case .invalidResponse: return "Audio8 返回无效响应"
            case let .server(code, message): return "Audio8 服务错误（\(code)）：\(message)"
            case .unsupportedResponse: return "Audio8 未返回可播放的音频"
            }
        }

        var isModelWarmingUp: Bool {
            guard case let .server(code, message) = self, code == 503 else { return false }
            let value = message.lowercased()
            return value.contains("warming up") || value.contains("loading") || value.contains("starting")
        }
    }

    private let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 240
        configuration.timeoutIntervalForResource = 300
        return URLSession(configuration: configuration)
    }()

    func generate(text: String, referenceText: String, audioURL: URL, completion: @escaping (Result<Data, Error>) -> Void) -> URLSessionDataTask? {
        guard let url = URL(string: UrlConstants.audio8Generate), let audio = try? Data(contentsOf: audioURL) else {
            completion(.failure(ClientError.invalidResponse))
            return nil
        }
        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = multipartBody(
            boundary: boundary,
            text: text,
            referenceText: referenceText,
            audio: audio,
            audioURL: audioURL
        )

        let task = session.dataTask(with: request) { data, response, error in
            if let error { completion(.failure(error)); return }
            guard let http = response as? HTTPURLResponse, let data else {
                completion(.failure(ClientError.invalidResponse)); return
            }
            guard (200...299).contains(http.statusCode) else {
                let message = String(data: data.prefix(500), encoding: .utf8) ?? "请求失败"
                completion(.failure(ClientError.server(http.statusCode, message))); return
            }
            if data.starts(with: [0x52, 0x49, 0x46, 0x46]) || http.value(forHTTPHeaderField: "Content-Type")?.lowercased().contains("audio/") == true {
                completion(.success(data)); return
            }
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let encoded = (json["audio_base64"] ?? json["audio"]) as? String,
               let audioData = Data(base64Encoded: encoded) {
                completion(.success(audioData)); return
            }
            completion(.failure(ClientError.unsupportedResponse))
        }
        task.resume()
        return task
    }

    /// 导航中的动态补充专用：文件读取和 multipart 组装全部在后台完成。
    func generateInBackground(text: String, referenceText: String, audioURL: URL, completion: @escaping (Result<Data, Error>) -> Void) {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            _ = self.generate(text: text, referenceText: referenceText, audioURL: audioURL, completion: completion)
        }
    }

    private func multipartBody(boundary: String, text: String, referenceText: String, audio: Data, audioURL: URL) -> Data {
        var body = Data()
        func field(_ name: String, _ value: String) {
            body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".data(using: .utf8)!)
        }
        field("text", text)
        field("reference_text", referenceText)
        field("temperature", "0.8")
        field("top_p", "0.95")
        field("top_k", "50")
        field("max_new_tokens", "256")
        let ext = audioURL.pathExtension.lowercased()
        let mimeType: String
        switch ext {
        case "mp3": mimeType = "audio/mpeg"
        case "m4a": mimeType = "audio/mp4"
        default: mimeType = "audio/wav"
        }
        body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"reference_audio\"; filename=\"reference.\(ext.isEmpty ? "wav" : ext)\"\r\nContent-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(audio)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        return body
    }
}

/// 在后台串行补齐未命中的动态导航文案。导航播放绝不等待此队列。
final class DynamicPersonalVoiceCache {
    static let shared = DynamicPersonalVoiceCache()

    private struct WorkItem {
        let text: String
        let packID: String
        let referenceText: String
        let referenceAudioURL: URL
        let retryCount: Int
    }

    private let store = PersonalVoicePackStore.shared
    private let client = Audio8VoiceClient()
    private var pending: [WorkItem] = []
    private var queuedKeys = Set<String>()
    private var attemptedKeys = Set<String>()
    private var isGenerating = false

    private init() {}

    /// 实际播报未命中时优先加入队首，但调用方应当先播放系统兜底语音。
    func collectAndGenerate(_ text: String) {
        enqueue(text, highPriority: true)
    }

    /// 当前播报模式不朗读的文案也保留为低优先级缓存候选。
    func collectForLater(_ text: String) {
        enqueue(text, highPriority: false)
    }

    /// 算路成功后预热前若干条路线诱导，不阻塞开始导航。
    func prewarm(_ texts: [String]) {
        var seen = Set<String>()
        var acceptedCount = 0
        // 不使用 lazy.prefix：高德回调可能来自地图渲染线程，延迟序列在部分
        // SDK 数据桥接场景中会触发 Collection 下标范围异常。
        for text in texts {
            guard acceptedCount < 12 else { break }
            let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleanText.isEmpty, seen.insert(cleanText).inserted else { continue }
            enqueue(cleanText, highPriority: false)
            acceptedCount += 1
        }
    }

    /// 新语音包完成基础词条后，在后台串行补齐其他语音包已有的动态文案。
    /// 不限制为导航预热队列的20条上限；真实导航的高优先级文案仍会插队。
    func backfillExistingDynamicVoices(into packID: String) {
        guard let context = store.generationContext(for: packID) else { return }
        let entries = store.generatedDynamicEntriesFromOtherPacks(excluding: packID)
        for entry in entries {
            enqueue(
                entry.text,
                context: context,
                highPriority: false,
                maximumPendingCount: nil
            )
        }
    }

    private func enqueue(_ text: String, highPriority: Bool) {
        let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (2...180).contains(cleanText.count),
              let context = store.activeGenerationContext(),
              store.cachedDynamicAudioURL(for: cleanText, packID: context.packID) == nil else { return }

        enqueue(
            cleanText,
            context: context,
            highPriority: highPriority,
            maximumPendingCount: highPriority ? 30 : 20
        )
    }

    private func enqueue(
        _ text: String,
        context: (packID: String, referenceText: String, referenceAudioURL: URL),
        highPriority: Bool,
        maximumPendingCount: Int?
    ) {
        let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (2...180).contains(cleanText.count),
              store.cachedDynamicAudioURL(for: cleanText, packID: context.packID) == nil else { return }

        let key = "\(context.packID)|\(cleanText)"
        _ = store.recordDynamicRequest(cleanText, packID: context.packID)
        guard !queuedKeys.contains(key), !attemptedKeys.contains(key) else { return }
        // 队列满时不做“已入队”标记，后续再次遇到该文案仍可补充。
        if let maximumPendingCount, pending.count >= maximumPendingCount { return }
        let item = WorkItem(
            text: cleanText,
            packID: context.packID,
            referenceText: context.referenceText,
            referenceAudioURL: context.referenceAudioURL,
            retryCount: 0
        )
        queuedKeys.insert(key)
        if highPriority { pending.insert(item, at: 0) }
        else { pending.append(item) }
        startNextIfNeeded()
    }

    private func startNextIfNeeded() {
        guard !isGenerating, !pending.isEmpty else { return }
        isGenerating = true
        let item = pending.removeFirst()
        let key = "\(item.packID)|\(item.text)"
        queuedKeys.remove(key)
        attemptedKeys.insert(key)
        client.generateInBackground(
            text: item.text,
            referenceText: item.referenceText,
            audioURL: item.referenceAudioURL
        ) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                var didSave = false
                if case let .success(data) = result {
                    do {
                        try self.store.saveDynamicAudio(data, text: item.text, packID: item.packID)
                        didSave = true
                    } catch {
                        #if DEBUG
                        print("Dynamic voice save failed: \(error.localizedDescription)")
                        #endif
                    }
                }
                self.isGenerating = false
                self.attemptedKeys.remove(key)
                if !didSave, item.retryCount < 2 {
                    let retryItem = WorkItem(
                        text: item.text,
                        packID: item.packID,
                        referenceText: item.referenceText,
                        referenceAudioURL: item.referenceAudioURL,
                        retryCount: item.retryCount + 1
                    )
                    self.queuedKeys.insert(key)
                    let delay: TimeInterval = item.retryCount == 0 ? 8 : 15
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                        guard let self else { return }
                        self.pending.append(retryItem)
                        self.startNextIfNeeded()
                    }
                }
                self.startNextIfNeeded()
            }
        }
    }
}

/// 个人语音包顶部的视频式引导。视频为本地资源，不消耗流量；文字覆盖层
/// 跟随视频进度切换，即使视频资源异常也能完整展示操作步骤。
private final class PersonalVoiceGradientButton: UIButton {
    private static let backgroundColors = [
        UIColor(red: 0.08, green: 0.58, blue: 1.0, alpha: 1).cgColor,
        UIColor(red: 0.12, green: 0.38, blue: 0.94, alpha: 1).cgColor,
        UIColor(red: 0.29, green: 0.31, blue: 0.90, alpha: 1).cgColor
    ]

    private static func makeGradientBackgroundImage(size: CGSize) -> UIImage {
        UIGraphicsImageRenderer(size: size).image { context in
            guard let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: backgroundColors as CFArray,
                locations: [0, 0.55, 1]
            ) else { return }
            context.cgContext.drawLinearGradient(
                gradient,
                start: CGPoint(x: 0, y: size.height / 2),
                end: CGPoint(x: size.width, y: size.height / 2),
                options: []
            )
        }
    }

    static let gradientBackgroundImage: UIImage = {
        makeGradientBackgroundImage(size: CGSize(width: 320, height: 58))
            .resizableImage(withCapInsets: UIEdgeInsets(top: 20, left: 70, bottom: 20, right: 70), resizingMode: .stretch)
    }()

    /// 顶部紧凑按钮不能使用宽按钮的 capInsets，否则左右渐变会被压缩。
    static let compactGradientBackgroundImage = makeGradientBackgroundImage(
        size: CGSize(width: 96, height: 42)
    )

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupStyle()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupStyle()
    }

    override var isEnabled: Bool {
        didSet { alpha = isEnabled ? 1 : 0.48 }
    }

    private func setupStyle() {
        layer.cornerRadius = 15
        layer.cornerCurve = .continuous
        layer.shadowColor = UIColor(red: 0.05, green: 0.35, blue: 0.90, alpha: 1).cgColor
        layer.shadowOpacity = 0.24
        layer.shadowRadius = 10
        layer.shadowOffset = CGSize(width: 0, height: 6)
        tintColor = .white
        setTitleColor(.white, for: .normal)
        setTitleColor(UIColor.white.withAlphaComponent(0.72), for: .disabled)
        titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        addTarget(self, action: #selector(pressDown), for: [.touchDown, .touchDragEnter])
        addTarget(self, action: #selector(pressUp), for: [.touchUpInside, .touchCancel, .touchDragExit])
    }

    @objc private func pressDown() {
        UIView.animate(withDuration: 0.12) { self.transform = CGAffineTransform(scaleX: 0.975, y: 0.975) }
    }

    @objc private func pressUp() {
        UIView.animate(withDuration: 0.18, delay: 0, options: [.curveEaseOut]) { self.transform = .identity }
    }
}

private final class PersonalVoiceGuideView: UIView {
    private struct Step {
        let number: String
        let title: String
        let detail: String
        let symbol: String
        let color: UIColor
    }

    private let steps: [Step] = [
        .init(number: "01", title: "准备一段清晰声音", detail: "录制或上传 10～20 秒单人声音", symbol: "waveform.and.mic", color: .systemBlue),
        .init(number: "02", title: "填写参考文字", detail: "无需逐字一致，声音清晰即可", symbol: "text.quote", color: .systemTeal),
        .init(number: "03", title: "确认授权并生成", detail: "生成期间请保持当前页面开启", symbol: "wand.and.stars", color: .systemOrange),
        .init(number: "04", title: "试听并开启使用", detail: "导航时会优先播放你的声音", symbol: "checkmark.seal.fill", color: .systemPurple)
    ]

    private let playerContainer = UIView()
    private let playerLayer = AVPlayerLayer()
    private let shadeView = UIView()
    private let badgeLabel = UILabel()
    private let iconView = UIImageView()
    private let presenterView = UIImageView()
    private let titleLabel = UILabel()
    private let detailLabel = UILabel()
    private let progressStack = UIStackView()
    private let detailsStack = UIStackView()
    private let expandButton = UIButton(type: .system)
    private let replayButton = UIButton(type: .system)
    private var player: AVPlayer?
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var currentStep = -1

    override init(frame: CGRect) {
        super.init(frame: frame)
        buildUI()
        configurePlayer()
        showStep(0, animated: false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit {
        if let timeObserver { player?.removeTimeObserver(timeObserver) }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer.frame = playerContainer.bounds
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil {
            startPresenterAnimationIfNeeded()
        } else {
            presenterView.layer.removeAnimation(forKey: "presenterNaturalMotion")
        }
    }

    func play() { player?.play() }
    func pause() { player?.pause() }

    private func buildUI() {
        backgroundColor = .secondarySystemGroupedBackground
        layer.cornerRadius = 22
        layer.cornerCurve = .continuous
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.06
        layer.shadowRadius = 18
        layer.shadowOffset = CGSize(width: 0, height: 8)

        let heading = UILabel()
        heading.text = "1 分钟学会制作"
        heading.font = .systemFont(ofSize: 19, weight: .bold)
        heading.textColor = .label
        let subheading = UILabel()
        subheading.text = "跟着视频完成 4 个步骤"
        subheading.font = .systemFont(ofSize: 12, weight: .medium)
        subheading.textColor = .secondaryLabel
        let headingStack = UIStackView(arrangedSubviews: [heading, subheading])
        headingStack.axis = .vertical
        headingStack.spacing = 2

        replayButton.setImage(UIImage(systemName: "arrow.counterclockwise"), for: .normal)
        replayButton.setTitle(" 重播", for: .normal)
        replayButton.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
        replayButton.addTarget(self, action: #selector(replay), for: .touchUpInside)
        let topRow = UIStackView(arrangedSubviews: [headingStack, UIView(), replayButton])
        topRow.alignment = .center

        playerContainer.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.08)
        playerContainer.layer.cornerRadius = 17
        playerContainer.layer.cornerCurve = .continuous
        playerContainer.clipsToBounds = true
        playerContainer.heightAnchor.constraint(equalTo: playerContainer.widthAnchor, multiplier: 406.0 / 720.0).isActive = true
        playerLayer.videoGravity = .resizeAspectFill
        playerContainer.layer.addSublayer(playerLayer)

        shadeView.backgroundColor = UIColor.black.withAlphaComponent(0.03)
        shadeView.isUserInteractionEnabled = false
        shadeView.translatesAutoresizingMaskIntoConstraints = false
        playerContainer.addSubview(shadeView)

        badgeLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .bold)
        badgeLabel.textAlignment = .left
        iconView.contentMode = .scaleAspectFit
        iconView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 26, weight: .semibold)
        titleLabel.font = .systemFont(ofSize: 22, weight: .bold)
        titleLabel.textColor = UIColor(red: 0.08, green: 0.13, blue: 0.23, alpha: 1)
        titleLabel.adjustsFontSizeToFitWidth = true
        titleLabel.minimumScaleFactor = 0.78
        detailLabel.font = .systemFont(ofSize: 14, weight: .medium)
        detailLabel.textColor = UIColor(red: 0.34, green: 0.40, blue: 0.50, alpha: 1)
        detailLabel.numberOfLines = 2

        let textStack = UIStackView(arrangedSubviews: [titleLabel, detailLabel])
        textStack.axis = .vertical
        textStack.spacing = 7
        let videoContent = UIStackView(arrangedSubviews: [badgeLabel, textStack])
        videoContent.axis = .vertical
        videoContent.alignment = .leading
        videoContent.spacing = 12
        videoContent.translatesAutoresizingMaskIntoConstraints = false
        playerContainer.addSubview(videoContent)

        // 人物使用独立常驻图层，不依赖 AVPlayer 的首帧解码；页面一进入就显示。
        presenterView.image = UIImage(named: "personal_voice_presenter")
        presenterView.contentMode = .scaleAspectFit
        presenterView.translatesAutoresizingMaskIntoConstraints = false
        presenterView.isUserInteractionEnabled = false
        playerContainer.addSubview(presenterView)

        progressStack.axis = .horizontal
        progressStack.spacing = 6
        progressStack.distribution = .fillEqually
        for _ in steps {
            let segment = UIView()
            segment.backgroundColor = UIColor.label.withAlphaComponent(0.12)
            segment.layer.cornerRadius = 2
            segment.heightAnchor.constraint(equalToConstant: 4).isActive = true
            progressStack.addArrangedSubview(segment)
        }

        detailsStack.axis = .vertical
        detailsStack.spacing = 9
        detailsStack.isHidden = true
        for (index, step) in steps.enumerated() {
            let marker = UILabel()
            marker.text = "\(index + 1)"
            marker.textAlignment = .center
            marker.font = .systemFont(ofSize: 12, weight: .bold)
            marker.textColor = .white
            marker.backgroundColor = step.color
            marker.layer.cornerRadius = 12
            marker.clipsToBounds = true
            marker.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([marker.widthAnchor.constraint(equalToConstant: 24), marker.heightAnchor.constraint(equalToConstant: 24)])
            let text = UILabel()
            text.text = "\(step.title) · \(step.detail)"
            text.numberOfLines = 0
            text.font = .systemFont(ofSize: 13, weight: .medium)
            text.textColor = .secondaryLabel
            let row = UIStackView(arrangedSubviews: [marker, text])
            row.alignment = .center
            row.spacing = 9
            detailsStack.addArrangedSubview(row)
        }

        expandButton.setTitle("查看完整步骤", for: .normal)
        expandButton.setImage(UIImage(systemName: "chevron.down"), for: .normal)
        expandButton.semanticContentAttribute = .forceRightToLeft
        expandButton.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
        expandButton.addTarget(self, action: #selector(toggleDetails), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [topRow, playerContainer, progressStack, expandButton, detailsStack])
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -14),
            shadeView.topAnchor.constraint(equalTo: playerContainer.topAnchor),
            shadeView.leadingAnchor.constraint(equalTo: playerContainer.leadingAnchor),
            shadeView.trailingAnchor.constraint(equalTo: playerContainer.trailingAnchor),
            shadeView.bottomAnchor.constraint(equalTo: playerContainer.bottomAnchor),
            videoContent.leadingAnchor.constraint(equalTo: playerContainer.leadingAnchor, constant: 20),
            videoContent.trailingAnchor.constraint(lessThanOrEqualTo: presenterView.leadingAnchor, constant: -6),
            videoContent.topAnchor.constraint(equalTo: playerContainer.topAnchor, constant: 18),
            badgeLabel.heightAnchor.constraint(equalToConstant: 22),
            presenterView.trailingAnchor.constraint(equalTo: playerContainer.trailingAnchor, constant: -2),
            presenterView.bottomAnchor.constraint(equalTo: playerContainer.bottomAnchor),
            presenterView.heightAnchor.constraint(equalTo: playerContainer.heightAnchor, multiplier: 0.94),
            presenterView.widthAnchor.constraint(equalTo: presenterView.heightAnchor, multiplier: 2.0 / 3.0)
        ])
    }

    private func configurePlayer() {
        guard let url = Bundle.main.url(forResource: "personal_voice_guide", withExtension: "mp4") else { return }
        let player = AVPlayer(url: url)
        player.isMuted = true
        player.actionAtItemEnd = .none
        self.player = player
        playerLayer.player = player
        let interval = CMTime(seconds: 0.25, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            let seconds = max(0, CMTimeGetSeconds(time))
            self?.showStep(min(3, Int(seconds / 4)), animated: true)
        }
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: player.currentItem, queue: .main) { [weak self] _ in
            self?.player?.seek(to: .zero)
            self?.player?.play()
        }
        player.play()
    }

    private func startPresenterAnimationIfNeeded() {
        guard presenterView.layer.animation(forKey: "presenterNaturalMotion") == nil else { return }

        // 小幅呼吸 + 上下浮动 + 身体轻摆。使用关键帧合成为一个动画，
        // 不修改 Auto Layout 约束，也不会在页面滚动或展开步骤时跳位。
        let motion = CAKeyframeAnimation(keyPath: "transform")
        motion.values = [
            CATransform3DIdentity,
            CATransform3DConcat(
                CATransform3DMakeTranslation(-2.5, -4.0, 0),
                CATransform3DConcat(CATransform3DMakeRotation(-0.012, 0, 0, 1), CATransform3DMakeScale(1.018, 1.018, 1))
            ),
            CATransform3DConcat(
                CATransform3DMakeTranslation(2.5, -6.0, 0),
                CATransform3DConcat(CATransform3DMakeRotation(0.010, 0, 0, 1), CATransform3DMakeScale(1.025, 1.025, 1))
            ),
            CATransform3DConcat(
                CATransform3DMakeTranslation(1.2, -2.5, 0),
                CATransform3DConcat(CATransform3DMakeRotation(0.006, 0, 0, 1), CATransform3DMakeScale(1.012, 1.012, 1))
            ),
            CATransform3DIdentity
        ]
        motion.keyTimes = [0, 0.24, 0.5, 0.76, 1]
        motion.timingFunctions = [
            CAMediaTimingFunction(name: .easeInEaseOut),
            CAMediaTimingFunction(name: .easeInEaseOut),
            CAMediaTimingFunction(name: .easeInEaseOut),
            CAMediaTimingFunction(name: .easeInEaseOut)
        ]
        motion.duration = 4.2
        motion.repeatCount = .infinity
        motion.isRemovedOnCompletion = false
        presenterView.layer.add(motion, forKey: "presenterNaturalMotion")
    }

    private func showStep(_ index: Int, animated: Bool) {
        guard steps.indices.contains(index), currentStep != index else { return }
        currentStep = index
        let apply = {
            let step = self.steps[index]
            self.badgeLabel.text = step.number
            self.badgeLabel.textColor = step.color
            self.badgeLabel.backgroundColor = .clear
            self.iconView.image = UIImage(systemName: step.symbol)
            self.iconView.tintColor = step.color
            self.titleLabel.text = step.title
            self.detailLabel.text = step.detail
            for (segmentIndex, segment) in self.progressStack.arrangedSubviews.enumerated() {
                segment.backgroundColor = segmentIndex == index ? step.color : UIColor.label.withAlphaComponent(0.12)
            }
        }
        if animated {
            UIView.transition(with: playerContainer, duration: 0.25, options: [.transitionCrossDissolve, .allowAnimatedContent], animations: apply)
        } else { apply() }
    }

    @objc private func replay() {
        player?.seek(to: .zero)
        showStep(0, animated: true)
        player?.play()
    }

    @objc private func toggleDetails() {
        let willShow = detailsStack.isHidden
        detailsStack.isHidden = !willShow
        expandButton.setTitle(willShow ? "收起步骤" : "查看完整步骤", for: .normal)
        expandButton.setImage(UIImage(systemName: willShow ? "chevron.up" : "chevron.down"), for: .normal)
        UIView.animate(withDuration: 0.25) { self.superview?.layoutIfNeeded() }
    }
}

final class PersonalVoicePackViewController: UIViewController, AVAudioRecorderDelegate, AVAudioPlayerDelegate, UIDocumentPickerDelegate {
    private let store = PersonalVoicePackStore.shared
    private let client = Audio8VoiceClient()
    private let transcriptView = UITextView()
    private let recordButton = PersonalVoiceGradientButton(type: .system)
    private let importAudioButton = PersonalVoiceGradientButton(type: .system)
    private let importedAudioLabel = UILabel()
    private let importAudioProgress = UIActivityIndicatorView(style: .medium)
    private let generateButton = PersonalVoiceGradientButton(type: .system)
    private let enableSwitch = UISwitch()
    private let consentSwitch = UISwitch()
    private let genderControl = UISegmentedControl(items: ["男声", "女声"])
    private let statusLabel = UILabel()
    private let progressView = UIProgressView(progressViewStyle: .default)
    private let previewGeneratedButton = PersonalVoiceGradientButton(type: .system)
    private let referencePreviewButton = PersonalVoiceGradientButton(type: .system)
    private let backButton = UIButton(type: .system)
    private let renameButton = PersonalVoiceGradientButton(type: .system)
    private let titleLabel = UILabel()
    private let guideView = PersonalVoiceGuideView()
    private var recorder: AVAudioRecorder?
    private var previewPlayer: AVAudioPlayer?
    private var activeTask: URLSessionDataTask?
    private var isGenerating = false
    private var warmupRetryIndex = 0
    private var warmupRetryWorkItem: DispatchWorkItem?
    private let warmupRetryDelays: [TimeInterval] = [8, 15, 30]

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
        setupTopBar()
        setupUI()
        refreshStatus()
        resumeDynamicBackfillIfNeeded()
    }

    private func resumeDynamicBackfillIfNeeded() {
        guard store.generatedCount() == PersonalVoicePhrase.driveCatalog.count,
              store.shouldSyncExistingDynamicVoices,
              let packID = store.selectedPackID else { return }
        DispatchQueue.global(qos: .utility).async {
            DynamicPersonalVoiceCache.shared.backfillExistingDynamicVoices(into: packID)
        }
    }

    private func setupTopBar() {
        var configuration = UIButton.Configuration.filled()
        configuration.image = UIImage(systemName: "chevron.left")
        configuration.baseForegroundColor = .white
        configuration.baseBackgroundColor = UIColor.black.withAlphaComponent(0.16)
        configuration.cornerStyle = .capsule
        configuration.contentInsets = .zero
        backButton.configuration = configuration
        backButton.accessibilityLabel = L10n.t("common.back")
        backButton.translatesAutoresizingMaskIntoConstraints = false
        backButton.addTarget(self, action: #selector(tapBack), for: .touchUpInside)
        view.addSubview(backButton)

        titleLabel.text = store.selectedPack?.name ?? "编辑语音包"
        titleLabel.font = .systemFont(ofSize: 20, weight: .semibold)
        titleLabel.textColor = .label
        titleLabel.textAlignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(titleLabel)

        var renameConfiguration = UIButton.Configuration.plain()
        renameConfiguration.image = UIImage(
            systemName: "ellipsis",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .bold)
        )
        renameConfiguration.baseForegroundColor = .white
        renameConfiguration.imageColorTransformer = UIConfigurationColorTransformer { _ in .white }
        renameConfiguration.background.backgroundColor = .clear
        renameConfiguration.background.image = PersonalVoiceGradientButton.compactGradientBackgroundImage
        renameConfiguration.background.imageContentMode = .scaleToFill
        renameConfiguration.background.cornerRadius = 12
        renameConfiguration.cornerStyle = .medium
        renameConfiguration.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 10, bottom: 6, trailing: 10)
        renameButton.configuration = renameConfiguration
        renameButton.layer.cornerRadius = 12
        renameButton.accessibilityLabel = "修改语音包名称"
        renameButton.translatesAutoresizingMaskIntoConstraints = false
        renameButton.addTarget(self, action: #selector(renamePack), for: .touchUpInside)
        view.addSubview(renameButton)

        NSLayoutConstraint.activate([
            backButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            backButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            backButton.widthAnchor.constraint(equalToConstant: 42),
            backButton.heightAnchor.constraint(equalToConstant: 42),
            titleLabel.centerYAnchor.constraint(equalTo: backButton.centerYAnchor),
            titleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            titleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: backButton.trailingAnchor, constant: 8),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: renameButton.leadingAnchor, constant: -8),
            renameButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            renameButton.centerYAnchor.constraint(equalTo: backButton.centerYAnchor),
            renameButton.widthAnchor.constraint(equalToConstant: 36),
            renameButton.heightAnchor.constraint(equalToConstant: 34)
        ])
    }

    @objc private func tapBack() {
        navigationController?.popViewController(animated: true)
    }

    @objc private func renamePack() {
        let alert = UIAlertController(title: "修改语音包名称", message: nil, preferredStyle: .alert)
        alert.addTextField { [weak self] textField in
            textField.text = self?.store.selectedPack?.name
            textField.placeholder = "请输入语音包名称"
            textField.clearButtonMode = .whileEditing
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "保存", style: .default) { [weak self, weak alert] _ in
            guard let self else { return }
            let name = alert?.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !name.isEmpty else {
                self.showMessage("语音包名称不能为空。")
                return
            }
            self.store.renameSelectedPack(to: String(name.prefix(30)))
            self.titleLabel.text = self.store.selectedPack?.name ?? name
        })
        present(alert, animated: true)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        recorder?.stop()
        previewPlayer?.stop()
        stopReferenceWaveAnimation()
        guideView.pause()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guideView.play()
    }

    private func setupUI() {
        transcriptView.text = store.selectedReferenceText()
            ?? "你好，这是我的个人导航声音，请注意行车安全，祝您一路平安。"
        transcriptView.font = .systemFont(ofSize: 16)
        transcriptView.backgroundColor = .secondarySystemGroupedBackground
        transcriptView.layer.cornerRadius = 10
        transcriptView.heightAnchor.constraint(equalToConstant: 92).isActive = true

        recordButton.configuration = filledConfiguration(title: "开始录音", image: "mic.fill")
        recordButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 50).isActive = true
        recordButton.addTarget(self, action: #selector(toggleRecording), for: .touchUpInside)

        importAudioButton.configuration = tintedConfiguration(title: "上传 MP3/M4A/WAV 声音文件", image: "doc.badge.plus")
        importAudioButton.addTarget(self, action: #selector(selectAudioFile), for: .touchUpInside)
        importedAudioLabel.font = .systemFont(ofSize: 13)
        importedAudioLabel.textColor = .secondaryLabel
        importedAudioLabel.numberOfLines = 0
        importedAudioLabel.isHidden = true
        importAudioProgress.hidesWhenStopped = true
        importAudioProgress.color = .systemBlue

        referencePreviewButton.configuration = filledConfiguration(title: "试听参考声音", image: "play.fill")
        referencePreviewButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 50).isActive = true
        referencePreviewButton.addTarget(self, action: #selector(playRecording), for: .touchUpInside)
        genderControl.selectedSegmentIndex = store.gender == .male ? 0 : 1
        genderControl.addTarget(self, action: #selector(changeGender), for: .valueChanged)
        let genderRow = makeRow(title: "声音类型（录音后自动判断，可修改）", control: genderControl)
        generateButton.configuration = filledConfiguration(title: "生成/继续生成语音包", image: "waveform.badge.plus")
        generateButton.addTarget(self, action: #selector(toggleGeneration), for: .touchUpInside)
        previewGeneratedButton.configuration = filledConfiguration(title: "试听已生成的本地语音", image: "speaker.wave.2.fill")
        previewGeneratedButton.addTarget(self, action: #selector(selectGeneratedPreview), for: .touchUpInside)
        let deleteButton = makeButton(title: "删除个人语音包", image: "trash", action: #selector(confirmDelete), color: .systemRed)

        let intro = makeLabel("准备一段清晰人声，下方文字可按实际内容填写，无需逐字一致。")
        let importRules = makeLabel("声音要求：MP3/M4A/WAV，0.5～30秒且不超过15MB；建议使用10～20秒清晰单人声音。")
        importRules.font = .systemFont(ofSize: 13)
        importRules.textColor = .secondaryLabel
        let consentNotice = makeLabel("生成时会将参考声音、对应文字和导航词条加密发送至在线生成服务，生成结果保存在本机。")
        consentNotice.font = .systemFont(ofSize: 13)
        consentNotice.textColor = .secondaryLabel
        let consent = makeRow(title: "我同意上述处理，并确认声音已获授权", control: consentSwitch)
        let enabled = makeRow(title: "驾车导航使用个人语音包", control: enableSwitch)
        enableSwitch.addTarget(self, action: #selector(toggleEnabled), for: .valueChanged)

        statusLabel.font = .systemFont(ofSize: 14)
        statusLabel.textColor = .secondaryLabel
        statusLabel.numberOfLines = 0
        progressView.progress = 0

        let importStatusRow = UIStackView(arrangedSubviews: [importAudioProgress, importedAudioLabel])
        importStatusRow.axis = .horizontal
        importStatusRow.alignment = .center
        importStatusRow.spacing = 8
        let stack = UIStackView(arrangedSubviews: [guideView, intro, transcriptView, recordButton, importAudioButton, importStatusRow, importRules, referencePreviewButton, genderRow, consentNotice, consent, generateButton, progressView, statusLabel, previewGeneratedButton, enabled, deleteButton])
        stack.axis = .vertical
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        let scrollView = UIScrollView()
        scrollView.alwaysBounceVertical = true
        scrollView.keyboardDismissMode = .interactive
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        scrollView.addSubview(stack)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 62),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 18),
            stack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -18),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -24),
            stack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -36)
        ])
    }

    private func makeLabel(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.numberOfLines = 0
        label.font = .systemFont(ofSize: 15)
        return label
    }

    private func makeRow(title: String, control: UIControl) -> UIView {
        let label = makeLabel(title)
        let stack = UIStackView(arrangedSubviews: [label, control])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 12
        return stack
    }

    private func filledConfiguration(title: String, image: String) -> UIButton.Configuration {
        var config = UIButton.Configuration.plain()
        var attributedTitle = AttributedString(title)
        attributedTitle.foregroundColor = .white
        attributedTitle.font = .systemFont(ofSize: 16, weight: .semibold)
        config.attributedTitle = attributedTitle
        config.image = UIImage(systemName: image)
        config.imagePadding = 8
        config.baseForegroundColor = .white
        config.imageColorTransformer = UIConfigurationColorTransformer { _ in .white }
        config.background.backgroundColor = .clear
        config.background.image = PersonalVoiceGradientButton.gradientBackgroundImage
        config.background.imageContentMode = .scaleToFill
        config.background.cornerRadius = 15
        config.contentInsets = NSDirectionalEdgeInsets(top: 13, leading: 16, bottom: 13, trailing: 16)
        config.cornerStyle = .medium
        return config
    }

    private func tintedConfiguration(title: String, image: String) -> UIButton.Configuration {
        filledConfiguration(title: title, image: image)
    }

    private func makeButton(title: String, image: String, action: Selector, color: UIColor = .systemBlue) -> UIButton {
        let usesBlueGradient = color == .systemBlue
        let button: UIButton = usesBlueGradient ? PersonalVoiceGradientButton(type: .system) : UIButton(type: .system)
        var config = usesBlueGradient ? UIButton.Configuration.plain() : UIButton.Configuration.tinted()
        if usesBlueGradient {
            var attributedTitle = AttributedString(title)
            attributedTitle.foregroundColor = .white
            attributedTitle.font = .systemFont(ofSize: 16, weight: .semibold)
            config.attributedTitle = attributedTitle
            config.imageColorTransformer = UIConfigurationColorTransformer { _ in .white }
        } else {
            config.title = title
        }
        config.image = UIImage(systemName: image)
        config.imagePadding = 8
        config.baseForegroundColor = usesBlueGradient ? .white : color
        if usesBlueGradient {
            config.background.backgroundColor = .clear
            config.background.image = PersonalVoiceGradientButton.gradientBackgroundImage
            config.background.imageContentMode = .scaleToFill
            config.background.cornerRadius = 15
        }
        config.contentInsets = NSDirectionalEdgeInsets(top: 13, leading: 16, bottom: 13, trailing: 16)
        config.cornerStyle = .medium
        button.configuration = config
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: 50).isActive = true
        button.addTarget(self, action: action, for: .touchUpInside)
        return button
    }

    @objc private func toggleRecording() {
        if recorder?.isRecording == true {
            recorder?.stop()
            recordButton.configuration = filledConfiguration(title: "重新录音", image: "mic.fill")
            refreshStatus()
            return
        }
        AVAudioSession.sharedInstance().requestRecordPermission { [weak self] allowed in
            DispatchQueue.main.async {
                guard allowed else { self?.showMessage("请在系统设置中允许麦克风权限。") ; return }
                self?.startRecording()
            }
        }
    }

    @objc private func selectAudioFile() {
        guard !isGenerating else {
            showMessage("请先停止当前语音包生成任务。")
            return
        }
        let mp3 = UTType(filenameExtension: "mp3") ?? .audio
        let m4a = UTType(filenameExtension: "m4a") ?? .audio
        let wav = UTType(filenameExtension: "wav") ?? .audio
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [mp3, m4a, wav], asCopy: true)
        picker.delegate = self
        picker.allowsMultipleSelection = false
        present(picker, animated: true)
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let sourceURL = urls.first else { return }
        importReferenceAudio(from: sourceURL)
    }

    private func importReferenceAudio(from sourceURL: URL) {
        let ext = sourceURL.pathExtension.lowercased()
        guard ["mp3", "m4a", "wav"].contains(ext) else {
            showMessage("文件格式不支持，请选择 MP3、M4A 或 WAV 文件。")
            return
        }
        setAudioImporting(true, message: "正在读取并转换声音文件…")
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let accessGranted = sourceURL.startAccessingSecurityScopedResource()
            defer {
                if accessGranted { sourceURL.stopAccessingSecurityScopedResource() }
            }
            do {
                let values = try sourceURL.resourceValues(forKeys: [.fileSizeKey, .nameKey])
                let byteCount = values.fileSize ?? 0
                guard byteCount > 0, byteCount <= 15 * 1024 * 1024 else {
                    throw ImportAudioError.invalidSize
                }
                let sourceFile = try AVAudioFile(forReading: sourceURL)
                let duration = Double(sourceFile.length) / sourceFile.processingFormat.sampleRate
                guard duration.isFinite, (0.5...30).contains(duration) else {
                    throw ImportAudioError.invalidDuration
                }
                let storedURL = try self.store.replaceReferenceAudio(with: sourceURL)
                guard let player = try? AVAudioPlayer(contentsOf: storedURL),
                      (0.5...30).contains(player.duration) else {
                    throw ImportAudioError.conversionFailed
                }
                let detected = Self.detectGender(from: storedURL)
                let fileName = values.name ?? sourceURL.lastPathComponent
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.recorder = nil
                    self.store.gender = detected
                    self.genderControl.selectedSegmentIndex = detected == .male ? 0 : 1
                    self.recordButton.configuration = self.filledConfiguration(title: "重新录音", image: "mic.fill")
                    self.importedAudioLabel.text = "已导入：\(fileName) · \(Self.durationText(duration)) · 将以原格式上传"
                    self.importedAudioLabel.isHidden = false
                    self.setAudioImporting(false)
                    self.refreshStatus(extra: "声音文件导入成功，已自动判断为\(detected == .male ? "男声" : "女声")。")
                    self.showMessage("声音文件导入成功。\n\n生成时将以原文件格式作为音色参考上传。")
                }
            } catch {
                DispatchQueue.main.async { [weak self] in
                    self?.setAudioImporting(false)
                    self?.showMessage((error as? LocalizedError)?.errorDescription ?? "声音文件导入失败：\(error.localizedDescription)")
                }
            }
        }
    }

    private func setAudioImporting(_ importing: Bool, message: String? = nil) {
        importAudioButton.isEnabled = !importing
        recordButton.isEnabled = !importing
        generateButton.isEnabled = !importing
        if importing {
            importAudioProgress.startAnimating()
            importedAudioLabel.text = message
            importedAudioLabel.isHidden = false
        } else {
            importAudioProgress.stopAnimating()
        }
    }

    private enum ImportAudioError: LocalizedError {
        case invalidSize
        case invalidDuration
        case conversionFailed

        var errorDescription: String? {
            switch self {
            case .invalidSize: return "声音文件必须大于0字节且不超过15MB。"
            case .invalidDuration: return "声音时长必须在0.5～30秒之间，建议使用10～20秒的清晰单人语音。"
            case .conversionFailed: return "无法读取或转换该声音文件，请确认文件未损坏且为有效的MP3/M4A音频。"
            }
        }
    }

    private static func convertToReferenceWAV(
        sourceFile: AVAudioFile,
        outputURL: URL,
        progress: @escaping (Double) -> Void
    ) throws {
        guard let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 44_100,
            channels: 1,
            interleaved: false
        ) else {
            throw ImportAudioError.conversionFailed
        }
        guard let converter = AVAudioConverter(from: sourceFile.processingFormat, to: outputFormat) else {
            throw ImportAudioError.conversionFailed
        }
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }
        let outputFile = try AVAudioFile(forWriting: outputURL, settings: outputFormat.settings)
        let inputFormat = sourceFile.processingFormat
        let inputChunkSize: AVAudioFrameCount = 4_096
        let ratio = outputFormat.sampleRate / inputFormat.sampleRate
        let outputCapacity = AVAudioFrameCount(ceil(Double(inputChunkSize) * ratio)) + 64
        var processedFrames: AVAudioFramePosition = 0

        while processedFrames < sourceFile.length {
            autoreleasepool {
                progress(min(0.99, Double(processedFrames) / Double(max(1, sourceFile.length))))
            }
            guard let inputBuffer = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: inputChunkSize),
                  let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: outputCapacity) else {
                throw ImportAudioError.conversionFailed
            }
            try sourceFile.read(into: inputBuffer, frameCount: inputChunkSize)
            guard inputBuffer.frameLength > 0 else { break }
            processedFrames += AVAudioFramePosition(inputBuffer.frameLength)

            var suppliedInput = false
            var conversionError: NSError?
            let status = converter.convert(to: outputBuffer, error: &conversionError) { _, inputStatus in
                if suppliedInput {
                    inputStatus.pointee = .noDataNow
                    return nil
                }
                suppliedInput = true
                inputStatus.pointee = .haveData
                return inputBuffer
            }
            if let conversionError { throw conversionError }
            guard status == .haveData || status == .inputRanDry || status == .endOfStream,
                  outputBuffer.frameLength > 0 else {
                throw ImportAudioError.conversionFailed
            }
            try outputFile.write(from: outputBuffer)
        }
        guard processedFrames > 0 else { throw ImportAudioError.conversionFailed }
        progress(1)
    }

    private static func durationText(_ duration: TimeInterval) -> String {
        String(format: "%.1f秒", duration)
    }

    private func startRecording() {
        do {
            try store.ensureDirectory()
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker])
            try session.setActive(true)
            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatLinearPCM),
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 1,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false
            ]
            let recordingURL = store.recordingReferenceAudioURL
            for ext in ["mp3", "m4a"] {
                let oldURL = store.packDirectory.appendingPathComponent("reference.\(ext)")
                if FileManager.default.fileExists(atPath: oldURL.path) {
                    try FileManager.default.removeItem(at: oldURL)
                }
            }
            recorder = try AVAudioRecorder(url: recordingURL, settings: settings)
            recorder?.delegate = self
            recorder?.record()
            importedAudioLabel.text = nil
            importedAudioLabel.isHidden = true
            recordButton.configuration = filledConfiguration(title: "停止录音", image: "stop.fill")
            statusLabel.text = "正在录音，请保持声音清晰、环境安静……"
        } catch { showMessage(error.localizedDescription) }
    }

    @objc private func playRecording() {
        if previewPlayer?.isPlaying == true {
            previewPlayer?.stop()
            stopReferenceWaveAnimation()
            return
        }
        guard FileManager.default.fileExists(atPath: store.referenceAudioURL.path) else {
            showMessage("请先完成录音或上传声音文件。")
            return
        }
        do {
            previewPlayer = try AVAudioPlayer(contentsOf: store.referenceAudioURL)
            previewPlayer?.delegate = self
            previewPlayer?.play()
            startReferenceWaveAnimation()
        } catch {
            stopReferenceWaveAnimation()
            showMessage(error.localizedDescription)
        }
    }

    private func startReferenceWaveAnimation() {
        guard var configuration = referencePreviewButton.configuration else { return }
        configuration.image = UIImage(systemName: "speaker.wave.2.fill")
        referencePreviewButton.configuration = configuration
        referencePreviewButton.layoutIfNeeded()

        let breathe = CAKeyframeAnimation(keyPath: "transform.scale")
        breathe.values = [1.0, 1.12, 0.96, 1.0]
        breathe.keyTimes = [0, 0.38, 0.72, 1]
        breathe.duration = 1.6
        breathe.repeatCount = .infinity
        breathe.timingFunctions = [
            CAMediaTimingFunction(name: .easeInEaseOut),
            CAMediaTimingFunction(name: .easeInEaseOut),
            CAMediaTimingFunction(name: .easeInEaseOut)
        ]
        referencePreviewButton.imageView?.layer.add(breathe, forKey: "referenceSpeakerBreathe")
    }

    private func stopReferenceWaveAnimation() {
        referencePreviewButton.imageView?.layer.removeAllAnimations()
        referencePreviewButton.imageView?.transform = .identity
        guard var configuration = referencePreviewButton.configuration else { return }
        configuration.image = UIImage(systemName: "play.fill")
        referencePreviewButton.configuration = configuration
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        guard player === previewPlayer else { return }
        stopReferenceWaveAnimation()
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        guard player === previewPlayer else { return }
        stopReferenceWaveAnimation()
    }

    @objc private func selectGeneratedPreview() {
        let phrases = store.generatedPhrases()
        let dynamicEntries = Array(store.dynamicEntries().prefix(40))
        guard !phrases.isEmpty || !dynamicEntries.isEmpty else {
            showMessage("当前语音包还没有生成可试听的语音。")
            return
        }
        let alert = UIAlertController(title: "选择本地语音", message: "试听不会请求网络", preferredStyle: .actionSheet)
        for phrase in phrases {
            alert.addAction(UIAlertAction(title: phrase.text, style: .default) { [weak self] _ in
                guard let self, let url = self.store.generatedAudioURL(for: phrase) else { return }
                do {
                    try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
                    try AVAudioSession.sharedInstance().setActive(true)
                    self.previewPlayer = try AVAudioPlayer(contentsOf: url)
                    self.previewPlayer?.play()
                } catch { self.showMessage(error.localizedDescription) }
            })
        }
        for entry in dynamicEntries {
            alert.addAction(UIAlertAction(title: "动态：\(entry.text)", style: .default) { [weak self] _ in
                guard let self, let url = self.store.cachedDynamicAudioURL(for: entry.text, packID: self.store.selectedPackID) else { return }
                do {
                    try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
                    try AVAudioSession.sharedInstance().setActive(true)
                    self.previewPlayer = try AVAudioPlayer(contentsOf: url)
                    self.previewPlayer?.play()
                } catch { self.showMessage(error.localizedDescription) }
            })
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        if let popover = alert.popoverPresentationController {
            popover.sourceView = previewGeneratedButton
            popover.sourceRect = previewGeneratedButton.bounds
        }
        present(alert, animated: true)
    }

    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        guard flag else { return }
        let detected = Self.detectGender(from: store.referenceAudioURL)
        store.gender = detected
        genderControl.selectedSegmentIndex = detected == .male ? 0 : 1
        refreshStatus(extra: "已自动判断为\(detected == .male ? "男声" : "女声")，如不准确可手动修改。")
    }

    @objc private func changeGender() {
        store.gender = genderControl.selectedSegmentIndex == 0 ? .male : .female
    }

    private static func detectGender(from url: URL) -> PersonalVoiceGender {
        guard let file = try? AVAudioFile(forReading: url),
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)),
              (try? file.read(into: buffer)) != nil,
              let samples = buffer.floatChannelData?[0] else { return .male }
        let count = Int(buffer.frameLength)
        let sampleRate = file.processingFormat.sampleRate
        let window = min(4096, count)
        guard window >= 2048, sampleRate > 0 else { return .male }
        let minLag = max(1, Int(sampleRate / 300.0))
        let maxLag = min(window / 2, Int(sampleRate / 80.0))
        let windowCount = min(10, max(1, count / window))
        var pitches: [Double] = []

        for index in 0..<windowCount {
            let start = min(max(0, (index + 1) * count / (windowCount + 1) - window / 2), count - window)
            var mean: Float = 0
            for i in 0..<window { mean += samples[start + i] }
            mean /= Float(window)
            var energy: Float = 0
            for i in 0..<window { let value = samples[start + i] - mean; energy += value * value }
            guard energy / Float(window) > 0.00005 else { continue }

            var bestLag = 0
            var bestScore: Float = 0
            for lag in minLag...maxLag {
                var correlation: Float = 0
                var leftEnergy: Float = 0
                var rightEnergy: Float = 0
                for i in 0..<(window - lag) {
                    let left = samples[start + i] - mean
                    let right = samples[start + i + lag] - mean
                    correlation += left * right
                    leftEnergy += left * left
                    rightEnergy += right * right
                }
                let score = correlation / max(0.000001, sqrt(leftEnergy * rightEnergy))
                if score > bestScore { bestScore = score; bestLag = lag }
            }
            if bestLag > 0, bestScore > 0.3 { pitches.append(sampleRate / Double(bestLag)) }
        }
        guard !pitches.isEmpty else { return .male }
        let median = pitches.sorted()[pitches.count / 2]
        return median < 165 ? .male : .female
    }

    @objc private func toggleGeneration() {
        if isGenerating {
            activeTask?.cancel()
            warmupRetryWorkItem?.cancel()
            warmupRetryWorkItem = nil
            isGenerating = false
            generateButton.configuration = filledConfiguration(title: "继续生成语音包", image: "waveform.badge.plus")
            refreshStatus()
            return
        }
        presentGenerationOptions()
    }

    private func presentGenerationOptions() {
        let alert = UIAlertController(
            title: "生成语音包",
            message: "是否在基础语音生成完成后，后台同步其他语音包已有的动态导航文本？同步会占用更多本机存储空间。无论选择哪项，实际导航中未命中的语音仍会按需生成。",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "仅生成基础语音", style: .default) { [weak self] _ in
            self?.startGeneration(syncExistingDynamicVoices: false)
        })
        alert.addAction(UIAlertAction(title: "生成并后台同步", style: .default) { [weak self] _ in
            self?.startGeneration(syncExistingDynamicVoices: true)
        })
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        present(alert, animated: true)
    }

    private func startGeneration(syncExistingDynamicVoices: Bool) {
        guard consentSwitch.isOn else { showMessage("请先确认声音授权。") ; return }
        guard FileManager.default.fileExists(atPath: store.referenceAudioURL.path) else { showMessage("请先完成录音或上传声音文件。") ; return }
        guard let recording = try? AVAudioPlayer(contentsOf: store.referenceAudioURL),
              (0.5...30).contains(recording.duration) else {
            showMessage("参考声音必须在0.5～30秒之间，请重新录音或上传符合要求的文件。")
            return
        }
        let transcript = transcriptView.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !transcript.isEmpty else { showMessage("请输入参考文本。") ; return }
        do {
            try store.saveReferenceText(transcript)
        } catch {
            showMessage("保存录音文字稿失败：\(error.localizedDescription)")
            return
        }
        store.setShouldSyncExistingDynamicVoices(syncExistingDynamicVoices)
        isGenerating = true
        warmupRetryIndex = 0
        generateButton.configuration = filledConfiguration(title: "停止生成", image: "stop.fill")
        generateNext(referenceText: transcript)
    }

    private func generateNext(referenceText: String) {
        guard isGenerating else { return }
        let remaining = PersonalVoicePhrase.driveCatalog.filter { !store.isGenerated($0) }
        guard let phrase = remaining.first else {
            isGenerating = false
            store.isEnabled = true
            enableSwitch.isOn = true
            generateButton.configuration = filledConfiguration(title: "语音包已完成", image: "checkmark.circle.fill")
            refreshStatus()
            if store.shouldSyncExistingDynamicVoices,
               let packID = store.selectedPackID {
                DynamicPersonalVoiceCache.shared.backfillExistingDynamicVoices(into: packID)
            }
            let message = store.shouldSyncExistingDynamicVoices
                ? "我的语音包生成完成，正在后台同步其他语音包的动态导航文本。"
                : "我的语音包基础语音生成完成。导航中未命中的语音仍会按需补充。"
            showMessage(message)
            return
        }
        let done = PersonalVoicePhrase.driveCatalog.count - remaining.count
        progressView.progress = Float(done) / Float(PersonalVoicePhrase.driveCatalog.count)
        statusLabel.text = "正在生成 \(done + 1)/\(PersonalVoicePhrase.driveCatalog.count)：\(phrase.text)\n公开预览服务可能排队，请保持页面开启。"
        activeTask = client.generate(text: phrase.text, referenceText: referenceText, audioURL: store.referenceAudioURL) { [weak self] result in
            DispatchQueue.main.async {
                guard let self, self.isGenerating else { return }
                switch result {
                case let .success(data):
                    do {
                        guard (try? AVAudioPlayer(data: data)) != nil else {
                            throw NSError(domain: "PersonalVoicePack", code: 1, userInfo: [NSLocalizedDescriptionKey: "服务返回的内容不是有效音频，请稍后重试。"])
                        }
                        try self.store.ensureDirectory()
                        try data.write(to: self.store.audioURL(for: phrase), options: .atomic)
                        self.warmupRetryIndex = 0
                        self.generateNext(referenceText: referenceText)
                    } catch {
                        self.stopGeneration(with: error.localizedDescription)
                    }
                case let .failure(error):
                    if let clientError = error as? Audio8VoiceClient.ClientError,
                       clientError.isModelWarmingUp,
                       self.warmupRetryIndex < self.warmupRetryDelays.count {
                        let delay = self.warmupRetryDelays[self.warmupRetryIndex]
                        self.warmupRetryIndex += 1
                        self.activeTask = nil
                        self.statusLabel.text = "Audio8 模型正在启动，第 \(self.warmupRetryIndex)/\(self.warmupRetryDelays.count) 次等待。\n将在 \(Int(delay)) 秒后自动继续生成“\(phrase.text)”，无需重复点击。"
                        let workItem = DispatchWorkItem { [weak self] in
                            guard let self, self.isGenerating else { return }
                            self.generateNext(referenceText: referenceText)
                        }
                        self.warmupRetryWorkItem = workItem
                        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
                        return
                    }
                    self.stopGeneration(with: "生成“\(phrase.text)”失败：\(error.localizedDescription)\n已完成的词条已保存，稍后可继续。")
                }
            }
        }
    }

    private func stopGeneration(with message: String) {
        warmupRetryWorkItem?.cancel()
        warmupRetryWorkItem = nil
        isGenerating = false
        activeTask = nil
        generateButton.configuration = filledConfiguration(title: "继续生成语音包", image: "arrow.clockwise")
        refreshStatus(extra: message)
    }

    @objc private func toggleEnabled() {
        guard store.generatedCount() > 0 else {
            enableSwitch.setOn(false, animated: true)
            showMessage("请先生成至少一条个人导航语音。")
            return
        }
        store.isEnabled = enableSwitch.isOn
    }

    @objc private func confirmDelete() {
        let alert = UIAlertController(title: "删除我的语音包？", message: "录音和已生成的导航语音都将从本机删除。", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "删除", style: .destructive) { [weak self] _ in
            try? self?.store.removePack()
            self?.navigationController?.popViewController(animated: true)
        })
        present(alert, animated: true)
    }

    private func refreshStatus(extra: String? = nil) {
        let count = store.generatedCount()
        let dynamicCount = store.cachedDynamicCount()
        enableSwitch.isOn = store.isEnabled && count > 0
        progressView.progress = Float(count) / Float(PersonalVoicePhrase.driveCatalog.count)
        let base = "已生成 \(count)/\(PersonalVoicePhrase.driveCatalog.count) 条基础语音，后台补充 \(dynamicCount) 条动态导航语音。首次未命中会立即使用系统语音，不等待网络。"
        statusLabel.text = extra.map { "\($0)\n\(base)" } ?? base
        previewGeneratedButton.isEnabled = count + dynamicCount > 0
        previewGeneratedButton.alpha = count + dynamicCount > 0 ? 1 : 0.5
    }

    private func showMessage(_ message: String) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "知道了", style: .default))
        present(alert, animated: true)
    }
}

final class PersonalVoicePackListViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    private let store = PersonalVoicePackStore.shared
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let emptyLabel = UILabel()
    private var packs: [PersonalVoicePackStore.PackInfo] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
        setupTopBar()
        setupTable()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reloadPacks()
    }

    private func setupTopBar() {
        let back = UIButton(type: .system)
        var backConfig = UIButton.Configuration.filled()
        backConfig.image = UIImage(systemName: "chevron.left")
        backConfig.baseForegroundColor = .white
        backConfig.baseBackgroundColor = UIColor.black.withAlphaComponent(0.16)
        backConfig.cornerStyle = .capsule
        backConfig.contentInsets = .zero
        back.configuration = backConfig
        back.accessibilityLabel = L10n.t("common.back")
        back.addTarget(self, action: #selector(goBack), for: .touchUpInside)

        let title = UILabel()
        title.text = "我的语音包"
        title.font = .systemFont(ofSize: 20, weight: .semibold)
        title.textAlignment = .center

        let add = PersonalVoiceGradientButton(type: .system)
        var addConfig = UIButton.Configuration.plain()
        addConfig.image = UIImage(
            systemName: "plus",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        )
        var addTitle = AttributedString("新增")
        addTitle.foregroundColor = .white
        addTitle.font = .systemFont(ofSize: 13, weight: .semibold)
        addConfig.attributedTitle = addTitle
        addConfig.imagePadding = 4
        addConfig.baseForegroundColor = .white
        addConfig.imageColorTransformer = UIConfigurationColorTransformer { _ in .white }
        addConfig.background.backgroundColor = .clear
        addConfig.background.image = PersonalVoiceGradientButton.compactGradientBackgroundImage
        addConfig.background.imageContentMode = .scaleToFill
        addConfig.background.cornerRadius = 12
        addConfig.cornerStyle = .medium
        addConfig.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 8)
        add.configuration = addConfig
        add.layer.cornerRadius = 12
        add.addTarget(self, action: #selector(addPack), for: .touchUpInside)

        [back, title, add].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; view.addSubview($0) }
        NSLayoutConstraint.activate([
            back.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            back.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            back.widthAnchor.constraint(equalToConstant: 42), back.heightAnchor.constraint(equalToConstant: 42),
            title.centerXAnchor.constraint(equalTo: view.centerXAnchor), title.centerYAnchor.constraint(equalTo: back.centerYAnchor),
            add.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12), add.centerYAnchor.constraint(equalTo: back.centerYAnchor),
            add.heightAnchor.constraint(equalToConstant: 34),
            title.leadingAnchor.constraint(greaterThanOrEqualTo: back.trailingAnchor, constant: 8),
            title.trailingAnchor.constraint(lessThanOrEqualTo: add.leadingAnchor, constant: -8)
        ])
    }

    private func setupTable() {
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = 72
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)

        emptyLabel.text = "还没有语音包\n点击右上角“新增”录制一个新音色"
        emptyLabel.textAlignment = .center
        emptyLabel.numberOfLines = 0
        emptyLabel.textColor = .secondaryLabel
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(emptyLabel)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 62),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            emptyLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            emptyLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 30)
        ])
    }

    private func reloadPacks() {
        packs = store.packs()
        emptyLabel.isHidden = !packs.isEmpty
        tableView.reloadData()
    }

    @objc private func goBack() { navigationController?.popViewController(animated: true) }

    @objc private func addPack() {
        let alert = UIAlertController(title: "新增语音包", message: "不同家人或不同音色可以分别保存。", preferredStyle: .alert)
        alert.addTextField { $0.placeholder = "语音包名称，例如：爸爸的声音" }
        func create(_ gender: PersonalVoiceGender) {
            let name = alert.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines)
            let fallback = gender == .male ? "我的男声音色" : "我的女声音色"
            do {
                _ = try self.store.createPack(name: (name?.isEmpty == false ? name! : fallback), gender: gender)
                self.navigationController?.pushViewController(PersonalVoicePackViewController(), animated: true)
            } catch { self.showError(error.localizedDescription) }
        }
        alert.addAction(UIAlertAction(title: "创建男声包", style: .default) { _ in create(.male) })
        alert.addAction(UIAlertAction(title: "创建女声包", style: .default) { _ in create(.female) })
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        present(alert, animated: true)
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { packs.count }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let id = "voicePack"
        let cell = tableView.dequeueReusableCell(withIdentifier: id) ?? UITableViewCell(style: .subtitle, reuseIdentifier: id)
        let pack = packs[indexPath.row]
        let count = store.generatedCount(for: pack.id)
        cell.textLabel?.text = pack.name
        let dynamicCount = store.cachedDynamicCount(for: pack.id)
        cell.detailTextLabel?.text = "\(pack.gender == .male ? "男声" : "女声") · 基础 \(count)/\(PersonalVoicePhrase.driveCatalog.count) · 动态 \(dynamicCount)"
        cell.imageView?.image = UIImage(systemName: "waveform.circle.fill")
        cell.imageView?.tintColor = .systemPurple
        cell.accessoryType = store.activePackID == pack.id ? .checkmark : .disclosureIndicator
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        store.selectPack(packs[indexPath.row].id)
        navigationController?.pushViewController(PersonalVoicePackViewController(), animated: true)
    }

    func tableView(_ tableView: UITableView, leadingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        let pack = packs[indexPath.row]
        guard store.generatedCount(for: pack.id) > 0 else { return nil }
        let use = UIContextualAction(style: .normal, title: "启用") { [weak self] _, _, done in
            self?.store.activatePack(pack.id)
            self?.reloadPacks()
            done(true)
        }
        use.backgroundColor = .systemGreen
        return UISwipeActionsConfiguration(actions: [use])
    }

    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        let pack = packs[indexPath.row]
        let rename = UIContextualAction(style: .normal, title: "改名") { [weak self] _, _, done in
            self?.showRenamePack(pack, completion: done)
        }
        rename.backgroundColor = .systemBlue
        let delete = UIContextualAction(style: .destructive, title: "删除") { [weak self] _, _, done in
            do { try self?.store.removePack(id: pack.id); self?.reloadPacks(); done(true) }
            catch { self?.showError(error.localizedDescription); done(false) }
        }
        return UISwipeActionsConfiguration(actions: [delete, rename])
    }

    private func showRenamePack(_ pack: PersonalVoicePackStore.PackInfo, completion: @escaping (Bool) -> Void) {
        let alert = UIAlertController(title: "修改语音包名称", message: nil, preferredStyle: .alert)
        alert.addTextField {
            $0.text = pack.name
            $0.placeholder = "请输入语音包名称"
            $0.clearButtonMode = .whileEditing
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel) { _ in completion(false) })
        alert.addAction(UIAlertAction(title: "保存", style: .default) { [weak self, weak alert] _ in
            guard let self else { completion(false); return }
            let name = alert?.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !name.isEmpty else {
                self.showError("语音包名称不能为空。")
                completion(false)
                return
            }
            self.store.selectPack(pack.id)
            self.store.renameSelectedPack(to: String(name.prefix(30)))
            self.reloadPacks()
            completion(true)
        })
        present(alert, animated: true)
    }

    private func showError(_ message: String) {
        let alert = UIAlertController(title: "操作失败", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "知道了", style: .default))
        present(alert, animated: true)
    }
}
