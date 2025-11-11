//
//  PlayerView.swift
//  GazeDetection
//
//  Created by clli02 on 11/3/25.
//

import SwiftUI
import AVKit
import AVFoundation
import Combine

struct PlayerWithProgress: View {
    let url: URL
    @StateObject private var vm = PlayerViewModel()

    var body: some View {
        ZStack(alignment: .bottom) {
            VideoPlayer(player: vm.player)
                .onAppear { vm.configure(with: url) }
                .onDisappear { vm.cleanup() }
                .ignoresSafeArea()

            VStack(spacing: 8) {
                Slider(value: $vm.currentSeconds,
                       in: 0...max(vm.durationSeconds, 0.1),
                       onEditingChanged: { editing in
                           vm.seeking = editing
                           vm.seekIfNeeded()
                       })
                .padding(.horizontal, 16)

                HStack {
                    Text(timeString(vm.currentSeconds))
                    Spacer()
                    Text(timeString(max(vm.durationSeconds - vm.currentSeconds, 0)))
                }
                .font(.caption.monospacedDigit())
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
            .background(Color.black.opacity(0.35).ignoresSafeArea(edges: .bottom))
        }
    }

    private func timeString(_ seconds: Double) -> String {
        guard seconds.isFinite && !seconds.isNaN else { return "--:--" }
        let s = Int(seconds.rounded(.down))
        let m = s / 60
        let r = s % 60
        return String(format: "%d:%02d", m, r)
    }
}

final class PlayerViewModel: ObservableObject {
    let player = AVPlayer()
    private var timeObserver: Any?
    private var statusObserver: NSKeyValueObservation?

    @Published var durationSeconds: Double = 0
    @Published var currentSeconds: Double = 0
    @Published var seeking: Bool = false

    func configure(with url: URL) {
        let item = AVPlayerItem(url: url)
        player.replaceCurrentItem(with: item)

        statusObserver = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            guard let self else { return }
            if item.status == .readyToPlay {
                let dur = item.asset.duration.seconds ?? 0
                DispatchQueue.main.async { self.durationSeconds = dur.isFinite ? dur : 0 }
                self.player.play()
            } else if item.status == .failed {
                print("Player item failed: \(String(describing: item.error))")
            }
        }

        let interval = CMTime(seconds: 0.25, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] t in
            guard let self, !self.seeking else { return }
            self.currentSeconds = t.seconds ?? 0
        }
    }

    func seekIfNeeded() {
        guard seeking else { return }
        let target = CMTime(seconds: currentSeconds, preferredTimescale: 600)
        player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func cleanup() {
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        timeObserver = nil
        statusObserver = nil
        player.pause()
    }
}

private extension CMTime {
    var seconds: Double? {
        guard flags.contains(.valid), timescale != 0 else { return nil }
        return Double(value) / Double(timescale)
    }
}
