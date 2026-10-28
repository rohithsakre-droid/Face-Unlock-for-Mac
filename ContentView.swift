import SwiftUI
import ApplicationServices

struct ContentView: View {
    @StateObject private var cameraManager = CameraManager()
    @State private var passwordInput: String = ""
    @State private var statusMessage: String = "Enroll face and save password to activate."

    var body: some View {
        VStack(spacing: 16) {
            Text("Face ID Unlock Utility")
                .font(.headline)
            
            GeometryReader { geometry in
                ZStack {
                    if let pixelBuffer = cameraManager.currentFrame {
                        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
                        if let nsImage = nsImageFromCIImage(ciImage) {
                            Image(nsImage: nsImage)
                                .resizable()
                                .scaledToFit()
                                .cornerRadius(12)
                        }
                    } else {
                        Rectangle()
                            .fill(Color.gray.opacity(0.3))
                            .cornerRadius(12)
                    }
                    
                    if let box = cameraManager.detectedFaceBoundingBox {
                        let viewSize = geometry.size
                        let rect = CGRect(
                            x: box.origin.x * viewSize.width,
                            y: (1 - box.origin.y - box.height) * viewSize.height,
                            width: box.width * viewSize.width,
                            height: box.height * viewSize.height
                        )
                        
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(cameraManager.isMatched ? Color.green : Color.yellow, lineWidth: 3)
                            .frame(width: rect.width, height: rect.height)
                            .position(x: rect.midX, y: rect.midY)
                    }
                }
            }
            .frame(width: 480, height: 320)
            
            HStack {
                SecureField("Enter macOS Password", text: $passwordInput)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .frame(width: 220)
                
                Button("Save to Keychain") {
                    if KeychainHelper.savePassword(passwordInput) {
                        statusMessage = "Password encrypted and saved."
                    } else {
                        statusMessage = "Error saving password."
                    }
                }
            }
            
            HStack(spacing: 20) {
                Button(cameraManager.isEnrolled ? "Re-enroll Face" : "Enroll Face") {
                    cameraManager.enrollCurrentFace()
                    statusMessage = "Face registered successfully!"
                }
                
                Button("Test Unlock Simulation") {
                    guard let savedPassword = KeychainHelper.getPassword() else {
                        statusMessage = "Please save password first."
                        return
                    }
                    
                    guard cameraManager.isEnrolled else {
                        statusMessage = "Access Denied: No face enrolled."
                        return
                    }
                    
                    guard cameraManager.isMatched else {
                        statusMessage = "Access Denied: Face not recognized!"
                        return
                    }
                    
                    statusMessage = "Face Verified! Injecting keys in 2s..."
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        UnlockService.typePasswordAndUnlock(password: savedPassword)
                    }
                }
            }
            
            VStack(spacing: 4) {
                Text("Match Score: \(String(format: "%.2f", cameraManager.similarityScore * 100))%")
                    .font(.caption)
                    .foregroundColor(cameraManager.isMatched ? .green : .secondary)
                
                Text(statusMessage)
                    .font(.caption2)
                    .foregroundColor(cameraManager.isMatched ? .green : .orange)
            }
        }
        .padding()
        .onAppear {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
            _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
        }
    }
    
    private func nsImageFromCIImage(_ ciImage: CIImage) -> NSImage? {
        let rep = NSCIImageRep(ciImage: ciImage)
        let nsImage = NSImage(size: rep.size)
        nsImage.addRepresentation(rep)
        return nsImage
    }
}
