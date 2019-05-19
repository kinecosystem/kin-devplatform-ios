//
//  Blockchain.swift
//  KinEcosystem
//
//  Created by Elazar Yifrach on 11/02/2018.
//  Copyright © 2018 Kik Interactive. All rights reserved.
//

import StellarErrors
import KinMigrationModule

struct PaymentMemoIdentifier: CustomStringConvertible, Equatable, Hashable {
    let version = "1"
    var appId: String
    var id: String

    var hashValue: Int {
        return description.hashValue
    }

    var description: String {
        return "\(version)-\(appId)-\(id)"
    }

    static func ==(lhs: PaymentMemoIdentifier, rhs: PaymentMemoIdentifier) -> Bool {
        return lhs.description == rhs.description
    }
}

enum BlockchainError: Error {
    case watchNotStarted
    case watchTimedOut
}

@available(iOS 9.0, *)
class Blockchain {
    let migrationManager: KinMigrationManager
    fileprivate(set) var account: KinAccountProtocol?
    private let linkBag = LinkBag()
    private var paymentObservers = [PaymentMemoIdentifier : Observable<String>]()
    private var balanceObservers = [String : (Balance) -> ()]()
    private var paymentsWatcher: PaymentWatchProtocol?
    private var balanceWatcher: BalanceWatchProtocol?
    let onboardEvent = Observable<Bool>()
    fileprivate(set) var balanceObservable = Observable<Balance>()
    fileprivate(set) var lastBalance: Balance? {
        get {
            if  let data = UserDefaults.standard.data(forKey: KinPreferenceKey.lastBalance.rawValue),
                let cachedBalance = try? JSONDecoder().decode(Balance.self, from: data) {
                    return cachedBalance
            }
            return nil
        }
        set {
            let oldValue = lastBalance
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: KinPreferenceKey.lastBalance.rawValue)
            }
            if let balance = newValue {
                balanceObservable.next(balance)
            } else {
                UserDefaults.standard.set(nil, forKey: KinPreferenceKey.lastBalance.rawValue)
            }
            if newValue != oldValue {
                updateBalanceObservers()
            }
        }


    }
    fileprivate(set) var onboarded: Bool {
        get {
            return account?.extra != nil
        }
        set {
            guard newValue else {
                account?.extra = nil
                return
            }
            onboardEvent.next(true)
            onboardEvent.finish()
            account?.extra = Data()
        }
    }

    init(serviceProvider: ServiceProviderProtocol, appId: AppId) throws {
        migrationManager = KinMigrationManager(serviceProvider: serviceProvider, appId: appId)
    }

    func getAccount(with client: KinClientProtocol) -> KinAccountProtocol? {
        if client.accounts.count > 0, let account = client.accounts[client.accounts.count - 1] {
            return account
        }

        return nil
    }

    func startAccount(with client: KinClientProtocol) throws -> KinAccountProtocol {
        if Kin.shared.needsReset {
            lastBalance = nil
        }

        let account: KinAccountProtocol

        if let acc = getAccount(with: client) {
            account = acc
        } else {
            Kin.track { try StellarAccountCreationRequested() }
            account = try client.addAccount()
        }
        
        self.account = account
        _ = balance()

        return account
    }
    
    func balance() -> Promise<Decimal> {
        if let account = account {
            let p = Promise<Decimal>()

            account.balance()
                .then { [weak self] kin in
                    self?.lastBalance = Balance(amount: kin)
                    p.signal(kin)
                }
                .error { error in
                    p.signal(error)
            }

            return p
        }
        else {
            return Promise(KinEcosystemError.client(.internalInconsistency, nil))
        }
    }

    func onboard() -> Promise<Void> {
        let p = Promise<Void>()

        if onboarded {
            return p.signal(())
        }

        balance()
            .then { _ in
                self.onboarded = true
                p.signal(())
            }
            .error { (bError) in
                if let error = bError as? KinError {
                    switch error {
                    case .missingAccount:
                        do {
                            try self.account?.watchCreation()
                                .then {
                                    self.account?.activate()
                                        .then {
                                            Kin.track { try StellarKinTrustlineSetupSucceeded() }
                                            Kin.track { try WalletCreationSucceeded() }
                                            self.onboarded = true
                                            p.signal(())
                                        }
                                        .error { error in
                                            Kin.track { try StellarKinTrustlineSetupFailed(errorReason: error.localizedDescription) }
                                            p.signal(error)
                                    }
                                }.error { error in
                                    Kin.track { try StellarKinTrustlineSetupFailed(errorReason: error.localizedDescription) }
                                    p.signal(error)
                            }
                        } catch {
                            p.signal(error)
                        }
                    case .missingBalance:
                        self.account?.activate()
                            .then { _ in
                                Kin.track { try StellarKinTrustlineSetupSucceeded() }
                                Kin.track { try WalletCreationSucceeded() }
                                self.onboarded = true
                                p.signal(())
                            }.error { error in
                                Kin.track { try StellarKinTrustlineSetupFailed(errorReason: error.localizedDescription) }
                                p.signal(error)
                        }
                    default:
                        p.signal(KinError.unknown)
                    }
                }
                else {
                    p.signal(bError)
                }
        }

        return p
    }


    func pay(to recipient: String, kin: Decimal, memo: String?, whitelist: @escaping WhitelistClosure) -> Promise<TransactionId> {
        guard let account = account else {
            return Promise(KinEcosystemError.client(.internalInconsistency, nil))
        }

        return account.sendTransaction(to: recipient, kin: kin, memo: memo, fee: 0, whitelist: whitelist)
    }

    func startWatchingForNewPayments(with memo: PaymentMemoIdentifier) throws {
        guard paymentsWatcher == nil else {
            logInfo("payment watcher already started, added watch for \(memo)...")
            paymentObservers[memo] = Observable<String>()
            return
        }
        paymentsWatcher = try account?.watchPayments(cursor: "now")
        paymentsWatcher?.emitter.on(next: { [weak self] paymentInfo in
            guard let metadata = paymentInfo.memoText else { return }
            guard let match = self?.paymentObservers.first(where: { (memoKey, _) -> Bool in
                memoKey.description == metadata
            })?.value else { return }
            logInfo("payment found in blockchain for \(metadata)...")
            match.next(paymentInfo.hash)
            match.finish()
        }).add(to: linkBag)
        logInfo("added watch for \(memo)...")
        paymentObservers[memo] = Observable<String>()
    }

    func stopWatchingForNewPayments(with memo: PaymentMemoIdentifier? = nil) {
        guard let memo = memo else {
            paymentObservers.removeAll()
            paymentsWatcher = nil
            logInfo("removed all payment observers")
            return
        }
        paymentObservers.removeValue(forKey: memo)
        if paymentObservers.count == 0 {
            paymentsWatcher = nil
        }
        logInfo("removed payment observer for \(memo)")
    }

    func waitForNewPayment(with memo: PaymentMemoIdentifier, timeout: TimeInterval = 300.0) -> Promise<String> {
        let p = Promise<String>()
        guard paymentObservers.keys.contains(where: { key -> Bool in
            key == memo
        }) else {
            return p.signal(BlockchainError.watchNotStarted)
        }
        var found = false
        paymentObservers[memo]?.on(next: { [weak self] txHash in
            found = true
            _ = self?.balance()
            p.signal(txHash)
        }).add(to: linkBag)
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
            if !found {
                p.signal(BlockchainError.watchTimedOut)
            }
        }
        return p
    }

    private func updateBalanceObservers() {
        guard let balance = lastBalance else { return }
        balanceObservers.values.forEach { block in
            block(balance)
        }
    }

    func addBalanceObserver(with block:@escaping (Balance) -> (), identifier: String? = nil) throws -> String {

        let observerIdentifier = identifier ?? UUID().uuidString
        balanceObservers[observerIdentifier] = block

        if balanceWatcher == nil {
            balanceWatcher = try account?.watchBalance(lastBalance?.amount)
            balanceWatcher?.emitter.on(next: { [weak self] amount in
                self?.lastBalance = Balance(amount: amount)
            }).add(to: linkBag)
        }
        if let balance = lastBalance {
            block(balance)
        }

        return observerIdentifier
    }

    func removeBalanceObserver(with identifier: String) {
        balanceObservers[identifier] = nil
        if balanceObservers.count == 0 {
            balanceWatcher?.emitter.unlink()
            balanceWatcher = nil
        }
    }
}

// MARK: Debugging

@available(iOS 9.0, *)
extension Blockchain {
    func deleteKeystore() {
        migrationManager.deleteKeystore()
    }
}
