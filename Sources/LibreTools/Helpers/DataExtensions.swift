//
//  DataExtensions.swift
//  LibreTools
//
//  Created by Ivan Valkou on 06.08.2020.
//

import Foundation

extension Data {
    func hexEncodedString() -> String {
        return map { String(format: "%02X", $0) }.joined(separator: " ")
    }
}
