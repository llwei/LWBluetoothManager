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
private func LWBLEPrint<T>(message: T, fileName: String = #file, methodName: String = #function, lineNumber: Int = #line) {
    #if DEBUG
        let str: String = (fileName as NSString).pathComponents.last!.stringByReplacingOccurrencesOfString("swift", withString: "")
        print("\(str)\(methodName)[\(lineNumber)]: \(message)")
    #endif
}


// 保存于NSUserDefault中，被系统蓝牙给搜索或链接的设备服务码数组的 key
private let kRetrieveOptionDic = "kRetrieveOptionDic"


// MARK: - Private methods

class LWCentralManager: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    
    // MARK:  Properties
    
    private static let instance = LWCentralManager()
    private var bleQueue = dispatch_queue_create("LWCentralManager", DISPATCH_QUEUE_SERIAL)
    private var centralManager: CBCentralManager!
    
    private var connectedOptions = [String : [String : [String]]]()
    private var observers = [LWObserver]()
    

    
    // MARK:  Initial
    
    private override init() {
        super.init()
        
        let restoreIdentifier = NSBundle.mainBundle().infoDictionary?["CFBundleIdentifier"] ?? NSStringFromClass(LWCentralManager.self)
        
        centralManager = CBCentralManager(delegate: self,
                                          queue: bleQueue,
                                          options: [
                                            CBCentralManagerOptionShowPowerAlertKey : true,
                                            CBCentralManagerOptionRestoreIdentifierKey : restoreIdentifier])
     
    }
    
    
    // MARK: Helper methods
    
    /**
     Attempts to retrieve the <code>CBPeripheral</code> object(s) with the corresponding <i>identifiers</i>.
     */
    private func retrievePeripherals() {
        guard let optionDic = NSUserDefaults.standardUserDefaults().dictionaryForKey(kRetrieveOptionDic) else { return }
        
        // optionDic: [identifier : [serviceUUID : [characteristic]]]
        
        var nsuuids = [NSUUID]()
        for identifier in optionDic.keys {
            if let nsuuid = NSUUID(UUIDString: identifier) {
                nsuuids.append(nsuuid)
            }
        }
        
        if nsuuids.count > 0 {
            let peripherals = centralManager.retrievePeripheralsWithIdentifiers(nsuuids)
            for peripheral in peripherals {
                for observer in observers {
                    observer.scanPeripheralHandler?(central: centralManager,
                                                    discoverPeripheral: peripheral,
                                                    advertisementData: nil,
                                                    RSSI: peripheral.RSSI)
                }
            }
        }
    }
    
    
    private func retrieveConnectedPeripherals() {
        guard let optionDic = NSUserDefaults.standardUserDefaults().dictionaryForKey(kRetrieveOptionDic) else { return }
        
        // optionDic: [identifier : [serviceUUID : [characteristic]]]
        
        var cbuuids = [CBUUID]()
        for identifier in optionDic.keys {
            if let nsuuid = NSUUID(UUIDString: identifier), let value = optionDic[identifier] as? [String : [String]] {
                let cbuuid = CBUUID(NSUUID: nsuuid)
                cbuuids.append(cbuuid)
                // Update connectedOptions
                connectedOptions.updateValue(value, forKey: identifier)
            }
        }
        if cbuuids.count > 0 {
            let peripherals = centralManager.retrieveConnectedPeripheralsWithServices(cbuuids)
            for peripheral in peripherals {
                centralManager.connectPeripheral(peripheral, options: nil)
            }
        }
    }
    
    
    private func cleanup() {
        connectedOptions.removeAll(keepCapacity: false)
    }
    
    
    
    // MARK: CBCentralManagerDelegate
    
    func centralManagerDidUpdateState(central: CBCentralManager) {
        
        for observer in observers {
            observer.centralManagerStateHandler?(flag: supportHardware())
        }
        
        if !supportHardware() {
            cleanup()
        }
    }
    
    func centralManager(central: CBCentralManager, willRestoreState dict: [String : AnyObject]) {
        
        LWBLEPrint("CBCentralManagerRestoredStatePeripheralsKey: \(dict[CBCentralManagerRestoredStatePeripheralsKey])")
        LWBLEPrint("CBCentralManagerRestoredStateScanServicesKey: \(dict[CBCentralManagerRestoredStateScanServicesKey])")
        LWBLEPrint("CBCentralManagerRestoredStateScanOptionsKey: \(dict[CBCentralManagerRestoredStateScanOptionsKey])")
    }
    
    
    func centralManager(central: CBCentralManager,
                        didDiscoverPeripheral peripheral: CBPeripheral,
                                              advertisementData: [String : AnyObject],
                                              RSSI: NSNumber) {
        
        LWBLEPrint("发现设备:\n  peripheral: \(peripheral), advertisementData: \(advertisementData), RSSI: \(RSSI)")
        
        for observer in observers {
            observer.scanPeripheralHandler?(central: central,
                                            discoverPeripheral: peripheral,
                                            advertisementData: advertisementData,
                                            RSSI: RSSI)
        }
    }
    
    
    func centralManager(central: CBCentralManager, didConnectPeripheral peripheral: CBPeripheral) {
        
        LWBLEPrint("连接设备成功:\n  peripheral: \(peripheral)")
        
        for observer in observers {
            observer.peripheralConnectedHandler?(peripheral: peripheral,
                                                 connected: true,
                                                 error: nil)
        }
        
        // Discover services
        peripheral.delegate = self
        peripheral.discoverServices(nil)
    }
    
    func centralManager(central: CBCentralManager,
                        didFailToConnectPeripheral peripheral: CBPeripheral,
                                                   error: NSError?) {
        
        LWBLEPrint("连接设备失败:\n  peripheral: \(peripheral), error: \(error)")
        
        for observer in observers {
            observer.peripheralConnectedHandler?(peripheral: peripheral,
                                                 connected: false,
                                                 error: error)
        }
        // Update connectedOptions
        connectedOptions.removeValueForKey(peripheral.identifier.UUIDString)
    }
    
    func centralManager(central: CBCentralManager,
                        didDisconnectPeripheral peripheral: CBPeripheral,
                                                error: NSError?) {
        
        LWBLEPrint("设备断开连接:\n  peripheral: \(peripheral), error: \(error)")
        
        for observer in observers {
            observer.peripheralConnectedHandler?(peripheral: peripheral,
                                                 connected: false,
                                                 error: error)
        }
        // Update connectedOptions
        connectedOptions.removeValueForKey(peripheral.identifier.UUIDString)
    }
    
    
    // MARK: CBPeripheralDelegate
    
    func peripheral(peripheral: CBPeripheral, didDiscoverServices error: NSError?) {
        guard error == nil else {
            LWBLEPrint("寻找服务码出错：\(error)")
            return
        }
            
        // Discover characteristics for service
        if let services = peripheral.services {
            for service in services {
                LWBLEPrint("发现服务码：\(services)")
                
                if let serviceDic = connectedOptions[peripheral.identifier.UUIDString] {
                    for key in serviceDic.keys {
                        if service.UUID.UUIDString == key {
                            LWBLEPrint("已找到指定了服务码：\(key)")
                            // Discover characteristics
                            peripheral.discoverCharacteristics(nil, forService: service)
                            break
                        }
                    }
                }
            }
        }
    }
    
    
    func peripheral(peripheral: CBPeripheral,
                    didDiscoverCharacteristicsForService service: CBService,
                                                         error: NSError?) {
        guard error == nil else {
            LWBLEPrint("寻找特征码出错：\(error)")
            return
        }
        
        // Discover characteristics
        if let characteristics = service.characteristics {
            for characteristic in characteristics {
                LWBLEPrint("发现特征码：\(characteristic)")
                
                if let characteristicStrings = connectedOptions[peripheral.identifier.UUIDString]?[service.UUID.UUIDString] {
                    for characteristicString in characteristicStrings {
                        if characteristic.UUID.UUIDString == characteristicString {
                            LWBLEPrint("监听指定的特征码")
                            // Read characteristic value
                            peripheral.readValueForCharacteristic(characteristic)
                            break
                        }
                    }
                }
            }
        }
    }
    
    func peripheral(peripheral: CBPeripheral,
                    didUpdateValueForCharacteristic characteristic: CBCharacteristic,
                                                    error: NSError?) {
        for observer in observers {
            observer.peripheralDidUpdateValueHandler?(peripheral: peripheral,
                                                      characteristic: characteristic,
                                                      error: error)
        }
    }
    
    func peripheral(peripheral: CBPeripheral,
                    didWriteValueForCharacteristic characteristic: CBCharacteristic,
                                                   error: NSError?) {
        for observer in observers {
            observer.peripheralDidWriteValueHandler?(peripheral: peripheral,
                                                     characteristic: characteristic,
                                                     error: error)
        }
    }
    
    
}


// MARK: - Public methods

extension LWCentralManager {

    
    static func shareManager() -> LWCentralManager {
        return LWCentralManager.instance
    }
    
    
    private func supportHardware() -> Bool {
        
        switch centralManager.state {
        case .PoweredOff:
            LWBLEPrint("当前设备的蓝牙为开启")
        case .PoweredOn:
            LWBLEPrint("当前设备的蓝牙已开启")
            return true
        case .Resetting:
            LWBLEPrint("当前设备的蓝牙正在重启")
        case .Unauthorized:
            LWBLEPrint("当前App未获得用户对蓝牙的调用许可")
        case .Unknown:
            LWBLEPrint("当前蓝牙状态未知")
        case .Unsupported:
            LWBLEPrint("当前设备不支持蓝牙功能")
        }
        return false
    }
    
    /**
     Starts scanning for peripherals
     */
    func startScanPeripheralsWithServices(serviceUUIDs: [String]?, allowDuplicates: Bool) {
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
        centralManager.scanForPeripheralsWithServices(services, options: [CBCentralManagerScanOptionAllowDuplicatesKey : allowDuplicates])
        
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
    func connectPeripheral(peripheral: CBPeripheral,
                           notifyOnConnection: Bool,
                           notifyOnDisconnection: Bool,
                           notifyOnNotification: Bool,
                           options: [String : [String]]) {
        
        guard peripheral.state == .Disconnected else {
            LWBLEPrint("peripheral: \(peripheral) 当前不是断开状态，无法尝试链接")
            return
        }
        
        connectedOptions.updateValue(options, forKey: peripheral.identifier.UUIDString)
        centralManager.connectPeripheral(peripheral, options: [
            CBConnectPeripheralOptionNotifyOnConnectionKey : notifyOnConnection,
            CBConnectPeripheralOptionNotifyOnDisconnectionKey : notifyOnDisconnection,
            CBConnectPeripheralOptionNotifyOnNotificationKey : notifyOnNotification]
        )
    }
    
    
    func cancelConnectPeripheral(peripheral: CBPeripheral) {
        guard peripheral.state == .Connected else { return }
        
        centralManager.cancelPeripheralConnection(peripheral)
        peripheral.delegate = nil
        for observer in observers {
            observer.peripheralConnectedHandler?(peripheral: peripheral,
                                                 connected: false,
                                                 error: nil)
        }
        // Update connectedOptions
        connectedOptions.removeValueForKey(peripheral.identifier.UUIDString)
    }
    
    
    func addObserver(observer: NSObject,
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
    
    
    func removeObserver(observer: NSObject) {
        observers = observers.filter({ $0.objectSelf != observer })
    }
    
    
    /**
     把可能会被系统要去的设备的服务、特征码存入NSUserDefault
     
     - parameter optionKey:     设备identifier
     - parameter optionValue:   [serviceUUID : [characteristic]]
     */
    func addSaveDevice(mightBeAppointBySystem optionKey: String, optionValue: [String : [String]]) {
        
        var storedDevices = NSUserDefaults.standardUserDefaults().dictionaryForKey(kRetrieveOptionDic) as? [String : [String : [String]]]
        if storedDevices == nil {
            storedDevices = [String : [String : [String]]]()
        }
        
        storedDevices!.updateValue(optionValue, forKey: optionKey)
        NSUserDefaults.standardUserDefaults().setObject(storedDevices!, forKey: kRetrieveOptionDic)
        NSUserDefaults.standardUserDefaults().synchronize()
    }
    
    func removeDevice(mightBeAppointBySystem optionKey: String) {
        guard var storedDevices = NSUserDefaults.standardUserDefaults().dictionaryForKey(kRetrieveOptionDic) as? [String : [String : [String]]] else { return }
        
        storedDevices.removeValueForKey(optionKey)
        NSUserDefaults.standardUserDefaults().setObject(storedDevices, forKey: kRetrieveOptionDic)
        NSUserDefaults.standardUserDefaults().synchronize()
    }
    
}


// MARK: - LWObserver

typealias CentralManagerStateHandler = ((flag: Bool) -> Void)
typealias ScanPeripheralsHandler = ((central: CBCentralManager, discoverPeripheral: CBPeripheral, advertisementData: [String : AnyObject]?, RSSI: NSNumber?) -> Void)
typealias PeripheralConnectedHandler = ((peripheral: CBPeripheral, connected: Bool, error: NSError?) -> Void)
typealias PeripheralDidWriteValueHandler = ((peripheral: CBPeripheral, characteristic: CBCharacteristic, error: NSError?) -> Void)
typealias PeripheralDidUpdateValueHandler = ((peripheral: CBPeripheral, characteristic: CBCharacteristic, error: NSError?) -> Void)


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

