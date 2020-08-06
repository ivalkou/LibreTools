//
//  LibreToolsView.swift
//  LibreTools
//
//  Created by Ivan Valkou on 10.07.2020.
//  Copyright © 2020 Ivan Valkou. All rights reserved.
//

#if canImport(Combine)

import SwiftUI

@available(iOS 13.0, OSX 10.15, tvOS 13.0, watchOS 6.0, *)
struct LibreToolsView: View {
    @ObservedObject var viewModel: LibreToolsViewModel

    @State private var showingActionSheet = false
    @State private var showingUnlockView = false

    init(unlockCode: Int? = nil, password: Data? = nil) {
        viewModel = LibreToolsViewModel(unlockCode: unlockCode, password: password)
    }

    var body: some View {
        Form {
            Section(header: Text("Tag operations")) {
                Button("Check state") {
                    self.viewModel.read()
                }

                Button("Read history") {
                    self.viewModel.readHistory()
                }

                Button("Read FRAM") {
                    self.viewModel.dump()
                }

                protectedButtons

                if viewModel.canEditUnlockCredentials {
                    Button("Edit unlock credentials") {
                        self.showingUnlockView = true
                    }
                }
            }
            Section(header: Text("NFC session log"), footer: Text("Tap on text to copy")) {
                Text(viewModel.log)
                    .font(.system(size: 16, weight: .regular, design: .monospaced))
                    .onTapGesture {
                        UIPasteboard.general.string = self.viewModel.log
                }
            }
        }
            .actionSheet(isPresented: $showingActionSheet) {
                ActionSheet(title: Text("Select region"), message: nil, buttons:
                    SensorRegion.selectCases.map { region in
                        ActionSheet.Button.default(Text(region.description)) {
                            self.viewModel.changeRegion(to: region)
                        }
                    } + [.cancel()]
                )
            }
            .sheet(isPresented: $showingUnlockView) { self.unlockView }
    }

    var protectedButtons: some View {
        guard !viewModel.unlockCode.isEmpty, !viewModel.password.isEmpty else {
            return AnyView(EmptyView())
        }

        return AnyView(
            Group {
                Button("Reset to new state") {
                    self.viewModel.reset()
                }

                Button("Activate") {
                    self.viewModel.activate()
                }

                Button("Change region") {
                    self.showingActionSheet = true
                }
            }
        )
    }

    var unlockView: some View {
        NavigationView {
            Form {
                Section() {
                    TextField("Unlock code", text: self.$viewModel.unlockCode)
                        .keyboardType(.asciiCapable)
                        .autocapitalization(.allCharacters)
                        .disableAutocorrection(true)
                    TextField("Password", text: self.$viewModel.password)
                        .keyboardType(.asciiCapable)
                        .autocapitalization(.allCharacters)
                        .disableAutocorrection(true)
                }

                Section() {
                    Button("Save") {
                        self.viewModel.saveUnlockCredentials()
                        self.showingUnlockView = false
                    }
                }

            }.navigationBarTitle("Unlock credentials")
        }
    }
}

#endif
