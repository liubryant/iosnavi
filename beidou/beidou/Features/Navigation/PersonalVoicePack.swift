import UIKit
import AVFoundation
import CryptoKit

struct PersonalVoicePhrase: Codable, Hashable {
    let id: String
    let text: String

    static let driveCatalog: [PersonalVoicePhrase] = [
        .init(id: "start", text: "开始导航"),
        .init(id: "navigation_end", text: "导航结束"),
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
            if newValue { activePackID = selectedPackID }
            else if activePackID == selectedPackID { activePackID = nil }
        }
    }

    var gender: PersonalVoiceGender {
        get { selectedPack?.gender ?? .male }
        set { updateSelectedPack { $0.gender = newValue } }
    }

    var activeGender: PersonalVoiceGender { activePack?.gender ?? .male }

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
        guard let id else { activePackID = nil; return }
        guard packs().contains(where: { $0.id == id }), generatedCount(for: id) > 0 else { return }
        activePackID = id
    }

    var packDirectory: URL {
        let id = selectedPackID ?? "unselected"
        return packsRoot.appendingPathComponent(id, isDirectory: true)
    }

    var referenceAudioURL: URL { packDirectory.appendingPathComponent("reference.wav") }

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
        if normalized.contains("准备出发") || normalized.contains("开始导航") { append("start") }
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
        let audioURL = directory.appendingPathComponent("reference.wav")
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
        let filtered = generatedOnly ? entries.filter { cachedDynamicAudioURL(forID: $0.id, packID: id) != nil } : entries
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
        if activePackID == id { activePackID = nil }
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
        request.httpBody = multipartBody(boundary: boundary, text: text, referenceText: referenceText, audio: audio)

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

    private func multipartBody(boundary: String, text: String, referenceText: String, audio: Data) -> Data {
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
        body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"reference_audio\"; filename=\"reference.wav\"\r\nContent-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
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

final class PersonalVoicePackViewController: UIViewController, AVAudioRecorderDelegate {
    private let store = PersonalVoicePackStore.shared
    private let client = Audio8VoiceClient()
    private let transcriptView = UITextView()
    private let recordButton = UIButton(type: .system)
    private let generateButton = UIButton(type: .system)
    private let enableSwitch = UISwitch()
    private let consentSwitch = UISwitch()
    private let genderControl = UISegmentedControl(items: ["男声", "女声"])
    private let statusLabel = UILabel()
    private let progressView = UIProgressView(progressViewStyle: .default)
    private let previewGeneratedButton = UIButton(type: .system)
    private let backButton = UIButton(type: .system)
    private let renameButton = UIButton(type: .system)
    private let titleLabel = UILabel()
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
              let packID = store.selectedPackID else { return }
        DynamicPersonalVoiceCache.shared.backfillExistingDynamicVoices(into: packID)
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

        var renameConfiguration = UIButton.Configuration.tinted()
        renameConfiguration.image = UIImage(
            systemName: "ellipsis",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .bold)
        )
        renameConfiguration.baseForegroundColor = .systemBlue
        renameConfiguration.cornerStyle = .capsule
        renameConfiguration.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 13, bottom: 8, trailing: 13)
        renameButton.configuration = renameConfiguration
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
            renameButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 42),
            renameButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 38)
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
    }

    private func setupUI() {
        transcriptView.text = store.selectedReferenceText()
            ?? "你好，这是我的个人导航声音，请注意行车安全，祝您一路平安。"
        transcriptView.font = .systemFont(ofSize: 16)
        transcriptView.backgroundColor = .secondarySystemGroupedBackground
        transcriptView.layer.cornerRadius = 10
        transcriptView.heightAnchor.constraint(equalToConstant: 92).isActive = true

        var recordConfig = UIButton.Configuration.filled()
        recordConfig.title = "开始录音"
        recordConfig.image = UIImage(systemName: "mic.fill")
        recordConfig.imagePadding = 8
        recordConfig.contentInsets = NSDirectionalEdgeInsets(top: 13, leading: 16, bottom: 13, trailing: 16)
        recordConfig.cornerStyle = .medium
        recordButton.configuration = recordConfig
        recordButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 50).isActive = true
        recordButton.addTarget(self, action: #selector(toggleRecording), for: .touchUpInside)

        let playButton = makeButton(title: "试听录音", image: "play.fill", action: #selector(playRecording))
        genderControl.selectedSegmentIndex = store.gender == .male ? 0 : 1
        genderControl.addTarget(self, action: #selector(changeGender), for: .valueChanged)
        let genderRow = makeRow(title: "声音类型（录音后自动判断，可修改）", control: genderControl)
        generateButton.configuration = filledConfiguration(title: "生成/继续生成语音包", image: "waveform.badge.plus")
        generateButton.addTarget(self, action: #selector(toggleGeneration), for: .touchUpInside)
        previewGeneratedButton.configuration = filledConfiguration(title: "试听已生成的本地语音", image: "speaker.wave.2.fill")
        previewGeneratedButton.addTarget(self, action: #selector(selectGeneratedPreview), for: .touchUpInside)
        let deleteButton = makeButton(title: "删除个人语音包", image: "trash", action: #selector(confirmDelete), color: .systemRed)

        let intro = makeLabel("请朗读下方文字。录音与文字必须完全一致，建议在安静环境中录制10～20秒。")
        let consentNotice = makeLabel("生成时，录音、逐字稿和导航词条将通过加密网络发送至 Hugging Face 托管的 Audio8 预览服务。生成结果保存在本机。请阅读隐私政策后自行决定是否使用。")
        consentNotice.font = .systemFont(ofSize: 13)
        consentNotice.textColor = .secondaryLabel
        let consent = makeRow(title: "我同意上述处理，并确认声音已获授权", control: consentSwitch)
        let enabled = makeRow(title: "驾车导航使用个人语音包", control: enableSwitch)
        enableSwitch.addTarget(self, action: #selector(toggleEnabled), for: .valueChanged)

        statusLabel.font = .systemFont(ofSize: 14)
        statusLabel.textColor = .secondaryLabel
        statusLabel.numberOfLines = 0
        progressView.progress = 0

        let stack = UIStackView(arrangedSubviews: [intro, transcriptView, recordButton, playButton, genderRow, consentNotice, consent, generateButton, progressView, statusLabel, previewGeneratedButton, enabled, deleteButton])
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
        var config = UIButton.Configuration.filled()
        config.title = title
        config.image = UIImage(systemName: image)
        config.imagePadding = 8
        config.contentInsets = NSDirectionalEdgeInsets(top: 13, leading: 16, bottom: 13, trailing: 16)
        config.cornerStyle = .medium
        return config
    }

    private func makeButton(title: String, image: String, action: Selector, color: UIColor = .systemBlue) -> UIButton {
        let button = UIButton(type: .system)
        var config = UIButton.Configuration.tinted()
        config.title = title
        config.image = UIImage(systemName: image)
        config.imagePadding = 8
        config.baseForegroundColor = color
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
            recorder = try AVAudioRecorder(url: store.referenceAudioURL, settings: settings)
            recorder?.delegate = self
            recorder?.record()
            recordButton.configuration = filledConfiguration(title: "停止录音", image: "stop.fill")
            statusLabel.text = "正在录音，请完整朗读文字稿……"
        } catch { showMessage(error.localizedDescription) }
    }

    @objc private func playRecording() {
        guard FileManager.default.fileExists(atPath: store.referenceAudioURL.path) else {
            showMessage("请先完成录音。")
            return
        }
        do {
            previewPlayer = try AVAudioPlayer(contentsOf: store.referenceAudioURL)
            previewPlayer?.play()
        } catch { showMessage(error.localizedDescription) }
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
        guard consentSwitch.isOn else { showMessage("请先确认声音授权。") ; return }
        guard FileManager.default.fileExists(atPath: store.referenceAudioURL.path) else { showMessage("请先完成录音。") ; return }
        guard let recording = try? AVAudioPlayer(contentsOf: store.referenceAudioURL),
              (0.5...30).contains(recording.duration) else {
            showMessage("参考录音必须在0.5～30秒之间，请重新录音。")
            return
        }
        let transcript = transcriptView.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !transcript.isEmpty else { showMessage("请输入与录音完全一致的文字稿。") ; return }
        do {
            try store.saveReferenceText(transcript)
        } catch {
            showMessage("保存录音文字稿失败：\(error.localizedDescription)")
            return
        }
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
            if let packID = store.selectedPackID {
                DynamicPersonalVoiceCache.shared.backfillExistingDynamicVoices(into: packID)
            }
            showMessage("我的语音包生成完成。")
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

        let add = UIButton(type: .system)
        var addConfig = UIButton.Configuration.tinted()
        addConfig.image = UIImage(systemName: "plus")
        addConfig.title = "新增"
        addConfig.imagePadding = 4
        addConfig.contentInsets = NSDirectionalEdgeInsets(top: 9, leading: 10, bottom: 9, trailing: 10)
        add.configuration = addConfig
        add.addTarget(self, action: #selector(addPack), for: .touchUpInside)

        [back, title, add].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; view.addSubview($0) }
        NSLayoutConstraint.activate([
            back.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            back.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            back.widthAnchor.constraint(equalToConstant: 42), back.heightAnchor.constraint(equalToConstant: 42),
            title.centerXAnchor.constraint(equalTo: view.centerXAnchor), title.centerYAnchor.constraint(equalTo: back.centerYAnchor),
            add.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12), add.centerYAnchor.constraint(equalTo: back.centerYAnchor),
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
