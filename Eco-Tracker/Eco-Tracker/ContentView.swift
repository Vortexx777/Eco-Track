//
//  ContentView.swift
//  Eco-Tracker
//
//  Created by Abylaikhan on 11.02.2026.
//

import SwiftUI
import Combine
import AVFoundation
import UIKit
import SceneKit
import RealityKit
import CoreML
import Vision

struct ContentView: View {
    @AppStorage("isAuthenticated") private var isAuthenticated: Bool = false
    @AppStorage("userName") private var userName: String = ""
    @AppStorage("ecoPoints") private var ecoPoints: Int = 0

    var body: some View {
        if !isAuthenticated {
            AuthView()
        } else {
            TabView {
                HexMapScreen()
                    .tabItem {
                        Image(systemName: "map")
                    }

                CameraScreen()
                    .tabItem {
                        Image(systemName: "camera")
                    }

                ScrollView {
                    VStack(spacing: 24) {
                        ZStack(alignment: .topTrailing) {
                            Circle()
                                .fill(LinearGradient(colors: [.green.opacity(0.6), .blue.opacity(0.6)], startPoint: .topLeading, endPoint: .bottomTrailing))
                                .frame(width: 120, height: 120)
                                .overlay(
                                    Image(systemName: "person.fill")
                                        .font(.system(size: 56))
                                        .foregroundStyle(.white.opacity(0.9))
                                )
                                .shadow(radius: 8, y: 4)


                            Text("1")
                                .font(.subheadline.weight(.bold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(.ultraThickMaterial, in: Capsule())
                                .overlay(
                                    Capsule()
                                        .strokeBorder(.white.opacity(0.6), lineWidth: 1)
                                )
                                .offset(x: 8, y: -8)
                        }

                        Text(userName.isEmpty ? "Пользователь" : userName)
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(.primary)

                        // Stats card
                        VStack(spacing: 0) {
                            ProfileStatRow(title: "Эко‑очки", value: String(ecoPoints), systemImage: "leaf")
                            Divider()
                            ProfileStatRow(title: "За день", value: "+300", systemImage: "calendar")
                            Divider()
                            ProfileStatRow(title: "Открытые регионы", value: "5", systemImage: "map")
                        }
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(.thinMaterial)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(.separator, lineWidth: 0.5)
                        )

                        Spacer()

                        Button("Выйти из аккаунта") {
                            isAuthenticated = false
                            userName = ""
                        }
                        .tint(.red)
                        .buttonStyle(.borderedProminent)
                        .padding(.horizontal)
                    }
                    .padding(.horizontal)
                    .padding(.top, 24)
                    .padding(.bottom, 32)
                }
                .tabItem {
                    Image(systemName: "person")
                }
            }
        }
    }

    private struct AuthView: View {
        @AppStorage("isAuthenticated") private var isAuthenticated: Bool = false
        @AppStorage("userName") private var userName: String = ""
        @State private var isRegister: Bool = false
        @State private var name: String = ""
        @State private var email: String = ""
        @State private var password: String = ""

        var body: some View {
            VStack(spacing: 16) {
                Text(isRegister ? "Регистрация" : "Вход")
                    .font(.largeTitle.bold())

                TextField("Имя", text: $name)
                    .textContentType(.name)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .opacity(isRegister ? 1 : 0)
                    .frame(height: isRegister ? nil : 0)

                TextField("Email", text: $email)
                    .textContentType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)

                SecureField("Пароль", text: $password)
                    .textContentType(.password)

                Button(isRegister ? "Зарегистрироваться" : "Войти") {
                    if isRegister {
                        userName = name.isEmpty ? "Пользователь" : name
                        isAuthenticated = true
                    } else {
                        userName = email.isEmpty ? "Пользователь" : email.components(separatedBy: "@").first ?? "Пользователь"
                        isAuthenticated = true
                    }
                }
                .buttonStyle(.borderedProminent)

                Button(isRegister ? "Уже есть аккаунт? Войти" : "Нет аккаунта? Зарегистрироваться") {
                    withAnimation(.spring) { isRegister.toggle() }
                }
                .buttonStyle(.bordered)
            }
            .padding()
        }
    }

    private struct ProfileStatRow: View {
        let title: String
        let value: String
        let systemImage: String

        var body: some View {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .frame(width: 28, height: 28)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.tint)
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.accentColor.opacity(0.12))
                    )

                Text(title)
                    .font(.body)
                    .foregroundStyle(.secondary)

                Spacer()

                Text(value)
                    .font(.headline)
                    .foregroundStyle(.primary)
            }
            .padding(16)
        }
    }

    final class CameraManager: NSObject, ObservableObject {
        @Published var isAuthorized: Bool = false
        @Published var isRunning: Bool = false
        @Published var lastPhoto: UIImage?

        let session = AVCaptureSession()
        private let sessionQueue = DispatchQueue(label: "camera.session.queue")
        private var photoOutput = AVCapturePhotoOutput()
        private let videoOutput = AVCaptureVideoDataOutput()
        private let visionQueue = DispatchQueue(label: "camera.vision.queue")
        @Published var lastPrediction: String = ""
        @Published var lastConfidence: Float = 0
        private var model: VNCoreMLModel? = {
            do {
                let config = MLModelConfiguration()
                let mlModel = try best(configuration: config).model
                return try VNCoreMLModel(for: mlModel)
            } catch {
                print("[ML] Failed to load model: \(error)")
                return nil
            }
        }()
        // Simple anti-farming state
        private var lastScoredAt: Date = .distantPast
        private var consecutiveInBinFrames: Int = 0
        private let inBinThresholdFrames = 8
        private let scoreCooldown: TimeInterval = 5

        override init() {
            super.init()
            checkAuthorization()
        }

        func checkAuthorization() {
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized:
                isAuthorized = true
                configureSession()
            case .notDetermined:
                AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                    DispatchQueue.main.async {
                        self?.isAuthorized = granted
                        if granted {
                            self?.configureSession()
                        }
                    }
                }
            default:
                isAuthorized = false
            }
        }

        private func configureSession() {
            sessionQueue.async { [weak self] in
                guard let self else { return }
                session.beginConfiguration()
                session.sessionPreset = .photo

                // Inputs
                if let currentInput = session.inputs.first {
                    session.removeInput(currentInput)
                }
                guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                      let input = try? AVCaptureDeviceInput(device: device),
                      session.canAddInput(input) else {
                    session.commitConfiguration()
                    return
                }
                session.addInput(input)

                // Outputs
                if session.canAddOutput(photoOutput) {
                    session.addOutput(photoOutput)
                    if #available(iOS 16.0, *) {
                        // Set a reasonable high quality dimension for photos on iOS 16+
                        // Use the active format's max still image dimensions if available.
                        if let device = (self.session.inputs.first as? AVCaptureDeviceInput)?.device {
                            let dims = CMVideoFormatDescriptionGetDimensions(device.activeFormat.formatDescription)
                            let maxSide = max(Int(dims.width), Int(dims.height))
                            // Clamp to a sane upper bound to avoid excessive memory use
                            let clamped = min(maxSide, 4000)
                            let newDims = CMVideoDimensions(width: Int32(clamped), height: Int32(clamped))
                            photoOutput.maxPhotoDimensions = newDims
                        }
                    } else {
                        photoOutput.isHighResolutionCaptureEnabled = true
                    }
                }

                videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
                videoOutput.alwaysDiscardsLateVideoFrames = true
                if session.canAddOutput(videoOutput) {
                    session.addOutput(videoOutput)
                    videoOutput.setSampleBufferDelegate(self, queue: visionQueue)
                }

                session.commitConfiguration()
            }
        }

        func start() {
            guard isAuthorized else { return }
            sessionQueue.async { [weak self] in
                guard let self, !session.isRunning else { return }
                session.startRunning()
                DispatchQueue.main.async { self.isRunning = true }
            }
        }

        func stop() {
            sessionQueue.async { [weak self] in
                guard let self, session.isRunning else { return }
                session.stopRunning()
                DispatchQueue.main.async { self.isRunning = false }
            }
        }

        func capturePhoto() {
            let settings = AVCapturePhotoSettings()
            if #available(iOS 16.0, *) {
                // No per-photo high resolution flag needed on iOS 16+
            } else {
                settings.isHighResolutionPhotoEnabled = true
            }
            photoOutput.capturePhoto(with: settings, delegate: self)
        }

        func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
            guard error == nil, let data = photo.fileDataRepresentation(), let image = UIImage(data: data) else { return }
            DispatchQueue.main.async { [weak self] in
                self?.lastPhoto = image
            }
        }

        func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
            handle(pixelBuffer: pixelBuffer)
        }

        private func handle(pixelBuffer: CVPixelBuffer) {
            guard let model = model else { return }
            let request = VNCoreMLRequest(model: model) { [weak self] req, _ in
                guard let self else { return }
                if let results = req.results as? [VNClassificationObservation], let top = results.first {
                    DispatchQueue.main.async {
                        self.lastPrediction = top.identifier
                        self.lastConfidence = top.confidence
                    }
                    self.evaluateScoringIfInBin(observation: top)
                }
            }
            request.imageCropAndScaleOption = .centerCrop
            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
            try? handler.perform([request])
        }

        private func evaluateScoringIfInBin(observation: VNClassificationObservation) {
            // Heuristic: if confidence high and object considered "in bin" by ROI crossing, award points.
            // Here we simulate ROI crossing by requiring sustained high confidence; you can replace this with actual bbox/pose logic if your model provides it.
            let high = observation.confidence > 0.75
            if high { consecutiveInBinFrames += 1 } else { consecutiveInBinFrames = 0 }
            guard consecutiveInBinFrames >= inBinThresholdFrames else { return }
            let now = Date()
            guard now.timeIntervalSince(lastScoredAt) > scoreCooldown else { return }
            lastScoredAt = now
            consecutiveInBinFrames = 0
            // Score by class name
            let id = observation.identifier.lowercased()
            var delta = 0
            if id.contains("plastic") || id.contains("пластик") { delta = 10 }
            else if id.contains("metal") || id.contains("металл") { delta = 20 }
            else if id.contains("glass") || id.contains("стекло") { delta = 30 }
            DispatchQueue.main.async {
                UserDefaults.standard.set(UserDefaults.standard.integer(forKey: "ecoPoints") + delta, forKey: "ecoPoints")
            }
        }
    }

    private struct CameraPreview: UIViewRepresentable {
        let session: AVCaptureSession

        func makeUIView(context: Context) -> UIView {
            let view = UIView()
            let layer = AVCaptureVideoPreviewLayer(session: session)
            layer.videoGravity = .resizeAspectFill
            layer.frame = view.bounds
            view.layer.addSublayer(layer)
            return view
        }

        func updateUIView(_ uiView: UIView, context: Context) {
            guard let layer = uiView.layer.sublayers?.first as? AVCaptureVideoPreviewLayer else { return }
            layer.session = session
            layer.frame = uiView.bounds
        }
    }

    private struct CameraScreen: View {
        @StateObject private var camera = CameraManager()

        var body: some View {
            ZStack {
                if camera.isAuthorized {
                    GeometryReader { proxy in
                        CameraPreview(session: camera.session)
                            .onAppear { camera.start() }
                            .onDisappear { camera.stop() }
                            .ignoresSafeArea()
                            .overlay(alignment: .bottom) {
                                VStack(spacing: 8) {
                                    if !camera.lastPrediction.isEmpty {
                                        Text("Обнаружено: \(camera.lastPrediction) • \(Int(camera.lastConfidence * 100))%")
                                            .font(.headline)
                                            .padding(8)
                                            .background(.ultraThinMaterial, in: Capsule())
                                    }
                                    Button("Подтвердить выброс") {
                                        // Manual confirmation awards based on lastPrediction
                                        let id = camera.lastPrediction.lowercased()
                                        var delta = 0
                                        if id.contains("plastic") || id.contains("пластик") { delta = 10 }
                                        else if id.contains("metal") || id.contains("металл") { delta = 20 }
                                        else if id.contains("glass") || id.contains("стекло") { delta = 30 }
                                        let current = UserDefaults.standard.integer(forKey: "ecoPoints")
                                        UserDefaults.standard.set(current + delta, forKey: "ecoPoints")
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(.green)
                                }
                                .padding(.bottom, 24)
                            }
                    }
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(.secondary)
                        Text("Для съёмки нужен доступ к камере")
                            .multilineTextAlignment(.center)
                        HStack(spacing: 12) {
                            Button("Разрешить") {
                                camera.checkAuthorization()
                            }
                            .buttonStyle(.borderedProminent)

                            Button("Настройки") {
                                if let url = URL(string: UIApplication.openSettingsURLString) {
                                    UIApplication.shared.open(url)
                                }
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding()
                }
            }
        }
    }

    private struct HexMapScreen: View {
        @State private var ecoProgress: Int = 0
        @State private var darkIndices: Set<Int> = []

        private let islandNames: [String] = [
            "Island_1", "Island_2", "Island_3", "Island_4", "Island_5", "Island_6"
        ]
        private let mainFileName = "platforms"

        var body: some View {
            VStack(spacing: 12) {
                SceneKitHexMapView(darkIndices: darkIndices, ecoProgress: ecoProgress)
                    .ignoresSafeArea()

                VStack(spacing: 8) {
                    Text("Эко‑прогресс: \(ecoProgress)/100")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ProgressView(value: Double(ecoProgress), total: 100)
                        .tint(.green)
                    Text("Накопленные эко‑очки влияют на прогресс")
                        .font(.footnote)
                        .foregroundStyle(.secondary.opacity(0.7))
                }
                .padding(.horizontal)
                .padding(.bottom, 12)
            }
            .onAppear { setupDarkness() }
            .onChange(of: ecoProgress) { _, newValue in
                updateDarkness(for: newValue)
            }
        }

        private func setupDarkness() {
            // Center (0) is dark + 3 random from 1...5
            var set: Set<Int> = [0]
            let others = Array(1...5).shuffled().prefix(3)
            for i in others { set.insert(i) }
            darkIndices = set
        }

        private func updateDarkness(for progress: Int) {
            // At 100 progress, center island becomes alive
            if progress >= 100 {
                darkIndices.remove(0)
            } else {
                darkIndices.insert(0)
            }
        }
    }

    private struct SceneKitHexMapView: UIViewRepresentable {
        let darkIndices: Set<Int>
        let ecoProgress: Int

        private let islandNames: [String] = [
            "Island_1", "Island_2", "Island_3", "Island_4", "Island_5", "Island_6"
        ]

        func makeUIView(context: Context) -> SCNView {
            let view = SCNView()
            view.scene = SCNScene()
            view.backgroundColor = UIColor.black
            view.autoenablesDefaultLighting = true
            view.allowsCameraControl = false

            // Camera
            let cameraNode = SCNNode()
            cameraNode.camera = SCNCamera()
            cameraNode.position = SCNVector3(0, 5, 10)
            cameraNode.camera?.zNear = 0.1
            cameraNode.camera?.zFar = 1000
            cameraNode.camera?.fieldOfView = 60
            view.scene?.rootNode.addChildNode(cameraNode)

            // Ambient light for subtle illumination
            let ambient = SCNNode()
            ambient.light = SCNLight()
            ambient.light?.type = .ambient
            ambient.light?.color = UIColor(white: 0.4, alpha: 1.0)
            view.scene?.rootNode.addChildNode(ambient)

            // Directional light for highlights
            let directional = SCNNode()
            directional.light = SCNLight()
            directional.light?.type = .directional
            directional.eulerAngles = SCNVector3(-Float.pi/3, Float.pi/4, 0)
            directional.light?.intensity = 800
            view.scene?.rootNode.addChildNode(directional)

            // Container node to pan the whole cluster
            let container = SCNNode()
            container.name = "container"
            view.scene?.rootNode.addChildNode(container)

            // Add islands
            let positions: [SCNVector3] = [
                SCNVector3(0, 0, 0),
                SCNVector3(-2.0, 0, -1.2),
                SCNVector3(2.0, 0, -1.2),
                SCNVector3(-2.0, 0, 1.2),
                SCNVector3(2.0, 0, 1.2),
                SCNVector3(0, 0, 2.4)
            ]

            for i in 0..<min(6, islandNames.count) {
                // Загружаем конкретный островок из общего файла
                let node = loadModel(named: islandNames[i], fromFile: "platforms")
                    ?? SCNNode(geometry: SCNBox(width: 1, height: 1, length: 1, chamferRadius: 0))

                node.position = positions[i]
                node.name = "island_\(i)"
                applyAppearance(to: node, dark: darkIndices.contains(i))
                container.addChildNode(node)
            }

            // Pan gesture
            let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
            view.addGestureRecognizer(pan)

            context.coordinator.container = container
            return view
        }

        func updateUIView(_ view: SCNView, context: Context) {
            // Update dark/alive appearance based on darkIndices and progress
            if let container = view.scene?.rootNode.childNode(withName: "container", recursively: false) {
                for i in 0..<container.childNodes.count {
                    let n = container.childNodes[i]
                    let isDark = darkIndices.contains(i)
                    applyAppearance(to: n, dark: isDark)
                }
            }
        }

        func makeCoordinator() -> Coordinator { Coordinator() }

        final class Coordinator: NSObject {
            weak var container: SCNNode?
            private var lastTranslation: CGPoint = .zero

            @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
                let t = gesture.translation(in: gesture.view)
                switch gesture.state {
                case .began, .changed:
                    let dx = Float(t.x - lastTranslation.x) * 0.01
                    let dz = Float(t.y - lastTranslation.y) * 0.01
                    container?.position.x += dx
                    container?.position.z += dz
                    lastTranslation = t
                default:
                    lastTranslation = .zero
                }
            }
        }

        // MARK: - Helpers
        private func loadModel(named islandName: String, fromFile fileName: String) -> SCNNode? {
            // Ищем файл platforms.usdc
            guard let url = Bundle.main.url(forResource: fileName, withExtension: "usdc"),
                  let scene = try? SCNScene(url: url, options: nil) else {
                return nil
            }

            // Ищем внутри файла объект по имени
            if let islandNode = scene.rootNode.childNode(withName: islandName, recursively: true) {
                let clonedNode = islandNode.clone() // Обязательно клонируем
                clonedNode.scale = SCNVector3(0.1, 0.1, 0.1) // Подбери размер здесь
                return clonedNode
            }

            // Если нода не найдена по имени, попробуем собрать остров из примитивов Cube.*, Cylinder.*, Sphere.*
            let container = SCNNode()
            let primitivePrefixes = ["Cube", "Cylinder", "Sphere"]
            var foundAny = false
            for prefix in primitivePrefixes {
                scene.rootNode.enumerateChildNodes { node, _ in
                    if let name = node.name, name == prefix || name.hasPrefix(prefix + ".") {
                        let clone = node.clone()
                        foundAny = true
                        container.addChildNode(clone)
                    }
                }
            }
            if foundAny {
                container.scale = SCNVector3(0.1, 0.1, 0.1)
                return container
            }

            return nil
        }

        private func applyAppearance(to node: SCNNode, dark: Bool) {
            node.enumerateChildNodes { child, _ in
                if let geom = child.geometry {
                    for m in geom.materials {
                        if dark {
                            m.metalness.contents = 0.0
                            m.roughness.contents = 0.95
                            m.diffuse.contents = UIColor(white: 0.08, alpha: 1.0)
                            m.emission.contents = UIColor.black
                        } else {
                            m.metalness.contents = 0.15
                            m.roughness.contents = 0.5
                            m.diffuse.contents = UIColor.systemGreen
                            m.emission.contents = UIColor.systemGreen.withAlphaComponent(0.12)
                        }
                    }
                }
            }
        }
    }
}

extension ContentView.CameraManager: AVCapturePhotoCaptureDelegate {}

nonisolated(unsafe) extension ContentView.CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {}

private extension SCNNode {
    func cloneFirstGeometryNode() -> SCNNode? {
        if geometry != nil { return clone() }
        for child in childNodes {
            if let n = child.cloneFirstGeometryNode() { return n }
        }
        return nil
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

#Preview {
    ContentView()
}

