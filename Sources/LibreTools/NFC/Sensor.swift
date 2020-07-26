//
//  Sensor.swift
//  LibreTools
//
//  Created by Ivan Valkou on 16.07.2020.
//  Copyright © 2020 Ivan Valkou. All rights reserved.
//

import Foundation

enum SensorType {
    case libre1
    case libre1new
    case libreUS14day
    case libre2
    case libreProH
    case unknown

    init(patchInfo: String) {
        switch patchInfo.prefix(8) {
        case "DF 00 00": self = .libre1
        case "A2 08 00": self = .libre1new
        case "E5 00 03": self = .libreUS14day
        case "9D 08 30": self = .libre2
        case "70 00 10": self = .libreProH
        default: self = .unknown
        }
    }

    var displayType: String {
        switch self {
        case .libre1: return "Libre 1 old"
        case .libre1new: return "Libre 1 new"
        case .libreUS14day: return "Libre US 14day"
        case .libre2: return "Libre 2"
        case .libreProH: return "Libre Pro/H"
        default: return "unknown"
        }
    }

    var isWritable: Bool {
        switch self {
        case .libre1, .libre1new: return true
        default: return false
        }
    }


    var crcBlockModified: Data {
        switch self {
        case .libre1: return Data([UInt8]([0x01, 0x6E, 0x21, 0x83, 0xF2, 0x90, 0x07, 0x00]))
        case .libre1new: return Data([UInt8]([0x31, 0xD5, 0x21, 0x83, 0xF2, 0x90, 0x07, 0x00]))
        default: fatalError("Unsuppotred sensor type")
        }
    }

    var crcBlockOriginal: Data {
        switch self {
        case .libre1: return Data([UInt8]([0x9E, 0x42, 0x21, 0x83, 0xF2, 0x90, 0x07, 0x00]))
        case .libre1new: return Data([UInt8]([0xAE, 0xF9 , 0x21, 0x83, 0xF2, 0x90, 0x07, 0x00]))
        default: fatalError("Unsuppotred sensor type")
        }
    }

    var commandBlockModified: Data {
        Data([UInt8]([0xA3, 0x00, 0x56, 0x5A, 0xA2, 0x00, 0xAE, 0xFB]))
    }

    var commandBlockOriginal: Data {
        Data([UInt8]([0xA3, 0x00, 0x56, 0x5A, 0xA2, 0x00, 0xBA, 0xF9]))
    }

    var crcBlockNumber: UInt8 { 0x2B }

    var commandBlockNumber: UInt8 { 0xEC }
}

enum SensorState: UInt8 {
    case unknown = 0
    case new
    case activating
    case operational
    case expiring
    case expired
    case error
}

extension SensorRegion {
    static let selectCases: [SensorRegion] = [.europe, .usa, .newZeland, .asia]
}

extension SensorRegion: CustomStringConvertible {
    public var description: String {
        switch self {
        case .europe:
            return "01 - Europe"
        case .usa:
            return "02 - US"
        case .newZeland:
            return "04 - New Zeland"
        case .asia:
            return "08 - Asia and world wide"
        case .unknown:
            return "Unknown"
        }
    }
}

extension SensorRegion: Identifiable {
    public var id: UInt8 { rawValue }
}
