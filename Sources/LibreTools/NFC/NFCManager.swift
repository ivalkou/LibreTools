//
//  NFCManager.swift
//  LibreTools
//
//  Created by Ivan Valkou on 10.07.2020.
//  Copyright © 2020 Ivan Valkou. All rights reserved.
//

import CoreNFC
import Combine
import Foundation

enum NFCManagerError: Error, LocalizedError {
    case unsupportedSensorType
    case missingUnlockParameters

    var errorDescription: String? {
        switch self {
        case .unsupportedSensorType:
            return "Unsupported Sensor Type"
        case .missingUnlockParameters:
            return "Missing Unlock Parameters"
        }
    }
}

@available(iOS 13.0, OSX 10.15, tvOS 13.0, watchOS 6.0, *)
final class BaseNFCManager: NSObject, NFCManager {
    private enum Config {
        static let numberOfFRAMBlocks = 0xF4
    }

    private var session: NFCTagReaderSession?

    private let nfcQueue = DispatchQueue(label: "NFCManager.nfcQueue")
    private let accessQueue = DispatchQueue(label: "NFCManager.accessQueue")

    private var sessionToken: AnyCancellable?

    private var actionRequest: ActionRequest? {
        didSet {
            guard actionRequest != nil else { return }
            startSession()
        }
    }

    @Published private var sessionLog = ""

    private var unlockCode: Int?
    private var password: Data?

    func perform(_ request: ActionRequest) -> AnyPublisher<String, Never> {
        sessionLog = ""
        log("Start processing...")
        actionRequest = request
        return $sessionLog.eraseToAnyPublisher()
    }

    func setCredentials(unlockCode: Int, password: Data) {
        self.unlockCode = unlockCode
        self.password = password
    }

    init(unlockCode: Int? = nil, password: Data? = nil) {
        self.unlockCode = unlockCode
        self.password = password
    }

    private func startSession() {
        guard NFCReaderSession.readingAvailable, actionRequest != nil else {
            sessionLog = "You phone is not supporting NFC"
            actionRequest = nil
            return
        }

        accessQueue.async {
            self.session = NFCTagReaderSession(pollingOption: .iso15693, delegate: self, queue: self.nfcQueue)
            self.session?.alertMessage = "Hold your iPhone near the item to learn more about it."
            self.session?.begin()
        }
    }

    private func processTag(_ tag: NFCISO15693Tag) {
        dispatchPrecondition(condition: .onQueue(accessQueue))

        guard let actionRequest = actionRequest else {
            session?.invalidate()
            return
        }

        log("Tag connected")
        log("UID: \(tag.identifier.hexEncodedString())")

        sessionToken = tag.getPatchInfo()
            .flatMap { data -> AnyPublisher<Data, Error> in
                let patchInfo = data.hexEncodedString()
                let sensorType = SensorType(patchInfo: patchInfo)
                let region = SensorRegion(rawValue: [UInt8](data)[3]) ?? .unknown
                self.log("Patch Info: " + patchInfo)
                self.log("Type: " + sensorType.displayType)
                self.log("Region: \(region)")
                switch actionRequest {
                case .readState:
                    return tag.readFRAM(blocksCount: 1)
                case .readFRAM:
                    return tag.readFRAM(blocksCount: Config.numberOfFRAMBlocks)
                case .reset:
                    guard let unlockCode = self.unlockCode, let password = self.password else {
                        return Fail(error: NFCManagerError.missingUnlockParameters).eraseToAnyPublisher()
                    }
                    return tag.reinitialize(sensorType: sensorType, unlockCode: unlockCode, password: password)
                        .map { Data() }
                        .eraseToAnyPublisher()
                case .activate:
                    guard let password = self.password else {
                        return Fail(error: NFCManagerError.missingUnlockParameters).eraseToAnyPublisher()
                    }
                    return tag.activate(sensorType: sensorType, password: password)
                        .map { Data() }
                        .eraseToAnyPublisher()
                case let .changeRegion(region):
                    guard let unlockCode = self.unlockCode, let password = self.password else {
                        return Fail(error: NFCManagerError.missingUnlockParameters).eraseToAnyPublisher()
                    }
                    return tag.changeRegion(sensorType: sensorType, region: region, unlockCode: unlockCode, password: password)
                        .map { Data() }
                        .eraseToAnyPublisher()
                }
            }
            .receive(on: accessQueue)
            .sink(
                receiveCompletion: { completion in
                    switch completion {
                    case .finished:
                        self.log("Completed")
                        self.session?.invalidate()
                    case let .failure(error):
                        self.log("Error: \(error.localizedDescription)")
                        self.session?.invalidate(errorMessage: error.localizedDescription)
                    }
                },
                receiveValue: { self.processResult(with: $0) }
            )
    }


    private func processResult(with data: Data) {
        dispatchPrecondition(condition: .onQueue(accessQueue))

        print(data)
        let bytes = [UInt8](data)

        switch actionRequest {
        case .readState:
            let state = SensorState(rawValue: bytes[4]) ?? .unknown
            self.log("Sensor state: \(state) (\(state.rawValue))")
        case .readFRAM:
            let state = SensorState(rawValue: bytes[4]) ?? .unknown
            self.log("Sensor state: \(state) (\(state.rawValue))")
            self.log("\nFRAM dump:\n\n\(data.dumpString)")
        case .activate:
            self.log("Sensor activated successfully")
        case .reset:
            self.log("Sensor restarted successfully")
        case let .changeRegion(region):
            self.log("Region changed to \(region)")
        default: break
        }
        actionRequest = nil
    }

    private func log(_ message: String) {
        print(message)
        sessionLog += message + "\n"
    }
}

@available(iOS 13.0, OSX 10.15, tvOS 13.0, watchOS 6.0, *)
extension BaseNFCManager: NFCTagReaderSessionDelegate {
    func tagReaderSessionDidBecomeActive(_ session: NFCTagReaderSession) {
        print("Started scanning for tags")
    }

    func tagReaderSession(_ session: NFCTagReaderSession, didInvalidateWithError error: Error) {
        print("Session did invalidate with error: \(error)")
    }

    func tagReaderSession(_ session: NFCTagReaderSession, didDetect tags: [NFCTag]) {
        if let tag = tags.first {
            switch tag {
            case let .iso15693(libreTag):
                print("Tag found")
                session.connect(to: tag) { _ in
                    self.accessQueue.async {
                        self.processTag(libreTag)
                    }
                }
            default: break
            }
        }
    }
}

extension Data {
    func hexEncodedString() -> String {
        return map { String(format: "%02X", $0) }.joined(separator: " ")
    }
}

@available(iOS 13.0, OSX 10.15, tvOS 13.0, watchOS 6.0, *)
private extension NFCISO15693Tag {
    func runCommand(_ cmd: CustomCommand, parameters: Data = Data()) -> AnyPublisher<Data, Error> {
        Future { promise in
            self.customCommand(requestFlags: .highDataRate, customCommandCode: cmd.code, customRequestParameters: parameters) { data, error in
                guard error == nil else {
                    promise(.failure(error!))
                    return
                }
                promise(.success(data))
            }
        }.eraseToAnyPublisher()
    }

    func readBlock(number: UInt8) -> AnyPublisher<Data, Error> {
        Future { promise in
            self.readSingleBlock(requestFlags: .highDataRate, blockNumber: number) { data, error in
                guard error == nil else {
                    promise(.failure(error!))
                    return
                }
                promise(.success(data))
            }
        }.eraseToAnyPublisher()
    }

    func readFRAM(blocksCount: Int) -> AnyPublisher<Data, Error> {
        Publishers.Sequence(
                sequence: (UInt8(0) ..< UInt8(blocksCount))
                    .map { self.readBlock(number: $0) }
            )
            .flatMap { $0 }
            .collect()
            .map { $0.reduce(Data(), +) }
            .eraseToAnyPublisher()
    }

    func getPatchInfo() -> AnyPublisher<Data, Error> {
        runCommand(.getPatchInfo)
    }

    func writeBlock(number: UInt8, data: Data) -> AnyPublisher<Void, Error> {
        Future<Void, Error> { promise in
            self.writeSingleBlock(
                requestFlags: .highDataRate,
                blockNumber: number,
                dataBlock: data
            ) { promise( $0.map { Result.failure($0) } ?? .success(())) }
        }.eraseToAnyPublisher()
    }

    func unlock(_ code: Int, password: Data) -> AnyPublisher<Void, Error> {
        runCommand(.init(code: code), parameters: password).asEmpty()
    }

    func lock(password: Data) -> AnyPublisher<Void, Error> {
        runCommand(.lock, parameters: password).asEmpty()
    }

    func activate(sensorType: SensorType, password: Data) -> AnyPublisher<Void, Error> {
        guard sensorType.isWritable else {
            return Fail<Void, Error>(error: NFCManagerError.unsupportedSensorType).eraseToAnyPublisher()
        }
        return runCommand(.activate, parameters: password).asEmpty()
    }

    func reinitialize(sensorType: SensorType, unlockCode: Int, password: Data) -> AnyPublisher<Void, Error> {
        guard sensorType.isWritable else {
            return Fail<Void, Error>(error: NFCManagerError.unsupportedSensorType).eraseToAnyPublisher()
        }

        return unlock(unlockCode, password: password)
            .flatMap { self.writeBlock(number: sensorType.commandBlockNumber, data: sensorType.commandBlockModified) }
            .flatMap { self.writeBlock(number: sensorType.crcBlockNumber, data: sensorType.crcBlockModified) }
            .flatMap { self.getPatchInfo().asEmpty() }
            .flatMap { self.writeBlock(number: sensorType.commandBlockNumber, data: sensorType.commandBlockOriginal)}
            .flatMap { self.writeBlock(number: sensorType.crcBlockNumber, data: sensorType.crcBlockOriginal) }
            .flatMap { self.lock(password: password) }
            .eraseToAnyPublisher()
    }

    func changeRegion(sensorType: SensorType, region: SensorRegion, unlockCode: Int, password: Data) -> AnyPublisher<Void, Error> {
        guard sensorType.isWritable else {
            return Fail<Void, Error>(error: NFCManagerError.unsupportedSensorType).eraseToAnyPublisher()
        }

        return Publishers
            .Sequence(sequence: (0x28 ... 0x2A).map { self.readBlock(number: $0) })
            .flatMap { $0 }
            .collect()
            .map { [UInt8]($0.reduce(Data(), +) )}
            .flatMap { bytes -> AnyPublisher<Void, Error> in
                var bytes = bytes
                bytes[3] = region.rawValue
                bytes = Crc.bytesWithCorrectCRC(bytes)
                return self.unlock(unlockCode, password: password)
                    .flatMap {
                        self.writeBlock(number: 0x28, data: Data(bytes[0 ..< 8])).asEmpty()
                    }
                    .eraseToAnyPublisher()
            }
            .flatMap { self.lock(password: password) }
            .eraseToAnyPublisher()
    }
}

struct CustomCommand {
    let code: Int

    static let activate = CustomCommand(code: 0xA0)
    static let getPatchInfo = CustomCommand(code: 0xA1)
    static let lock = CustomCommand(code: 0xA2)
    static let rawRead = CustomCommand(code: 0xA3)
}

extension Data {
    var dumpString: String {
        var result = ""

        let bytes = [UInt8](self)

        for number in 0 ..< bytes.count / 8 {
            guard number * 8 < bytes.count else { break }

            let data = Data(bytes[number * 8 ..< number * 8 + 8])

            result += "\(String(format: "%02X", 0xF860 + number * 8)) \(String(format: "%02X", number)): \(data.hexEncodedString())\n"
        }

        return result
    }
}


