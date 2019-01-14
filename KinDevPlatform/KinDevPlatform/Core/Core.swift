//
//  Core.swift
//  KinEcosystem
//
//  Created by Elazar Yifrach on 04/03/2018.
//  Copyright © 2018 Kik Interactive. All rights reserved.
//


@available(iOS 9.0, *)
class Core {
    let network: EcosystemNet
    let kinCoreEnvironment: Environment
    let kinSDKEnvironment: Environment
    let data: EcosystemData
    let blockchain: Blockchain
    
    init(kinCoreEnvironment: Environment,
         kinSDKEnvironment: Environment,
         network: EcosystemNet,
         data: EcosystemData,
         blockchain: Blockchain) throws
    {
        self.network = network
        self.kinCoreEnvironment = kinCoreEnvironment
        self.kinSDKEnvironment = kinSDKEnvironment
        self.data = data
        self.blockchain = blockchain
    }

    var environment: Environment {
        return kinSDKEnvironment
    }
}
