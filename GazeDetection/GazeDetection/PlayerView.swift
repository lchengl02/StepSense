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
    @ObservedObject var vm: PlayerViewModel

    var body: some View {
        ZStack(alignment: .bottom) {
            VideoPlayer(player: vm.player)
                .onAppear { vm.configure(with: url) }
                .onDisappear { vm.cleanup() }
                .ignoresSafeArea()

            VStack(spacing: 8) {
                Slider(
                    value: $vm.currentSeconds,
                    in: 0...max(vm.durationSeconds, 0.1),
                    onEditingChanged: { editing in
                        vm.seeking = editing
                        vm.seekIfNeeded()
                    }
                )
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

    enum PlaybackMode {
        case normal
        case fastForward
        case rewind
    }

    @Published var mode: PlaybackMode = .normal

    private var controlTimer: AnyCancellable?
    
    @Published private(set) var volume: Float = 1.0


    func configure(with url: URL) {
        let item = AVPlayerItem(url: url)

        item.audioTimePitchAlgorithm = .timeDomain   // 或 .spectral

        player.replaceCurrentItem(with: item)

        statusObserver = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            guard let self else { return }
            if item.status == .readyToPlay {
                let dur = item.asset.duration.seconds ?? 0
                DispatchQueue.main.async { self.durationSeconds = dur.isFinite ? dur : 0 }
            } else if item.status == .failed {
                print("Player item failed: \(String(describing: item.error))")
            }
        }

        let interval = CMTime(seconds: 0.25, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] t in
            guard let self, !self.seeking else { return }
            self.currentSeconds = t.seconds ?? 0
        }

        controlTimer = Timer.publish(every: 0.25, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.applyCurrentMode()
            }
        setVolume(0.5)
    }
    
    func setVolume(_ v: Float) {
    
        let clamped = max(0, min(v, 1))
        volume = clamped
        player.volume = clamped
        print("[Player] volume set to", clamped)

        }

    func bumpVolume(delta: Float) {
        setVolume(volume + delta)
    }


    func applyDirection(_ dir: FootDirection) {
        switch dir {
        case .neutral:
            mode = .normal
        case .forward:
            mode = .fastForward
        case .backward:
            mode = .rewind
        }
    }

    private func applyCurrentMode() {
        guard player.currentItem != nil else { return }

        switch mode {
        case .normal:
            player.isMuted = false
            if player.rate != 1.0 {
                player.rate = 1.0
            }

        case .fastForward:
            player.isMuted = false
            if let item = player.currentItem {
                if item.audioTimePitchAlgorithm != .timeDomain {
                    item.audioTimePitchAlgorithm = .timeDomain
                }
            }
            if player.rate != 2.0 {
                player.rate = 2.0
            }

        case .rewind:
            player.isMuted = true

            if let item = player.currentItem, item.canPlayReverse {
                if player.rate != -1.0 {
                    player.rate = -1.0
                }
            } else {
                player.rate = 0.0

                guard durationSeconds > 0 else { return }

                let step: Double = 0.5 * 2.0
                let targetSeconds = max(currentSeconds - step, 0)
                let target = CMTime(seconds: targetSeconds, preferredTimescale: 600)

                player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
                currentSeconds = targetSeconds
            }
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
        controlTimer?.cancel()
        controlTimer = nil
        player.pause()
    }
}

private extension CMTime {
    var seconds: Double? {
        guard flags.contains(.valid), timescale != 0 else { return nil }
        return Double(value) / Double(timescale)
    }
}

