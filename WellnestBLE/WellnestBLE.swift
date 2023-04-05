//
//  CommunicationModule.swift
//  Wellnest Module
//
//  Created by Mayank Verma on 27/12/19.
//  Copyright © 2019 Royale Cheese. All rights reserved.
//

import UIKit
import CoreBluetooth

/**
    The configuration to be set for uploading the token and getting the key for the ecg device.
*/
open class Configuration {    
    public static var ApiUrl: String?
    public static var ApiKey: String?
    public static var ApiPassword: String?
}

public protocol StatusDelegate {
    func didGetBatteryStatus(batteryLevel: Int8, chargingLevel: Int8)
    func didGetElectrodeStatus(electrodeStatus: Array<UInt8>)
}
public protocol FirmwareStatusDelegate {
    func didGetFirmwareVersion(versionNo: String)
}
public protocol RecordingDelegate {
    /**
     Calls when ECG Recording is complete and will return the Recording taken from the Wellnest device.
     -Returns: Parsed data of Recording in Array of Array of Double.
     ##Important Notes##
    Parsed Array will be in a format of
            - Array 1       ->          L1
            - Array 2       ->          L2
            - Array 3       ->          L3
            - Array 4       ->          aVR
            - Array 5       ->          aVL
            - Array 6       ->          aVF
            - Array 7       ->          V1
            - Array 8       ->          V2
            - Array 9       ->          V3
            - Array 10     ->          V4
            - Array 11     ->          V5
            - Array 12     ->          V6
     Where These labels display particular Leads.
     */
    func recordingCompleted(rawData: Data, parsedData: [[Double]])
    
    /**
     Calls when there is a intruption in recording.
     */
    func recordingDisrupted()
    
    func getLiveRecording(rawData: [[Double]])
}

public protocol PeripheralDelegate {
    func didDiscoverPeripherals(peripherals : [WellnestPeripheral])
    func authentication(peripheral : WellnestPeripheral?, error: String?)
    func didDisconnect(peripheral : WellnestPeripheral?, error: NSError?)
}

public protocol CommunicationProtocol {
    /**
    It start searching and displays a list of discovered devices, from which have to be selected to connect.
    */
    func startScan()
    
    /**
    It connects the previously connected device which is stored in `UserDefaults`. When connected call the .
    -Note: Will not be able to connect the device if Application is installed for the first time or Device gets disconnected while terminating the application.
    */
    func connect(peripheral: WellnestPeripheral)
    func startRecording()
    func getBatteryStatus()
    func getElectrodeStatus()
    func autoconnect()
    func upgradeDevice(wifiSSID:String, wifiPassword: String)
    func checkFirwareVersion()
    func isConnected() -> Bool
    
    func stopRecording(wantData: Bool)
    /**
     Get all callbacks related to connection or discovery of ECG Device
     */
    var peripheralDelegate: PeripheralDelegate? { get set };
    
    /**
    Get all callbacks related to recording of ecg via the ECG Device
    */
    var recordingDelegate: RecordingDelegate? { get set }
    
    /**
    Get all callbacks related to status of battery or electrode of the ECG Device
    */
    var statusDelegate: StatusDelegate? { get set }
    
    var firmwareStatusDelegate: FirmwareStatusDelegate? { get set }
}

open class CommunicationFactory: NSObject {
    public static func getCommunicationHandler() -> CommunicationProtocol {
        return CommunicationHandler.sharedInstance
    }
    
    public static func getMockCommunicationHandler() -> CommunicationProtocol {
        return CommunicationHandler.sharedMockInstance
    }
}
