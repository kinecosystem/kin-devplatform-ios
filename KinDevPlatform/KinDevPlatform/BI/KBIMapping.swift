//
//  KBIMapping.swift
//  KinDevPlatform
//
//  Created by Corey Werner on 17/01/2019.
//  Copyright © 2019 Kin Foundation. All rights reserved.
//

import KinMigrationModule

extension KinVersion {
    var mapToKBI: KBITypes.SDKVersion {
        switch self {
        case .kinCore:
            return .the2
        case .kinSDK:
            return .the3
        }
    }
}

extension KinMigrationBIReadyReason {
    var mapToKBI: KBITypes.SelectedSDKReason {
        switch self {
        case .alreadyMigrated:
            return .alreadyMigrated
        case .apiCheck:
            return .apiCheck
        case .migrated:
            return .migrated
        case .noAccountToMigrate:
            return .noAccountToMigrate
        }
    }
}

extension KinMigrationBIBurnReason {
    var mapToKBI: KBITypes.BurnReason {
        switch self {
        case .alreadyBurned:
            return .alreadyBurned
        case .burned:
            return .burned
        case .noAccount:
            return .noAccount
        case .noTrustline:
            return .noTrustline
        }
    }
}

extension KinMigrationBIMigrateReason {
    var mapToKBI: KBITypes.MigrationReason {
        switch self {
        case .alreadyMigrated:
            return .alreadyMigrated
        case .migrated:
            return .migrated
        case .noAccount:
            return .accountNotFound
        }
    }
}
