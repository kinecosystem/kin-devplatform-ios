//  ViewController.swift
//  EcosystemSampleApp
//
//  Created by Elazar Yifrach on 14/02/2018.
//  Copyright © 2018 Kik Interactive. All rights reserved.
//

import UIKit
import KinDevPlatform
import JWT
import KinUtil

class SampleAppViewController: UIViewController, UITextFieldDelegate {
    
    @IBOutlet weak var continueButton: UIButton!
    @IBOutlet weak var currentUserLabel: UILabel!
    @IBOutlet weak var newUserButton: UIButton!
    @IBOutlet weak var buyStickerButton: UIButton!
    @IBOutlet weak var titleLabel: UILabel!

    fileprivate var operationPromise: Promise<Void>?
    let loader = UIActivityIndicatorView(style: .whiteLarge)
    var lastOfferId: String? = nil

    let environment: Environment = .playground

    var appKey: String? {
        return configValue(for: "appKey", of: String.self)
    }
    
    var appId: String? {
        return configValue(for: "appId", of: String.self)
    }
    
    var useJWT: Bool {
        return configValue(for: "IS_JWT_REGISTRATION", of: Bool.self) ?? false
    }
    
    var privateKey: String? {
        return configValue(for: "RS512_PRIVATE_KEY", of: String.self)
    }
    
    var lastUser: String {
        get {
            if let user = UserDefaults.standard.string(forKey: "SALastUser") {
                return user
            }
            let first = "user_\(arc4random_uniform(99999))_0"
            UserDefaults.standard.set(first, forKey: "SALastUser")
            return first
        }
    }
    
    func configValue<T>(for key: String, of type: T.Type) -> T? {
        if  let path = Bundle.main.path(forResource: "defaultConfig", ofType: "plist"),
            let value = NSDictionary(contentsOfFile: path)?[key] as? T {
            return value
        }
        return nil
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        currentUserLabel.text = lastUser
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
        titleLabel.text = "\(version) (\(build))"

        Kin.shared.migrationDelegate = self

        loader.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        loader.translatesAutoresizingMaskIntoConstraints = false
        loader.isHidden = true
        view.addSubview(loader)
        loader.topAnchor.constraint(equalTo: view.topAnchor).isActive = true
        loader.leadingAnchor.constraint(equalTo: view.leadingAnchor).isActive = true
        loader.bottomAnchor.constraint(equalTo: view.bottomAnchor).isActive = true
        loader.trailingAnchor.constraint(equalTo: view.trailingAnchor).isActive = true
    }
    
    func alertConfigIssue() {
        let alert = UIAlertController(title: "Config Missing", message: "an app id and app key (or a jwt) is required in order to use the sample app. Please refer to the readme in the sample app repo for more information", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Oh ok", style: .cancel, handler: { [weak alert] action in
            alert?.dismiss(animated: true, completion: nil)
        }))
        self.present(alert, animated: true, completion: nil)
    }
    
    @IBAction func newUserTapped(_ sender: Any) {
        let numberIndex = lastUser.index(after: lastUser.range(of: "_", options: [.backwards])!.lowerBound)
        let plusone = Int(lastUser.suffix(from: numberIndex))! + 1
        let newUser = String(lastUser.prefix(upTo: numberIndex) + "\(plusone)")
        UserDefaults.standard.set(newUser, forKey: "SALastUser")
        currentUserLabel.text = lastUser
        let alert = UIAlertController(title: "Please Restart", message: "A new user was created.", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Oh ok", style: .cancel, handler: { action in
            exit(0)
        }))
        self.present(alert, animated: true, completion: nil)
        
    }
    
    @IBAction func continueTapped(_ sender: Any) {
        guard let id = appId else {
            alertConfigIssue()
            return
        }

        func launch() {
            showLoader()

            operationPromise = Promise().then {
                self.hideLoader()
                self.launchMarketplace()
            }
        }

        if useJWT {
            do {
                try jwtLoginWith(lastUser, appId: id)
                launch()
            } catch {
                alertStartError(error)
            }
        } else {
            guard let key = appKey else {
                alertConfigIssue()
                return
            }
            do {
                try start(user: lastUser, apiKey: key, appId: id)
                launch()
            } catch {
                alertStartError(error)
            }
        }
    }
    
    func jwtLoginWith(_ user: String, appId: String) throws {
        guard  let jwtPKey = privateKey else {
            alertConfigIssue()
            return
        }

        // NOTE: This condition is for testing purposes.
        // Always use the playground environment with this sample app.
        if environment.name == Environment.production.name {
            requestJWT(user, request : "/register/token?user_id=\(user)") { jwt in
                do {
                    try self.start(user: user, appId: appId, jwt: jwt)
                }
                catch {
                    print (error)
                }
            }
        }
        else {
            guard let encoded = JWTUtil.encode(header: ["alg": "RS512",
                                                        "typ": "jwt",
                                                        "kid" : "rs512_0"],
                                               body: ["user_id":user],
                                               subject: "register",
                                               id: appId, privateKey: jwtPKey) else {
                                                alertConfigIssue()
                                                return
            }

            try start(user: user, appId: appId, jwt: encoded)
        }
    }

    private func start(user: String, apiKey: String? = nil, appId: String, jwt: String? = nil) throws {
        try Kin.shared.start(userId: user, appId: appId, jwt: jwt, environment: environment)
    }

    fileprivate func launchMarketplace() {
        let offer = NativeOffer(id: "wowowo12345",
                                title: "Renovate!",
                                description: "Your new home",
                                amount: 1000,
                                image: "https://www.makorrishon.co.il/nrg/images/archive/300x225/270/557.jpg",
                                isModal: true)
        do {
            try Kin.shared.add(nativeOffer: offer)
        } catch {
            print("failed to add native offer, error: \(error)")
        }
        Kin.shared.nativeOfferHandler = { offer in
            DispatchQueue.main.async {
                let alert = UIAlertController(title: "Native Offer", message: "You tapped a native offer and the handler was invoked.", preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "Close", style: .cancel, handler: { [weak alert] action in
                    alert?.dismiss(animated: true, completion: nil)
                }))

                let presentor = self.presentedViewController ?? self
                presentor.present(alert, animated: true, completion: nil)
            }
        }
        Kin.shared.launchMarketplace(from: self)
    }
    
    fileprivate func alertStartError(_ error: Error) {
        let alert = UIAlertController(title: "Start failed", message: "Error: \(error)", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Oh ok", style: .cancel, handler: { [weak alert] action in
            alert?.dismiss(animated: true, completion: nil)
        }))
        self.present(alert, animated: true, completion: nil)
    }

    @IBAction func buyStickerTapped(_ sender: Any) {
        
        guard   let id = appId,
            let jwtPKey = privateKey else {
                alertConfigIssue()
                return
        }

        let offerID = "WOWOMGCRAZY"+"\(arc4random_uniform(999999))"
        lastOfferId = offerID

        buyStickerButton.isEnabled = false
        showLoader()

        func purchase(offerJWT: String) {
            _ = Kin.shared.purchase(offerJWT: offerJWT) { jwtConfirmation, error in
                DispatchQueue.main.async { [weak self] in
                    self?.buyStickerButton.isEnabled = true
                    self?.hideLoader()
                    let alert = UIAlertController(title: nil, message: nil, preferredStyle: .alert)
                    if let confirm = jwtConfirmation {
                        alert.title = "Success"
                        alert.message = "Purchase complete. You can view the confirmation on jwt.io"
                        alert.addAction(UIAlertAction(title: "View on jwt.io", style: .default, handler: { [weak alert] action in
                            let url = URL(string:"https://jwt.io/#debugger-io?token=\(confirm)")!
                            UIApplication.shared.open(url, options: [:])
                            alert?.dismiss(animated: true, completion: nil)
                        }))
                    } else if let e = error {
                        alert.title = "Failure"
                        alert.message = "Purchase failed (\(e.localizedDescription))"
                    }

                    alert.addAction(UIAlertAction(title: "Close", style: .cancel, handler: { [weak alert] action in
                        alert?.dismiss(animated: true, completion: nil)
                    }))

                    self?.present(alert, animated: true, completion: nil)
                }
            }
        }

        // NOTE: This condition is for testing purposes.
        // Always use the playground environment with this sample app.
        if environment.name == Environment.production.name {
            let spendOffer = [
                "subject" : "spend",
                "payload" : [
                    "offer" : [
                        "id" : offerID,
                        "amount" : 10
                    ],
                    "sender" : [
                        "user_id" : lastUser,
                        "title" : "Native Spend",
                        "description" : "A native spend example"
                    ]
                ],
                ] as [String : Any]

            let requestData = jsonToData(json: spendOffer)
            if (requestData != nil) {
                signJWT(requestData!){ jwt in
                    self.operationPromise = Promise().then {
                        purchase(offerJWT: jwt)
                    }

                    do {
                        try self.jwtLoginWith(self.lastUser, appId: id)
                    } catch {
                        self.alertStartError(error)
                    }
                }
            }
        }
        else {
            guard let encoded = JWTUtil.encode(header: ["alg": "RS512",
                                                        "typ": "jwt",
                                                        "kid" : "rs512_0"],
                                               body: ["offer":["id":offerID, "amount":10],
                                                      "sender": ["title":"Native Spend",
                                                                 "description":"A native spend example",
                                                                 "user_id":lastUser]],
                                               subject: "spend",
                                               id: id, privateKey: jwtPKey) else {
                                                alertConfigIssue()
                                                return
            }

            operationPromise = Promise().then {
                purchase(offerJWT: encoded)
            }

            do {
                try jwtLoginWith(lastUser, appId: id)
            } catch {
                alertStartError(error)
            }
        }
    }

    @IBAction func payToUserTapped(_ sender: Any) {

        let amount = 10

        guard let appId = appId, let jwtPKey = privateKey else {
            alertConfigIssue()
            return
        }

        let offerID = "WOWOMGCRAZY"+"\(arc4random_uniform(999999))"
        lastOfferId = offerID

        showLoader()

        func payToUser(offerJWT: String, receipientUserId: String) {
            _ = Kin.shared.payToUser(offerJWT: offerJWT) { jwtConfirmation, error in
                DispatchQueue.main.async { [weak self] in
                    self?.buyStickerButton.isEnabled = true
                    self?.hideLoader()
                    let alert = UIAlertController(title: nil, message: nil, preferredStyle: .alert)
                    if let confirm = jwtConfirmation {
                        alert.title = "Pay To User - Success"
                        alert.message = "You sent to: \(receipientUserId)\nAmount: \(amount)\nYou can view the confirmation on jwt.io"
                        alert.addAction(UIAlertAction(title: "View on jwt.io", style: .default, handler: { [weak alert] action in
                            let url = URL(string:"https://jwt.io/#debugger-io?token=\(confirm)")!
                            UIApplication.shared.open(url, options: [:])
                            alert?.dismiss(animated: true, completion: nil)
                        }))
                    } else if let e = error {
                        alert.title = "Failure"
                        alert.message = "Pay To User failed: (\(e.localizedDescription))"
                    }

                    alert.addAction(UIAlertAction(title: "Close", style: .cancel, handler: { [weak alert] action in
                        alert?.dismiss(animated: true, completion: nil)
                    }))

                    self?.present(alert, animated: true, completion: nil)
                }
            }
        }

        // NOTE: This condition is for testing purposes.
        // Always use the playground environment with this sample app.
        if environment.name == Environment.production.name {
            let receipientUserId = "user_26121_0"

            let payToUserOffer = [
                "subject" : "pay_to_user",
                "payload" : [
                    "offer" : [
                        "id" : offerID,
                        "amount" : amount
                    ],
                    "sender" : [
                        "user_id" : lastUser,
                        "title" : "Pay To User",
                        "description" : "A P2P example"
                    ],
                    "recipient": [
                        "user_id": receipientUserId,
                        "title": "Received Kin",
                        "description": "A P2P example"
                    ]
                ],
                ] as [String : Any]

            let requestData = jsonToData(json: payToUserOffer)
            if (requestData != nil) {
                signJWT(requestData!){ jwt in
                    self.operationPromise = Promise().then {
                        payToUser(offerJWT: jwt, receipientUserId: receipientUserId)
                    }

                    do {
                        try self.jwtLoginWith(self.lastUser, appId: appId)
                    } catch {
                        self.alertStartError(error)
                    }
                }
            }
        }
        else {
            let receipientUserId = "user_37786_2"

            guard let encoded = JWTUtil.encode(header: ["alg": "RS512",
                                                        "typ": "jwt",
                                                        "kid" : "rs512_0"],
                                               body: ["offer":["id": offerID, "amount": amount],
                                                      "sender":
                                                        ["title":"Pay To User",
                                                         "description":"A P2P example",
                                                         "user_id":lastUser],
                                                      "recipient":
                                                        ["title":"Received Kin",
                                                         "description":"A P2P example",
                                                         "user_id": receipientUserId]],
                                               subject: "pay_to_user",
                                               id: appId,
                                               privateKey: jwtPKey) else {
                                                alertConfigIssue()
                                                return
            }

            operationPromise = Promise().then {
                payToUser(offerJWT: encoded, receipientUserId: receipientUserId)
            }

            do {
                try jwtLoginWith(lastUser, appId: appId)
            } catch {
                alertStartError(error)
            }
        }
    }

    @IBAction func nativeEarnTapped(_ sender: Any) {
        let amount = 10
        let offerID = "WOWOMGCRAZY"+"\(arc4random_uniform(999999))"
        lastOfferId = offerID

        guard let appId = appId, let jwtPKey = privateKey else {
            alertConfigIssue()
            return
        }

        showLoader()

        func requestPayment(offerJWT: String) {
            _ = Kin.shared.requestPayment(offerJWT: offerJWT) { jwtConfirmation, error in
                DispatchQueue.main.async { [weak self] in
                    self?.buyStickerButton.isEnabled = true
                    self?.hideLoader()
                    let alert = UIAlertController(title: nil, message: nil, preferredStyle: .alert)
                    if let confirm = jwtConfirmation {
                        alert.title = "Native Earn - Success"
                        alert.message = "Amount: \(amount)\nYou can view the confirmation on jwt.io"
                        alert.addAction(UIAlertAction(title: "View on jwt.io", style: .default, handler: { [weak alert] action in
                            let url = URL(string:"https://jwt.io/#debugger-io?token=\(confirm)")!
                            UIApplication.shared.open(url, options: [:])
                            alert?.dismiss(animated: true, completion: nil)
                        }))
                    } else if let e = error {
                        alert.title = "Failure"
                        alert.message = "Native Earn failed: (\(e.localizedDescription))"
                    }

                    alert.addAction(UIAlertAction(title: "Close", style: .cancel, handler: { [weak alert] action in
                        alert?.dismiss(animated: true, completion: nil)
                    }))

                    self?.present(alert, animated: true, completion: nil)
                }
            }
        }

        // NOTE: This condition is for testing purposes.
        // Always use the playground environment with this sample app.
        if environment.name == Environment.production.name {
            let earnOffer = [
                "subject" : "earn",
                "payload" : [
                    "offer" : [
                        "id" : offerID,
                        "amount" : amount
                    ],
                    "recipient": [
                        "user_id": lastUser,
                        "title": "Received Kin",
                        "description": "Native Earn example"
                    ]
                ],
                ] as [String : Any]

            let requestData = jsonToData(json: earnOffer)
            if (requestData != nil) {
                signJWT(requestData!){ jwt in
                    self.operationPromise = Promise().then {
                        requestPayment(offerJWT: jwt)
                    }

                    do {
                        try self.jwtLoginWith(self.lastUser, appId: appId)
                    } catch {
                        self.alertStartError(error)
                    }
                }
            }
        }
        else {
            guard let encoded = JWTUtil.encode(header: ["alg": "RS512",
                                                        "typ": "jwt",
                                                        "kid" : "rs512_0"],
                                               body: ["offer":["id":offerID, "amount": amount],
                                                      "recipient":
                                                        ["title":"Received Kin",
                                                         "description":"Native Earn example",
                                                         "user_id": lastUser]],
                                               subject: "earn",
                                               id: appId,
                                               privateKey: jwtPKey) else {
                                                alertConfigIssue()
                                                return
            }

            operationPromise = Promise().then {
                requestPayment(offerJWT: encoded)
            }

            do {
                try jwtLoginWith(lastUser, appId: appId)
            } catch {
                alertStartError(error)
            }
        }
    }

    private var presentedLoaders: Set<String> = Set()

    fileprivate func showLoader(id: String = "default") {
        presentedLoaders.insert(id)

        guard loader.isHidden else {
            return
        }

        loader.isHidden = false
        loader.alpha = 0
        loader.startAnimating()

        UIView.animate(withDuration: 0.3) {
            self.loader.alpha = 1
        }
    }

    fileprivate func hideLoader(id: String = "default") {
        presentedLoaders.remove(id)

        guard !loader.isHidden && presentedLoaders.count == 0 else {
            return
        }

        UIView.animate(withDuration: 0.3, animations: {
            self.loader.alpha = 0
        }) { _ in
            self.loader.isHidden = false
            self.loader.stopAnimating()
        }
    }
    
    @IBAction func orderConfirmationTapped(_ sender: Any) {
        guard let offerId = lastOfferId else{
            
            let alert = UIAlertController(title: "No Order has Been Made", message: "No Order was sent in this session yet.", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Oh ok", style: .cancel))
            self.present(alert, animated: true, completion: nil)
            
            return
        }
        print("orderConfirmationTapped offerId : \(offerId)")
        guard let appId = appId, let _ = privateKey else {
            alertConfigIssue()
            return
        }
        
        do {
            try jwtLoginWith(lastUser, appId: appId)
        } catch {
            alertStartError(error)
        }
        
        Kin.shared.orderConfirmation(for: offerId) { (status, err) in
            DispatchQueue.main.async { [weak self] in
                if let s = status {
                    let statusMsg :String = String(reflecting :s)
                    
                    let alert = UIAlertController(title: nil, message: nil, preferredStyle: .alert)
                    if let e = err {
                        alert.title = "Failure"
                        alert.message = "Native Earn failed: (\(e.localizedDescription))"
                    } else {
                        alert.title = "Get Order Confirmation - Success"
                        alert.message = "status: \(statusMsg)\n"
                        switch s{
                        case .completed(let jwt):
                            alert.addAction(UIAlertAction(title: "You can view the confirmation on jwt.io, View on jwt.io", style: .default, handler: { [weak alert] action in
                                UIApplication.shared.open(URL(string:"https://jwt.io/#debugger-io?token=\(jwt)")!, options: [:])
                                alert?.dismiss(animated: true, completion: nil)
                            }))
                        case .pending: break
                        case .failed: break
                        }
                        
                        alert.addAction(UIAlertAction(title: "Close", style: .cancel))
                        
                        self?.present(alert, animated: true, completion: nil)
                    }
                }
            }
        }
    }
}

extension SampleAppViewController: KinMigrationDelegate {
    private var loaderMigrationId: String {
        return "migration"
    }

    func kinMigrationDidStart() {
        showLoader(id: loaderMigrationId)
    }

    func kinMigrationDidFinish() {
        hideLoader(id: loaderMigrationId)
    }

    func kinMigrationIsReady() {
        operationPromise?.signal(Void())
        operationPromise = nil
    }

    func kinMigration(error: Error) {
        hideLoader(id: loaderMigrationId)
        alertStartError(error)
    }
}

// MARK: - Testing Production

extension SampleAppViewController {
    /**
     The local IP for testing on the production environment.

     Due to encryption limitations, using this sample app on production needs
     additional functionality.

     - Note: This code is not intended to be an example. Always use the
     playground environment with this sample app.
     */
    fileprivate var localIp: String {
        return ""
    }

    fileprivate func requestJWT(_ user: String, request: String, completion: @escaping (_ jwt: String) -> ()) {
        let url = URL(string: "http://\(localIp)\(request)")!

        let task = URLSession.shared.dataTask(with: url) {(data, response, error) in
            guard let data = data else {
                return
            }

            print(String(data: data, encoding: .utf8)!)

            do {
                let json = try JSONSerialization.jsonObject(with: data, options: []) as! [String: String]
                if let jwt = json["jwt"] {
                    print("generated jwt = " + jwt)
                    completion(jwt)
                }
            } catch {
                print(error)
            }
        }

        task.resume()
    }

    fileprivate func jsonToData(json: Any) -> Data? {
        if JSONSerialization.isValidJSONObject(json) { // True
            do {
                return try JSONSerialization.data(withJSONObject: json, options: .prettyPrinted)
            } catch {
                print("spend JSONSerialization error" + "\(error)")
            }
        }
        return nil
    }

    fileprivate func signJWT(_ signData: Data,completion: @escaping (_ jwt: String) -> ()) {
        let endpoint = URL(string: "http://\(localIp)/sign")
        var request = URLRequest(url: endpoint!)
        request.httpMethod = "POST"
        request.httpBody = signData
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("application/json", forHTTPHeaderField: "Accept")

        let task = URLSession.shared.dataTask(with: request) {(data, response, error) in
            guard let data = data else { return }
            print(String(data: data, encoding: .utf8)!)

            do {
                let json = try JSONSerialization.jsonObject(with: data, options: []) as! [String: String]
                if let jwt = json["jwt"] {
                    print("generated jwt = " + jwt)
                    completion(jwt)
                }
            } catch {
                print(error)
            }
        }
        task.resume()
    }
}
