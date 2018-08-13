//
//  OrderViewModel.swift
//  KinEcosystem
//
//  Created by Elazar Yifrach on 01/03/2018.
//  Copyright © 2018 Kik Interactive. All rights reserved.
//

import Foundation

@available(iOS 9.0, *)
class OrderViewModel {
    
    let id: String
    var title: NSAttributedString?
    var subtitle: NSAttributedString?
    var amount: NSAttributedString?
    var details: String = ""
    var image: UIImage?
    var last: Bool?
    var color: UIColor?
    var indicatorColor: UIColor = .kinLightBlueGrey
    var titleColor: UIColor = .kinBlueGrey
    var detailsColor: UIColor = .kinDeepSkyBlue
    
    init(with model: Order, selfPublicAddress: String? ,last: Bool) {
        self.last = last
        id = model.id
        
        switch model.offerType {
        case .pay_to_user:
            if let address = selfPublicAddress, address == model.blockchain_data?.recipient_address {
                image = UIImage(named: "coins", in: Bundle.ecosystem, compatibleWith: nil)
            } else {
                image = UIImage(named: "invoice", in: Bundle.ecosystem, compatibleWith: nil)
            }
            checkOrderStatus(model: model)
        case .spend:
            image = UIImage(named: "invoice", in: Bundle.ecosystem, compatibleWith: nil)
            checkOrderStatus(model: model)
        default:
            image = UIImage(named: "coins", in: Bundle.ecosystem, compatibleWith: nil)
        }
        color = indicatorColor
        
        title = model.title.attributed(18.0, weight: .regular, color: titleColor) +
                details.attributed(14.0, weight: .regular, color: detailsColor)
        var subtitleString = model.description_
        if let shortDate = Iso8601DateFormatter.shortString(from: model.completion_date as Date) {
            subtitleString = subtitleString + " - " + shortDate
        }
        
        subtitle = subtitleString.attributed(14.0, weight: .regular, color: .kinBlueGreyTwo)
        
        var amountOperator = ""
        switch model.offerType {
        case .earn:
            amountOperator = "+"
        case .pay_to_user:
            if let address = selfPublicAddress {
                amountOperator = address == model.blockchain_data?.recipient_address ? "+" : "-"
            }
        default: // .spend
            amountOperator = "-"
        }
        
        amount = ((amountOperator) + "\(Decimal(model.amount).currencyString()) ").attributed(16.0, weight: .medium, color: .kinBlueGreyTwo)
    }
    
    fileprivate func checkOrderStatus(model: Order) {
        switch model.orderStatus {
        case .completed:
            indicatorColor = .kinDeepSkyBlue
            titleColor = .kinDeepSkyBlue
            if let action = model.call_to_action {
                details = " - " + action
            } else {
                details =  ""
            }
        case .failed:
            indicatorColor = .kinWatermelon
            detailsColor = .kinWatermelon
            details = " - " + (model.error?.error ?? "Transaction failed")
        default:
            details = ""
        }
    }
}
