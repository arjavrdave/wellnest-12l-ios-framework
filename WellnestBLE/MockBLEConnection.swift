//
//  BLEConnection.swift
//  WellNest Module
//
//  Created by Mayank Verma on 15/10/18.
//  Copyright © 2018 Mayank Verma. All rights reserved.

// This is the core  class for connecting to the BLE device.

import UIKit
import CoreBluetooth

internal class MockBluetoothSerial: BluetoothSerial {
    
    // MARK: Variables
    
    /// Whether this serial is ready to send and receive data
    override var isReady: Bool {
        get {
            return connectedPeripheral != nil
        }
    }
    
    /// Whether this serial is looking for advertising peripherals
    override var isScanning: Bool {
        return centralManager.isScanning
    }
    
    /// Whether the state of the centralManager is .poweredOn
    override var isPoweredOn: Bool {
        return centralManager.state == .poweredOn
    }
    
    
    // MARK: functions
    
    /// Always use this to initialize an instance
    override init() {
        super.init()
    }
    
    /// Start scanning for peripherals
    override func startScan() {
        let peripheral:WellnestPeripheral = WellnestPeripheral()
        peripheral.name = "Wellnest ECG (Mock)"
        delegate.serialDidDiscoverPeripheral(peripheral, RSSI: nil)
    }
    
    /// Try to connect to the given peripheral
    override func connectToPeripheral(_ peripheral: WellnestPeripheral) {
        connectedPeripheral = peripheral
        
        // notify the delegate we're ready for communication
        self.delegate.serialIsReady()
        self.delegate.serialDidConnect(connectedPeripheral!)
    }
    
    /// Send a string to the device
    override func sendMessageToDevice(_ message: String,_ awaitVal: Bool) {
        print("SENDED \(message)")
        guard isReady else { return }
        
        if awaitVal {
            commandQueue.append(message)
        }
        
        // Mock for all commands
        if (message.starts(with: "+GETDID")) {
            self.delegate.serialDidReceiveString("+MOCKGETAUT");
        } else if (message.starts(with: "+GETSTR=1")) {
            
            DispatchQueue.global(qos: .background).async {
                // Send 80k random data
                for i in 0..<5000 {
                    usleep(100)
                    self.delegate.serialDidReceiveData(Data(hex: dummyECGData[i]))
                }
            }
            
        } else if (message.starts(with: "+ELESTA")) {
            self.delegate.serialDidReceiveString("+ELESTA=ff8");
        } else if (message.starts(with: "+GETSTA")) {
           self.delegate.serialDidReceiveString("+GETSTA=1,3");
       }
    }
}


