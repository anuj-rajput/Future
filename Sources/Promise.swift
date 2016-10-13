// The MIT License (MIT)
//
// Copyright (c) 2016 Alexander Grebenyuk (github.com/kean).

import Foundation

public final class Promise<T> {
    private var state: State<T> = .pending(Handlers<T>())
    private let lock = NSLock()
    
    public init(_ closure: (_ fulfill: @escaping (T) -> Void, _ reject: @escaping (Error) -> Void) -> Void) {
        closure({ self.resolve(resolution: .fulfilled($0)) },
                { self.resolve(resolution: .rejected($0)) })
    }
    
    public init(value: T) {
        state = .resolved(.fulfilled(value))
    }
    
    public init(error: Error) {
        state = .resolved(.rejected(error))
    }
    
    private func resolve(resolution: Resolution<T>) {
        lock.lock()
        if case let .pending(handlers) = self.state {
            self.state = .resolved(resolution)
            handlers.objects.forEach { $0(resolution) }
        }
        lock.unlock()
    }
    
    public func completion(on queue: DispatchQueue = .main, _ closure: @escaping (Resolution<T>) -> Void) {
        let completion: (Resolution<T>) -> Void = { resolution in
            queue.async { closure(resolution) }
        }
        lock.lock()
        switch self.state {
        case let .pending(handlers): handlers.objects.append(completion)
        case let .resolved(resolution): completion(resolution)
        }
        lock.unlock()
    }
}

public extension Promise {
    @discardableResult public func then(on queue: DispatchQueue = .main, _ closure: @escaping (T) -> Void) -> Promise {
        return then(on: queue, fulfilment: closure, rejection: nil)
    }
    
    public func then<U>(on queue: DispatchQueue = .main, _ closure: @escaping (T) -> U) -> Promise<U> {
        return then(on: queue) { Promise<U>(value: closure($0)) }
    }
    
    public func then<U>(on queue: DispatchQueue = .main, _ closure: @escaping (T) -> Promise<U>) -> Promise<U> {
        return Promise<U>() { fulfill, reject in
            then(
                on: queue,
                fulfilment: {
                    closure($0).then(
                        fulfilment: { fulfill($0) },
                        rejection: { reject($0) })
                },
                rejection: { reject($0) }) // bubble up error
        }
    }
    
    @discardableResult public func `catch`(on queue: DispatchQueue = .main, _ closure: @escaping (Error) -> Void) {
        then(on: queue, fulfilment: nil, rejection: closure)
    }
    
    public func recover(on queue: DispatchQueue = .main, _ closure: @escaping (Error) -> Promise) -> Promise {
        return Promise() { fulfill, reject in
            then(
                on: queue,
                fulfilment: { fulfill($0) }, // bubble up value
                rejection: {
                    closure($0).then(
                        fulfilment: { fulfill($0) },
                        rejection: { reject($0) })
            })
        }
    }
    
    @discardableResult public func then(on queue: DispatchQueue = .main, fulfilment: ((T) -> Void)?, rejection: ((Error) -> Void)?) -> Promise {
        completion(on: queue) { resolution in
            switch resolution {
            case let .fulfilled(val): fulfilment?(val)
            case let .rejected(err): rejection?(err)
            }
        }
        return self
    }
}

// FIXME: make nested type when compiler adds support for it
private final class Handlers<T> {
    var objects = [(Resolution<T>) -> Void]()
}

private enum State<T> {
    case pending(Handlers<T>), resolved(Resolution<T>)
}

public enum Resolution<T> {
    case fulfilled(T), rejected(Error)
}
