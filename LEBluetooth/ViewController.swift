//
//  ViewController.swift
//  LEBluetooth
//
//  Created by Leo_hsu on 2015/11/11.
//  Copyright © 2015年 Leo_hsu. All rights reserved.
//

import UIKit
import CoreBluetooth

class ViewController: UITableViewController, LECoreBluetoothProtocol {

    var foundPeripherals: [CBPeripheral]?
    var leBLE: LECoreBluetooth = LECoreBluetooth.sharedInstance
    
    override func viewDidLoad() {
        super.viewDidLoad()
        leBLE.LEDelegate = self
    }

    // MARK: - Table view data source
    override func numberOfSectionsInTableView(tableView: UITableView) -> Int {
        return 1
    }
    
    override func tableView(tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return (foundPeripherals == nil) ? 0 : foundPeripherals!.count
    }
    
    override func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCellWithIdentifier("Cell", forIndexPath: indexPath)
        if let p = foundPeripherals?[indexPath.row] {
            cell.textLabel?.text = p.name
        }
        return cell
    }
    
    // MARK: - TableViewDelegate
    override func tableView(tableView: UITableView, didSelectRowAtIndexPath indexPath: NSIndexPath) {
        if let foundPeripherals = foundPeripherals {
            let p: CBPeripheral = foundPeripherals[indexPath.row]
            leBLE.connect(p)
        }
    }
    
    // MARK: - LECoreBluetoothProtocol
    func didUpdateState(isAvailable: Bool, message msg: String, status: CBCentralManagerState) {
        if isAvailable {
            leBLE.scan()
        }
    }
    
    func peripheral(peripheral: CBPeripheral, didDiscoverCharacteristicsForService service: CBService, error: NSError?) {
        for characteristic in service.characteristics! as [CBCharacteristic] {
            let uuidStr = characteristic.UUID.UUIDString
            switch uuidStr {
//                case "yourCase":
                    // If characteristic can notify, subscribe to it
//                    peripheral.setNotifyValue(true, forCharacteristic: characteristic)
                case "2A29":
                    // Read value form characteristic
                    peripheral.readValueForCharacteristic(characteristic)
                case "2A24":
                    // Read value form characteristic
                    peripheral.readValueForCharacteristic(characteristic)
                case "2F0A0002-69AA-F316-3E78-4194989A6C1A":
                    // Write value to characteristic
                    var random = NSInteger(arc4random_uniform(99) + 1) //(1-100)
                    let data = NSData(bytes: &random, length: 3)
                    var out: NSInteger = 0
                    data.getBytes(&out, length: sizeof(NSInteger))
                    print("number is \(out)")
                    peripheral.writeValue(data, forCharacteristic: characteristic, type: CBCharacteristicWriteType.WithResponse)
            default:
                break
            }

        }
    }
    
    func didUpdateValueWithPeripheral(peripheral: CBPeripheral, Characteristics cbUUID: CBUUID, stringData: String, binaryData: NSData, error: NSError?) {
        
    }
    
    func didDiscoverPeripheral(foundPeripherals: [CBPeripheral]?) {
        self.foundPeripherals = foundPeripherals
        self.tableView.reloadData()
    }
    
    func didUpdateValue(cbUUID: CBUUID, stringData: String, binaryData: NSData, error: NSError?) {
        if let stringFromData = NSString(data: binaryData, encoding: NSUTF8StringEncoding) {
            print("Received: \(stringFromData)")
        } else {
            print("Invalid data")
        }
    }
    
    func peripheral(peripheral: CBPeripheral, didWriteValueForCharacteristic characteristic: CBCharacteristic, error: NSError?) {
        if let error = error {
            print("Error write to characteristic: \(error.localizedDescription)")
            return
        }
        print("write to \(characteristic.UUID) done.")
    }
    
    func didConnected(peripheral: CBPeripheral, error: NSError?) {
        
    }
    
    func didDisconnected(peripheral: CBPeripheral, error: NSError?) {
        
    }
    
    func didFailToConnect(peripheral: CBPeripheral, error: NSError?) {
        
    }
}

