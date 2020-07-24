//
//  NFCManager.swift
//  LibreTools
//
//  Created by Ivan Valkou on 24.07.2020.
//  Copyright © 2020 Ivan Valkou. All rights reserved.
//

import SwiftUI

@available(iOS 13.0, OSX 10.15, tvOS 13.0, watchOS 6.0, *)
public enum LibreTools {
    public static func makeNFCManager(unlockCode: Int? = nil, password: Data? = nil) -> NFCManager {
        BaseNFCManager(unlockCode: unlockCode, password: password)
    }

    public static func makeView(unlockCode: Int? = nil, password: Data? = nil) -> some View {
        LibreToolsView(unlockCode: unlockCode, password: password)
    }

    public static func makeViewController(unlockCode: Int? = nil, password: Data? = nil) -> UIViewController {
        let vc = LibreToolsViewController()
        let navigationView = NavigationView {
                makeView(unlockCode: unlockCode, password: password)
                .navigationBarTitle("Libre Tools")
                .navigationBarItems(leading: Button("Close") { [weak vc] in vc?.dismiss(animated: true)} )
        }
        vc.rootView = AnyView(navigationView)
        return vc
    }
}

@available(iOS 13.0, OSX 10.15, tvOS 13.0, watchOS 6.0, *)
final class LibreToolsViewController: UIHostingController<AnyView> {
    convenience init() {
        self.init(rootView: AnyView(EmptyView()))
    }
}
