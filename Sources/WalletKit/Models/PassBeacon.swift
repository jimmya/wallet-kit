//
//  PassBeacon.swift
//  Async
//
//  Created by Jimmy Arts on 12/09/2019.
//

import Foundation

public struct PassBeacon: Codable {
    /// Major identifier of a Bluetooth Low Energy location beacon.
    public var major: UInt16?
    /// Minor identifier of a Bluetooth Low Energy location beacon.
    public var minor: UInt16?
    /// Unique identifier of a Bluetooth Low Energy location beacon.
    public var proximityUUID: String
    /// Text displayed on the lock screen when the pass is currently relevant. For example, a description of the nearby location such as “Store nearby on 1st and Main.”
    public var relevantText: String?
}
