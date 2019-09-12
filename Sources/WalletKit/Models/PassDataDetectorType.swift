//
//  PassDataDetectorType.swift
//  Async
//
//  Created by Jimmy Arts on 12/09/2019.
//

import Foundation

public enum PassDataDetectorType: String, Codable {
    case phoneNumber = "PKDataDetectorTypePhoneNumber"
    case link = "PKDataDetectorTypeLink"
    case address = "PKDataDetectorTypeAddress"
    case calendarEvent = "PKDataDetectorTypeCalendarEvent"
}
