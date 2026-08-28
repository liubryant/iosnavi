//
//  PoiKeywordSearchViewController.swift
//  beidou
//  Author: Liuzheng <bryant_liu24@126.com>
//
//  关键字POI搜索 (对应 Android 路线规划"输入终点"联想)。
//  使用高德 Web服务 关键字搜索接口，选中后通过 onSelect 回调返回。
//

import AVFoundation
import CoreLocation
import Speech
import UIKit

#if canImport(AMapSearchKit)
import AMapSearchKit
#endif
#if canImport(AMapNaviKit)
import AMapNaviKit
#endif

final class PoiKeywordSearchViewController: UIViewController {

    var onSelect: ((SelectedPOI) -> Void)?
    var onSelectHistory: ((SelectedPOI) -> Void)?

    private let city: String
    private let location: CurrentLocation?
    private let backButton = UIButton(type: .system)
    private let searchBar = UISearchBar()
    private let voiceButton = UIButton(type: .system)
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var voiceSilenceWorkItem: DispatchWorkItem?
    private var isVoiceRecognizing = false
    private var hasInstalledAudioTap = false
    private lazy var speechRecognizer: SFSpeechRecognizer? = {
        let locale = Locale.current.languageCode == "zh"
            ? Locale(identifier: "zh-CN")
            : Locale.current
        return SFSpeechRecognizer(locale: locale) ?? SFSpeechRecognizer(locale: Locale(identifier: "zh-CN"))
    }()
    #if canImport(AMapNaviKit)
    private let mapView = MAMapView()
    #else
    private let mapView = UIView()
    #endif
    private let tableView = UITableView()
    private let statusLabel = UILabel()
    private var results: [SelectedPOI] = []
    private var isShowingHistory = false
    private var searchWorkItem: DispatchWorkItem?
    private var latestKeyword = ""

    #if canImport(AMapSearchKit)
    private let searchAPI = AMapSearchAPI()
    #endif

    init(city: String, location: CurrentLocation? = nil) {
        self.city = city
        self.location = location
        super.init(nibName: nil, bundle: nil)
        self.title = L10n.t("search.destination_title")
        #if canImport(AMapSearchKit)
        searchAPI?.delegate = self
        #endif
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        setupBackButton()

        searchBar.placeholder = L10n.t("search.destination_placeholder")
        searchBar.delegate = self
        searchBar.searchBarStyle = .minimal
        searchBar.backgroundImage = UIImage()
        searchBar.translatesAutoresizingMaskIntoConstraints = false
        setupVoiceButton()

        setupMapPreview()

        tableView.delegate = self
        tableView.dataSource = self
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "poi")
        tableView.keyboardDismissMode = .onDrag

        statusLabel.text = L10n.t("search.no_history")
        statusLabel.textColor = .secondaryLabel
        statusLabel.font = .systemFont(ofSize: 14)
        statusLabel.textAlignment = .center
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(searchBar)
        view.addSubview(voiceButton)
        view.addSubview(mapView)
        view.addSubview(tableView)
        view.addSubview(statusLabel)
        NSLayoutConstraint.activate([
            searchBar.centerYAnchor.constraint(equalTo: backButton.centerYAnchor),
            searchBar.leadingAnchor.constraint(equalTo: backButton.trailingAnchor, constant: 6),
            searchBar.trailingAnchor.constraint(equalTo: voiceButton.leadingAnchor, constant: -6),
            searchBar.heightAnchor.constraint(equalToConstant: 42),

            voiceButton.centerYAnchor.constraint(equalTo: searchBar.centerYAnchor),
            voiceButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            voiceButton.widthAnchor.constraint(equalToConstant: 34),
            voiceButton.heightAnchor.constraint(equalToConstant: 34),

            mapView.topAnchor.constraint(equalTo: searchBar.bottomAnchor, constant: 8),
            mapView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            mapView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            mapView.heightAnchor.constraint(equalToConstant: 190),

            tableView.topAnchor.constraint(equalTo: mapView.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            statusLabel.centerXAnchor.constraint(equalTo: tableView.centerXAnchor),
            statusLabel.centerYAnchor.constraint(equalTo: tableView.centerYAnchor),
            statusLabel.leadingAnchor.constraint(greaterThanOrEqualTo: tableView.leadingAnchor, constant: 24),
            statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: tableView.trailingAnchor, constant: -24)
        ])
        showHistory()
    }

    private func setupVoiceButton() {
        var configuration = UIButton.Configuration.filled()
        configuration.image = UIImage(systemName: "mic.fill")
        configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
        configuration.baseForegroundColor = .white
        configuration.baseBackgroundColor = .systemBlue
        configuration.cornerStyle = .capsule
        configuration.contentInsets = .zero
        voiceButton.configuration = configuration
        voiceButton.accessibilityLabel = L10n.t("search.voice_start")
        voiceButton.accessibilityHint = L10n.t("search.voice_hint")
        voiceButton.translatesAutoresizingMaskIntoConstraints = false
        voiceButton.addTarget(self, action: #selector(tapVoiceSearch), for: .touchUpInside)
    }

    private func setupBackButton() {
        var configuration = UIButton.Configuration.filled()
        configuration.image = UIImage(systemName: "chevron.left")
        configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        configuration.baseForegroundColor = .white
        configuration.baseBackgroundColor = UIColor.black.withAlphaComponent(0.16)
        configuration.cornerStyle = .capsule
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)
        backButton.configuration = configuration
        backButton.accessibilityLabel = L10n.t("common.back")
        backButton.translatesAutoresizingMaskIntoConstraints = false
        backButton.addTarget(self, action: #selector(tapBack), for: .touchUpInside)

        view.addSubview(backButton)
        NSLayoutConstraint.activate([
            backButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            backButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            backButton.widthAnchor.constraint(equalToConstant: 34),
            backButton.heightAnchor.constraint(equalToConstant: 34)
        ])
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        searchBar.becomeFirstResponder()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        UMengAnalytics.shared.pageBegin("PoiKeywordSearchViewController")
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopVoiceRecognition(performSearchAfterStopping: false)
        UMengAnalytics.shared.pageEnd("PoiKeywordSearchViewController")
    }

    private func setupMapPreview() {
        mapView.translatesAutoresizingMaskIntoConstraints = false

        #if canImport(AMapNaviKit)
        mapView.delegate = self
        mapView.mapType = .standard
        mapView.showsCompass = false
        mapView.showsScale = false
        mapView.zoomLevel = 16

        let center = currentLocationPOI()
        let gcj02 = CLLocationCoordinate2D(latitude: center.latitude, longitude: center.longitude)
        mapView.setCenter(gcj02, animated: false)

        let annotation = MAPointAnnotation()
        annotation.coordinate = gcj02
        annotation.title = center.name
        annotation.subtitle = center.address
        mapView.addAnnotation(annotation)
        #else
        mapView.backgroundColor = .systemGray5
        let label = UILabel()
        label.text = L10n.t("common.current_location")
        label.font = .systemFont(ofSize: 16, weight: .semibold)
        label.textColor = .secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        mapView.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: mapView.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: mapView.centerYAnchor)
        ])
        #endif
    }

    private func currentLocationPOI() -> SelectedPOI {
        if let location {
            return SelectedPOI(name: L10n.t("common.my_location"), address: location.address, latitude: location.latitude, longitude: location.longitude)
        }
        if let cached = LocationManager.shared.lastKnownLocation {
            return SelectedPOI(name: L10n.t("common.my_location"), address: cached.address, latitude: cached.latitude, longitude: cached.longitude)
        }
        return SelectedPOI(name: L10n.t("common.my_location"), address: "", latitude: Constants.defaultStartLat, longitude: Constants.defaultStartLon)
    }

    private func performSearch(keyword: String) {
        let trimmedKeyword = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        latestKeyword = trimmedKeyword
        guard !trimmedKeyword.isEmpty else {
            showHistory()
            return
        }
        isShowingHistory = false
        statusLabel.text = L10n.t("search.searching_destination")
        statusLabel.isHidden = false

        #if canImport(AMapSearchKit)
        let request = AMapPOIKeywordsSearchRequest()
        request.keywords = trimmedKeyword
        request.city = city
        request.cityLimit = false
        request.offset = 20
        request.page = 1
        request.sortrule = 1
        request.location = AMapGeoPoint.location(
            withLatitude: CGFloat(currentLocationPOI().latitude),
            longitude: CGFloat(currentLocationPOI().longitude)
        )
        request.showFieldsType = .all
        searchAPI?.aMapPOIKeywordsSearch(request)
        #else
        ApiClient.searchPOI(keyword: keyword, city: city) { [weak self] pois in
            self?.applyResults(pois)
        }
        #endif
    }

    private func applyResults(_ pois: [SelectedPOI]) {
        isShowingHistory = false
        results = pois
        tableView.reloadData()
        statusLabel.text = pois.isEmpty ? (latestKeyword.isEmpty ? L10n.t("search.input_destination_hint") : L10n.t("search.no_results")) : nil
        statusLabel.isHidden = !pois.isEmpty
    }

    private func showHistory() {
        latestKeyword = ""
        isShowingHistory = true
        results = POIHistoryStore.load()
        tableView.reloadData()
        statusLabel.text = results.isEmpty ? L10n.t("search.no_history") : nil
        statusLabel.isHidden = !results.isEmpty
    }

    // MARK: - 语音搜索

    @objc private func tapVoiceSearch() {
        if isVoiceRecognizing {
            stopVoiceRecognition(performSearchAfterStopping: true)
            return
        }

        requestVoicePermissions { [weak self] granted in
            guard let self, granted else { return }
            self.startVoiceRecognition()
        }
    }

    private func requestVoicePermissions(completion: @escaping (Bool) -> Void) {
        requestSpeechRecognitionPermission { [weak self] speechGranted in
            guard let self else { return }
            guard speechGranted else {
                self.showVoicePermissionAlert()
                completion(false)
                return
            }

            let audioSession = AVAudioSession.sharedInstance()
            switch audioSession.recordPermission {
            case .granted:
                completion(true)
            case .denied:
                self.showVoicePermissionAlert()
                completion(false)
            case .undetermined:
                audioSession.requestRecordPermission { granted in
                    DispatchQueue.main.async {
                        if !granted { self.showVoicePermissionAlert() }
                        completion(granted)
                    }
                }
            @unknown default:
                self.showVoicePermissionAlert()
                completion(false)
            }
        }
    }

    private func requestSpeechRecognitionPermission(completion: @escaping (Bool) -> Void) {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            completion(true)
        case .denied, .restricted:
            completion(false)
        case .notDetermined:
            SFSpeechRecognizer.requestAuthorization { status in
                DispatchQueue.main.async {
                    completion(status == .authorized)
                }
            }
        @unknown default:
            completion(false)
        }
    }

    private func startVoiceRecognition() {
        guard let speechRecognizer, speechRecognizer.isAvailable else {
            showVoiceMessage(
                title: L10n.t("search.voice_unavailable_title"),
                message: L10n.t("search.voice_unavailable_message")
            )
            return
        }

        stopVoiceRecognition(performSearchAfterStopping: false)
        searchWorkItem?.cancel()
        searchBar.resignFirstResponder()

        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.record, mode: .measurement, options: [.duckOthers, .allowBluetoothHFP])
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            recognitionRequest = request

            let inputNode = audioEngine.inputNode
            let recordingFormat = inputNode.outputFormat(forBus: 0)
            guard recordingFormat.sampleRate > 0, recordingFormat.channelCount > 0 else {
                throw NSError(
                    domain: "PoiVoiceSearch",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: L10n.t("search.voice_microphone_unavailable")]
                )
            }
            inputNode.installTap(onBus: 0, bufferSize: 1_024, format: recordingFormat) { [weak request] buffer, _ in
                request?.append(buffer)
            }
            hasInstalledAudioTap = true

            audioEngine.prepare()
            try audioEngine.start()
            isVoiceRecognizing = true
            updateVoiceButtonAppearance()
            statusLabel.text = L10n.t("search.voice_listening")
            statusLabel.isHidden = false

            recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
                DispatchQueue.main.async {
                    guard let self, self.isVoiceRecognizing else { return }

                    if let result {
                        let transcript = result.bestTranscription.formattedString
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        if !transcript.isEmpty {
                            self.searchBar.text = transcript
                            self.statusLabel.text = L10n.t("search.voice_listening")
                            self.scheduleVoiceSilenceFinish()
                        }
                        if result.isFinal {
                            self.stopVoiceRecognition(performSearchAfterStopping: true)
                            return
                        }
                    }

                    if error != nil {
                        let hasTranscript = !(self.searchBar.text ?? "")
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                            .isEmpty
                        self.stopVoiceRecognition(performSearchAfterStopping: hasTranscript)
                        if !hasTranscript {
                            self.showVoiceMessage(
                                title: L10n.t("search.voice_failed_title"),
                                message: L10n.t("search.voice_failed_message")
                            )
                        }
                    }
                }
            }
        } catch {
            stopVoiceRecognition(performSearchAfterStopping: false)
            showVoiceMessage(title: L10n.t("search.voice_failed_title"), message: error.localizedDescription)
        }
    }

    private func scheduleVoiceSilenceFinish() {
        voiceSilenceWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard self?.isVoiceRecognizing == true else { return }
            self?.stopVoiceRecognition(performSearchAfterStopping: true)
        }
        voiceSilenceWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4, execute: workItem)
    }

    private func stopVoiceRecognition(performSearchAfterStopping: Bool) {
        guard isVoiceRecognizing || recognitionRequest != nil || audioEngine.isRunning else { return }
        isVoiceRecognizing = false
        voiceSilenceWorkItem?.cancel()
        voiceSilenceWorkItem = nil

        if audioEngine.isRunning {
            audioEngine.stop()
        }
        if hasInstalledAudioTap {
            audioEngine.inputNode.removeTap(onBus: 0)
            hasInstalledAudioTap = false
        }
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        updateVoiceButtonAppearance()

        guard performSearchAfterStopping else { return }
        let keyword = (searchBar.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if keyword.isEmpty {
            showHistory()
            showVoiceMessage(
                title: L10n.t("search.voice_failed_title"),
                message: L10n.t("search.voice_no_speech")
            )
        } else {
            performSearch(keyword: keyword)
        }
    }

    private func updateVoiceButtonAppearance() {
        var configuration = voiceButton.configuration
        configuration?.image = UIImage(systemName: isVoiceRecognizing ? "stop.fill" : "mic.fill")
        configuration?.baseBackgroundColor = isVoiceRecognizing ? .systemRed : .systemBlue
        voiceButton.configuration = configuration
        voiceButton.accessibilityLabel = L10n.t(isVoiceRecognizing ? "search.voice_stop" : "search.voice_start")
    }

    private func showVoicePermissionAlert() {
        let alert = UIAlertController(
            title: L10n.t("search.voice_permission_title"),
            message: L10n.t("search.voice_permission_message"),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: L10n.t("common.cancel"), style: .cancel))
        alert.addAction(UIAlertAction(title: L10n.t("search.open_settings"), style: .default) { _ in
            guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
            UIApplication.shared.open(url)
        })
        present(alert, animated: true)
    }

    private func showVoiceMessage(title: String, message: String) {
        guard presentedViewController == nil else { return }
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: L10n.t("common.ok"), style: .default))
        present(alert, animated: true)
    }

    @objc private func tapBack() {
        navigationController?.popViewController(animated: true)
    }
}

#if canImport(AMapSearchKit)
// MARK: - AMapSearchDelegate

extension PoiKeywordSearchViewController: AMapSearchDelegate {
    func onPOISearchDone(_ request: AMapPOISearchBaseRequest, response: AMapPOISearchResponse) {
        let pois = response.pois.compactMap { poi -> SelectedPOI? in
            guard let name = poi.name, !name.isEmpty, let location = poi.location else { return nil }
            let address = poi.address?.isEmpty == false ? (poi.address ?? "") : (poi.type ?? "")
            return SelectedPOI(
                name: name,
                address: address,
                latitude: Double(location.latitude),
                longitude: Double(location.longitude)
            )
        }
        applyResults(pois)
    }

    func aMapSearchRequest(_ request: Any, didFailWithError error: Error) {
        ApiClient.searchPOI(keyword: latestKeyword, city: city) { [weak self] pois in
            self?.applyResults(pois)
        }
    }
}
#endif

#if canImport(AMapNaviKit)
// MARK: - MAMapViewDelegate

extension PoiKeywordSearchViewController: MAMapViewDelegate {
    func mapView(_ mapView: MAMapView, viewFor annotation: MAAnnotation) -> MAAnnotationView? {
        guard annotation is MAPointAnnotation else { return nil }
        let identifier = "keywordCurrentLocation"
        var annotationView = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MAPinAnnotationView
        if annotationView == nil {
            annotationView = MAPinAnnotationView(annotation: annotation, reuseIdentifier: identifier)
        } else {
            annotationView?.annotation = annotation
        }
        annotationView?.canShowCallout = true
        return annotationView
    }
}
#endif

// MARK: - UISearchBarDelegate

extension PoiKeywordSearchViewController: UISearchBarDelegate {
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        searchWorkItem?.cancel()
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            showHistory()
            return
        }
        let workItem = DispatchWorkItem { [weak self] in
            self?.performSearch(keyword: searchText)
        }
        searchWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: workItem)
    }

    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        searchBar.resignFirstResponder()
        performSearch(keyword: searchBar.text ?? "")
    }
}

// MARK: - UITableViewDataSource / Delegate

extension PoiKeywordSearchViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        isShowingHistory && !results.isEmpty ? L10n.t("search.history") : nil
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        results.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "poi", for: indexPath)
        let poi = results[indexPath.row]
        var config = cell.defaultContentConfiguration()
        config.text = poi.name
        config.secondaryText = poi.address
        cell.contentConfiguration = config
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let poi = results[indexPath.row]
        if isShowingHistory {
            onSelectHistory?(poi)
            return
        }
        onSelect?(poi)
        navigationController?.popViewController(animated: true)
    }
}
