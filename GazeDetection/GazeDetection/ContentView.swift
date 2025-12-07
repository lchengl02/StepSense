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
    @StateObject private var playerVM = PlayerViewModel()
    
    @StateObject private var volumeBleVM = BLEVolumePressureManager()
    @State private var volumeHUDText: String? = nil



    @State private var useGazeRequirement: Bool = true

    private let videoURL: URL = {
        guard let url = Bundle.main.url(forResource: "demo", withExtension: "mp4") else {
            fatalError("Video not found")
        }
        return url
    }()
    
    var body: some View {
        ZStack(alignment: .top) {
            
            PlayerWithProgress(url: videoURL, vm: playerVM)
                .ignoresSafeArea()

            PressureOverlay(vm: bleVM)
                .ignoresSafeArea()
                .zIndex(1)
            
            if let hud = volumeHUDText {
                Text(hud)
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Color.black.opacity(0.7))
                    .cornerRadius(20)
                    .transition(.opacity)
                    .zIndex(5)
            }

            if gazeVM.isLooking {
                Text("Gaze detected.")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 14)
                    .background(Capsule().fill(Color.green))
                    .padding(.top, 16)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .animation(.easeInOut(duration: 0.2), value: gazeVM.isLooking)
                    .zIndex(2)
            }

            FaceHostView(vm: gazeVM)
                .frame(height: 1)
                .accessibilityHidden(true)

            VStack {
                Spacer()
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(bleVM.status)
                            .font(.caption2)
                            .foregroundColor(.white)
                            .padding(6)
                            .background(Color.black.opacity(0.5))
                            .cornerRadius(8)

                        Text(volumeBleVM.status + " | dir: \(volumeBleVM.direction.rawValue)")
                            .font(.caption2)
                            .foregroundColor(.white)
                            .padding(6)
                            .background(Color.black.opacity(0.5))
                            .cornerRadius(8)
                    }
                    Spacer()
                }
                .padding()
            }
            .zIndex(3)

            VStack {
                HStack(spacing: 8) {
                    Spacer()
                    
                    Button(action: {
                        playerVM.applyDirection(.neutral)

                        bleVM.startCalibration()
                        volumeBleVM.startCalibration()
                    }) {
                        Text("Re-Calibrate")
                            .font(.caption)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.black.opacity(0.5))
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }



                    Button(action: {
                        useGazeRequirement.toggle()
                    }) {
                        Text(useGazeRequirement ? "Gaze ON" : "Gaze OFF")
                            .font(.caption)
                            .padding(8)
                            .background(Color.black.opacity(0.5))
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }
                }
                .padding(.top, 40)
                .padding(.trailing, 16)

                Spacer()
            }
            .zIndex(10)


            if bleVM.calibrationPhase != .done {
                CalibrationOverlay(ble: bleVM, volumeBle: volumeBleVM)
                    .zIndex(100)
                    .transition(.opacity)
            }

        }

        .onChange(of: bleVM.direction) { newDir in
            if useGazeRequirement {
                if gazeVM.isLooking {
                    playerVM.applyDirection(newDir)
                } else {
                    playerVM.applyDirection(.neutral)
                }
            } else {
                playerVM.applyDirection(newDir)
            }
        }

        .onChange(of: gazeVM.isLooking) { looking in
            if useGazeRequirement {
                if looking {
                    playerVM.applyDirection(bleVM.direction)
                } else {
                    playerVM.applyDirection(.neutral)
                }
            }
        }
        .onChange(of: volumeBleVM.direction) { dir in
            print("[Volume] direction changed to:", dir.rawValue)

            switch dir {
            case .forward:
                playerVM.bumpVolume(delta: 0.2)
                let percent = Int((playerVM.volume * 100).rounded())
                showVolumeHUD("Volume Up \(percent)%")

            case .backward:
                playerVM.bumpVolume(delta: -0.2)
                let percent = Int((playerVM.volume * 100).rounded())
                showVolumeHUD("Volume Down \(percent)%")

            case .neutral:
                break
            }
        }
    }
    
    private func showVolumeHUD(_ text: String) {
        volumeHUDText = text

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            if volumeHUDText == text {
                volumeHUDText = nil
            }
        }
    }
}


struct CalibrationOverlay: View {
    @ObservedObject var ble: BLEPressureManager
    @ObservedObject var volumeBle: BLEVolumePressureManager


    private var instruction: String {
        if !ble.isConnected {
            return "Waiting for ESP32 connection…"
        }
        switch ble.calibrationPhase {
        case .notStarted:
            return "Waiting to start calibration…"
        case .neutral:
            return ble.isPhaseRunning
                ? "Stand still for 3 seconds."
                : "Stand still, then tap Start to record your neutral stance."
        case .forward:
            return ble.isPhaseRunning
                ? "Keep leaning forward for 3 seconds."
                : "Lean forward on your forefoot, then tap Start."
        case .backward:
            return ble.isPhaseRunning
                ? "Keep leaning backward on your heel for 3 seconds."
                : "Lean backward on your heel, then tap Start."
        case .done:
            return ""
        }
    }
    
    private var buttonTitle: String {
        switch ble.calibrationPhase {
        case .neutral:
            return "Start Neutral Calibration"
        case .forward:
            return "Start Forward Calibration"
        case .backward:
            return "Start Backward Calibration"
        default:
            return ""
        }
    }



    var body: some View {
        ZStack {
            Color.black.opacity(0.80).ignoresSafeArea()

            VStack(spacing: 20) {
                Text("Foot Pressure Calibration")
                    .font(.title2.weight(.bold))
                    .foregroundColor(.white)

                Text(instruction)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)

                if ble.calibrationPhase != .done && ble.isConnected {
                    Text("Time remaining: \(ble.calibrationCountdown)s")
                        .font(.title3.monospacedDigit())
                        .foregroundColor(.yellow)
                }
                
                if ble.calibrationPhase != .done && ble.isConnected {
                    if !buttonTitle.isEmpty {
                        Button(action: {
                            ble.startCurrentPhase()
                            volumeBle.startCurrentPhase()

                        }) {
                            Text(buttonTitle)
                                .font(.headline)
                                .foregroundColor(.black)
                                .padding(.horizontal, 24)
                                .padding(.vertical, 10)
                                .background(Color.white)
                                .cornerRadius(12)
                        }
                        .disabled(ble.isPhaseRunning)
                        .opacity(ble.isPhaseRunning ? 0.5 : 1.0)
                    }
                }


                if !ble.isConnected {
                    ProgressView()
                        .tint(.white)
                        .padding(.top, 8)
                }
            }
            .padding(32)
            .background(Color.black.opacity(0.6))
            .cornerRadius(20)
            .shadow(radius: 10)
        }
    }
}
