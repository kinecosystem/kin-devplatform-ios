//
//  JWTUtil.swift
//  EcosystemSampleApp
//
//  Created by Elazar Yifrach on 10/05/2018.
//  Copyright © 2018 Kik Interactive. All rights reserved.
//

import Foundation
import JWT
// Just a sample utility for encoding a rs512 jwt using an external framework
// with a default expiration time of 1 day

class JWTUtil {
    static func encode(header: [AnyHashable: Any], body: [AnyHashable: Any], subject: String, id: String, privateKey: String) -> String? {
        // In some instances the below guard can return false if this object isn't stored
        let dataHolder = JWTAlgorithmRSFamilyDataHolder()
        
        guard let key = try? JWTCryptoKeyPrivate(pemEncoded: privateKey, parameters: nil),
            let holder = (dataHolder.signKey(key)?.secretData(privateKey.data(using: .utf8))?.algorithmName(JWTAlgorithmNameRS512) as? JWTAlgorithmRSFamilyDataHolder) else {
                return nil
        }
        let claims = JWTClaimsSet()
        let issuedAt = Date()
        claims.issuer = id
        claims.issuedAt = issuedAt
        claims.expirationDate = issuedAt.addingTimeInterval(86400.0)
        claims.subject = subject
        
        guard var claimsDict = JWTClaimsSetSerializer.dictionary(with: claims) else {
            return nil
        }
        for (k, v) in body {
            claimsDict[k] = v
        }
        guard let result = JWTEncodingBuilder.encodePayload(claimsDict)
            .headers(header)?
            .addHolder(holder)?
            .result.successResult?.encoded else {
                return nil
        }
        return result
    }
}
