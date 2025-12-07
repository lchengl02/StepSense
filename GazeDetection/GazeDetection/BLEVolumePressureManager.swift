//
//  BLEVolumePressureManager.swift
//  GazeDetection
//
//  Created by clli02 on 12/3/25.
//

import Foundation
import CoreBluetooth
import SwiftUI
import Combine

final class BLEVolumePressureManager: NSObject, ObservableObject {

    private let serviceUUID        = CBUUID(string: "12345678-1234-1234-1234-1234567890ab")
    private let characteristicUUID = CBUUID(string: "abcd0001-1234-1234-1234-1234567890ab")

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?

    @Published var isConnected: Bool = false
    @Published var status: String = "Volume BT initializing…"
    
    @Published var direction: FootDirection = .neutral

    @Published var calibrationPhase: CalibrationPhase = .notStarted
    @Published var calibrationCountdown: Int = 3
    @Published var isPhaseRunning: Bool = false

    private let phaseDuration: TimeInterval = 3.0
    private var phaseStartTime: Date?

    private var neutralSum = [Int](repeating: 0, count: 4)
    private var forwardSum = [Int](repeating: 0, count: 4)
    private var backwardSum = [Int](repeating: 0, count: 4)

    private var neutralCount = 0
    private var forwardCount = 0
    private var backwardCount = 0

    private var neutralAvg: [Double]?
    private var forwardAvg: [Double]?
    private var backwardAvg: [Double]?

    private var calibrationTimer: Timer?

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    private func startScan() {
        status = "Scanning for Volume (Left) ESP32…"
        central.scanForPeripherals(withServices: [serviceUUID], options: nil)
    }

    private func resetCalibrationSums() {
        neutralSum = [Int](repeating: 0, count: 4)
        forwardSum = [Int](repeating: 0, count: 4)
        backwardSum = [Int](repeating: 0, count: 4)
        neutralCount = 0
        forwardCount = 0
        backwardCount = 0
    }

    func startCalibration() {
        resetCalibrationSums()
        DispatchQueue.main.async {
            self.calibrationPhase = .neutral
            self.calibrationCountdown = Int(self.phaseDuration)
            self.status = "Volume: stand still, then tap Start"
            self.isPhaseRunning = false
        }
        phaseStartTime = nil
        calibrationTimer?.invalidate()
    }

    func startCurrentPhase() {
        guard isConnected else { return }
        guard calibrationPhase == .neutral ||
              calibrationPhase == .forward ||
              calibrationPhase == .backward else { return }

        phaseStartTime = Date()
        DispatchQueue.main.async {
            self.calibrationCountdown = Int(self.phaseDuration)
            self.isPhaseRunning = true
        }

        calibrationTimer?.invalidate()
        startCalibrationTimer()
    }

    private func startCalibrationTimer() {
        calibrationTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self, let start = self.phaseStartTime else { return }

            let elapsed = Date().timeIntervalSince(start)
            let remain = max(0, self.phaseDuration - elapsed)

            DispatchQueue.main.async {
                self.calibrationCountdown = Int(ceil(remain))
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
            .compactMap { Int($0) }

        guard nums.count == 4 else { return }
        
        print("[Left] Sensors:",
              "s1 =", nums[0],
              "s2 =", nums[1],
              "s3 =", nums[2],
              "s4 =", nums[3],
              "| phase =", calibrationPhase.rawValue)

        processSamples(nums)
    }

    private func processSamples(_ nums: [Int]) {
        switch calibrationPhase {
        case .notStarted: break

        case .neutral:
            for i in 0..<4 { neutralSum[i] += nums[i] }
            neutralCount += 1

        case .forward:
            for i in 0..<4 { forwardSum[i] += nums[i] }
            forwardCount += 1

        case .backward:
            for i in 0..<4 { backwardSum[i] += nums[i] }
            backwardCount += 1

        case .done:
            classifyDirection(with: nums)
        }
    }

    private func completeCurrentPhase() {
        switch calibrationPhase {

        case .neutral:
            guard neutralCount > 0 else { return }
            neutralAvg = neutralSum.map { Double($0) / Double(neutralCount) }

            print("[Volume-Calib] Neutral Avg =", neutralAvg!)

            DispatchQueue.main.async {
                self.isPhaseRunning = false
                self.calibrationPhase = .forward
                self.status = "Volume: lean forward, then tap Start"
            }

        case .forward:
            guard forwardCount > 0 else { return }
            forwardAvg = forwardSum.map { Double($0) / Double(forwardCount) }

            print("[Volume-Calib] Forward Avg =", forwardAvg!)

            DispatchQueue.main.async {
                self.isPhaseRunning = false
                self.calibrationPhase = .backward
                self.status = "Volume: lean backward, then tap Start"
            }

        case .backward:
            guard backwardCount > 0 else { return }
            backwardAvg = backwardSum.map { Double($0) / Double(backwardCount) }

            print("[Volume-Calib] Backward Avg =", backwardAvg!)
            print("[Volume-Calib] All 3 segments completed")
            print("----------------------------------------")

            DispatchQueue.main.async {
                self.isPhaseRunning = false
                self.calibrationPhase = .done
                self.status = "Volume calibration completed"
            }

        default:
            break
        }

        phaseStartTime = nil
        calibrationTimer?.invalidate()
        calibrationTimer = nil
    }


    private func classifyDirection(with nums: [Int]) {
        guard
            let neutral = neutralAvg,
            let forward = forwardAvg,
            let backward = backwardAvg
        else { return }

        func front(_ v: [Double]) -> Double { (v[0] + v[1] + v[2]) / 3 }
        func back(_ v: [Double])  -> Double { v[3] }

        let fn = front(neutral)
        let bn = back(neutral)

        let ff = front(forward)
        let bf = back(forward)

        let fb = front(backward)
        let bb = back(backward)

        let featureNeutral  = fn - bn
        let featureForward  = ff - bf
        let featureBackward = fb - bb

        let curFront = Double(nums[0] + nums[1] + nums[2]) / 3.0
        let curBack  = Double(nums[3])
        let featureCurrent = curFront - curBack

        var forwardRatio: Double = 0
        var backwardRatio: Double = 0

        if featureCurrent >= featureNeutral {
            forwardRatio = (featureCurrent - featureNeutral) /
                           max(featureForward - featureNeutral, 1e-6)
            forwardRatio = min(max(forwardRatio, 0), 1)
        } else {
            backwardRatio = (featureNeutral - featureCurrent) /
                            max(featureNeutral - featureBackward, 1e-6)
            backwardRatio = min(max(backwardRatio, 0), 1)
        }

        let threshold = 0.99
        var newDir: FootDirection = .neutral
        if forwardRatio >= threshold { newDir = .forward }
        else if backwardRatio >= threshold { newDir = .backward }

        if newDir != direction {
            DispatchQueue.main.async {
                self.direction = newDir
                switch newDir {
                case .neutral:
                    self.status = "Volume: neutral"
                case .forward:
                    self.status = "Volume: UP"
                case .backward:
                    self.status = "Volume: DOWN"
                }
            }
        }
    }
}

// MARK: - CBCentralManagerDelegate
extension BLEVolumePressureManager: CBCentralManagerDelegate {

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            status = "Volume BT ON"
            startScan()
        default:
            status = "Volume BT state: \(central.state.rawValue)"
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String : Any],
        rssi RSSI: NSNumber
    ) {
        print("Found Volume device:", peripheral.name ?? "Unknown")
        self.peripheral = peripheral
        self.peripheral?.delegate = self

        central.stopScan()
        central.connect(peripheral)
        status = "Connecting to \(peripheral.name ?? "Volume ESP32")…"
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        status = "Volume device connected"
        isConnected = true

        startCalibration()
        peripheral.discoverServices([serviceUUID])
    }
}

// MARK: - CBPeripheralDelegate
extension BLEVolumePressureManager: CBPeripheralDelegate {

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
            status = "Subscribing to Volume notifications…"
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
