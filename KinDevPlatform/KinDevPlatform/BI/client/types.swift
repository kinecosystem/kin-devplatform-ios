import Foundation

struct KBITypes {
    enum OfferType: String, Codable {
        case coupon = "coupon"
        case external = "external"
        case p2P = "P2P"
        case poll = "poll"
        case quiz = "quiz"
        case tutorial = "tutorial"
    }
    enum Origin: String, Codable {
        case external = "external"
        case marketplace = "marketplace"
    }
    enum BurnReason: String, Codable {
        case alreadyBurned = "already_burned"
        case burned = "burned"
        case noAccount = "no_account"
        case noTrustline = "no_trustline"
    }
    enum SDKVersion: String, Codable {
        case the2 = "2"
        case the3 = "3"
    }
    enum SelectedSDKReason: String, Codable {
        case alreadyMigrated = "already_migrated"
        case apiCheck = "api_check"
        case migrated = "migrated"
        case noAccountToMigrate = "no_account_to_migrate"
    }
    enum CheckBurnReason: String, Codable {
        case alreadyBurned = "already_burned"
        case noAccount = "no_account"
        case noTrustline = "no_trustline"
        case notBurned = "not_burned"
    }
    enum MigrationReason: String, Codable {
        case accountNotFound = "account_not_found"
        case alreadyMigrated = "already_migrated"
        case migrated = "migrated"
    }
    enum RedeemTrigger: String, Codable {
        case systemInit = "system_init"
        case userInit = "user_init"
    }
}
