//
//  BLEPressureManager.swift
//  GazeDetection
//
//  Created by clli02 on 11/19/25.
//


import Foundation
import CoreBluetooth
import SwiftUI
import Combine

enum FootDirection: String {
    case neutral
    case forward
    case backward
}

enum CalibrationPhase: String {
    case notStarted
    case neutral
    case forward
    case backward
    case done
}

final class BLEPressureManager: NSObject, ObservableObject {

    private let serviceUUID        = CBUUID(string: "87654321-0000-0000-0000-000000000000")
    private let characteristicUUID = CBUUID(string: "dcba0001-0000-0000-0000-000000000000")

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?

    @Published var leftOpacity: CGFloat = 0.2
    @Published var rightOpacity: CGFloat = 0.2

    @Published var isConnected: Bool = false
    @Published var status: String = "Bluetooth initializing…"
    
    @Published var frontPercent: Int = 0
    @Published var backPercent: Int = 0
    
    @Published var isPhaseRunning: Bool = false

    @Published var calibrationPhase: CalibrationPhase = .notStarted
    @Published var calibrationCountdown: Int = 3
    @Published var direction: FootDirection = .neutral

    private let phaseDuration: TimeInterval = 3.0
    private var phaseStartTime: Date?

    private var neutralSum = [Int](repeating: 0, count: 4)
    private var forwardSum = [Int](repeating: 0, count: 4)

    private var backwardSumS4: Int = 0

    private var neutralCount = 0
    private var forwardCount = 0
    private var backwardCount = 0

    private var neutralAvg: [Double]?
    private var forwardAvg: [Double]?
    private var backwardAvgS4: Double?

    private var calibrationTimer: Timer?

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    private func startScan() {
        status = "Scanning for Right ESP32…"
        central.scanForPeripherals(withServices: [serviceUUID], options: nil)
    }

    // MARK: - Calibration control

    private func resetCalibrationSums() {
        neutralSum = [Int](repeating: 0, count: 4)
        forwardSum = [Int](repeating: 0, count: 4)
        backwardSumS4 = 0

        neutralCount = 0
        forwardCount = 0
        backwardCount = 0

        neutralAvg = nil
        forwardAvg = nil
        backwardAvgS4 = nil
    }

    func startCalibration() {
        resetCalibrationSums()

        DispatchQueue.main.async {
            self.calibrationPhase = .neutral
            self.calibrationCountdown = Int(self.phaseDuration)
            self.status = "Ready: stand still, then tap Start"
            self.isPhaseRunning = false
        }

        phaseStartTime = nil
        calibrationTimer?.invalidate()
    }
    
    func startCurrentPhase() {
        guard isConnected else { return }

        guard calibrationPhase == .neutral ||
              calibrationPhase == .forward ||
              calibrationPhase == .backward else {
            return
        }

        phaseStartTime = Date()

        DispatchQueue.main.async {
            self.calibrationCountdown = Int(self.phaseDuration)
            self.isPhaseRunning = true

            switch self.calibrationPhase {
            case .neutral:
                self.status = "Calibrating: stand still…"
            case .forward:
                self.status = "Calibrating: lean forward…"
            case .backward:
                self.status = "Calibrating: lean backward…"
            default:
                break
            }
        }

        calibrationTimer?.invalidate()
        startCalibrationTimer()
    }

    private func startCalibrationTimer() {
        calibrationTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self else { return }

            guard self.calibrationPhase == .neutral ||
                  self.calibrationPhase == .forward ||
                  self.calibrationPhase == .backward
            else { return }

            guard let start = self.phaseStartTime else { return }

            let now = Date()
            let elapsed = now.timeIntervalSince(start)
            let remain = max(0, self.phaseDuration - elapsed)

            let intRemain = max(0, Int(ceil(remain)))
            DispatchQueue.main.async {
                self.calibrationCountdown = intRemain
            }

            if elapsed >= self.phaseDuration {
                self.completeCurrentPhase()
            }
        }

        RunLoop.main.add(calibrationTimer!, forMode: .common)
    }

    private func handlePressureData(_ data: Data) {
        guard var text = String(data: data, encoding: .utf8) else { return }

        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        let nums = text
            .split(separator: ",")
            .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }

        guard nums.count == 4 else { return }

        print("[Right] Sensors:",
              "s1 =", nums[0],
              "s2 =", nums[1],
              "s3 =", nums[2],
              "s4 =", nums[3],
              "| phase =", calibrationPhase.rawValue)

        processSamples(nums)
    }

    private func processSamples(_ nums: [Int]) {
        switch calibrationPhase {
        case .notStarted:
            break

        case .neutral, .forward, .backward:
            switch calibrationPhase {
            case .neutral:
                for i in 0..<4 { neutralSum[i] += nums[i] }
                neutralCount += 1

            case .forward:
                for i in 0..<4 { forwardSum[i] += nums[i] }
                forwardCount += 1

            case .backward:
                backwardSumS4 += nums[3]
                backwardCount += 1

            default:
                break
            }

        case .done:
            updateOpacity(from: nums)
            classifyDirection(with: nums)
        }
    }

    private func completeCurrentPhase() {
        switch calibrationPhase {
        case .neutral:
            guard neutralCount > 0 else { return }
            let avg = neutralSum.map { Double($0) / Double(neutralCount) }
            neutralAvg = avg
            print("[Direction-Calib] Neutral Avg =", avg)

            DispatchQueue.main.async {
                self.isPhaseRunning = false
                self.calibrationPhase = .forward
                self.status = "Ready: lean forward, then tap Start"
                self.calibrationCountdown = Int(self.phaseDuration)
            }
            phaseStartTime = nil
            calibrationTimer?.invalidate()

        case .forward:
            guard forwardCount > 0 else { return }
            let avg = forwardSum.map { Double($0) / Double(forwardCount) }
            forwardAvg = avg
            print("[Direction-Calib] Forward Avg =", avg)

            DispatchQueue.main.async {
                self.isPhaseRunning = false
                self.calibrationPhase = .backward
                self.status = "Ready: lean backward, then tap Start"
                self.calibrationCountdown = Int(self.phaseDuration)
            }
            phaseStartTime = nil
            calibrationTimer?.invalidate()

        case .backward:
            guard backwardCount > 0 else { return }
            let heelAvg = Double(backwardSumS4) / Double(backwardCount)
            backwardAvgS4 = heelAvg
            print("[Direction-Calib] Backward Count =", backwardCount)
            print("[Direction-Calib] Backward Heel Sum (s4) =", backwardSumS4)
            print("[Direction-Calib] Backward Heel Avg (s4) =", heelAvg)
            print("[Direction-Calib] All 3 segments completed")
            print("----------------------------------------")

            DispatchQueue.main.async {
                self.isPhaseRunning = false
                self.calibrationPhase = .done
                self.status = "Calibration completed"
                self.calibrationCountdown = 0
            }
            phaseStartTime = nil
            calibrationTimer?.invalidate()
            calibrationTimer = nil

        default:
            break
        }
    }

    private func updateOpacity(from nums: [Int]) {
        guard
            let neutral = neutralAvg,
            let forward = forwardAvg,
            let heelBackward = backwardAvgS4
        else {
            return
        }

        let backward: [Double] = [
            neutral[0],
            neutral[1],
            neutral[2],
            heelBackward
        ]

        func front(_ vals: [Double]) -> Double { (vals[0] + vals[1] + vals[2]) / 3.0 }
        func back(_ vals: [Double]) -> Double { vals[3] }

        let neutralFront   = front(neutral)
        let neutralBack    = back(neutral)
        let forwardFront   = front(forward)
        let forwardBack    = back(forward)
        let backwardFront  = front(backward)
        let backwardBack   = back(backward)

        let featureNeutral  = neutralFront  - neutralBack
        let featureForward  = forwardFront  - forwardBack
        let featureBackward = backwardFront - backwardBack

        let currentFront = Double(nums[0] + nums[1] + nums[2]) / 3.0
        let currentBack  = Double(nums[3])
        let featureCurrent = currentFront - currentBack

        var forwardRatio: Double = 0
        var backwardRatio: Double = 0

        if featureCurrent >= featureNeutral {
            let denom = max(featureForward - featureNeutral, 1e-6)
            let r = (featureCurrent - featureNeutral) / denom
            forwardRatio = min(max(r, 0), 1)
            backwardRatio = 0
        } else {
            let denom = max(featureNeutral - featureBackward, 1e-6)
            let r = (featureNeutral - featureCurrent) / denom
            backwardRatio = min(max(r, 0), 1)
            forwardRatio = 0
        }

        let frontOpacity  = 0.2 + 0.7 * forwardRatio
        let backOpacity   = 0.2 + 0.7 * backwardRatio

        DispatchQueue.main.async {
            self.leftOpacity  = CGFloat(frontOpacity)
            self.rightOpacity = CGFloat(backOpacity)

            self.frontPercent = Int((forwardRatio  * 100).rounded())
            self.backPercent  = Int((backwardRatio * 100).rounded())
        }
    }

    private func classifyDirection(with nums: [Int]) {
        guard
            let neutral = neutralAvg,
            let forward = forwardAvg,
            let heelBackward = backwardAvgS4
        else {
            return
        }

        let backward: [Double] = [
            neutral[0],
            neutral[1],
            neutral[2],
            heelBackward
        ]

        func front(_ vals: [Double]) -> Double { (vals[0] + vals[1] + vals[2]) / 3.0 }
        func back(_ vals: [Double]) -> Double { vals[3] }

        let neutralFront   = front(neutral)
        let neutralBack    = back(neutral)
        let forwardFront   = front(forward)
        let forwardBack    = back(forward)
        let backwardFront  = front(backward)
        let backwardBack   = back(backward)

        let featureNeutral  = neutralFront  - neutralBack
        let featureForward  = forwardFront  - forwardBack
        let featureBackward = backwardFront - backwardBack

        let currentFront = Double(nums[0] + nums[1] + nums[2]) / 3.0
        let currentBack  = Double(nums[3])
        let featureCurrent = currentFront - currentBack

        var forwardRatio: Double = 0
        var backwardRatio: Double = 0

        if featureCurrent >= featureNeutral {
            let denom = max(featureForward - featureNeutral, 1e-6)
            let r = (featureCurrent - featureNeutral) / denom
            forwardRatio = min(max(r, 0), 1)
            backwardRatio = 0
        } else {
            let denom = max(featureNeutral - featureBackward, 1e-6)
            let r = (featureNeutral - featureCurrent) / denom
            backwardRatio = min(max(r, 0), 1)
            forwardRatio = 0
        }

        let fullThreshold = 0.99

        var newDirection: FootDirection = .neutral
        if forwardRatio >= fullThreshold {
            newDirection = .forward
        } else if backwardRatio >= fullThreshold {
            newDirection = .backward
        } else {
            newDirection = .neutral
        }

        if newDirection != direction {
            DispatchQueue.main.async {
                self.direction = newDirection
                switch newDirection {
                case .neutral:
                    self.status = "Neutral stance"
                case .forward:
                    self.status = "Leaning forward (fast-forward)"
                case .backward:
                    self.status = "Leaning backward (rewind)"
                }
            }
        }
    }
}

// MARK: - CBCentralManagerDelegate
extension BLEPressureManager: CBCentralManagerDelegate {

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            status = "Bluetooth ON"
            startScan()
        default:
            status = "BT state: \(central.state.rawValue)"
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String : Any],
        rssi RSSI: NSNumber
    ) {
        print("Found:", peripheral.name ?? "Unknown")

        self.peripheral = peripheral
        self.peripheral?.delegate = self

        central.stopScan()
        central.connect(peripheral)
        status = "Connecting to \(peripheral.name ?? "ESP32")…"
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        status = "Connected"
        isConnected = true
        startCalibration()
        peripheral.discoverServices([serviceUUID])
    }
}

// MARK: - CBPeripheralDelegate
extension BLEPressureManager: CBPeripheralDelegate {

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        for s in services where s.uuid == serviceUUID {
            peripheral.discoverCharacteristics([characteristicUUID], for: s)
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        guard let chars = service.characteristics else { return }

        for ch in chars where ch.uuid == characteristicUUID {
            status = "Subscribing to notifications…"
            peripheral.setNotifyValue(true, for: ch)
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard characteristic.uuid == characteristicUUID,
              let data = characteristic.value else { return }

        handlePressureData(data)
    }
}


