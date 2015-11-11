//
//  LECoreBluetooth.swift
//  LEBluetooth
//
//  Created by Leo_hsu on 2015/11/11.
//  Copyright © 2015年 Leo_hsu. All rights reserved.
//

import UIKit
import CoreBluetooth

@objc protocol LECoreBluetoothProtocol {
    func didDiscoverPeripheral(foundPeripherals: [CBPeripheral]?);
    func didConnected(peripheral: CBPeripheral, error: NSError?);
    func didDisconnected(peripheral: CBPeripheral, error: NSError?);
    func didFailToConnect(peripheral: CBPeripheral, error: NSError?);
    func peripheral(peripheral: CBPeripheral, didDiscoverCharacteristicsForService service: CBService, error: NSError?);
    
    optional func didUpdateState(isAvailable: Bool, message msg: String, status: CBCentralManagerState);
    optional func didDiscoverPeripheralNow(foundPeripheral: CBPeripheral, advertisementData foundAdvertisementData: [NSObject : AnyObject]);
    optional func didRetrievePeripheral(peripheral: CBPeripheral);
    optional func didRetrieveConnected(peripheral: CBPeripheral);
    optional func didUpdateRSSI(RSSI: Int, peripheral: CBPeripheral, error: NSError?);
    optional func peripheralDidUpdateName(peripheral: CBPeripheral);
    optional func peripheralDidInvalidateServices(peripheral: CBPeripheral);
    optional func didUpdateValue(cbUUID: CBUUID, stringData: String, binaryData: NSData, error: NSError?);
    optional func didUpdateValueWithPeripheral(peripheral: CBPeripheral, Characteristics cbUUID: CBUUID, stringData: String, binaryData: NSData, error: NSError?);
    optional func peripheral(peripheral: CBPeripheral, didWriteValueForCharacteristic characteristic: CBCharacteristic, error: NSError?);
    optional func peripheral(peripheral: CBPeripheral, didUpdateNotificationStateForCharacteristic characteristic: CBCharacteristic, error: NSError?);
}

let SCAN_TIMEOUT: Double = 3

class LECoreBluetooth: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {

    class var sharedInstance: LECoreBluetooth {
        struct Static {
            static var onceToken: dispatch_once_t = 0
            static var instance: LECoreBluetooth? = nil
        }
        dispatch_once(&Static.onceToken) {
            Static.instance = LECoreBluetooth()
        }
        return Static.instance!
    }
    
    private var centralManager: CBCentralManager?
    private var discoveredPeripheral: CBPeripheral?
    var LEDelegate: LECoreBluetoothProtocol?
    var foundPeripherals: [CBPeripheral]?
    private var scanTimer: NSTimer?
    
    
    private override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }
    
    deinit {
        DLog("Stopping scan")
        centralManager?.stopScan()
    }
    
    func scan() {
        self.scanWithUUIDStrings(nil)
    }
    
    func scanWithUUIDString(uuid: String?) {
        if let _uuid = uuid {
            self.scanWithUUIDStrings([_uuid])
        } else {
            self.scanWithUUIDStrings(nil)
        }
    }
    
    func scanWithUUIDStrings(uuids: [String]?) {
        var cbUUIDs: [CBUUID]?
        if let _uuids = uuids {
            cbUUIDs = [CBUUID]()
            for uuid in _uuids {
                cbUUIDs?.append(CBUUID(string: uuid))
            }
        }
        centralManager?.scanForPeripheralsWithServices(
            cbUUIDs, options: [CBCentralManagerScanOptionAllowDuplicatesKey : NSNumber(bool: true)]
        )
        DLog("Scanning started")
        
        scanTimer = NSTimer.scheduledTimerWithTimeInterval(SCAN_TIMEOUT, target: self, selector: "scanTimeout:", userInfo: nil, repeats: false)
    }
    
    func stopScanning() {
        if let cm = centralManager {
            cm.stopScan()
            DLog("stopScanning")
        }
        scanTimer?.invalidate()
    }
    
    @objc private func scanTimeout(timer: NSTimer) {
        DLog("scanTimeout")
        scanTimer = timer
        self.stopScanning()
        LEDelegate?.didDiscoverPeripheral(foundPeripherals)
    }
    
    func connect(peripheral: CBPeripheral) {
        if peripheral.state == .Disconnected {
            centralManager?.connectPeripheral(peripheral, options: nil)
            discoveredPeripheral = peripheral
            DLog("connecting...")
        }
    }
    
    //MARK: - CBCentralManagerDelegate
    func centralManagerDidUpdateState(central: CBCentralManager) {
        var isAvailable: Bool = false
        var msg: String = "UpdateState:"
        switch central.state {
        case CBCentralManagerState.PoweredOn:
            msg += "Powered on"
            isAvailable = true
        case CBCentralManagerState.PoweredOff:
            msg += "Powered off"
        case CBCentralManagerState.Unsupported:
            msg += "Unsupported"
        case CBCentralManagerState.Unauthorized:
            msg += "Unauthorized"
        case CBCentralManagerState.Unknown:
            msg += "Unknown"
        default:
            break
        }
        LEDelegate?.didUpdateState?(isAvailable, message: msg, status: central.state)
    }
    
    /** This callback comes whenever a peripheral that is advertising the TRANSFER_SERVICE_UUID is discovered.
     *  We check the RSSI, to make sure it's close enough that we're interested in it, and if it is,
     *  we start the connection process
     */
    func centralManager(central: CBCentralManager, didDiscoverPeripheral peripheral: CBPeripheral, advertisementData: [String : AnyObject], RSSI: NSNumber) {
        
        // Reject any where the value is above reasonable range
        // Reject if the signal strength is too low to be close enough (Close is around -22dB)
        
//        if  RSSI.integerValue < -15 && RSSI.integerValue > -35 {
//            println("Device not at correct range")
//            return
//        }
        
        DLog("Discovered \(peripheral.name) at \(RSSI) and infomations \(advertisementData)")
        
        // Init CBPeripheral array.
        if ((foundPeripherals == nil)) {
            foundPeripherals = [CBPeripheral]()
        }
        
        // Add peripheral and replace duplicate
        for index in 0..<foundPeripherals!.count {
            let p: CBPeripheral = foundPeripherals![index]
            if (p.identifier == peripheral.identifier) {
                foundPeripherals![index] = peripheral
                return
            }
        }
        
        foundPeripherals?.append(peripheral)
        
        LEDelegate?.didDiscoverPeripheralNow?(peripheral, advertisementData: advertisementData)
    }
    
    /** If the connection fails for whatever reason, we need to deal with it.
     */
    func centralManager(central: CBCentralManager, didFailToConnectPeripheral peripheral: CBPeripheral, error: NSError?) {
        DLog("Failed to connect to \(peripheral). (\(error!.localizedDescription))")
        LEDelegate?.didFailToConnect(peripheral, error: error)
        cleanup()
    }
    
    /** We've connected to the peripheral, now we need to discover the services and characteristics to find the 'transfer' characteristic.
     */
    func centralManager(central: CBCentralManager, didConnectPeripheral peripheral: CBPeripheral) {
        DLog("Peripheral Connected")
        
        self.stopScanning()
        
        // Make sure we get the discovery callbacks
        peripheral.delegate = self
        
        // Search only for services that match our UUID
//        peripheral.discoverServices([transferServiceUUID])
        peripheral.discoverServices(nil)
    }
    
    /** Once the disconnection happens, we need to clean up our local copy of the peripheral
     */
    func centralManager(central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: NSError?) {
        DLog("Peripheral Disconnected")
        discoveredPeripheral = nil
        LEDelegate?.didDisconnected(peripheral, error: error)
    }
    
    /** The Transfer Service was discovered
     */
    func peripheral(peripheral: CBPeripheral, didDiscoverServices error: NSError?) {
        if let error = error {
            DLog("Error discovering services: \(error.localizedDescription)")
            cleanup()
            return
        }
        
        // Discover the characteristic we want...
        DLog("====\(peripheral.name) have \(peripheral.services?.count) of service")
        
        // Loop through the newly filled peripheral.services array, just in case there's more than one.
        for service in peripheral.services! as [CBService] {
            peripheral.discoverCharacteristics(nil, forService: service)
            DLog("Service found with UUID:\(service.UUID)")
        }
    }
    
    /** The Transfer characteristic was discovered.
     *  Once this has been found, we want to subscribe to it, which lets the peripheral know we want the data it contains
     */
    func peripheral(peripheral: CBPeripheral, didDiscoverCharacteristicsForService service: CBService, error: NSError?) {
        // Deal with errors (if any)
        if let error = error {
            DLog("Error discovering services: \(error.localizedDescription)")
            cleanup()
            return
        }
        
        DLog("=========== Service UUID  \(service.UUID)===========")
        
        // Again, we loop through the array, just in case.
        for characteristic in service.characteristics! as [CBCharacteristic] {
            DLog("=========== Service characteristics UUID \(characteristic.UUID) and UUIDString \(characteristic.UUID.UUIDString)===========")
        }
        // Once this is complete, we just need to wait for the data to come in.
        
        LEDelegate?.peripheral(peripheral, didDiscoverCharacteristicsForService: service, error: error)
    }
    
    /** This callback lets us know more data has arrived via notification on the characteristic
     */
    func peripheral(peripheral: CBPeripheral, didUpdateValueForCharacteristic characteristic: CBCharacteristic, error: NSError?) {
        if let error = error {
            DLog("Error discovering services: \(error.localizedDescription)")
            return
        }
        let stringFromData: String = NSString(data: characteristic.value!, encoding: NSUTF8StringEncoding) as! String
        
        LEDelegate?.didUpdateValue?(characteristic.UUID, stringData: stringFromData, binaryData: characteristic.value!, error: error)
        LEDelegate?.didUpdateValueWithPeripheral?(peripheral, Characteristics: characteristic.UUID, stringData: stringFromData, binaryData: characteristic.value!, error: error)
    }
    
    func peripheral(peripheral: CBPeripheral, didWriteValueForCharacteristic characteristic: CBCharacteristic, error: NSError?) {
        LEDelegate?.peripheral?(peripheral, didWriteValueForCharacteristic: characteristic, error: error)
    }
    
    /** The peripheral letting us know whether our subscribe/unsubscribe happened or not
     */
    func peripheral(peripheral: CBPeripheral, didUpdateNotificationStateForCharacteristic characteristic: CBCharacteristic, error: NSError?) {
        if let error = error {
            DLog("Error changing notification state: \(error.localizedDescription)")
        }
        
       LEDelegate?.peripheral?(peripheral, didUpdateNotificationStateForCharacteristic: characteristic, error: error)
    }
    
    /** Call this when things either go wrong, or you're done with the connection.
     *  This cancels any subscriptions if there are any, or straight disconnects if not.
     *  (didUpdateNotificationStateForCharacteristic will cancel the connection if a subscription is involved)
     */
    private func cleanup() {
        // Don't do anything if we're not connected
        // self.discoveredPeripheral.isConnected is deprecated
        if discoveredPeripheral?.state != CBPeripheralState.Connected { // explicit enum required to compile here?
            return
        }
        
        // See if we are subscribed to a characteristic on the peripheral
        if let services = discoveredPeripheral?.services as [CBService]? {
            for service in services {
                if let characteristics = service.characteristics as [CBCharacteristic]? {
                    for characteristic in characteristics {
                        if characteristic.isNotifying {
                            discoveredPeripheral?.setNotifyValue(false, forCharacteristic: characteristic)
                            // And we're done.
                            return
                        }
                    }
                }
            }
        }
        
        // If we've got this far, we're connected, but we're not subscribed, so we just disconnect
        centralManager?.cancelPeripheralConnection(discoveredPeripheral!)
        DLog("clean up")
    }
    
    func DLog(logMessage: String, filePath: String = __FILE__, functionName: String = __FUNCTION__, line: Int = __LINE__) {
        NSLog("[%@ %d %@]: %@",(filePath as NSString).lastPathComponent,line,functionName,logMessage)
    }
}
