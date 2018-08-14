## Installation
The fastest way to get started with the sdk is with cocoapods (>= 1.4.0).
```
pod 'KinDevPlatform', '<latest version>'
```

latest version can be found in [github releases](https://github.com/kinecosystem/kin-devplatform-ios/releases)

> Notice for apps using swift 3.2: the pod installation will change your project's swift version target to 4.0</br>
> This is because the sdk uses swift 4.0, and cocoapods force the pod's swift version on the project. For now, you can manually change your project's swift version in the build setting. A better solution will be available soon.

## Playground and Production Environments 

Kin provides two working environments:

- **Playground** – a staging and testing environment using test servers and a blockchain test network.
- **Production** – uses production servers and the main blockchain network.

Use the Playground environment to develop, integrate and test your app. Transition to the Production environment when you’re ready to go live with your Kin-integrated app.

When your app calls ```Kin.start(…)```, you specify which environment to work with.

>* When working with the Playground environment, you can only register up to 1000 users. An attempt to register additional users will result in an error.
>* In order to switch between environments, you’ll need to clear the application data.

## Setting Up the Sample App ##

The Kin SDK Sample App demonstrates how to perform common workflows such as creating a user account and creating Spend and Earn offers. You can build the Sample App from the [sample app github repository](https://github.com/kinecosystem/kin-devplatform-ios-sample-app).  
We recommend building and running the Sample App as a good way to get started with the Kin SDK and familiarize yourself with its functions.

>**NOTE:** The Sample App is for demonstration only, and should not be used for any other purpose.

The Sample App is pre-configured with the default whitelist credentials `appId='test'` and
`apiKey='AyINT44OAKagkSav2vzMz'` and with a default RSA512 JWT private key. These credentials can be used for integration testing in any app, but authorization will fail if you attempt to use them in a production environment.

You can also request unique apiKey and appId values from Kin, and override the default settings, working either in whitelist or JWT authentication mode.

### Override the default credential settings

Edit the `EcosystemSampleApp/defaultConfig.plist`, using the credentials values and method you received.

```xml
   <dict>
    <key>RS512_PRIVATE_KEY</key>
    <string>YOUR_RS512_PRIVATE_KEY</string> <!-- Optional. Only required when testing JWT on the sample app. For production, JWT is created by server side with ES256 signature. -->
    <key>appKey</key>
    <string>YOUR_API_KEY</string> <!-- For whitelist registration. Default = 'AyINT44OAKagkSav2vzMz'. -->
    <key>appId</key>
    <string>YOUR_APP_ID</string> <!-- Your unique application id, required for both whitelist and JWT. Default = 'test'. -->
    <key>IS_JWT_REGISTRATION</key> <!-- // Optional. To test sample app JWT registration, set this property to true. If not specified, default=false. -->
    <false/>
</dict>
```

## Initialize Client SDK

Call ```Kin.shared.start(...)```, passing the desired environment (playground/production) and your chosen authentication credentials (either whitelist or JWT credentials).

#### Whitelist:

```swift
Kin.shared.start(userId: "myUserId", apiKey: "myAppKey", appId: "myAppId", environment: .playground)
```

userID - your application unique identifier for the user  
appID - your application unique identifier as provided by Kin.  
apiKey - your secret apiKey as provided by Kin.

#### jwt:

Request a registration JWT from your server, once the client received this token, you can now start the sdk using this token.

```swift
Kin.shared.start(userId: "myUserId", jwt: registrationJWT, environment: .playground)
```

### Launching the marketplace experience
To launch the marketplace experience, with earn and spend opportunities, from a viewController, simply call:

```swift
Kin.shared.launchMarketplace(from: self)
```
### Getting your public address
Once kin is onboarded, you can view the stellar wallet address using:
```swift
Kin.shared.publicAddress
```
> note: this variable will return nil if called before kin is onboarded

## Getting your balance

Balance is represented by a `Balance` struct:
```swift
public struct Balance: Codable, Equatable {
    public var amount: Decimal
}
```

You can get your current balance using one of three ways:

### Last known balance for the current account:

```swift
if let amount = Kin.shared.lastKnownBalance?.amount {
    print("your balance is \(amount) KIN")
} else {
  // Kin is not started or an account wasn't created yet.
}
```

### Asynchronous call to the blockchain network:
```swift
Kin.shared.balance { balance, error in
    guard let amount = balance?.amount else {
        if let error = error {
            print("balance fetch error: \(error)")
        }
        return
    }
    print("your balance is \(amount) KIN")
}
```

### Observing balance with a blockchain network observer:

```swift
var balanceObserverId: String? = nil
do {
    balanceObserverId = try Kin.shared.addBalanceObserver { balance in
        print("balance: \(balance.amount)")
    }
} catch {
    print("Error setting balance observer: \(error)")
}

// when you're done listening to balance changes, remove the observer:

if let observerId = balanceObserverId {
    Kin.shared.removeBalanceObserver(observerId)
}
```

## Custom Spend Offer

A custom Spend offer allows your users to unlock unique spend opportunities that you define within your app, Custom offers are created by your app, as opposed to built-in offers displayed in the Kin Marketplace offer wall.  
Your app displays the offer, request user approval, and then performing the purchase using the `purchase` API.

### Purchase Payment

1. Create a JWT that represents a [Spend offer JWT](jwt#SpendPayload) signed by your application server. The fastest way for building JWT tokens is to use the [JWT Service](jwt-service).  
Once you have the JWT Service set up, perform a [Spend query](jwt-service#Spend),
the service will response with the generated signed JWT token.

2. Call `purchase` method, while passing the JWT you built and a callback function that will receive purchase confirmation.

> The following snippet is taken from the SDK Sample App, in which the JWT is created and signed by the Android client side for presentation purposes only. Do not use this method in production! In production, the JWT must be signed by the server, with a secure private key.

```swift
Kin.shared.purchase(offerJWT: encodedNativeOffer) { jwtConfirmation, error in
  if let confirm = jwtConfirmation {
    // jwtConfirmation can be kept on digital service side as a receipt proving user received his Kin.
    // Send confirmation JWT back to the server in order prove that the user completed
    // the blockchain transaction and purchase can be unlocked for this user.
  } else if let e = error {
    // handle error
  }
}
```

3.	Complete the purchase after you receive confirmation from the Kin Server that the funds were transferred successfully.

### Adding to the Marketplace 
The Kin Marketplace offer wall displays built-in offers, which are served by Kin.  
Their purpose is to provide users with opportunities to earn initial Kin funding, which they can later spend on spend offers provided by hosting apps.

You can also choose to display a banner for your custom offer in the Kin Marketplace offer wall. This serves as additional "real estate" in which to let the user know about custom offers within your app. When the user clicks on your custom Spend offer in the Kin Marketplace, your app is notified, and then it continues to manage the offer activity in its own UX flow.

>**NOTE:** You will need to actively launch the Kin Marketplace offer wall so your user can see the offers you added to it.

*To add a custom Spend offer to the Kin Marketplace:*

1. Create a ```NativeSpendOffer``` struct as in the example below.

  ```swift
let offer = NativeOffer(id: "offer id", // OfferId must be a UUID
                        title: "offer title",
                        description: "offer description",
                        amount: 1000,
                        image: "an image URL string",
                        isModal: true)
```
> Note: setting a native offer's `isModal` property to true means that when a user taps on the native offer, the marketplace will first close (dismiss) before invoking the native offer's handler, if set. The default value is false.

2.	Set the  `nativeOfferHandler` closure on Kin.shared to receive a callback when the native offer has been tapped.</br>
The callback is of the form `public var nativeOfferHandler: ((NativeOffer) -> ())?`

  ```swift
// example from the sample app:
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
```

3.	Add the native offer you created in the following way:

  >Note: Each new offer is added as the first offer in Spend Offers list the Marketplace displays.

  ```swift
  do {
      try Kin.shared.add(nativeOffer: offer)
  } catch {
      print("failed to add native offer, error: \(error)")
  }
  ```
### Removing from Marketplace

To remove a custom Spend offer from the Kin Marketplace, call `Kin.shared.remove(...)`, passing the offer you want to remove.  

```swift
do {
    try Kin.shared.remove(nativeOfferId: offer.id)
} catch {
    print("Failed to remove offer, error: \(error)")
}
```

## Custom Earn Offer

A custom Earn offer allows your users to earn Kin as a reward for performing tasks you want to incentives, such as setting a profile picture or rating your app. Custom offers are created by your app, as opposed to built-in offers displayed in the Kin Marketplace offer wall.  
Once the user has completed the task associated with the Earn offer, you request Kin payment for the user.

### Request A Payment

1. Create a JWT that represents a [Earn offer JWT](jwt#EarnPayload) signed by your application server. The fastest way for building JWT tokens is to use the [JWT Service](jwt-service).  
Once you have the JWT Service set up, perform a [Earn query](jwt-service#Earn),
the service will response with the generated signed JWT token.

2. Call `requestPayment` while passing the JWT you built and a callback function that will receive purchase confirmation.

>* The following snippet is taken from the SDK Sample App, in which the JWT is created and signed by the Android client side for presentation purposes only. Do not use this method in production! In production, the JWT must be signed by the server, with a secure private key.     

```swift
let handler: ExternalOfferCallback = { jwtConfirmation, error in  
    let alert = UIAlertController(title: nil, message: nil, preferredStyle: .alert)
    if let confirm = jwtConfirmation {
        // Callback will be called once payment transaction to the user completed successfully.
        // jwtConfirmation can be kept on digital service side as a receipt proving user received his Kin.
    } else if let e = error {
        //handle error
    }  
}

Kin.shared.requestPayment(offerJWT: encodedJWT, completion: handler)
```

## Custom Pay To User Offer

A custom pay to user offer allows your users to unlock unique spend opportunities that you define within your app offered by other users.
(Custom offers are created by your app, as opposed to built-in offers displayed in the Kin Marketplace offer wall.  
Your app displays the offer, request user approval, and then performing the purchase using the `payToUser` API.

### Pay to user

*To request payment for a custom Pay To User offer:*

1. Create a JWT that represents a [Pay to User offer JWT](jwt#PayToUserPayload) signed by your application server. The fastest way for building JWT tokens is to use the [JWT Service](jwt-service).  
Once you have the JWT Service set up, perform a [Pay To User query](jwt-service#PayToUser),
the service will response with the generated signed JWT token.


2.	Call `Kin.payToUser(...)`, while passing the JWT you built and a callback function that will receive purchase confirmation.

> The following snippet is taken from the SDK Sample App, in which the JWT is created and signed by the Android client side for presentation purposes only. Do not use this method in production! In production, the JWT must be signed by the server, with a secure private key. 

```swift
Kin.shared.payToUser(offerJWT: encodedNativeOffer) { jwtConfirmation, error in
  if let confirm = jwtConfirmation {
    // jwtConfirmation can be kept on digital service side as a receipt proving user received his Kin.
    // Send confirmation JWT back to the server in order prove that the user completed
    // the blockchain transaction and purchase can be unlocked for this user.
  } else if let e = error {
    // handle error
  }
}
```

3.	Complete the pay to user offer after you receive confirmation from the Kin Server that the funds were transferred successfully.

## License
The kin-devplatform-ios library is licensed under [MIT license](LICENSE.md).