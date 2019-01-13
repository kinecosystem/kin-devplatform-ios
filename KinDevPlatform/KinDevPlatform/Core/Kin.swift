//
//
//  Kin.swift
//
//  Created by Kin Foundation
//  Copyright © 2018 Kin Foundation. All rights reserved.
//
//  kinecosystem.org
//

import StellarErrors
import KinMigrationModule

let SDKVersion = "0.8.4"

public typealias ExternalOfferCallback = (String?, Error?) -> ()
public typealias OrderConfirmationCallback = (ExternalOrderStatus?, Error?) -> ()
public typealias MigrationVersionCallback = (KinVersion?, Error?) -> ()

public typealias KinVersion = KinMigrationModule.KinVersion

public enum ExternalOrderStatus {
    case pending
    case failed
    case completed(String)
}

public struct NativeOffer: Equatable {
    public let id: String
    public let title: String
    public let description: String
    public let amount: Int32
    public let image: String
    public let isModal: Bool
    public init(id: String,
                title: String,
                description: String,
                amount: Int32,
                image: String,
                isModal: Bool = false) {
        self.id = id
        self.title = title
        self.description = description
        self.amount = amount
        self.image = image
        self.isModal = isModal
    }
}

public protocol KinMigrationDelegate: NSObjectProtocol {
    func kinMigrationNeedsVersion(callback: @escaping MigrationVersionCallback)
    func kinMigrationDidStartMigration()
    func kinMigrationIsReady()
    func kinMigration(error: Error)
}

@available(iOS 9.0, *)
public class Kin: NSObject {
    public static let shared = Kin()

    public weak var migrationDelegate: KinMigrationDelegate?
    public var whitelistClosure: WhitelistClosure?

    fileprivate(set) var core: Core?
    fileprivate(set) var needsReset = false
    fileprivate weak var mpPresentingController: UIViewController?
    fileprivate var bi: BIClient!
    fileprivate var prestartBalanceObservers = [String : (Balance) -> ()]()
    fileprivate var prestartNativeOffers = [NativeOffer]()
    fileprivate let psBalanceObsLock = NSLock()
    fileprivate let psNativeOLock = NSLock()
    
    public var lastKnownBalance: Balance? {
        guard let core = Kin.shared.core else {
            return nil
        }
        return core.blockchain.lastBalance
    }
    
    public var publicAddress: String? {
        guard let core = Kin.shared.core else {
            return nil
        }
        return core.blockchain.account?.publicAddress
    }
    
    public var isActivated: Bool {
        guard let core = Kin.shared.core else {
            return false
        }
        return core.blockchain.onboarded && core.network.tosAccepted
    }
    
    public var nativeOfferHandler: ((NativeOffer) -> ())?
    
    static func track<T: KBIEvent>(block: () throws -> (T)) {
        do {
            let event = try block()
            try Kin.shared.bi.send(event)
        } catch {
            logError("failed to send event, error: \(error)")
        }
    }

    public var blockchainVersion: KinVersion? {
        return core?.blockchain.migrationManager.version
    }

    private var startData: StartData?
    
    public func start(userId: String,
                      apiKey: String? = nil,
                      appId appIdValue: String,
                      jwt: String? = nil,
                      environment: Environment) throws {
        guard core == nil else {
            return
        }
        bi = try BIClient(endpoint: URL(string: environment.BIURL)!)
        setupBIProxies()
        Kin.track { try KinSDKInitiated() }
        let lastUser = UserDefaults.standard.string(forKey: KinPreferenceKey.lastSignedInUser.rawValue)
        let lastEnvironmentName = UserDefaults.standard.string(forKey: KinPreferenceKey.lastEnvironment.rawValue)
        if lastUser != userId || (lastEnvironmentName != nil && lastEnvironmentName != environment.name) {
            needsReset = true
            logInfo("new user or environment type detected - resetting everything")
            UserDefaults.standard.set(false, forKey: KinPreferenceKey.firstSpendSubmitted.rawValue)
        }
        UserDefaults.standard.set(userId, forKey: KinPreferenceKey.lastSignedInUser.rawValue)
        UserDefaults.standard.set(environment.name, forKey: KinPreferenceKey.lastEnvironment.rawValue)
        guard   let modelPath = Bundle.ecosystem.path(forResource: "KinEcosystem",
                                                      ofType: "momd") else {
            logError("start failed")
            throw KinEcosystemError.client(.internalInconsistency, nil)
        }

        let store: EcosystemData
        let chain: Blockchain
        let appId: AppId

        do {
            appId = try AppId(appIdValue)
            store = try EcosystemData(modelName: "KinEcosystem",
                                      modelURL: URL(string: modelPath)!)
            chain = try Blockchain(environment: environment, appId: appId)
            chain.migrationManager.delegate = self
            try chain.migrationManager.start()
        } catch {
            logError("prepare start failed")
            throw KinEcosystemError.client(.internalInconsistency, nil)
        }

        startData = StartData(environment: environment,
                              userId: userId,
                              apiKey: apiKey,
                              appId: appId,
                              jwt: jwt,
                              store: store,
                              blockchain: chain)
    }

    private func `continue`(with account: KinAccountProtocol) throws {
        guard let startData = startData else {
            throw KinEcosystemError.client(.internalInconsistency, nil)
        }

        self.startData = nil

        guard let marketplaceURL = URL(string: startData.environment.marketplaceURL) else {
            throw KinEcosystemError.client(.badRequest, nil)
        }

        let config = EcosystemConfiguration(baseURL: marketplaceURL,
                                            apiKey: startData.apiKey,
                                            appId: startData.appId,
                                            userId: startData.userId,
                                            jwt: startData.jwt,
                                            publicAddress: account.publicAddress)

        let network = EcosystemNet(config: config)
        let core = try Core(environment: startData.environment,
                            network: network,
                            data: startData.store,
                            blockchain: startData.blockchain)

        self.core = core

        let tosAccepted = core.network.tosAccepted
        network.authorize().then { [weak self] _ in
            core.blockchain.onboard()
                .then {
                    logInfo("blockchain onboarded successfully")
                }
                .error { error in
                    logError("blockchain onboarding failed - \(error)")
            }
            self?.updateData(with: OffersList.self, from: "offers").error { error in
                logError("data sync failed (\(error))")
            }
            if tosAccepted {
                self?.updateData(with: OrdersList.self, from: "orders").error { error in
                    logError("data sync failed (\(error))")
                }
            }
        }
        psBalanceObsLock.lock()
        defer {
            psBalanceObsLock.unlock()
        }
        try prestartBalanceObservers.forEach { (arg) in
            let (identifier, block) = arg
            _ = try core.blockchain.addBalanceObserver(with: block, identifier: identifier)
        }
        prestartBalanceObservers.removeAll()
        psNativeOLock.lock()
        defer {
            psNativeOLock.unlock()
        }
        try prestartNativeOffers.forEach({ offer in
            try add(nativeOffer: offer)
        })
        prestartNativeOffers.removeAll()
    }
    
    public func balance(_ completion: @escaping (Balance?, Error?) -> ()) {
        guard let core = core else {
            logError("Kin not started")
            completion(nil, KinEcosystemError.client(.notStarted, nil))
            return
        }
        core.blockchain.balance().then(on: DispatchQueue.main) { balance in
            completion(Balance(amount: balance), nil)
            }.error { error in
                let esError: KinEcosystemError
                switch error {
                    case KinError.internalInconsistency,
                         KinError.accountDeleted:
                        esError = KinEcosystemError.client(.internalInconsistency, error)
                    case KinError.balanceQueryFailed(let queryError):
                        switch queryError {
                        case StellarError.missingAccount:
                            esError = KinEcosystemError.blockchain(.notFound, error)
                        case StellarError.missingBalance:
                            esError = KinEcosystemError.blockchain(.activation, error)
                        case StellarError.unknownError:
                            esError = KinEcosystemError.unknown(.unknown, error)
                        default:
                            esError = KinEcosystemError.unknown(.unknown, error)
                        }
                    default:
                        esError = KinEcosystemError.unknown(.unknown, error)
                }
                completion(nil, esError)
        }
    }
    
    public func addBalanceObserver(with block:@escaping (Balance) -> ()) throws -> String {
        guard let core = core else {
            psBalanceObsLock.lock()
            defer {
                psBalanceObsLock.unlock()
            }
            let observerIdentifier = UUID().uuidString
            prestartBalanceObservers[observerIdentifier] = block
            return observerIdentifier
        }
        return try core.blockchain.addBalanceObserver(with: block)
    }
    
    public func removeBalanceObserver(_ identifier: String) {
        guard let core = core else {
            psBalanceObsLock.lock()
            defer {
                psBalanceObsLock.unlock()
            }
            prestartBalanceObservers[identifier] = nil
            return
        }
        core.blockchain.removeBalanceObserver(with: identifier)
    }
        
    
    public func launchMarketplace(from parentViewController: UIViewController) {
        Kin.track { try EntrypointButtonTapped() }
        guard let core = core else {
            logError("Kin not started")
            return
        }
        mpPresentingController = parentViewController
        if core.network.tosAccepted {
            let mpViewController = MarketplaceViewController(nibName: "MarketplaceViewController", bundle: Bundle.ecosystem)
            mpViewController.core = core
            let navigationController = KinNavigationViewController(nibName: "KinNavigationViewController",
                                                                   bundle: Bundle.ecosystem,
                                                                   rootViewController: mpViewController)
            navigationController.core = core
            parentViewController.present(navigationController, animated: true)
        } else {
            let welcomeVC = WelcomeViewController(nibName: "WelcomeViewController", bundle: Bundle.ecosystem)
            welcomeVC.core = core
            parentViewController.present(welcomeVC, animated: true)
        }
        
    }

    public func purchase(offerJWT: String, completion: @escaping ExternalOfferCallback) -> Bool {
        guard let core = core else {
            logError("Kin not started")
            completion(nil, KinEcosystemError.client(.notStarted, nil))
            return false
        }
        defer {
            Flows.nativeSpend(jwt: offerJWT, core: core).then { jwt in
                completion(jwt, nil)
                }.error { error in
                    completion(nil, KinEcosystemError.transform(error))
            }
        }
        return true
    }
    
    public func payToUser(offerJWT: String, completion: @escaping ExternalOfferCallback) -> Bool {
        guard let core = core else {
            logError("Kin not started")
            completion(nil, KinEcosystemError.client(.notStarted, nil))
            return false
        }
        defer {
            Flows.nativeSpend(jwt: offerJWT, core: core).then { jwt in
                completion(jwt, nil)
                }.error { error in
                    completion(nil, KinEcosystemError.transform(error))
            }
        }
        return true
    }
    
    public func requestPayment(offerJWT: String, completion: @escaping ExternalOfferCallback) -> Bool {
        guard let core = core else {
            logError("Kin not started")
            completion(nil, KinEcosystemError.client(.notStarted, nil))
            return false
        }
        defer {
            Flows.nativeEarn(jwt: offerJWT, core: core).then { jwt in
                completion(jwt, nil)
                }.error { error in
                    completion(nil, KinEcosystemError.transform(error))
            }
        }
        return true
    }
    
    public func orderConfirmation(for offerID: String, completion: @escaping OrderConfirmationCallback) {
        guard let core = core else {
            logError("Kin not started")
            completion(nil, KinEcosystemError.client(.notStarted, nil))
            return
        }
        core.network.authorize().then { [weak self] (_) -> Promise<Void> in
            guard let this = self else {
                return Promise<Void>().signal(KinError.internalInconsistency)
            }
            return this.updateData(with: OrdersList.self, from: "orders")
            }.then { _ in
                core.data.queryObjects(of: Order.self, with: NSPredicate(with: ["offer_id":offerID]), queryBlock: { orders in
                    guard let order = orders.first else {
                        let responseError = ResponseError(code: 4043, error: "NotFound", message: "Order not found")
                        completion(nil, KinEcosystemError.service(.response, responseError))
                        return
                    }
                    switch order.orderStatus {
                    case .pending,
                         .delayed:
                       completion(.pending, nil)
                    case .completed:
                        guard let jwt = (order.result as? JWTConfirmation)?.jwt else {
                            completion(nil, KinEcosystemError.client(.internalInconsistency, nil))
                            return
                        }
                        completion(.completed(jwt), nil)
                    case .failed:
                        completion(.failed, nil)
                    }
                })
            }.error { error in
                completion(nil, KinEcosystemError.transform(error))
        }
    }
    
    public func setLogLevel(_ level: LogLevel) {
        Logger.setLogLevel(level)
    }
    
    public func add(nativeOffer: NativeOffer) throws {
        guard let core = core else {
            psNativeOLock.lock()
            defer {
                psNativeOLock.unlock()
            }
            prestartNativeOffers.append(nativeOffer)
            return
        }
        var offerExists = false
        core.data.queryObjects(of: Offer.self, with: NSPredicate(with: ["id":nativeOffer.id])) { offers in
            offerExists = offers.count > 0
            }.then {
                guard offerExists == false else { return }
                core.data.stack.perform({ (context, _) in
                    let _ = try? Offer(with: nativeOffer, in: context)
                })
        }
    }
    
    public func remove(nativeOfferId: String) throws {
        guard let core = core else {
            psNativeOLock.lock()
            defer {
                psNativeOLock.unlock()
            }
            prestartNativeOffers = prestartNativeOffers.filter({ offer -> Bool in
                offer.id != nativeOfferId
            })
            return
        }
        _ = core.data.changeObjects(of: Offer.self, changeBlock: { context, offers in
            if let offer = offers.first {
                context.delete(offer)
            }
        }, with: NSPredicate(with: ["id":nativeOfferId]))
    }
    
    func updateData<T: EntityPresentor>(with dataPresentorType: T.Type, from path: String) -> Promise<Void> {
        guard let core = core else {
            logError("Kin not started")
            return Promise<Void>().signal(KinEcosystemError.client(.notStarted, nil))
        }
        return core.network.dataAtPath(path).then { data in
            return self.core!.data.sync(dataPresentorType, with: data)
        }
    }
    
    func closeMarketPlace(completion: (() -> ())? = nil) {
        mpPresentingController?.dismiss(animated: true, completion: completion)
    }
    
    fileprivate func setupBIProxies() {
        EventsStore.shared.userProxy = UserProxy(balance: { [weak self] () -> (Double) in
            guard let balance = self?.core?.blockchain.lastBalance else {
                return 0
            }
            return NSDecimalNumber(decimal: balance.amount).doubleValue
            }, digitalServiceID: { [weak self] () -> (String) in
                guard let appId = self?.core?.network.client.authToken?.app_id else {
                    if let startAppid = self?.core?.network.client.config.appId {
                        return startAppid.value
                    }
                    return ""
                }
                return appId
            }, digitalServiceUserID: { [weak self] () -> (String) in
                guard let uid = self?.core?.network.client.authToken?.user_id else {
                    if let startUid = self?.core?.network.client.config.userId {
                        return startUid
                    } else if let lastUser = UserDefaults.standard.string(forKey: KinPreferenceKey.lastSignedInUser.rawValue) {
                        return lastUser
                    }
                    return ""
                }
                return uid
            }, earnCount: { () -> (Int) in
                0
        }, entryPointParam: { () -> (String) in
            ""
        }, spendCount: { () -> (Int) in
            0
        }, totalKinEarned: { () -> (Double) in
            0
        }, totalKinSpent: { () -> (Double) in
            0
        }, transactionCount: { () -> (Int) in
            0
        })
        
        EventsStore.shared.clientProxy = ClientProxy(carrier: { [weak self] () -> (String) in
            return self?.bi.networkInfo.subscriberCellularProvider?.carrierName ?? ""
            }, deviceID: { () -> (String) in
                DeviceData.deviceId
            }, deviceManufacturer: { () -> (String) in
                "Apple"
        }, deviceModel: { () -> (String) in
            UIDevice.current.model
        }, language: { () -> (String) in
            Locale.autoupdatingCurrent.languageCode ?? ""
        }, os: { () -> (String) in
            UIDevice.current.systemVersion
        })
        
        EventsStore.shared.commonProxy = CommonProxy(eventID: { () -> (String) in
            UUID().uuidString
        }, platform: { () -> (String) in
            "iOS"
        }, timestamp: { () -> (String) in
            "\(Date().timeIntervalSince1970)"
        }, userID: { [weak self] () -> (String) in
            self?.core?.network.client.authToken?.ecosystem_user_id ?? ""
            }, version: { () -> (String) in
                SDKVersion
        })
    }
}

@available(iOS 9.0, *)
extension Kin {
    fileprivate struct StartData {
        let environment: Environment
        let userId: String
        let apiKey: String?
        let appId: AppId
        let jwt: String?
        let store: EcosystemData
        let blockchain: Blockchain
    }
}

@available(iOS 9.0, *)
extension Kin: KinMigrationManagerDelegate {
    public func kinMigrationManagerNeedsVersion(_ kinMigrationManager: KinMigrationManager) -> Promise<KinVersion> {
        guard let migrationDelegate = migrationDelegate else {
            fatalError("The `migrationDelegate` needs to be set.")
        }

        let promise = Promise<KinVersion>()

        migrationDelegate.kinMigrationNeedsVersion() { (kinVersion, error) in
            if let kinVersion = kinVersion {
                promise.signal(kinVersion)
            }
            else if let error = error {
                promise.signal(error)
            }
            else {
                promise.signal(KinEcosystemError.client(.internalInconsistency, nil))
            }
        }

        return promise
    }

    public func kinMigrationManagerDidStart(_ kinMigrationManager: KinMigrationManager) {
        migrationDelegate?.kinMigrationDidStartMigration()
    }

    public func kinMigrationManager(_ kinMigrationManager: KinMigrationManager, readyWith client: KinClientProtocol) {
        do {
            if let account = try startData?.blockchain.startAccount(with: client) {
                try `continue`(with: account)
            }
        }
        catch {
            logError("start failed")
        }

        migrationDelegate?.kinMigrationIsReady()
    }

    public func kinMigrationManager(_ kinMigrationManager: KinMigrationManager, error: Error) {
        logError(error.localizedDescription)

        migrationDelegate?.kinMigration(error: error)
    }
}
