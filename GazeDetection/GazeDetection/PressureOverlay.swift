//
//  PressureOverlay.swift
//  GazeDetection
//
//  Created by clli02 on 11/3/25.
//

import SwiftUI
import Combine

// ViewModel that you will feed from Bluetooth (ESP32) updates.
final class PressureOverlayViewModel: ObservableObject {
    // Public, normalized 0...1 forces.
    @Published private(set) var leftForce: CGFloat = 0
    @Published private(set) var rightForce: CGFloat = 0

    // Simple smoothing to avoid jitter (low-pass filter).
    // alpha in 0...1. Higher = snappier, lower = smoother.
    @Published var smoothingAlpha: CGFloat = 0.35

    // Optional clamping for incoming raw values; adjust to your sensor range.
    var inputMin: CGFloat = 0.0
    var inputMax: CGFloat = 1.0

    // Map a raw reading to 0...1, then apply low-pass filter.
    func updateLeft(raw: CGFloat) {
        let normalized = normalize(raw)
        let newL = lerp(from: leftForce, to: normalized, alpha: smoothingAlpha)
        DispatchQueue.main.async {
            self.leftForce = newL
        }
    }

    func updateRight(raw: CGFloat) {
        let normalized = normalize(raw)
        let newR = lerp(from: rightForce, to: normalized, alpha: smoothingAlpha)
        DispatchQueue.main.async {
            self.rightForce = newR
        }
    }

    // If you receive both values at once, this keeps them in sync on one main-thread hop.
    func update(leftRaw: CGFloat, rightRaw: CGFloat) {
        let l = normalize(leftRaw)
        let r = normalize(rightRaw)
        let newL = lerp(from: leftForce, to: l, alpha: smoothingAlpha)
        let newR = lerp(from: rightForce, to: r, alpha: smoothingAlpha)
        // Ensure UI updates on main thread
        DispatchQueue.main.async {
            self.leftForce = newL
            self.rightForce = newR
        }
    }

    private func normalize(_ raw: CGFloat) -> CGFloat {
        guard inputMax > inputMin else { return 0 }
        let t = (raw - inputMin) / (inputMax - inputMin)
        return min(max(t, 0), 1)
    }

    private func lerp(from a: CGFloat, to b: CGFloat, alpha: CGFloat) -> CGFloat {
        a + (b - a) * min(max(alpha, 0), 1)
    }
}

// The overlay view showing left/right pressure hints.
struct PressureOverlay: View {
    @ObservedObject var vm: PressureOverlayViewModel

    // Visual tuning
    var minOpacity: CGFloat = 0.06   // minimum visibility when force > 0
    var maxOpacity: CGFloat = 0.5    // max alpha at full force
    var widthFraction: CGFloat = 0.12 // fraction of screen width per side
    var cornerRadius: CGFloat = 0     // set >0 for rounded inner edges
    var verticalInset: CGFloat = 0    // inset from top/bottom if needed

    // Colors can be customized; using green-ish to match “OK/active”
    var leftColor: Color = .green
    var rightColor: Color = .green

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            let sideWidth = max(w * widthFraction, 12)

            ZStack {
                // Left hint
                sideHint(
                    force: vm.leftForce,
                    size: CGSize(width: sideWidth, height: h - verticalInset * 2),
                    color: leftColor,
                    align: .leading
                )
                .frame(width: sideWidth, height: h)
                .frame(maxWidth: .infinity, alignment: .leading)

                // Right hint
                sideHint(
                    force: vm.rightForce,
                    size: CGSize(width: sideWidth, height: h - verticalInset * 2),
                    color: rightColor,
                    align: .trailing
                )
                .frame(width: sideWidth, height: h)
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .frame(width: w, height: h)
            .ignoresSafeArea() // overlay across the content
        }
        .allowsHitTesting(false) // overlay is purely visual
    }

    @ViewBuilder
    private func sideHint(force: CGFloat,
                          size: CGSize,
                          color: Color,
                          align: HorizontalAlignment) -> some View {
        // Opacity scales with force in [0...1], with a min floor when > 0
        let alpha: CGFloat = force <= 0
            ? 0
            : minOpacity + (maxOpacity - minOpacity) * force

        // Gradient to fade into the content
        let gradient = LinearGradient(
            colors: [
                color.opacity(alpha),
                color.opacity(alpha * 0.6),
                color.opacity(0.0)
            ],
            startPoint: align == .leading ? .leading : .trailing,
            endPoint: align == .leading ? .trailing : .leading
        )

        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(gradient)
                .frame(width: size.width, height: size.height)
                .padding(.vertical, verticalInset)
        }
    }
}

//#if DEBUG
//import Testing
//
//@Suite("PressureOverlay basic mapping")
//struct PressureOverlayTests {
//    @Test
//    func lerpAndNormalize() async throws {
//        let vm = PressureOverlayViewModel()
//        vm.inputMin = 0
//        vm.inputMax = 100
//        vm.smoothingAlpha = 1.0 // no smoothing for test
//
//        vm.update(leftRaw: 0, rightRaw: 100)
//        #expect(vm.leftForce == 0)
//        #expect(vm.rightForce == 1)
//
//        vm.smoothingAlpha = 0.5
//        vm.updateLeft(raw: 100) // half way to 1
//        #expect(abs(vm.leftForce - 0.5) < 0.001)
//    }
//}
//#endif

