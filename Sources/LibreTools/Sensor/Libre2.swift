//
//  Libre2.swift
//  LibreTools
//
//  Created by Ivan Valkou on 28.07.2020.
//  Copyright © 2020 Ivan Valkou. All rights reserved.
//

import Foundation

enum Libre2 {
    /// Decrypts 43 blocks of Libre 2 FRAM
    /// - Parameters:
    ///   - type: Suppurted sensor type (.libre2, .libreUS14day)
    ///   - id: ID/Serial of the sensor. Could be retrieved from NFC as uid.
    ///   - info: Sensor info. Retrieved by sending command '0xa1' via NFC.
    ///   - data: Encrypted FRAM data
    /// - Returns: Decrypted FRAM data
    static func decryptFRAM(type: SensorType, id: [UInt8], info: [UInt8], data: [UInt8]) -> [UInt8]? {
        guard type == .libre2 || type == .libreUS14day else {
            print("Unsupported sensor type")
            return nil
        }

        var result = [UInt8]()

        for i in 0 ..< 43 {
            let s1: UInt16 = {
                switch type {
                case .libreUS14day:
                    if i < 3 || i >= 40 {
                        // For header and footer it is a fixed value.
                        return 0xcadc
                    }
                    return UInt16(info[5], info[4])
                case .libre2:
                    return ((UInt16(id[5], id[4]) + (UInt16(info[5], info[4]) ^ 0x44)) + UInt16(i))
                default: fatalError("Unsupported sensor type")
                }
            }()
            let s2 = UInt16(id[3], id[2]) + key[2]
            let s3 = UInt16(id[1], id[0]) + (UInt16(i) << 1)
            let s4 = 0x241a ^ key[3]

            let blockKey = processCrypto(input: [s1, s2, s3, s4], key: key);

            result.append(data[i * 8 + 0] ^ UInt8(truncatingIfNeeded: blockKey[3]))
            result.append(data[i * 8 + 1] ^ UInt8(truncatingIfNeeded: blockKey[3] >> 8))
            result.append(data[i * 8 + 2] ^ UInt8(truncatingIfNeeded: blockKey[2]))
            result.append(data[i * 8 + 3] ^ UInt8(truncatingIfNeeded: blockKey[2] >> 8))
            result.append(data[i * 8 + 4] ^ UInt8(truncatingIfNeeded: blockKey[1]))
            result.append(data[i * 8 + 5] ^ UInt8(truncatingIfNeeded: blockKey[1] >> 8))
            result.append(data[i * 8 + 6] ^ UInt8(truncatingIfNeeded: blockKey[0]))
            result.append(data[i * 8 + 7] ^ UInt8(truncatingIfNeeded: blockKey[0] >> 8))
        }
        return result
    }

}

private extension Libre2 {
    static let key: [UInt16] = [0xA0C5, 0x6860, 0x0000, 0x14C6]

    static func processCrypto(input: [UInt16], key: [UInt16]) -> [UInt16] {
        func op(_ value: UInt16) -> UInt16 {
            // We check for last 2 bits and do the xor with specific value if bit is 1
            var res = value >> 2 // Result does not include these last 2 bits

            if value & 1 != 0 { // If last bit is 1
                res = res ^ key[1]
            }

            if value & 2 != 0 { // If second last bit is 1
                res = res ^ key[0]
            }

            return res
        }

        let r0 = op(input[0]) ^ input[3]
        let r1 = op(r0) ^ input[2]
        let r2 = op(r1) ^ input[1]
        let r3 = op(r2) ^ input[0]
        let r4 = op(r3)
        let r5 = op(r4 ^ r0)
        let r6 = op(r5 ^ r1)
        let r7 = op(r6 ^ r2)

        let f1 = r0 ^ r4
        let f2 = r1 ^ r5
        let f3 = r2 ^ r6
        let f4 = r3 ^ r7

        return [f1, f2, f3, f4];
    }
}

extension UInt16 {
    init(_ byte0: UInt8, _ byte1: UInt8) {
        self = Data([byte1, byte0]).withUnsafeBytes { $0.load(as: UInt16.self) }
    }
}

extension Libre2 {
    enum Example {
        static let sensorInfo: [UInt8] = [
         157,
         8,
         48,
         1,
         115,
         23
        ]

        static let sensorId: [UInt8] = [
         157,
         129,
         194,
         0,
         0,
         164,
         7,
         224
        ]

        static let buffer: [UInt8] = [
         6,
         154,
         221,
         121,
         142,
         154,
         244,
         186,
         162,
         85,
         79,
         49,
         234,
         224,
         71,
         58,
         189,
         121,
         123,
         39,
         28,
         162,
         134,
         248,
         95,
         4,
         28,
         203,
         27,
         82,
         76,
         119,
         82,
         98,
         189,
         183,
         147,
         151,
         32,
         13,
         73,
         158,
         214,
         167,
         143,
         2,
         182,
         22,
         69,
         188,
         73,
         219,
         7,
         159,
         179,
         169,
         237,
         79,
         32,
         189,
         37,
         211,
         32,
         166,
         191,
         150,
         171,
         60,
         143,
         143,
         1,
         105,
         89,
         197,
         98,
         250,
         1,
         201,
         21,
         56,
         64,
         191,
         58,
         17,
         198,
         108,
         72,
         106,
         144,
         253,
         19,
         111,
         235,
         187,
         245,
         208,
         239,
         60,
         145,
         1,
         107,
         94,
         238,
         199,
         157,
         93,
         243,
         5,
         4,
         154,
         25,
         129,
         131,
         75,
         16,
         240,
         210,
         118,
         172,
         14,
         80,
         49,
         33,
         11,
         81,
         11,
         238,
         220,
         78,
         85,
         82,
         245,
         4,
         63,
         129,
         254,
         214,
         233,
         225,
         147,
         58,
         153,
         20,
         247,
         10,
         38,
         149,
         35,
         14,
         59,
         168,
         224,
         162,
         141,
         9,
         72,
         201,
         90,
         56,
         131,
         150,
         89,
         126,
         2,
         96,
         38,
         140,
         78,
         151,
         196,
         57,
         55,
         37,
         20,
         249,
         199,
         168,
         59,
         41,
         217,
         240,
         67,
         199,
         93,
         164,
         121,
         206,
         100,
         214,
         126,
         40,
         231,
         68,
         4,
         76,
         202,
         131,
         154,
         98,
         80,
         227,
         237,
         144,
         53,
         125,
         133,
         14,
         174,
         196,
         90,
         78,
         238,
         163,
         199,
         249,
         74,
         75,
         56,
         127,
         61,
         98,
         180,
         153,
         51,
         85,
         68,
         234,
         204,
         117,
         158,
         245,
         185,
         40,
         186,
         227,
         50,
         105,
         231,
         155,
         160,
         66,
         178,
         124,
         162,
         70,
         119,
         102,
         161,
         234,
         105,
         252,
         200,
         195,
         202,
         246,
         18,
         71,
         189,
         150,
         123,
         105,
         106,
         105,
         223,
         116,
         160,
         142,
         101,
         28,
         151,
         42,
         204,
         49,
         44,
         111,
         245,
         161,
         66,
         178,
         26,
         99,
         110,
         136,
         140,
         135,
         167,
         171,
         160,
         221,
         115,
         9,
         230,
         105,
         66,
         20,
         195,
         172,
         206,
         215,
         226,
         107,
         250,
         224,
         241,
         6,
         219,
         139,
         251,
         189,
         106,
         161,
         124,
         98,
         78,
         186,
         236,
         200,
         55,
         21,
         68,
         171,
         57,
         8,
         27,
         221,
         118,
         206,
         94,
         226,
         155,
         82,
         143,
         44,
         186,
         173,
         86,
         248,
         222,
         158,
         97,
         241,
         156,
         253,
         254
        ]
    }
}
