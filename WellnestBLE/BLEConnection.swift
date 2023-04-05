//
//  BLEConnection.swift
//  WellNest Module
//
//  Created by Mayank Verma on 15/10/18.
//  Copyright © 2018 Mayank Verma. All rights reserved.

// This is the core  class for connecting to the BLE device.

import UIKit
import CoreBluetooth

// Delegate functions
internal protocol BluetoothSerialDelegate {
    // ** Required **
    
    /// Called when de state of the CBCentralManager changes (e.g. when bluetooth is turned on/off)
    func serialDidChangeState()
    
    /// Called when a peripheral disconnected
    func serialDidDisconnect(_ peripheral: WellnestPeripheral?, error: NSError?)
    
    // ** Optionals **
    
    /// Called when a message is received
    func serialDidReceiveString(_ message: String)

    /// Called when a message is received
    func serialDidReceiveData(_ data: Data)
    
    /// Called when the RSSI of the connected peripheral is read
    func serialDidReadRSSI(_ rssi: NSNumber)
    
    /// Called when a new peripheral is discovered while scanning. Also gives the RSSI (signal strength)
    func serialDidDiscoverPeripheral(_ peripheral: WellnestPeripheral, RSSI: NSNumber?)
    
    /// Called when a peripheral is connected (but not yet ready for cummunication)
    func serialDidConnect(_ peripheral: WellnestPeripheral)
    
    /// Called when a pending connection failed
    func serialDidFailToConnect(_ peripheral: CBPeripheral, error: NSError?)
    
    /// Called when a peripheral is ready for communication
    func serialIsReady()
}


internal class BluetoothSerial: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    
    static let shared = BluetoothSerial()
    public var commandQueue: [String] = []
    public var response: String = ""
    
    // The peripheral to keep an instance of when auto connecting
    var autoconnectingPeripheral: CBPeripheral?
    
    private static var viewController: UIViewController {
        get {
            let appDelegate = UIApplication.shared.delegate
            var vc = appDelegate?.window??.rootViewController
            
            if vc is UINavigationController {
                vc = (vc as! UINavigationController).visibleViewController
            }
            return vc!
        }
    }
    
    // MARK: Variables
    
    var peripherals = [CBPeripheral]()
    
    /// The delegate object the BluetoothDelegate methods will be called upon
    var delegate: BluetoothSerialDelegate!
    
    /// The CBCentralManager this bluetooth serial handler used for... well, everything really
    var centralManager: CBCentralManager!
    
    /// The peripheral we're trying to connect to (nil if none)
    var pendingPeripheral: CBPeripheral?
    
    /// The connected peripheral (nil if none is connected)
    var connectedPeripheral: WellnestPeripheral?
    
    /// The characteristic we need to write to, of the connectedPeripheral
    weak var writeCharacteristic: CBCharacteristic?
    
    /// Whether this serial is ready to send and receive data
    var isReady: Bool {
        get {
            return centralManager.state == .poweredOn &&
                connectedPeripheral != nil &&
                writeCharacteristic != nil
        }
    }
    
    /// Whether this serial is looking for advertising peripherals
    var isScanning: Bool {
        return centralManager.isScanning
    }
    
    /// Whether the state of the centralManager is .poweredOn
    var isPoweredOn: Bool {
        return centralManager.state == .poweredOn
    }
    
    /// UUID of the service to look for.
    var serviceUUID = CBUUID(string: "FFE0")
    
    /// UUID of the characteristic to look for.
    var characteristicUUID = CBUUID(string: "FFE1")
    
    /// Whether to write to the HM10 with or without response. Set automatically.
    /// Legit HM10 modules (from JNHuaMao) require 'Write without Response',
    /// while fake modules (e.g. from Bolutek) require 'Write with Response'.
    private var writeType: CBCharacteristicWriteType = .withoutResponse
    
    
    // MARK: functions
    
    /// Always use this to initialize an instance
    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }
    
    /// Start scanning for peripherals
    func startScan() {
        print("Start Scanning");
        self.peripherals = []
        
        if let p = self.autoconnectingPeripheral {
            centralManager.cancelPeripheralConnection(p)
            self.autoconnectingPeripheral = nil
        }
        guard centralManager.state == .poweredOn else { return }
        
        // start scanning for all the peripherals
        centralManager.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey : false])
        
        
        // retrieve peripherals that are already connected
        // see this stackoverflow question http://stackoverflow.com/questions/13286487
        let peripherals = centralManager.retrieveConnectedPeripherals(withServices: [])
        for peripheral in peripherals {
            
            for p in self.peripherals {
               if p.identifier == peripheral.identifier {
                   continue
               }
           }
            
            self.peripherals.append(peripheral)
            
            print("Found retrieved peripherals");
            let p = WellnestPeripheral()
            p.identifier = peripheral.identifier
            p.name = peripheral.name
            delegate.serialDidDiscoverPeripheral(p, RSSI: nil)
        }
    }
    
    /// Stop scanning for peripherals
    func stopScan() {
        centralManager.stopScan()
    }
    
    /// Try to connect to the given peripheral
    func connectToPeripheral(_ peripheral: WellnestPeripheral) {
        for p in self.peripherals {
           if p.identifier == peripheral.identifier {
               pendingPeripheral = p
               centralManager.connect(pendingPeripheral!, options: nil)
               return
           }
       }
    }
    
    /// Disconnect from the connected peripheral or stop connecting to it
    func disconnect() {
        if let p = connectedPeripheral {
            let retrievedPeripherals  =  centralManager.retrievePeripherals(withIdentifiers: [p.identifier])
            if retrievedPeripherals.count > 0 {
                centralManager.cancelPeripheralConnection(retrievedPeripherals[0])
            }
        } else if let p = pendingPeripheral {
            let retrievedPeripherals  =  centralManager.retrievePeripherals(withIdentifiers: [p.identifier])
            if retrievedPeripherals.count > 0 {
                centralManager.cancelPeripheralConnection(retrievedPeripherals[0])
            }
        }
    }
    
    /// The didReadRSSI delegate function will be called after calling this function
    func readRSSI() {
        guard isReady else { return }
        let retrievedPeripherals  =  centralManager.retrievePeripherals(withIdentifiers: [connectedPeripheral!.identifier])
        if retrievedPeripherals.count > 0 {
            retrievedPeripherals[0].readRSSI()
        }
    }
    
    /// Send a string to the device
    func sendMessageToDevice(_ message: String,_ awaitVal: Bool) {
        print("ISREADY" ,isReady)
        print("THREE CONDITIONS ", centralManager.state == .poweredOn,connectedPeripheral != nil,
              writeCharacteristic != nil )
        guard isReady else { return }
        
        
        if awaitVal {
            commandQueue.append(message)
        }
        
        if let data = message.data(using: String.Encoding.utf8) {
            print ("Command: ")
            print (message)
            let retrievedPeripherals  =  centralManager.retrievePeripherals(withIdentifiers: [connectedPeripheral!.identifier])
           if retrievedPeripherals.count > 0 {
               print("HERE IT IS A")
                retrievedPeripherals[0].writeValue(data, for: writeCharacteristic!, type: writeType)
           }
        }
    }
    
//    /// Send an array of bytes to the device
//    func sendBytesToDevice(_ bytes: [UInt8]) {
//        guard isReady else { return }
//
//        let data = Data(bytes: UnsafePointer<UInt8>(bytes), count: bytes.count)
//        connectedPeripheral!.writeValue(data, for: writeCharacteristic!, type: writeType)
//    }
    
    // MARK: CBCentralManagerDelegate functions
    public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        
        for p in self.peripherals {
           if p.identifier == peripheral.identifier {
               return
           }
       }
        
        if let name = peripheral.name {
            if (name.starts(with: "Wellnest")) {
                self.peripherals.append(peripheral)
                let p = WellnestPeripheral()
                p.identifier = peripheral.identifier
                p.name = peripheral.name
                delegate.serialDidDiscoverPeripheral(p, RSSI: RSSI)
            }
        }
        
        // just send it to the delegate
        
    }
    
    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        // set some stuff right
        peripheral.delegate = self
        pendingPeripheral = nil
        let p = WellnestPeripheral()
        p.identifier = peripheral.identifier
        p.name = peripheral.name
        connectedPeripheral = p
        
        // send it to the delegate
        delegate.serialDidConnect(connectedPeripheral!)
        
        // Okay, the peripheral is connected but we're not ready yet!
        // First get the 0xFFE0 service
        // Then get the 0xFFE1 characteristic of this service
        // Subscribe to it & create a weak reference to it (for writing later on),
        // and find out the writeType by looking at characteristic.properties.
        // Only then we're ready for communication
//        peripheral.discoverServices([serviceUUID])
        peripheral.discoverServices(nil)
    }
    
    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        let p = WellnestPeripheral()
        p.identifier = peripheral.identifier
        p.name = peripheral.name
        peripheralDisconnected(p, error: error as NSError?)
        
    }
    
    private func peripheralDisconnected(_ peripheral: WellnestPeripheral?, error: NSError?) {
        connectedPeripheral = nil
        pendingPeripheral = nil
        
        self.commandQueue = []
        self.response = "";
        
        
        // send it to the delegate
        delegate.serialDidDisconnect(peripheral, error: error as NSError?)
    }
    
    public func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        pendingPeripheral = nil
        connectedPeripheral = nil
        autoconnectingPeripheral = nil
        print("Failed to conect");
        centralManager.cancelPeripheralConnection(peripheral)
        
        // just send it to the delegate
        delegate.serialDidFailToConnect(peripheral, error: error as NSError?)
    }
    
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        
        // note that "didDisconnectPeripheral" won't be called if BLE is turned off while connected
        connectedPeripheral = nil
        pendingPeripheral = nil
        
        
        switch central.state {
        case .poweredOff:
            print("Bluetooth Power OFF")
            // TODO: BLE is off
//            UIAlertUtil.alertWith(title: "Alert", message: "Please turn on your Bluetooth to connect the ECG Device.", OkTitle: "Open Settings", cancelTitle: "Cancel", viewController: BluetoothSerial.viewController) { (index) in
//                if index == 1 {
//                    BluetoothSerial.shared.OpenSettingForBluetooth()
//                } else {
//                }
//            }
            let err = NSError(domain: "TurnedOff", code: 404, userInfo: nil)
            peripheralDisconnected(WellnestPeripheral(), error: err)
            break
            
        case .poweredOn:
            print("Bluetooth Power ON")
            if let p = self.autoconnectingPeripheral{
                self.centralManager.connect(p, options: nil)
            }
            break
            
        default:
            print("Bluetooth Default Call")
            break
        }

//        // send it to the delegate
//        delegate?.serialDidChangeState()
    }
    
    
    // MARK: CBPeripheralDelegate functions
    
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        let p = WellnestPeripheral()
        p.identifier = peripheral.identifier
        p.name = peripheral.name
        
        // discover the 0xFFE1 characteristic for all services (though there should only be one)
//        delegate.serialDidDiscoverPeripheral(p, RSSI: nil)
        for service in peripheral.services! {
//            peripheral.discoverCharacteristics([characteristicUUID], for: service)
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }
    
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        // check whether the characteristic we're looking for (0xFFE1) is present - just to be sure
        for characteristic in service.characteristics! {
            if characteristic.properties == .write {
                // keep a reference to this characteristic so we can write to it
                writeCharacteristic = characteristic
                
                // find out writeType
                writeType = characteristic.properties.contains(.write) ? .withResponse : .withoutResponse
                
                // notify the delegate we're ready for communication
                delegate.serialIsReady()
            }
            
            if characteristic.properties.rawValue & 0x12 > 0 {
                // subscribe to this value (so we'll get notified when there is serial data for us..)
                peripheral.setNotifyValue(true, for: characteristic)
            }
        }
    }
    
    func recordingComplete() {
        if commandQueue.count > 0 && (commandQueue[0].contains("GETSTR") || commandQueue[0].contains("GETDAT")) {
            //Remove the command from the queue
            print("REMOVED COMMAND FROM QUEUE")
            commandQueue.remove(at: 0)
            print("Command queue after Completion :- \(commandQueue)")
            return;
        }
    }
    
    func autoconnect() {
        print("Start AutoConnecting");
        if let peripheralJSON = UserDefaults.standard.object(forKey: "peripheral") as? String {
            do {
                if let p = try JSONDecoder().decode(WellnestPeripheral?.self, from: peripheralJSON.data(using: .utf8)!){
                    let retrievedPeripherals  =  centralManager.retrievePeripherals(withIdentifiers: [p.identifier])
                    if retrievedPeripherals.count > 0 {
                        self.autoconnectingPeripheral = retrievedPeripherals[0]
                        print("Found autoconnecting peripheral");
                        centralManager.connect(retrievedPeripherals[0], options: nil)
                    }
                }
                
            } catch {}
        }
    }
    
    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        // notify the delegate in different ways
        let data = characteristic.value
        guard data != nil else { return }
        if commandQueue.count > 0 && (commandQueue[0].contains("GETSTR") || commandQueue[0].contains("GETDAT")) {
            self.delegate.serialDidReceiveData(data!)
            return;
        }
        
        var str = String(decoding: data!, as: UTF8.self)
        
        // Remove the command from the queue if its response is received completely
        if str.contains("\r\n") {
            
            // Remove the CR LF
            str = str.replacingOccurrences(of: "\r\n", with: "")
            
            //Append the remaining string to the response
            self.response.append(str)
            
            if commandQueue.count > 0 {
                //Remove the command from the queue
                commandQueue.remove(at: 0)
            }
            
            print(self.response)
            
            //Send the string response to delegate
            self.delegate.serialDidReceiveString(self.response)
            
            //Clear out the response for new command
            self.response = ""
        } else {
            self.response.append(str)
        }

        
    }
    
    public func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
        delegate.serialDidReadRSSI(RSSI)
    }
    
    func OpenSettingForBluetooth() {
        
        guard let settingsUrl = URL(string: UIApplication.openSettingsURLString) else {
          return
        }
        if UIApplication.shared.canOpenURL(settingsUrl)  {
            UIApplication.shared.open(settingsUrl, options: [:], completionHandler: nil)
        }
    }
    // Helper function inserted by Swift 4.2 migrator.
    fileprivate func convertToUIApplicationOpenExternalURLOptionsKeyDictionary(_ input: [String: Any]) -> [UIApplication.OpenExternalURLOptionsKey: Any] {
        return Dictionary(uniqueKeysWithValues: input.map { key, value in (UIApplication.OpenExternalURLOptionsKey(rawValue: key), value)})
    }
}


