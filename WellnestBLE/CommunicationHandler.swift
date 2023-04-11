//
//  BluetoothDeviceUtil.swift
//  wellnest-ios
//
//  Created by Mayank Verma on 26/12/18.
//  Copyright © 2018 WellNest. All rights reserved.
//

import Foundation
import UIKit
import CoreBluetooth
import CryptoSwift
import Combine


internal class CommunicationHandler : BluetoothSerialDelegate, CommunicationProtocol {
    
    private var leadRawDataDouble = [[Double]]()
    private var dataECG = Data(capacity: 80000)
    private var bytesList = [[Double]]()
    private var isRecordingCompleted = false
    private var chartsData = [[Double]]()
    private var _lastTimestamp: Date = Date.init(timeIntervalSinceNow: 0)
    
    static let sharedInstance = CommunicationHandler(isMock: false)
    static let sharedMockInstance = CommunicationHandler(isMock: true)
    var bluetoothSerial = BluetoothSerial.init()
    var connectedPeripheral : WellnestPeripheral?
    var isBluetoothTurnedON = Bool()
    var responseCollected = false
    var isComingFromPreviousDevice = false
    var foundPeripheralList = [WellnestPeripheral]()
    var isSearchingDevice = Bool()
    public var udidSaved = ""
    var uuid: String?
    open var peripheralDelegate: PeripheralDelegate?;
    open var recordingDelegate: RecordingDelegate?
    open var statusDelegate: StatusDelegate?
    open var firmwareStatusDelegate: FirmwareStatusDelegate?
    private var previousCount: Int = 0
    private var dataTimer: Timer?
    private var count = 0;
    private var dataPublisher = PassthroughSubject<Data, Never>()
    var subscriptions: [AnyCancellable] = []
    var tempECGCount = Data(capacity: 80000)
    var isProcessing = false
    
    private init(isMock: Bool) {
        if isMock {
            print("INITIATED AS MOCK")
            self.bluetoothSerial = MockBluetoothSerial.init()
        } else {
            print("INITIATED AS BLUETOOTH")
            self.bluetoothSerial = BluetoothSerial.init()
        }
        self.bluetoothSerial.delegate = self
        dataPublisher
            .sink(receiveCompletion: { completion in
                switch completion {
                case .finished :
                    print("DATA PARSED")
                case .failure(let error):
                    print("Error \(error.localizedDescription)")
                }
                
            }, receiveValue: { data in
                self.tempECGCount.append(data)
                guard !self.isProcessing else {return}
                while (self.tempECGCount.count >= 16) {
                    self.isProcessing = true
                    let subData = self.tempECGCount.subdata(in: 0..<16)
                    if subData.toHexString().starts(with: "ba") {
                        var arr2 = Array<Double>(repeating: 0, count: 16)
                        _ = arr2.withUnsafeMutableBytes { subData.copyBytes(to: $0) }
                        self.dataECG.append(subData)
                        if self.connectedPeripheral!.name!.contains("Wellnest ECG V3_1") {
                            self.bytesList.append(arr2)
                        } else {
                           
                            self.recordingDelegate?.getLiveRecording(rawData: self.parseRecording(dataECG: subData))
                            
                        }
                        self.tempECGCount.removeSubrange(0..<16)
                    } else {
                        self.tempECGCount.removeSubrange(0..<1)
                        
                        
                    }
                    
                    
                }
                self.isProcessing = false
                
                guard self.connectedPeripheral!.name!.contains("Wellnest ECG V3_1") else {return}
                
                let timeInterval: TimeInterval = fabs(self._lastTimestamp.timeIntervalSinceNow);
                if (timeInterval >= 5.0) {
                    print(self.dataECG.count)
                    self._lastTimestamp = Date.init(timeIntervalSinceNow: 0)
                }
                
                if (self.dataTimer == nil || self.dataTimer!.isValid == false){
                    print("Scheduling timer")
                    // If even after 3 seconds the dataECG count doesn't change
                    self.dataTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { (timer) in
                        if self.dataECG.count == self.previousCount {
                            timer.invalidate()
                            
                            // If new data is not received and we have 7 seconds of data use that
                            // else send a recording disrupted error
                            if (self.dataECG.count > 60000) {
                                self.processReccording()
                            } else {
                                print("Recording Disrupted (Lib)")
                                self.dataECG = Data(capacity: 80000)
                                self.previousCount = 0
                                self.recordingDelegate?.recordingDisrupted()
                            }
                        } else {
                           self.previousCount = self.dataECG.count
                       }
                        print("All Good")
                    }
                }

                
                // Check if we have all 10 seconds of data.
                if self.dataECG.count >= 80000 && self.isRecordingCompleted == false {
                    self.processReccording()
                }
            }).store(in: &subscriptions)
    }
    
    func serialDidReceiveString(_ message: String) {
        print("BLUETOOTH RECIEVES STRING = \(message)")
        if (message.starts(with:"+MOCKGETAUT")) {
            self.peripheralDelegate?.authentication(peripheral: self.connectedPeripheral, error: nil)
        }
        else if (message.starts(with:"+GETDID")) {
            let deviceId : String = String(message.split(separator: "=")[1])
            self.bluetoothSerial.stopScan()
            
            let encoder: JSONEncoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let jsonData = try? encoder.encode(self.connectedPeripheral)
            let jsonString = String(decoding: jsonData!, as: UTF8.self)
            UserDefaults.standard.set(jsonString, forKey: "peripheral")
            UserDefaults.standard.set(deviceId, forKey: "ECGDeviceId")
            
            self.uuid = UUID().uuidString.replacingOccurrences(of: "-", with: "")
            self.bluetoothSerial.sendMessageToDevice("+GETAUT=\(uuid!)", true)
        } else if (message.starts(with:"+GETAUT")) {
            let response : String = String(message.split(separator: "=")[1])
            let encryptedString : String = String(response.split(separator: ":")[0])
            let stringToEncrypt : String = String(response.split(separator: ":")[1])
            
            
            let ECGDeviceId = UserDefaults.standard.value(forKey: "ECGDeviceId")!
            
            if let privateKey = UserDefaults.standard.value(forKey: "\(ECGDeviceId)-PrivateKey"), let deviceId = UserDefaults.standard.value(forKey: "\(ECGDeviceId)-ServerDeviceId") {
                let pk = privateKey as! String
                let dId = deviceId as! Int
                let bytes = Array<UInt8>(hex: encryptedString)
                let decrypted: Array<UInt8> = try! AES(key: Array(pk.utf8), blockMode: ECB(), padding: .noPadding).decrypt(bytes)
                let decryptedHexString = decrypted.toHexString()

                
                if self.uuid!.caseInsensitiveCompare(decryptedHexString) == .orderedSame {
                    let bytesToEncrypt = Array<UInt8>(hex: stringToEncrypt)  // [1,2,3]
                    let encrypted: Array<UInt8> = try! AES(key: Array(pk.utf8), blockMode: ECB(), padding: .noPadding).encrypt(bytesToEncrypt)
                    self.bluetoothSerial.sendMessageToDevice("+AUTHOR=\(encrypted.toHexString())", true)
                    self.connectedPeripheral?.id = dId
                    self.peripheralDelegate?.authentication(peripheral: self.connectedPeripheral, error: nil)
                    // The device is now connected
                } else {
                    self.peripheralDelegate?.authentication(peripheral: nil, error: "There was an error authenticating the device. Code (401)")
                }
            } else {
                let semaphore = DispatchSemaphore (value: 0)

                var request = URLRequest(url: URL(string: "\(Configuration.ApiUrl!)/api/Device/\(ECGDeviceId)")!,timeoutInterval: Double.infinity)

                request.httpMethod = "GET"
                request.setValue(Configuration.ApiKey, forHTTPHeaderField: "apiKey")
                request.setValue(Configuration.ApiPassword, forHTTPHeaderField: "apiPassword")

                let task = URLSession.shared.dataTask(with: request) { data, response, error in
                  guard let data = data else {
                    print(String(describing: error))
                    self.peripheralDelegate?.authentication(peripheral: nil, error: "There was an error authenticating the device. Code (404)")
                    return
                  }
                    do {
                        if let privateKeyDictionary = try JSONSerialization.jsonObject(with: data, options : .allowFragments) as? Dictionary<String,Any>
                        {
                            let privateKey: String = privateKeyDictionary["privateKey"] as! String
                            UserDefaults.standard.set(privateKey, forKey: "\(ECGDeviceId)-PrivateKey")
                            
                            let deviceId: Int = privateKeyDictionary["id"] as! Int
                            UserDefaults.standard.set(deviceId, forKey: "\(ECGDeviceId)-ServerDeviceId")
                            
                            let bytes = Array<UInt8>(hex: encryptedString)
                            let decrypted: Array<UInt8> = try! AES(key: Array(privateKey.utf8), blockMode: ECB(), padding: .noPadding).decrypt(bytes)
                            let decryptedHexString = decrypted.toHexString()

                            
                            if self.uuid!.caseInsensitiveCompare(decryptedHexString) == .orderedSame {
                                let bytesToEncrypt = Array<UInt8>(hex: stringToEncrypt)  // [1,2,3]
                                let encrypted: Array<UInt8> = try! AES(key: Array(privateKey.utf8), blockMode: ECB(), padding: .noPadding).encrypt(bytesToEncrypt)
                                self.bluetoothSerial.sendMessageToDevice("+AUTHOR=\(encrypted.toHexString())", true)
                                self.connectedPeripheral?.id = deviceId
                                self.peripheralDelegate?.authentication(peripheral: self.connectedPeripheral, error: nil)
                                // The device is now connected
                            } else {
                                self.peripheralDelegate?.authentication(peripheral: nil, error: "There was an error authenticating the device. Code (401)")
                            }
                        } else {
                            print("bad json")
                            self.peripheralDelegate?.authentication(peripheral: nil, error: "There was an error authenticating the device. Code (400)")
                        }
                    } catch let error as NSError {
                        print("HELLO")
                        print(error.localizedDescription)
                        self.peripheralDelegate?.authentication(peripheral: nil, error: "There was an error authenticating the device. Code (400)")
                    }
                  
                  semaphore.signal()
                }

                task.resume()
                semaphore.wait()
            }
        } else if(message.starts(with:"+RECEND")) {
            self.isRecordingCompleted = false
            self.dataTimer = nil
            print("SETUP FOR V3")
            self.bluetoothSerial.sendMessageToDevice("+GETDAT=0,5000,3", true)
        } else if(message.contains("+GETSTA")) {
            let newMessage = message[message.range(of: "+GETSTA")!.lowerBound...]
            let statuses : String = String(newMessage.split(separator: "=")[1])
            print(statuses)
            let batteryLevel : Int8 = Int8(String(statuses.split(separator: ",")[0])) ?? 0
            let chargingLevel : Int8 = Int8(String(statuses.split(separator: ",")[1])) ?? 0
            self.statusDelegate?.didGetBatteryStatus(batteryLevel: batteryLevel, chargingLevel: chargingLevel)
        } else if(message.starts(with:"+ELESTA")) {
            let statuses : String = String(message.split(separator: "=")[1])
            print(statuses)
            let bytes = Array<UInt8>(hex: statuses)
            self.statusDelegate?.didGetElectrodeStatus(electrodeStatus: bytes)
        } else if(message.starts(with: "Firmware Version")) {
            let versionNo = String(message.split(separator: "_")[1])
            self.firmwareStatusDelegate?.didGetFirmwareVersion(versionNo: versionNo)
        }
    }
    
    
    
    func serialDidReadRSSI(_ rssi: NSNumber) {
        
    }
    
    
    func startScan() {
        self.foundPeripheralList = []
        self.bluetoothSerial.startScan()
    }
    
    func connect(peripheral: WellnestPeripheral) {
        self.bluetoothSerial.connectToPeripheral(peripheral)
    }
    
    func autoconnect() {
        self.bluetoothSerial.autoconnect()
    }
    func serialDidDiscoverPeripheral(_ peripheral: WellnestPeripheral, RSSI: NSNumber?) {
        if self.isComingFromPreviousDevice {
            checkUsefulDevice()
        }
        self.foundPeripheralList.append(peripheral)

        self.peripheralDelegate?.didDiscoverPeripherals(peripherals: self.foundPeripheralList)
    }
    
    func checkUsefulDevice()  {
        if self.bluetoothSerial.connectedPeripheral == nil {
            for periPheral in self.foundPeripheralList {
                self.responseCollected = false
                self.isSearchingDevice = true
                self.bluetoothSerial.connectToPeripheral(periPheral)
            }
        }
    }

    func serialDidConnect(_ peripheral: WellnestPeripheral) {
        self.connectedPeripheral = peripheral
//        self.delegateCommunication?.DeviceConnected(peripheral: peripheral)
    }

    func serialIsReady() {
        self.bluetoothSerial.sendMessageToDevice("+TSTEND\r\n", false)
        self.bluetoothSerial.sendMessageToDevice("+GETDID\r\n", true)
    }
    
    func startRecording() {
        self.bluetoothSerial.commandQueue = []
        self.isRecordingCompleted = false
        if let pheripheralName = self.connectedPeripheral?.name , pheripheralName.contains("V3") {
            self.bluetoothSerial.sendMessageToDevice("+RECORD\r\n", false)
        } else {
            self.bluetoothSerial.sendMessageToDevice("+GETSTR=1\r\n", true)
        }
    }
    func upgradeDevice(wifiSSID:String, wifiPassword: String) {
        self.bluetoothSerial.sendMessageToDevice("+WFSSID=\(wifiSSID)\r\n", true)
        self.bluetoothSerial.sendMessageToDevice("+WFPSWD=\(wifiPassword)\r\n", true)
        self.bluetoothSerial.sendMessageToDevice("+OTAUPG", true)
    }
    func checkFirwareVersion() {
        self.bluetoothSerial.sendMessageToDevice("+FWVERS=1", true)
    }
    func stopRecording(wantData: Bool) {
        self.dataTimer = nil
        self.bluetoothSerial.sendMessageToDevice("+GETSTR=0\r\n", false)
        self.bluetoothSerial.recordingComplete()
        self.isRecordingCompleted = true
        if wantData {
            self.recordingDelegate?.recordingCompleted(rawData: self.dataECG, parsedData: [[Double]]())
        }
        self.dataECG = Data(capacity: 80000)
    }
    
    func getBatteryStatus() {
        self.bluetoothSerial.sendMessageToDevice("+GETSTA\r\n", true)
    }
    
    func getElectrodeStatus() {
        self.bluetoothSerial.sendMessageToDevice("+ELESTA\r\n", true)
    }
    
    func serialDidReceiveData(_ data: Data) {
        self.dataPublisher.send(data)
    }
    
    
    private func processReccording() {
        self.dataTimer?.invalidate()
        self.isProcessing = false
        self.tempECGCount.removeAll()
        self.bluetoothSerial.recordingComplete()
        self.isRecordingCompleted = true
//        self.bluetoothSerial.disconnect()
        let chartsData = DataParser().setUpDataForRecording(bytesList);
        var sublist = [[Double]]()
        for j in 0..<12{
            sublist.append([Double]())
            for i in 0..<chartsData.count{
                sublist[j].append(chartsData[i][j])
            }
        }

        DispatchQueue.main.async {
            self.recordingDelegate?.recordingCompleted(rawData: self.dataECG, parsedData: sublist)
            self.dataECG = Data(capacity: 80000)
            self.previousCount = 0
            print("DATAECG AFTER COMPLETED :- \(self.dataECG.count)")
        }
    }
    
    func parseRecording(dataECG : Data) -> [[Double]] {
        let arr = [UInt8](dataECG)
        var finalArr = [[Double]]()
        var innerArr = [Double]()
        for a in arr {
            innerArr.append(Double(a))
            if(innerArr.count == 16) {
                finalArr.append(innerArr)
                innerArr = [Double]()
            }
        }
        let chartsData = DataParser().setUpDataForRecording(finalArr);
        var sublist = [[Double]]()
        for j in 0..<12{
            sublist.append([Double]())
            for i in 0..<chartsData.count{
                sublist[j].append(chartsData[i][j])
            }
        }
        return sublist;
    }

    func serialDidChangeState() {
        
    }
    
    func serialDidDisconnect(_ peripheral: WellnestPeripheral?, error: NSError?) {
        self.connectedPeripheral = nil
        self.recordingDelegate?.recordingDisrupted()
        self.peripheralDelegate?.didDisconnect(peripheral: peripheral, error: error)
    }
    func isConnected() -> Bool {
        return self.connectedPeripheral != nil
    }
    
    func disconnectDevice() {
        self.bluetoothSerial.disconnect()
        UserDefaults.standard.removeObject(forKey: "ECGDeviceId")
    }
    
    func serialDidFailToConnect(_ peripheral: CBPeripheral, error: NSError?) {
        print("Fail to Connect")
    }

    func updateTimer () {
        
    }
    
    func runTimer() {
        
    }
}

