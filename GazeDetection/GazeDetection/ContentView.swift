//
//  ContentView.swift
//  GazeDetection
//
//  Created by clli02 on 10/10/25.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var gazeVM = AttentionViewModel()
    @StateObject private var bleVM = BLEPressureManager()

    private let videoURL = URL(string: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4")!

    var body: some View {
        ZStack(alignment: .top) {
            PlayerWithProgress(url: videoURL)
                .ignoresSafeArea()

            PressureOverlay(vm: bleVM)
                .ignoresSafeArea()
                .zIndex(1)

            if gazeVM.isLooking {
                Text("Gaze detected.")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 14)
                    .background(
                        Capsule().fill(Color.green)
                    )
                    .padding(.top, 16)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .animation(.easeInOut(duration: 0.2), value: gazeVM.isLooking)
                    .zIndex(2)
            }

            FaceHostView(vm: gazeVM)
                .frame(height: 1)
                .accessibilityHidden(true)

            // 可选：在角落显示 BLE 状态 debug
            VStack {
                Spacer()
                HStack {
                    Text(bleVM.status)
                        .font(.caption2)
                        .foregroundColor(.white)
                        .padding(6)
                        .background(Color.black.opacity(0.5))
                        .cornerRadius(8)
                    Spacer()
                }
                .padding()
            }
            .zIndex(3)
        }
    }
}
