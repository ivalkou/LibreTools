//
//  NFCManager.swift
//  LibreTools
//
//  Created by Ivan Valkou on 24.07.2020.
//  Copyright © 2020 Ivan Valkou. All rights reserved.
//

#if canImport(Combine)

import SwiftUI
import Combine

@available(iOS 13.0, OSX 10.15, tvOS 13.0, watchOS 6.0, *)
/// LibreTools is a toolkit for reading and writing ISO15693 NFC tags with TI RF430 chips.
public enum LibreTools {
    /// This is the way to use LibreTools without UI
    /// - Parameters:
    ///   - unlockCode: code for the command to unlock a chip
    ///   - password: password protection data
    /// - Returns: instanse of NFCManager
    public static func makeNFCManager(unlockCode: Int? = nil, password: Data? = nil) -> NFCManager {
        BaseNFCManager(unlockCode: unlockCode, password: password)
    }

    /// The method for usage with SwiftUI
    /// - Parameters:
    ///   - unlockCode: code for the command to unlock a chip
    ///   - password: password protection data
    /// - Returns: SwiftUI view
    public static func makeView(unlockCode: Int? = nil, password: Data? = nil) -> some View {
        LibreToolsView(unlockCode: unlockCode, password: password)
    }

    /// The method for usage with UIKit
    /// - Parameters:
    ///   - unlockCode: code for the command to unlock a chip
    ///   - password: password protection data
    ///   - completion: called after the controller is dismissed by Close button
    /// - Returns: UIViewController to present
    public static func makeViewController(
        unlockCode: Int? = nil,
        password: Data? = nil,
        completion: (() -> Void)? = nil
    ) -> UIViewController {
        let vc = UIHostingController(rootView: AnyView(EmptyView()))
        let navigationView = NavigationView {
                makeView(unlockCode: unlockCode, password: password)
                .navigationBarTitle("Libre Tools")
                .navigationBarItems(leading: Button("Close") { [weak vc] in
                    vc?.dismiss(animated: true, completion: completion)
                } )
        }
        vc.rootView = AnyView(navigationView)
        return vc
    }
}

@available(iOS 13.0, OSX 10.15, tvOS 13.0, watchOS 6.0, *)
public protocol NFCManager {
    func perform(_ request: ActionRequest) -> AnyPublisher<Reading, Never>
    func setCredentials(unlockCode: Int, password: Data)
}

#endif

public enum ActionRequest {
    case readState
    case readFRAM
    case readHistory
    case reset
    case activate
    case changeRegion(SensorRegion)
}

public enum SensorRegion: UInt8 {
    case europe = 0x01
    case usa = 0x02
    case newZeland = 0x04
    case asia = 0x08
    case unknown = 0x00
}


