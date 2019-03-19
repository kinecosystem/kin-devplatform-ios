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

public typealias KinVersion = KinMigrationModule.KinVersion

let SDKVersion = "1.0.6"

public typealias ExternalOfferCallback = (String?, Error?) -> ()
public typealias OrderConfirmationCallback = (ExternalOrderStatus?, Error?) -> ()
public typealias MigrationVersionCallback = (KinVersion?, Error?) -> ()

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
    func kinMigrationDidStart()
    func kinMigrationDidFinish()
    func kinMigrationIsReady()
    func kinMigration(error: Error)
}

@available(iOS 9.0, *)
public class Kin: NSObject {
    public static let shared = Kin()

    public weak var migrationDelegate: KinMigrationDelegate?

    fileprivate(set) var core: Core?
    fileprivate(set) var needsReset = false
    fileprivate weak var mpPresentingController: UIViewController?
    fileprivate var bi: BIClient!
    fileprivate var prestartBalanceObservers = [String : (Balance) -> ()]()
    fileprivate var prestartNativeOffers = [NativeOffer]()
    fileprivate let psBalanceObsLock = NSLock()
    fileprivate let psNativeOLock = NSLock()
    fileprivate var didStartMigration = false

    fileprivate var onboardPromise: Promise<Void>?

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

    /**
     The blockchain version being used.

     After calling `Kin.start()` and the `kinMigrationIsReady()` delegate is called,
     this property will return the value of the chosen blockchain.

     - Returns: `nil` if the migration module is not ready, a `KinVersion` otherwise.
     */
    public var blockchainVersion: KinVersion? {
        return core?.blockchain.migrationManager.version
    }

    /**
     Did the migration happen.

     After calling `Kin.start()` and the `kinMigrationIsReady()` delegate is called,
     this property will return a `Bool`.

     - Returns: `nil` if the migration module is not ready, a `Bool` otherwise.
     */
    public var isMigrated: Bool? {
        return core?.blockchain.migrationManager.isMigrated
    }

    private var startData: StartData?
    
    public func start(userId: String,
                      apiKey: String? = nil,
                      appId appIdValue: String,
                      jwt: String? = nil,
                      environment: Environment) throws
    {
        core = nil
        bi = try BIClient(endpoint: URL(string: environment.BIURL)!)
        setupBIProxies(appIdValue: appIdValue, userId: userId)
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

        do {
            let appId = try AppId(appIdValue)
            let store = try EcosystemData(modelName: "KinEcosystem", modelURL: URL(string: modelPath)!)
            let serviceProvider = try environment.mapToMigrationModuleServiceProvider()

            let chain = try Blockchain(serviceProvider: serviceProvider, appId: appId)
            chain.migrationManager.delegate = self
            chain.migrationManager.biDelegate = self

            startData = StartData(environment: environment,
                                  userId: userId,
                                  apiKey: apiKey,
                                  appId: appId,
                                  jwt: jwt,
                                  store: store,
                                  blockchain: chain)

            try chain.migrationManager.start()
        }
        catch {
            logError("prepare start failed")
            throw KinEcosystemError.client(.internalInconsistency, nil)
        }
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

        onboardPromise = network.authorize()
            .then { _ in
                core.blockchain.onboard()
                    .then {
                        logInfo("blockchain onboarded successfully")
                    }
                    .error { error in
                        logError("blockchain onboarding failed - \(error)")
                }
            }
            .then {
                core.network.acceptTOS()
                    .then {
                        logInfo("accepted tos successfully")
                    }
                    .error { error in
                        if case let EcosystemNetError.server(errString) = error {
                            logError("server returned bad answer: \(errString)")
                        } else {
                            logError("accepted tos failed - \(error)")
                        }
                }
            }
            .then { [weak self] _ in
                self?.updateData(with: OrdersList.self, from: "orders").error { error in
                    logError("data sync failed (\(error))")
                }
                self?.updateData(with: OffersList.self, from: "offers").error { error in
                    logError("data sync failed (\(error))")
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
    
    fileprivate func setupBIProxies(appIdValue: String, userId: String) {
        EventsStore.shared.userProxy = UserProxy(balance: { [weak self] () -> (Double) in
            guard let balance = self?.core?.blockchain.lastBalance else {
                return 0
            }
            return NSDecimalNumber(decimal: balance.amount).doubleValue
            }, digitalServiceID: { [weak self] () -> (String) in
                return self?.core?.network.client.authToken?.app_id ?? appIdValue
            }, digitalServiceUserID: { [weak self] () -> (String) in
                return self?.core?.network.client.authToken?.user_id ?? userId
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
        guard let appId = startData?.appId, let environment = startData?.environment else {
            return Promise(KinEcosystemError.client(.internalInconsistency, nil))
        }

        let promise = Promise<KinVersion>()
        let url = URL(string: "\(environment.marketplaceURL)/config/blockchain/\(appId.value)")!

        URLSession.shared.dataTask(with: url) { (data, _, error) in
            if let error = error {
                promise.signal(error)
                return
            }

            if let data = data,
                let dataString = String(data: data, encoding: .utf8),
                let dataInt = Int(dataString),
                let kinVersion = KinVersion(rawValue: dataInt)
            {
                promise.signal(kinVersion)
            }
            else {
                promise.signal(KinEcosystemError.client(.invalidSDKVersion, nil))
            }
        }.resume()

        return promise
    }

    public func kinMigrationManagerDidStart(_ kinMigrationManager: KinMigrationManager) {
        didStartMigration = true
        migrationDelegate?.kinMigrationDidStart()
    }

    public func kinMigrationManager(_ kinMigrationManager: KinMigrationManager, readyWith client: KinClientProtocol) {
        needsReset = client.accounts.count > 1
        onboardPromise = nil

        do {
            if let account = try startData?.blockchain.startAccount(with: client) {
                try `continue`(with: account)
            }
        }
        catch {
            logError("start failed")
        }

        if didStartMigration {
            didStartMigration = false
            migrationDelegate?.kinMigrationDidFinish()
        }

        if onboardPromise == nil {
            migrationDelegate?.kinMigrationIsReady()
        }
        else {
            onboardPromise?.then(on: .main, { _ in
                self.migrationDelegate?.kinMigrationIsReady()
            })
        }
    }

    public func kinMigrationManager(_ kinMigrationManager: KinMigrationManager, error: Error) {
        logError(error.localizedDescription)

        migrationDelegate?.kinMigration(error: error)
    }
}

@available(iOS 9.0, *)
extension Kin: KinMigrationBIDelegate {
    public func kinMigrationMethodStarted() {
        Kin.track { try MigrationMethodStarted() }
    }

    public func kinMigrationCallbackStart() {
        Kin.track { try MigrationCallbackStart() }
    }

    public func kinMigrationCallbackReady(reason: KinMigrationBIReadyReason, version: KinVersion) {
        Kin.track { try MigrationCallbackReady(sdkVersion: version.mapToKBI, selectedSDKReason: reason.mapToKBI) }
    }

    public func kinMigrationCallbackFailed(error: Error) {
        Kin.track { try MigrationCallbackFailed(errorCode: "", errorMessage: error.localizedDescription, errorReason: "") }
    }

    public func kinMigrationVersionCheckStarted() {
        Kin.track { try MigrationVersionCheckStarted() }
    }

    public func kinMigrationVersionCheckSucceeded(version: KinVersion) {
        Kin.track { try MigrationVersionCheckSucceeded(sdkVersion: version.mapToKBI) }
    }

    public func kinMigrationVersionCheckFailed(error: Error) {
        Kin.track { try MigrationVersionCheckFailed(errorCode: "", errorMessage: error.localizedDescription, errorReason: "") }
    }

    public func kinMigrationBurnStarted(publicAddress: String) {
        Kin.track { try MigrationBurnStarted(publicAddress: publicAddress) }
    }

    public func kinMigrationBurnSucceeded(reason: KinMigrationBIBurnReason, publicAddress: String) {
        Kin.track { try MigrationBurnSucceeded(burnReason: reason.mapToKBI, publicAddress: publicAddress) }
    }

    public func kinMigrationBurnFailed(error: Error, publicAddress: String) {
        Kin.track { try MigrationBurnFailed(errorCode: "", errorMessage: error.localizedDescription, errorReason: "", publicAddress: publicAddress) }
    }

    public func kinMigrationRequestAccountMigrationStarted(publicAddress: String) {
        Kin.track { try MigrationRequestAccountMigrationStarted(publicAddress: publicAddress) }
    }

    public func kinMigrationRequestAccountMigrationSucceeded(reason: KinMigrationBIMigrateReason, publicAddress: String) {
        Kin.track { try MigrationRequestAccountMigrationSucceeded(migrationReason: reason.mapToKBI, publicAddress: publicAddress) }
    }

    public func kinMigrationRequestAccountMigrationFailed(error: Error, publicAddress: String) {
        Kin.track { try MigrationRequestAccountMigrationFailed(errorCode: "", errorMessage: error.localizedDescription, errorReason: "", publicAddress: publicAddress) }
    }
}

// MARK: Migration

@available(iOS 9.0, *)
extension Kin {
    struct BlockchainVersion {
        let version: KinVersion?

        init(_ version: KinVersion?) {
            self.version = version
        }

        init(_ version: String?) {
            if let versionString = version,
                let versionInt = Int(versionString),
                let v = KinVersion(rawValue: versionInt)
            {
                self.version = v
            }
            else {
                self.version = nil
            }
        }
    }

    enum MigrationAlert: String {
        case `default` = "Kin is being upgraded, you will be able to complete the operation after you force close the app and restart."
        case saved = "Kin is being upgraded, you will be able to complete the operation after you force close the app and restart.\n\nYour Kin will appear after the upgrade is complete."
    }

    static func needsToMigrate(_ blockchainVersionA: BlockchainVersion, _ blockchainVersionB: BlockchainVersion) -> Bool {
        if let blockchainVersionA = blockchainVersionA.version,
            let blockchainVersionB = blockchainVersionB.version,
            blockchainVersionA != blockchainVersionB
        {
            return true
        }
        return false
    }

    static func presentMigrationAlertIfNeeded(alert: MigrationAlert) {
        func presentMigrationAlert() {
            let alertController = UIAlertController(title: "Upgrading Kin", message: alert.rawValue, preferredStyle: .alert)
            alertController.addAction(UIAlertAction(title: "Ok", style: .cancel))
            topViewController()?.present(alertController, animated: true)
        }

        if Thread.isMainThread {
            presentMigrationAlert()
        }
        else {
            DispatchQueue.main.async {
                presentMigrationAlert()
            }
        }
    }

    private static func topViewController(controller: UIViewController? = UIApplication.shared.keyWindow?.rootViewController) -> UIViewController? {
        if let navigationController = controller as? UINavigationController {
            return topViewController(controller: navigationController.visibleViewController)
        }
        if let tabController = controller as? UITabBarController {
            if let selected = tabController.selectedViewController {
                return topViewController(controller: selected)
            }
        }
        if let presented = controller?.presentedViewController {
            return topViewController(controller: presented)
        }
        return controller
    }
}

// MARK: Debugging

@available(iOS 9.0, *)
extension Kin {
    public func deleteKeystoreIfPossible() {
        core?.blockchain.deleteKeystore()
    }
}
