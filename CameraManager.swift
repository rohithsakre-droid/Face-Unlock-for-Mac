import AVFoundation
import CoreImage
import Combine
import SwiftUI
import Vision
import AppKit

class CameraManager: NSObject, ObservableObject {
    private var captureSession = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    
    @Published var currentFrame: CVPixelBuffer?
    @Published var detectedFaceBoundingBox: CGRect?
    @Published var similarityScore: Float = 0.0
    @Published var isEnrolled: Bool = false
    @Published var isMatched: Bool = false
    
    private var enrolledVector: [Float]?
    private let enrollmentKey = "savedFaceEmbeddingVector"
    
    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var scanTimer: Timer?
    
    override init() {
        super.init()
        loadEnrolledFace()
        checkPermissions()
        setupEventObservers()
    }
    
    // MARK: - Enrollment & Vector Storage
    func enrollCurrentFace() {
        if !captureSession.isRunning {
            DispatchQueue.global(qos: .userInitiated).async {
                self.captureSession.startRunning()
            }
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self = self, let frame = self.currentFrame else { return }
            FaceMatcher.extractFaceFeatureVector(from: frame) { vector in
                guard let vector = vector else { return }
                DispatchQueue.main.async {
                    self.enrolledVector = vector
                    self.isEnrolled = true
                    UserDefaults.standard.set(vector, forKey: self.enrollmentKey)
                    print("Face vector securely saved to disk!")
                }
            }
        }
    }
    
    private func loadEnrolledFace() {
        if let savedVector = UserDefaults.standard.array(forKey: enrollmentKey) as? [Float] {
            self.enrolledVector = savedVector
            self.isEnrolled = true
        } else {
            self.enrolledVector = nil
            self.isEnrolled = false
        }
    }
    
    // MARK: - Camera Control (On-Demand)
    private func startCameraSession() {
        guard !captureSession.isRunning else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            self.captureSession.startRunning()
        }
    }
    
    private func stopCameraSession() {
        guard captureSession.isRunning else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            self.captureSession.stopRunning()
            DispatchQueue.main.async {
                self.currentFrame = nil
                self.detectedFaceBoundingBox = nil
                self.similarityScore = 0.0
                self.isMatched = false
            }
        }
    }
    
    // MARK: - Event Listeners (Lid Open & Lock Screen Clicks Only)
    private func setupEventObservers() {
        // Lid Open / Screen Wake Event
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleWakeOrClickEvent),
            name: NSWorkspace.screensDidWakeNotification,
            object: nil
        )
        
        // Global Mouse Click (Strictly filtered by active Lock Screen state)
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] _ in
            if self?.isScreenLocked() == true {
                self?.handleWakeOrClickEvent()
            }
        }
        
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] event in
            if self?.isScreenLocked() == true {
                self?.handleWakeOrClickEvent()
            }
            return event
        }
    }
    
    private func isScreenLocked() -> Bool {
        guard let sessionDict = CGSessionCopyCurrentDictionary() as? [String: Any],
              let isLocked = sessionDict["CGSSessionScreenIsLocked"] as? Bool else {
            return false
        }
        return isLocked
    }
    
    @objc private func handleWakeOrClickEvent() {
        guard isEnrolled, let savedPassword = KeychainHelper.getPassword() else { return }
        
        scanTimer?.invalidate()
        startCameraSession()
        
        let startTime = Date()
        
        scanTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] timer in
            guard let self = self else {
                timer.invalidate()
                return
            }
            
            if self.isMatched {
                print("Face matched on lock screen! Injecting password...")
                UnlockService.typePasswordAndUnlock(password: savedPassword)
                timer.invalidate()
                self.stopCameraSession()
                return
            }
            
            if Date().timeIntervalSince(startTime) > 4.0 {
                print("Scan window timed out. Turning off camera.")
                timer.invalidate()
                self.stopCameraSession()
            }
        }
    }
    
    // MARK: - Vision Pipeline & Setup
    private func processFaceMatching(pixelBuffer: CVPixelBuffer) {
        let request = VNDetectFaceRectanglesRequest { [weak self] request, _ in
            guard let self = self else { return }
            guard let results = request.results as? [VNFaceObservation],
                  let firstFace = results.first else {
                DispatchQueue.main.async {
                    self.detectedFaceBoundingBox = nil
                    self.similarityScore = 0.0
                    self.isMatched = false
                }
                return
            }
            
            DispatchQueue.main.async {
                self.detectedFaceBoundingBox = firstFace.boundingBox
            }
            
            guard let enrolled = self.enrolledVector else { return }
            
            FaceMatcher.extractFaceFeatureVector(from: pixelBuffer) { liveVector in
                guard let liveVector = liveVector else { return }
                let score = FaceMatcher.cosineSimilarity(a: enrolled, b: liveVector)
                
                DispatchQueue.main.async {
                    self.similarityScore = score
                    self.isMatched = score > 0.95
                }
            }
        }
        
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        try? handler.perform([request])
    }
    
    private func checkPermissions() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            setupSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                if granted {
                    DispatchQueue.main.async { self?.setupSession() }
                }
            }
        default:
            print("Camera access denied.")
        }
    }
    
    private func setupSession() {
        captureSession.beginConfiguration()
        captureSession.sessionPreset = .vga640x480
        
        guard let videoDevice = AVCaptureDevice.default(for: .video),
              let videoInput = try? AVCaptureDeviceInput(device: videoDevice),
              captureSession.canAddInput(videoInput) else {
            captureSession.commitConfiguration()
            return
        }
        captureSession.addInput(videoInput)
        
        if captureSession.canAddOutput(videoOutput) {
            captureSession.addOutput(videoOutput)
            videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)]
            let queue = DispatchQueue(label: "camera.frame.processing.queue")
            videoOutput.setSampleBufferDelegate(self, queue: queue)
        }
        
        captureSession.commitConfiguration()
    }
    
    deinit {
        if let monitor = globalMouseMonitor { NSEvent.removeMonitor(monitor) }
        if let monitor = localMouseMonitor { NSEvent.removeMonitor(monitor) }
        scanTimer?.invalidate()
    }
}

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        DispatchQueue.main.async {
            self.currentFrame = pixelBuffer
        }
        processFaceMatching(pixelBuffer: pixelBuffer)
    }
}
