# LibreTools

LibreTools is a toolkit for reading and writing ISO15693 NFC tags with TI RF430 chips.

# Requirements

LibreTools framework required iOS SDK version of 13.0. In `Package.swift`  version of 10.0 is specified only for compatibility with applications with target version below 13.0.

# Swift Package Manager

LibreTools can be installed via SPM. Create a new Xcode project and navigate to File > Swift Packages > Add Package Dependency. Enter the url `https://github.com/ivalkou/LibreTools` and tap Next. Choose the master branch, and on the next screen, check off the packages as needed.

# Usage

## Option 1: NFCManager

```swift
import Combine
import LibreTools

let nfcManager = LibreTools.makeNFCManager(unlockCode: code, password: password)
let subscription: AnyCancellable?

// perform a request
subscription = nfcManager.perform(.readState)
    .reseive(on: DispatchQueue.main)
    .assign(to: \.log, on: self)
```

## Option 2: SwiftUI

```swift
import SwiftUI
import LibreTools

struct ContentView: View {
    var body: some View {
        NavigationView {
            LibreTools.makeView(unlockCode: code, password: password)
        }
    }
}
```

## Option 3: UIKit

```swift
import UIKit
import LibreTools

// make view controller and present it
let viewController = LibreTools.makeViewController(unlockCode: code, password: password)
present(viewController, animated: true)
```

*Note: unlock code and password are not included in this repository.*
