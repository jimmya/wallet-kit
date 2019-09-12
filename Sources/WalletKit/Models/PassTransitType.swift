//
//  PassTransitType.swift
//  Async
//
//  Created by Jimmy Arts on 12/09/2019.
//

import Foundation

public enum PassTransitType: String, Codable {
    case air = "PKTransitTypeAir"
    case boat = "PKTransitTypeBoat"
    case bus = "PKTransitTypeBus"
    case generic = "PKTransitTypeGeneric"
    case train = "PKTransitTypeTrain"
}
