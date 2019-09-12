//
//  PassLocation.swift
//  Async
//
//  Created by Jimmy Arts on 12/09/2019.
//

import Foundation

public struct PassLocation: Codable {
    /// Altitude, in meters, of the location.
    public var altitude: Double?
    /// Latitude, in degrees, of the location.
    public var latitude: Double
    /// Longitude, in degrees, of the location.
    public var longitude: Double
    /// Text displayed on the lock screen when the pass is currently relevant. For example, a description of the nearby location such as “Store nearby on 1st and Main.”
    public var relevantText: String?
}
