//
//  LWBluetoothManager.swift
//  LWBluetoothManager
//
//  Created by lailingwei on 16/6/7.
//  Copyright © 2016年 lailingwei. All rights reserved.
//

import Foundation
import CoreBluetooth

/**
 调试打印
 
 - discussion TARGET -> Build Setting -> Custom Flags -> Other Swift Flags -> Debug add "-D DEBUG"
 */
private func LWBLEPrint<T>(_ message: T, fileName: String = #file, methodName: String = #function, lineNumber: Int = #line) {
    #if DEBUG
        let str: String = (fileName as NSString).pathComponents.last!.replacingOccurrences(of: "swift", with: "")
        print("\(str)\(methodName)[\(lineNumber)]: \(message)")
    #endif
}


// 保存于NSUserDefault中，被系统蓝牙给搜索或链接的设备服务码数组的 key
private let kRetrieveOptionDic = "kRetrieveOptionDic"


// MARK: - Private methods

class LWCentralManager: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    
    // MARK:  Properties
    
    fileprivate static let instance = LWCentralManager()
    fileprivate var bleQueue = DispatchQueue(label: "LWCentralManager", attributes: [])
    fileprivate var centralManager: CBCentralManager!
    
    fileprivate var connectedOptions = [String : [String : [String]]]()
    fileprivate var observers = [LWObserver]()
    

    
    // MARK:  Initial
    
    fileprivate override init() {
        super.init()
        
        let restoreIdentifier = Bundle.main.infoDictionary?["CFBundleIdentifier"] ?? NSStringFromClass(LWCentralManager.self)
        
        centralManager = CBCentralManager(delegate: self,
                                          queue: bleQueue,
                                          options: [
                                            CBCentralManagerOptionShowPowerAlertKey : true,
                                            CBCentralManagerOptionRestoreIdentifierKey : restoreIdentifier])
     
    }
    
    
    // MARK: Helper methods
    
    fileprivate func supportHardware() -> Bool {
        
        switch centralManager.state {
        case .poweredOff:
            LWBLEPrint("当前设备的蓝牙为开启")
        case .poweredOn:
            LWBLEPrint("当前设备的蓝牙已开启")
            return true
        case .resetting:
            LWBLEPrint("当前设备的蓝牙正在重启")
        case .unauthorized:
            LWBLEPrint("当前App未获得用户对蓝牙的调用许可")
        case .unknown:
            LWBLEPrint("当前蓝牙状态未知")
        case .unsupported:
            LWBLEPrint("当前设备不支持蓝牙功能")
        }
        return false
    }
    
    /**
     Attempts to retrieve the <code>CBPeripheral</code> object(s) with the corresponding <i>identifiers</i>.
     */
    fileprivate func retrievePeripherals() {
        guard let optionDic = UserDefaults.standard.dictionary(forKey: kRetrieveOptionDic) else { return }
        
        // optionDic: [identifier : [serviceUUID : [characteristic]]]
        
        var nsuuids = [UUID]()
        for identifier in optionDic.keys {
            if let nsuuid = UUID(uuidString: identifier) {
                nsuuids.append(nsuuid)
            }
        }
        
        if nsuuids.count > 0 {
            let peripherals = centralManager.retrievePeripherals(withIdentifiers: nsuuids)
            for peripheral in peripherals {
                for observer in observers {
                    observer.scanPeripheralHandler?(centralManager,
                                                    peripheral,
                                                    nil,
                                                    peripheral.rssi)
                }
            }
        }
    }
    
    
    fileprivate func retrieveConnectedPeripherals() {
        guard let optionDic = UserDefaults.standard.dictionary(forKey: kRetrieveOptionDic) else { return }
        
        // optionDic: [identifier : [serviceUUID : [characteristic]]]
        
        var cbuuids = [CBUUID]()
        for identifier in optionDic.keys {
            if let nsuuid = UUID(uuidString: identifier), let value = optionDic[identifier] as? [String : [String]] {
                let cbuuid = CBUUID(nsuuid: nsuuid)
                cbuuids.append(cbuuid)
                // Update connectedOptions
                connectedOptions.updateValue(value, forKey: identifier)
            }
        }
        if cbuuids.count > 0 {
            let peripherals = centralManager.retrieveConnectedPeripherals(withServices: cbuuids)
            for peripheral in peripherals {
                centralManager.connect(peripheral, options: nil)
            }
        }
    }
    
    
    fileprivate func cleanup() {
        connectedOptions.removeAll(keepingCapacity: false)
    }
    
    
    
    // MARK: CBCentralManagerDelegate
    
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        
        for observer in observers {
            observer.centralManagerStateHandler?(supportHardware())
        }
        
        if !supportHardware() {
            cleanup()
        }
    }
    
    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String : Any]) {
        
        LWBLEPrint("CBCentralManagerRestoredStatePeripheralsKey: \(dict[CBCentralManagerRestoredStatePeripheralsKey])")
        LWBLEPrint("CBCentralManagerRestoredStateScanServicesKey: \(dict[CBCentralManagerRestoredStateScanServicesKey])")
        LWBLEPrint("CBCentralManagerRestoredStateScanOptionsKey: \(dict[CBCentralManagerRestoredStateScanOptionsKey])")
    }
    
    
    func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                                              advertisementData: [String : Any],
                                              rssi RSSI: NSNumber) {
        
        LWBLEPrint("发现设备:\n  peripheral: \(peripheral), advertisementData: \(advertisementData), RSSI: \(RSSI)")
        
        for observer in observers {
            observer.scanPeripheralHandler?(central,
                                            peripheral,
                                            advertisementData,
                                            RSSI)
        }
    }
    
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        
        LWBLEPrint("连接设备成功:\n  peripheral: \(peripheral)")
        
        for observer in observers {
            observer.peripheralConnectedHandler?(peripheral,
                                                 true,
                                                 nil)
        }
        
        // Discover services
        peripheral.delegate = self
        peripheral.discoverServices(nil)
    }
    
    func centralManager(_ central: CBCentralManager,
                        didFailToConnect peripheral: CBPeripheral,
                                                   error: Error?) {
        
        LWBLEPrint("连接设备失败:\n  peripheral: \(peripheral), error: \(error)")
        
        for observer in observers {
            observer.peripheralConnectedHandler?(peripheral,
                                                 false,
                                                 error)
        }
        // Update connectedOptions
        connectedOptions.removeValue(forKey: peripheral.identifier.uuidString)
    }
    
    func centralManager(_ central: CBCentralManager,
                        didDisconnectPeripheral peripheral: CBPeripheral,
                                                error: Error?) {
        
        LWBLEPrint("设备断开连接:\n  peripheral: \(peripheral), error: \(error)")
        
        for observer in observers {
            observer.peripheralConnectedHandler?(peripheral,
                                                 false,
                                                 error)
        }
        // Update connectedOptions
        connectedOptions.removeValue(forKey: peripheral.identifier.uuidString)
    }
    
    
    // MARK: CBPeripheralDelegate
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil else {
            LWBLEPrint("寻找服务码出错：\(error)")
            return
        }
            
        // Discover characteristics for service
        if let services = peripheral.services {
            for service in services {
                LWBLEPrint("发现服务码：\(services)")
                
                if let serviceDic = connectedOptions[peripheral.identifier.uuidString] {
                    for key in serviceDic.keys {
                        if service.uuid.uuidString == key {
                            LWBLEPrint("已找到指定了服务码：\(key)")
                            // Discover characteristics
                            peripheral.discoverCharacteristics(nil, for: service)
                            break
                        }
                    }
                }
            }
        }
    }
    
    
    func peripheral(_ peripheral: CBPeripheral,
                    didDiscoverCharacteristicsFor service: CBService,
                                                         error: Error?) {
        guard error == nil else {
            LWBLEPrint("寻找特征码出错：\(error)")
            return
        }
        
        // Discover characteristics
        if let characteristics = service.characteristics {
            for characteristic in characteristics {
                LWBLEPrint("发现特征码：\(characteristic)")
                
                if let characteristicStrings = connectedOptions[peripheral.identifier.uuidString]?[service.uuid.uuidString] {
                    for characteristicString in characteristicStrings {
                        if characteristic.uuid.uuidString == characteristicString {
                            LWBLEPrint("监听指定的特征码")
                            // Read characteristic value
                            peripheral.readValue(for: characteristic)
                            break
                        }
                    }
                }
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateValueFor characteristic: CBCharacteristic,
                                                    error: Error?) {
        for observer in observers {
            observer.peripheralDidUpdateValueHandler?(peripheral,
                                                      characteristic,
                                                      error)
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral,
                    didWriteValueFor characteristic: CBCharacteristic,
                                                   error: Error?) {
        for observer in observers {
            observer.peripheralDidWriteValueHandler?(peripheral,
                                                     characteristic,
                                                     error)
        }
    }
    

}


// MARK: - Public methods

extension LWCentralManager {

    
    static func shareManager() -> LWCentralManager {
        return LWCentralManager.instance
    }
    
    
    /**
     Starts scanning for peripherals
     */
    func startScanPeripheralsWithServices(_ serviceUUIDs: [String]?, allowDuplicates: Bool) {
        guard supportHardware() else {
            LWBLEPrint("当前蓝牙不可用，无法开始扫描设备")
            return
        }
        
        if #available(iOS 9.0, *) {
            guard !centralManager.isScanning else {
                LWBLEPrint("当前蓝牙已经在扫描，若要重新开始，请先停止扫描")
                return
            }
        }
        
        LWBLEPrint("开始扫描")
        
        var services: [CBUUID]?
        if let serviceUUIDs = serviceUUIDs {
            if serviceUUIDs.count > 0 {
                services = [CBUUID]()
                for uuid in serviceUUIDs {
                    services?.append(CBUUID(string: uuid))
                }
            }
        }
        centralManager.scanForPeripherals(withServices: services, options: [CBCentralManagerScanOptionAllowDuplicatesKey : allowDuplicates])
        
        // Try to retrieve peripherals
        retrievePeripherals()
        retrieveConnectedPeripherals()
    }
    
    
    func stopScan() {
        if #available(iOS 9.0, *) {
            guard centralManager.isScanning else { return }
        }
        
        LWBLEPrint("停止扫描")
        centralManager.stopScan()
    }
    
    
    /**
     Try to connect periperal
     
     - parameter peripheral:            he <code>CBPeripheral</code> to be connected.
     - parameter notifyOnConnection:    A Boolean value that specifies whether the system should display an alert
                                        for a given peripheral if the app is suspended when a successful connection is made.
                                        当应用挂起时，如果有一个连接成功时，是否想要系统为指定的peripheral显示一个提示。
     - parameter notifyOnDisconnection: A Boolean value that specifies whether the system should display a disconnection
                                        alert for a given peripheral if the app is suspended at the time of the disconnection.
                                        当应用挂起时，如果连接断开时，是否想要系统为指定的peripheral显示一个断开连接的提示。
     - parameter notifyOnNotification:  A Boolean value that specifies whether the system should display an alert for all
                                        notifications received from a given peripheral if the app is suspended at the time.
                                        当应用挂起时，使用该key值表示只要接收到给定peripheral端的通知就显示一个提示。
     - parameter options:               [serviceUUID : [characteristic]]
     */
    func connectPeripheral(_ peripheral: CBPeripheral,
                           notifyOnConnection: Bool,
                           notifyOnDisconnection: Bool,
                           notifyOnNotification: Bool,
                           options: [String : [String]]) {
        
        guard peripheral.state == .disconnected else {
            LWBLEPrint("peripheral: \(peripheral) 当前不是断开状态，无法尝试链接")
            return
        }
        
        connectedOptions.updateValue(options, forKey: peripheral.identifier.uuidString)
        centralManager.connect(peripheral, options: [
            CBConnectPeripheralOptionNotifyOnConnectionKey : notifyOnConnection,
            CBConnectPeripheralOptionNotifyOnDisconnectionKey : notifyOnDisconnection,
            CBConnectPeripheralOptionNotifyOnNotificationKey : notifyOnNotification]
        )
    }
    
    
    func cancelConnectPeripheral(_ peripheral: CBPeripheral) {
        guard peripheral.state == .connected else { return }
        
        centralManager.cancelPeripheralConnection(peripheral)
        peripheral.delegate = nil
        for observer in observers {
            observer.peripheralConnectedHandler?(peripheral,
                                                 false,
                                                 nil)
        }
        // Update connectedOptions
        connectedOptions.removeValue(forKey: peripheral.identifier.uuidString)
    }
    
    
    func addObserver(_ observer: NSObject,
                     centralManagerState stateHandler: CentralManagerStateHandler?,
                                         scanPeripheralHandler: ScanPeripheralsHandler?,
                                         peripheralConnectedHandler: PeripheralConnectedHandler?,
                                         peripheralDidUpdateValueHandler: PeripheralDidUpdateValueHandler?,
                                         peripheralDidWriteValueHandler: PeripheralDidWriteValueHandler?) {
        
        observers = observers.filter({ $0.objectSelf != observer })
        
        let obj = LWObserver(object: observer)
        observers.append(obj)
        
        obj.centralManagerStateHandler = stateHandler
        obj.scanPeripheralHandler = scanPeripheralHandler
        obj.peripheralConnectedHandler = peripheralConnectedHandler
        obj.peripheralDidUpdateValueHandler = peripheralDidUpdateValueHandler
        obj.peripheralDidWriteValueHandler = peripheralDidWriteValueHandler
    }
    
    
    func removeObserver(_ observer: NSObject) {
        observers = observers.filter({ $0.objectSelf != observer })
    }
    
    
    /**
     把可能会被系统要去的设备的服务、特征码存入NSUserDefault
     
     - parameter optionKey:     设备identifier
     - parameter optionValue:   [serviceUUID : [characteristic]]
     */
    func addSaveDevice(mightBeAppointBySystem optionKey: String, optionValue: [String : [String]]) {
        
        var storedDevices = UserDefaults.standard.dictionary(forKey: kRetrieveOptionDic) as? [String : [String : [String]]]
        if storedDevices == nil {
            storedDevices = [String : [String : [String]]]()
        }
        
        storedDevices!.updateValue(optionValue, forKey: optionKey)
        UserDefaults.standard.set(storedDevices!, forKey: kRetrieveOptionDic)
        UserDefaults.standard.synchronize()
    }
    
    func removeDevice(mightBeAppointBySystem optionKey: String) {
        guard var storedDevices = UserDefaults.standard.dictionary(forKey: kRetrieveOptionDic) as? [String : [String : [String]]] else { return }
        
        storedDevices.removeValue(forKey: optionKey)
        UserDefaults.standard.set(storedDevices, forKey: kRetrieveOptionDic)
        UserDefaults.standard.synchronize()
    }
    
}


// MARK: - LWObserver

typealias CentralManagerStateHandler = ((_ flag: Bool) -> Void)
typealias ScanPeripheralsHandler = ((_ central: CBCentralManager, _ discoverPeripheral: CBPeripheral, _ advertisementData: [String : Any]?, _ RSSI: NSNumber?) -> Void)
typealias PeripheralConnectedHandler = ((_ peripheral: CBPeripheral, _ connected: Bool, _ error: Error?) -> Void)
typealias PeripheralDidWriteValueHandler = ((_ peripheral: CBPeripheral, _ characteristic: CBCharacteristic, _ error: Error?) -> Void)
typealias PeripheralDidUpdateValueHandler = ((_ peripheral: CBPeripheral, _ characteristic: CBCharacteristic, _ error: Error?) -> Void)


private class LWObserver: NSObject {
    
    let objectSelf: NSObject
    
    var centralManagerStateHandler: CentralManagerStateHandler?
    var scanPeripheralHandler: ScanPeripheralsHandler?
    var peripheralConnectedHandler: PeripheralConnectedHandler?
    var peripheralDidWriteValueHandler: PeripheralDidWriteValueHandler?
    var peripheralDidUpdateValueHandler: PeripheralDidUpdateValueHandler?
    
    init(object: NSObject) {
        objectSelf = object
        super.init()
    }
}

