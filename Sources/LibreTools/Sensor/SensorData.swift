//
//  SensorData
//  LibreMonitor
//
//  Created by Uwe Petersen on 26.07.16.
//  Copyright © 2016 Uwe Petersen. All rights reserved.
//

import Foundation

extension String {
    //https://stackoverflow.com/questions/39677330/how-does-string-substring-work-in-swift
    //usage
    //let s = "hello"
    //s[0..<3] // "hel"
    //s[3..<s.count] // "lo"
    subscript(_ range: CountableRange<Int>) -> String {
        let idx1 = index(startIndex, offsetBy: max(0, range.lowerBound))
        let idx2 = index(startIndex, offsetBy: min(self.count, range.upperBound))
        return String(self[idx1..<idx2])
    }
}

extension StringProtocol where Index == String.Index {
    ///can be used to split a string in array of strings, splitted by other string
    func indexes(of string: Self, options: String.CompareOptions = []) -> [Index] {
        var result: [Index] = []
        var start = startIndex
        while start < endIndex,
            let range = self[start..<endIndex].range(of: string, options: options) {
                result.append(range.lowerBound)
                start = range.lowerBound < range.upperBound ? range.upperBound :
                    index(range.lowerBound, offsetBy: 1, limitedBy: endIndex) ?? endIndex
        }
        return result
    }
}


/// Structure for data from Freestyle Libre sensor
/// To be initialized with the bytes as read via nfc. Provides all derived data.
public struct SensorData {
    
    /// Parameters for the temperature compensation algorithm
    //let temperatureAlgorithmParameterSet: TemperatureAlgorithmParameters?
    /// The uid of the sensor
    let uuid: Data
    /// The serial number of the sensor
    let serialNumber: String
    /// Number of bytes of sensor data to be used (read only), i.e. 344 bytes (24 for header, 296 for body and 24 for footer)
    private let numberOfBytes = 344 // Header and body and footer of Freestyle Libre data (i.e. 40 blocks of 8 bytes)
    /// Array of 344 bytes as read via nfc
    let bytes: [UInt8]
    /// Subarray of 24 header bytes
    let header: [UInt8]
    /// Subarray of 296 body bytes
    let body: [UInt8]
    /// Subarray of 24 footer bytes
    let footer: [UInt8]
    /// Date when data was read from sensor
    let date: Date
    /// Minutes (approx) since start of sensor
    let minutesSinceStart: Int
    /// Index on the next block of trend data that the sensor will measure and store
    let nextTrendBlock: Int
    /// Index on the next block of history data that the sensor will create from trend data and store
    let nextHistoryBlock: Int
    /// true if all crc's are valid
    var hasValidCRCs: Bool {
        return hasValidHeaderCRC && hasValidBodyCRC && hasValidFooterCRC
    }
    /// true if the header crc, stored in the first two header bytes, is equal to the calculated crc
    var hasValidHeaderCRC: Bool {
        return Crc.hasValidCrc16InFirstTwoBytes(header)
    }
    /// true if the body crc, stored in the first two body bytes, is equal to the calculated crc
    var hasValidBodyCRC: Bool {
        return Crc.hasValidCrc16InFirstTwoBytes(body)
    }
    /// true if the footer crc, stored in the first two footer bytes, is equal to the calculated crc
    var hasValidFooterCRC: Bool {
        return Crc.hasValidCrc16InFirstTwoBytes(footer)
    }
    /// Footer crc needed for checking integrity of SwiftLibreOOPWeb response
    var footerCrc: UInt16 {
        return  Crc.crc16(Array(footer.dropFirst(2)), seed: 0xffff)
    }
    
    /// Sensor state (ready, failure, starting etc.)
    var state: LibreSensorState {
        return LibreSensorState(stateByte: header[4])
    }
    
    var isLikelyLibre1 : Bool {
        if bytes.count > 23 {
            let subset = bytes[9...23]
            return !subset.contains(where: { $0 > 0})
        }
        return false
        
    }
    
    public var patchUid: String?
    var patchInfo: String? {
        didSet {
            if let patchInfo = patchInfo, patchInfo.count > 2 {
                let sub = patchInfo[0 ..< 2]
                switch sub {
                case "70":
                    sensorName = "Libre Pro/H"
                case "9D":
                    sensorName = "Libre 2"
                case "DF":
                    sensorName = "Libre 1"
                case "E5":
                    sensorName = "Libre US 14 Days"
                default:
                    sensorName = "Libre"
                }
            } else {
                sensorName = "Libre"
            }
        }
    }
    var sensorName = "Libre"
    
    var isSecondSensor: Bool {
        return sensorName == "Libre 2" || sensorName == "Libre US 14 Days"
    }
    
    var isFirstSensor: Bool {
        return sensorName == "Libre" || sensorName == "Libre 1" || sensorName == "Libre Pro/H"
    }
    
    var humanReadableSensorAge : String {
        
        
        let sensorStart = Calendar.current.date(byAdding: .minute, value: -self.minutesSinceStart, to: self.date)!
        
        return  sensorStart.timeIntervalSinceNow.stringDaysFromTimeInterval() +  " day(s)"
    }
    
    public init?(uuid: Data, bytes: [UInt8], date: Date = Date(), patchInfo: String?) {
        guard bytes.count == numberOfBytes else {
            return nil
        }
        self.bytes = bytes
        // we don't actually know when this reading was done, only that
        // it was produced within the last minute
        self.date = date.rounded(on: 1, .minute)
        
        let headerRange =   0..<24   //  24 bytes, i.e.  3 blocks a 8 bytes
        let bodyRange   =  24..<320  // 296 bytes, i.e. 37 blocks a 8 bytes
        let footerRange = 320..<344  //  24 bytes, i.e.  3 blocks a 8 bytes
        
        self.header = Array(bytes[headerRange])
        self.body   = Array(bytes[bodyRange])
        self.footer = Array(bytes[footerRange])
        
        self.nextTrendBlock = Int(body[2])
        self.nextHistoryBlock = Int(body[3])
        self.minutesSinceStart = Int(body[293]) << 8 + Int(body[292])

        self.uuid = uuid
        self.patchUid = uuid.hexEncodedString().uppercased()
        self.patchInfo = patchInfo
        self.serialNumber = SensorSerialNumber(withUID: uuid, patchInfo: patchInfo)?.serialNumber ?? "-"
    }
    
    /// Get date of most recent history value.
    /// History values are updated every 15 minutes. Their corresponding time from start of the sensor in minutes is 15, 30, 45, 60, ..., but the value is delivered three minutes later, i.e. at the minutes 18, 33, 48, 63, ... and so on. So for instance if the current time in minutes (since start of sensor) is 67, the most recent value is 7 minutes old. This can be calculated from the minutes since start. Unfortunately sometimes the history index is incremented earlier than the minutes counter and they are not in sync. This has to be corrected.
    ///
    /// - Returns: the date of the most recent history value and the corresponding minute counter
    func dateOfMostRecentHistoryValue() -> (date: Date, counter: Int) {
        // Calculate correct date for the most recent history value.
        //        date.addingTimeInterval( 60.0 * -Double( (minutesSinceStart - 3) % 15 + 3 ) )
        let nextHistoryIndexCalculatedFromMinutesCounter = ( (minutesSinceStart - 3) / 15 ) % 32
        let delay = (minutesSinceStart - 3) % 15 + 3 // in minutes
        if nextHistoryIndexCalculatedFromMinutesCounter == nextHistoryBlock {
            // Case when history index is incremented togehter with minutesSinceStart (in sync)
            //            print("delay: \(delay), minutesSinceStart: \(minutesSinceStart), result: \(minutesSinceStart-delay)")
            return (date: date.addingTimeInterval( 60.0 * -Double(delay) ), counter: minutesSinceStart - delay)
        } else {
            // Case when history index is incremented before minutesSinceStart (and they are async)
            //            print("delay: \(delay), minutesSinceStart: \(minutesSinceStart), result: \(minutesSinceStart-delay-15)")
            return (date: date.addingTimeInterval( 60.0 * -Double(delay - 15)), counter: minutesSinceStart - delay)
        }
    }
    
    
    /// Get date of most recent history value.
    /// History values are updated every 15 minutes. Their corresponding time from start of the sensor in minutes is 15, 30, 45, 60, ..., but the value is delivered three minutes later, i.e. at the minutes 18, 33, 48, 63, ... and so on. So for instance if the current time in minutes (since start of sensor) is 67, the most recent value is 7 minutes old. This can be calculated from the minutes since start. Unfortunately sometimes the history index is incremented earlier than the minutes counter and they are not in sync. This has to be corrected.
    ///
    /// - Returns: the date of the most recent history value
    func dateOfMostRecentHistoryValue() -> Date {
        // Calculate correct date for the most recent history value.
        //        date.addingTimeInterval( 60.0 * -Double( (minutesSinceStart - 3) % 15 + 3 ) )
        let nextHistoryIndexCalculatedFromMinutesCounter = ( (minutesSinceStart - 3) / 15 ) % 32
        let delay = (minutesSinceStart - 3) % 15 + 3 // in minutes
        if nextHistoryIndexCalculatedFromMinutesCounter == nextHistoryBlock {
            // Case when history index is incremented togehter with minutesSinceStart (in sync)
            //            print("delay: \(delay), minutesSinceStart: \(minutesSinceStart), result: \(minutesSinceStart-delay)")
            return date.addingTimeInterval( 60.0 * -Double(delay) )
        } else {
            // Case when history index is incremented before minutesSinceStart (and they are async)
            //            print("delay: \(delay), minutesSinceStart: \(minutesSinceStart), result: \(minutesSinceStart-delay-15)")
            return date.addingTimeInterval( 60.0 * -Double(delay - 15))
        }
    }
    
    func oopWebInterfaceInput() -> String {
        return Data(bytes).base64EncodedString()
    }
    
    /// Returns a new array of 344 bytes of FRAM with correct crc for header, body and footer.
    ///
    /// Usefull, if some bytes are modified in order to investigate how the OOP algorithm handles this modification.
    /// - Returns: 344 bytes of FRAM with correct crcs
    func bytesWithCorrectCRC() -> [UInt8] {
        return Crc.bytesWithCorrectCRC(header) + Crc.bytesWithCorrectCRC(body) + Crc.bytesWithCorrectCRC(footer)
    }
}

// Code by Ivan Valkou

public extension SensorData {
    var history: [UInt8] {
        Array(bytes[124 ..< 316])
    }

    var trend: [UInt8] {
        Array(bytes[28 ..< 124])
    }

    var glucoseHistory: [UInt16] {
        var index = 0
        var result = [UInt16]()

        repeat {
            let record = UInt16(history[index + 1], history[index])
            result.append(glucose(record))
            index += 6
        } while index < 192

        return Array(result[nextHistoryBlock...] + result[..<nextHistoryBlock])
    }

    var glucoseTrend: [UInt16] {
        var index = 0
        var result = [UInt16]()

        repeat {
            let record = UInt16(trend[index + 1], trend[index])
            result.append(glucose(record))
            index += 6
        } while index < 96

        return Array(result[nextTrendBlock...] + result[..<nextTrendBlock])
    }

    func glucose(_ record: UInt16) -> UInt16 {
       record & 0x3FFF / 6 - 37
    }
}
