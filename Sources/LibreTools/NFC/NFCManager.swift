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
    case tagDamaged

    var errorDescription: String? {
        switch self {
        case .unsupportedSensorType:
            return "Unsupported Sensor Type"
        case .missingUnlockParameters:
            return "Missing Unlock Parameters"
        case .tagDamaged:
            return "Tag damaged"
        }
    }
}

@available(iOS 13.0, OSX 10.15, tvOS 13.0, watchOS 6.0, *)
final class BaseNFCManager: NSObject, NFCManager {
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

    private var sessionLog = ""
    private var readingsSubject = PassthroughSubject<Reading, Never>()

    private var unlockCode: Int?
    private var password: Data?

    func perform(_ request: ActionRequest) -> AnyPublisher<Reading, Never> {
        sessionLog = ""
        log("Start processing...")
        actionRequest = request
        return readingsSubject.eraseToAnyPublisher()
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
            sessionLog = "Your phone does not support NFC"
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
        let uid = Data(tag.identifier.reversed())
        log("UID: \(uid.hexEncodedString())")

        sessionToken = tag.getPatchInfo()
            .flatMap { patchInfo -> AnyPublisher<(SensorType, Data, Data), Error> in
                guard !patchInfo.isEmpty || self.actionRequest == .recover else {
                    return Fail(error: NFCManagerError.tagDamaged).eraseToAnyPublisher()
                }

                let sensorType = SensorType(patchInfo: patchInfo.hexEncodedString())
                let region = SensorRegion(rawValue: [UInt8](patchInfo)[safe: 3] ?? 0) ?? .unknown
                self.log("Patch Info: " + patchInfo.hexEncodedString())
                self.log("Type: " + sensorType.displayType)
                self.log("Region: \(region)")
                switch actionRequest {
                case .readState:
                    let count = (sensorType == .libre2 || sensorType == .libreUS14day) ? 43 : 1
                    return tag.readFRAM(blocksCount: count)
                        .map { (sensorType, $0, patchInfo) }
                        .eraseToAnyPublisher()
                case .readFRAM:
                    return tag.readFRAM(blocksCount: 0xFF)
                        .map { (sensorType, $0, patchInfo) }
                        .eraseToAnyPublisher()
                case .readHistory:
                    return tag.readFRAM(blocksCount: 43)
                        .map { (sensorType, $0, patchInfo) }
                        .eraseToAnyPublisher()
                case .reset:
                    guard let unlockCode = self.unlockCode, let password = self.password else {
                        return Fail(error: NFCManagerError.missingUnlockParameters).eraseToAnyPublisher()
                    }
                    guard sensorType.isWritable else {
                        return Fail(error: NFCManagerError.unsupportedSensorType).eraseToAnyPublisher()
                    }

                    return tag.reinitialize(sensorType: sensorType, unlockCode: unlockCode, password: password)
                        .map { (sensorType, Data(), patchInfo) }
                        .eraseToAnyPublisher()
                case .activate:
                    switch sensorType {
                    case .libre1, .libre1new, .libreProH:
                        guard let password = self.password else {
                            return Fail(error: NFCManagerError.missingUnlockParameters).eraseToAnyPublisher()
                        }
                        return tag.activate(sensorType: sensorType, parameters: password)
                            .map { (sensorType, Data(), patchInfo) }
                            .eraseToAnyPublisher()
                    case .libreUS14day, .libre2:
                        return tag.activate(sensorType: sensorType, parameters: Libre2.activateParameters(id: [UInt8](uid)))
                            .map { (sensorType, Data(), patchInfo) }
                            .eraseToAnyPublisher()
                    case .unknown:
                        return Fail(error: NFCManagerError.unsupportedSensorType).eraseToAnyPublisher()
                    }
                case let .changeRegion(region):
                    guard let unlockCode = self.unlockCode, let password = self.password else {
                        return Fail(error: NFCManagerError.missingUnlockParameters).eraseToAnyPublisher()
                    }
                    guard sensorType.isWritable else {
                        return Fail(error: NFCManagerError.unsupportedSensorType).eraseToAnyPublisher()
                    }

                    return tag.changeRegion(sensorType: sensorType, region: region, unlockCode: unlockCode, password: password)
                        .map { (sensorType, Data(), patchInfo) }
                        .eraseToAnyPublisher()
                case .removeLifetimeLimitation:
                    guard let unlockCode = self.unlockCode, let password = self.password else {
                        return Fail(error: NFCManagerError.missingUnlockParameters).eraseToAnyPublisher()
                    }

                    return tag.removeLifetimeLimitation(sensorType: sensorType, unlockCode: unlockCode, password: password)
                        .map { (sensorType, Data(), patchInfo) }
                        .eraseToAnyPublisher()
                case .recover:
                    guard let unlockCode = self.unlockCode, let password = self.password else {
                        return Fail(error: NFCManagerError.missingUnlockParameters).eraseToAnyPublisher()
                    }

                    return tag.recoverCommandSection(sensorType: .libre1new, unlockCode: unlockCode, password: password)
                        .map { (sensorType, Data(), patchInfo) }
                        .eraseToAnyPublisher()
                case .custom(let cmd, let data):
                    return tag.runCommand(.init(code: cmd), parameters: data ?? Data())
                        .map { data in (sensorType, data, patchInfo) }
                        .eraseToAnyPublisher()
                case let .readBlock(block):
                    return tag.readBlock(number: block)
                        .map { data in (sensorType, data, patchInfo) }
                        .eraseToAnyPublisher()
                case .writeBlock(let block, let data):
                    return tag.writeBlock(number: block, data: data)
                        .map { (sensorType, Data(), patchInfo) }
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
                        if let nfcError = error as? NFCManagerError, nfcError == .tagDamaged {
                            self.accessQueue.async {
                                self.actionRequest = .recover
                                self.processTag(tag)
                            }
                        } else {
                            self.session?.invalidate(errorMessage: error.localizedDescription)
                        }

                    }
                },
                receiveValue: { self.processResult(sensorType: $0.0, data: $0.1, uid: uid, patchInfo: $0.2) }
            )
    }


    private func processResult(sensorType: SensorType, data: Data, uid: Data, patchInfo: Data) {
        dispatchPrecondition(condition: .onQueue(accessQueue))
        print(data)

        let bytes:[UInt8] = {
            switch sensorType {
            case .libre2, .libreUS14day:
                return try! Libre2.decryptFRAM(type: sensorType, id: [UInt8](uid), info: [UInt8](patchInfo), data: [UInt8](data))
            default:
                return [UInt8](data)
            }
        }()

        var sensorData: SensorData? = nil

        switch actionRequest {
        case .readState:
            let state = SensorState(rawValue: bytes[4]) ?? .unknown
            log("Tag state: \(state) (\(state.rawValue))")
        case .readFRAM:
            let state = SensorState(rawValue: bytes[4]) ?? .unknown
            log("Tag state: \(state) (\(state.rawValue))")
            log("\nFRAM dump:\n\n\(data.dumpString)")
        case .activate:
            log("Tag activated successfully")
        case .reset:
            log("Tag restarted successfully")
        case let .changeRegion(region):
            log("Region changed to \(region)")
        case .readHistory:
            let state = SensorState(rawValue: bytes[4]) ?? .unknown
            log("Tag state: \(state) (\(state.rawValue))")
            sensorData = SensorData(uuid: uid, bytes: bytes, date: Date(), patchInfo: patchInfo.hexEncodedString())
            if let sensorData = sensorData {
                log("Age: \(sensorData.humanReadableSensorAge)")
                log("Raw history: \(sensorData.glucoseHistory)")
                log("Raw trend: \(sensorData.glucoseTrend)")
            }
        case .removeLifetimeLimitation:
            log("Lifetime limitation removed")
        case .recover:
            log("Tag recovered. Please retry your action")
        case .custom:
            log("Command succeeded")
        case .readBlock:
            log("Read succeeded")
        case .writeBlock:
            log("Write succeeded")
        case .none: break
        }
        actionRequest = nil
        readingsSubject.send(Reading(log: sessionLog, sensorData: sensorData))
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
                    .map { self.readBlock(number: $0)
                        .catch { _ -> Future<Data, Error> in
                            Future { $0(.success(Data())) }
                    }
                }
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

    func activate(sensorType: SensorType, parameters: Data) -> AnyPublisher<Void, Error> {
        switch sensorType {
        case .libre1, .libre1new, .libreProH:
            return runCommand(.activate, parameters: parameters).asEmpty()
        case .libreUS14day, .libre2:
            return runCommand(.libre2Universal, parameters: Data()).asEmpty()
        case .unknown:
            return Fail<Void, Error>(error: NFCManagerError.unsupportedSensorType).eraseToAnyPublisher()
        }
    }

    func reinitialize(sensorType: SensorType, unlockCode: Int, password: Data) -> AnyPublisher<Void, Error> {
        return changeCommandSection(
            sensorType: sensorType,
            unlockCode: unlockCode,
            password: password
        )
        .flatMap { self.getPatchInfo().asEmpty() }
        .flatMap {
            self.recoverCommandSection(
                sensorType: sensorType,
                unlockCode: unlockCode,
                password: password
            )
        }
        .eraseToAnyPublisher()
    }

    func changeCommandSection(sensorType: SensorType, unlockCode: Int, password: Data) -> AnyPublisher<Void, Error> {
        guard sensorType.isWritable else {
            return Fail<Void, Error>(error: NFCManagerError.unsupportedSensorType).eraseToAnyPublisher()
        }

        return unlock(unlockCode, password: password)
            .flatMap { self.writeBlock(number: sensorType.commandBlockNumber, data: sensorType.commandBlockModified) }
            .flatMap { self.writeBlock(number: sensorType.crcBlockNumber, data: sensorType.crcBlockModified) }
            .eraseToAnyPublisher()
    }

    func recoverCommandSection(sensorType: SensorType, unlockCode: Int, password: Data) -> AnyPublisher<Void, Error> {
        guard sensorType.isWritable else {
            return Fail<Void, Error>(error: NFCManagerError.unsupportedSensorType).eraseToAnyPublisher()
        }

        return writeBlock(number: sensorType.commandBlockNumber, data: sensorType.commandBlockOriginal)
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

    func removeLifetimeLimitation(sensorType: SensorType, unlockCode: Int, password: Data) -> AnyPublisher<Void, Error> {
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
                bytes[6] = 0xFF
                bytes[7] = 0xFF
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
    static let libre2Universal = CustomCommand(code: 0xA1)
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

extension Collection {
    subscript (safe index: Index) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}
