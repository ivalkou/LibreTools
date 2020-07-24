//
//  Combine.swift
//  LibreTools
//
//  Created by Ivan Valkou on 10.07.2020.
//  Copyright © 2020 Ivan Valkou. All rights reserved.
//


import Combine

protocol OptionalType {
    associatedtype Wrapped

    var optional: Wrapped? { get }
}

extension Optional: OptionalType {
    public var optional: Wrapped? { self }
}

extension Publisher where Output: OptionalType {
    func ignoreNil() -> AnyPublisher<Output.Wrapped, Failure> {
        flatMap { output -> AnyPublisher<Output.Wrapped, Failure> in
            guard let output = output.optional else {
                return Empty<Output.Wrapped, Failure>(completeImmediately: false).eraseToAnyPublisher()
            }
            return Just(output).setFailureType(to: Failure.self).eraseToAnyPublisher()
        }
        .eraseToAnyPublisher()
    }
}

extension Publisher {
    func asEmpty() -> AnyPublisher<Void, Failure> {
        map { _ in () }.eraseToAnyPublisher()
    }

    func get(_ output: @escaping (Output) -> Void) -> AnyPublisher<Output, Failure> {
        map { value -> Output in
            output(value)
            return value
        }.eraseToAnyPublisher()
    }
}
