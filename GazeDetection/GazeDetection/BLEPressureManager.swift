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

final class BLEPressureManager: NSObject, ObservableObject {

    private let serviceUUID        = CBUUID(string: "12345678-1234-1234-1234-1234567890ab")
    private let characteristicUUID = CBUUID(string: "abcd0001-1234-1234-1234-1234567890ab")

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?

    @Published var leftOpacity: CGFloat = 0.2
    @Published var rightOpacity: CGFloat = 0.2

    @Published var isConnected: Bool = false
    @Published var status: String = "Bluetooth initializing…"


    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    private func startScan() {
        status = "Scanning for ESP32…"
        central.scanForPeripherals(withServices: [serviceUUID], options: nil)
    }


    private func handlePressureData(_ data: Data) {
        guard let text = String(data: data, encoding: .utf8) else { return }

        print("BLE RX:", text)

        //  "SensorVal = 10,20,30,40"
        guard let range = text.range(of: "=") else { return }
        let numbersString = text[range.upperBound...].trimmingCharacters(in: .whitespaces)

        let nums = numbersString
            .split(separator: ",")
            .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }

        guard nums.count == 4 else { return }

        let s1 = nums[0]
        let s2 = nums[1]
        let s3 = nums[2]
        let s4 = nums[3]

        // TODO: define logic here
        // How to calculate pressure
        let leftVal  = CGFloat(s1 + s2) / 2.0
        let rightVal = CGFloat(s3 + s4) / 2.0

        // reflect on opacity 0.2 ~ 0.9
        let leftNorm  = max(0.2, min(0.9, leftVal / 100.0))
        let rightNorm = max(0.2, min(0.9, rightVal / 100.0))

        DispatchQueue.main.async {
            self.leftOpacity = leftNorm
            self.rightOpacity = rightNorm
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
