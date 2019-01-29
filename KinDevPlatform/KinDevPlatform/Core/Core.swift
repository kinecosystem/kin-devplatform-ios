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
    let environment: Environment
    let data: EcosystemData
    let blockchain: Blockchain
    
    init(environment: Environment,
         network: EcosystemNet,
         data: EcosystemData,
         blockchain: Blockchain) throws
    {
        self.network = network
        self.environment = environment
        self.data = data
        self.blockchain = blockchain
    }
}
