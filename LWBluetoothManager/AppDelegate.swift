//
//  AppDelegate.swift
//  LWBluetoothManager
//
//  Created by lailingwei on 16/6/7.
//  Copyright © 2016年 lailingwei. All rights reserved.
//

import UIKit

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?


    func application(application: UIApplication, didFinishLaunchingWithOptions launchOptions: [NSObject: AnyObject]?) -> Bool {

        LWBluetoothManager.shareManager().addObserver(self,
                                                      centralManagerState: { (flag) in
                                                        if flag {
                                                            LWBluetoothManager.shareManager().startScanPeripherals(true)
                                                        }
            }, scanPeripheralHandler: { (central, discoverPeripheral, advertisementData, RSSI) in
                
                print(discoverPeripheral)
                
            }, peripheralConnectedHandler: { (peripheral, connected, error) in
                
                if connected {
                    LWBluetoothManager.shareManager().stopScan()
                }
                
            }, peripheralDidUpdateValueHandler: { (peripheral, characteristic, error) in
                
            }) { (peripheral, characteristic, error) in
                
        }
        
        
        return true
    }


    

}

