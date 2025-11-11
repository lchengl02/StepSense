//
//  GazeDetection.swift
//  GazeDetection
//
//  Created by clli02 on 11/3/25.
//

import SwiftUI
import Combine

// MARK: - ViewModel
final class AttentionViewModel: ObservableObject {
    @Published var isSupported: Bool = PlatformSupport.isFaceTrackingAvailable
    @Published var permissionDenied: Bool = false
    @Published var isLooking: Bool = false
    @Published var statusText: String = "Initializing…"

    // Adjustable smoothing / tolerance
    // smoothingWindow: number of recent samples to consider
    // onThreshold: fraction (0...1) of "true" needed to switch to ON
    // offThreshold: fraction (0...1) of "true" needed to stay ON; below this switches to OFF
    // Example: window 8, on 0.65, off 0.45 gives some hysteresis.
    @Published var smoothingWindow: Int = 8
    @Published var onThreshold: Double = 0.65
    @Published var offThreshold: Double = 0.45

    private var recentFlags: [Bool] = []

    func update(looking flag: Bool) {
        guard isSupported else { return }

        // Append and trim to window
        recentFlags.append(flag)
        if recentFlags.count > smoothingWindow {
            recentFlags.removeFirst(recentFlags.count - smoothingWindow)
        }

        // Compute ratio of true samples
        let trueCount = recentFlags.reduce(0) { $0 + ($1 ? 1 : 0) }
        let total = max(recentFlags.count, 1)
        let ratio = Double(trueCount) / Double(total)

        // Hysteresis: different thresholds for turning on vs off
        let nextLooking: Bool
        if isLooking {
            nextLooking = ratio >= offThreshold
        } else {
            nextLooking = ratio >= onThreshold
        }

        DispatchQueue.main.async {
            self.isLooking = nextLooking
            self.statusText = nextLooking ? "Looking at screen" : "Not looking at screen"
        }
    }

    func setPermissionDenied() {
        DispatchQueue.main.async {
            self.permissionDenied = true
            self.statusText = "Camera permission denied"
        }
    }
}

struct FaceHostView: View {
    let vm: AttentionViewModel
    var body: some View { PlatformFaceView(vm: vm) }
}

enum PlatformSupport {
    static var isFaceTrackingAvailable: Bool {
        #if canImport(ARKit)
        #if targetEnvironment(macCatalyst)
        return false
        #else
        return ARKitBridge.isSupported
        #endif
        #else
        return false
        #endif
    }
}

#if canImport(ARKit) && !targetEnvironment(macCatalyst)
import ARKit
import AVFoundation
import UIKit

struct PlatformFaceView: UIViewControllerRepresentable {
    let vm: AttentionViewModel

    func makeUIViewController(context: Context) -> ARFaceController {
        let controller = ARFaceController()
        controller.vm = vm
        return controller
    }

    func updateUIViewController(_ uiViewController: ARFaceController, context: Context) {
        // no-op
    }
}

enum ARKitBridge { static var isSupported: Bool { ARFaceTrackingConfiguration.isSupported } }

final class ARFaceController: UIViewController, ARSessionDelegate {
    var vm: AttentionViewModel!
    private let session = ARSession()
    private var requested = false
    private let debugLogging = true

    override func viewDidLoad() {
        super.viewDidLoad()
        session.delegate = self
        view.isHidden = true // UI hidden; sensor-only host
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard ARFaceTrackingConfiguration.isSupported else { return }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            run()
        case .notDetermined:
            guard !requested else { return }
            requested = true
            AVCaptureDevice.requestAccess(for: .video) { [weak self] ok in
                guard let self else { return }
                if ok { self.run() } else { self.vm.setPermissionDenied() }
            }
        default:
            vm.setPermissionDenied()
        }
    }

    private func run() {
        let cfg = ARFaceTrackingConfiguration()
        cfg.isLightEstimationEnabled = false
        session.run(cfg, options: [.resetTracking, .removeExistingAnchors])
    }

    func session(_ session: ARSession, didAdd anchors: [ARAnchor]) { handle(anchors) }
    func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) { handle(anchors) }

    private func handle(_ anchors: [ARAnchor]) {
        guard let face = anchors.compactMap({ $0 as? ARFaceAnchor }).first else { return }
        let blinkL = (face.blendShapes[.eyeBlinkLeft])?.floatValue ?? 0
        let blinkR = (face.blendShapes[.eyeBlinkRight])?.floatValue ?? 0
        let eyesOpen = (blinkL + blinkR) * 0.5 < 0.6

        guard let frame = session.currentFrame else { return }

        let cameraWorld = frame.camera.transform
        let faceWorld = face.transform
        let worldToFace = simd_inverse(faceWorld)

        // Camera forward (into face local space)
        let camFwdLocal = normalize((worldToFace * cameraWorld).columns.2.xyz) * -1

        // Eye forward vectors (already in face local)
        let leftFLocal = (face.leftEyeTransform.columns.2.xyz) * -1
        let rightFLocal = (face.rightEyeTransform.columns.2.xyz) * -1

        let aL = angleBetween(normalize(leftFLocal), normalize(camFwdLocal))
        let aR = angleBetween(normalize(rightFLocal), normalize(camFwdLocal))
        let deg = (aL + aR) * 0.5 * 180 / .pi

        let looking = face.isTracked && eyesOpen && deg < 22.5

        if debugLogging {
            print(String(format: "blinkL %.2f blinkR %.2f eyesOpen %@ deg %.1f tracked %@",
                         blinkL, blinkR, eyesOpen.description, deg, face.isTracked.description))
        }
        vm.update(looking: looking)
    }
}
#else
// Fallback for platforms without ARKit
struct PlatformFaceView: View {
    let vm: AttentionViewModel
    var body: some View { Color.clear }
}
enum ARKitBridge { static var isSupported: Bool { false } }
#endif

// MARK: - Math helpers
fileprivate func angleBetween(_ a: simd_float3, _ b: simd_float3) -> Float {
    let d = max(-1.0, min(1.0, simd_dot(a, b)))
    return acosf(d)
}

extension simd_float4 { var xyz: simd_float3 { simd_float3(x, y, z) } }

