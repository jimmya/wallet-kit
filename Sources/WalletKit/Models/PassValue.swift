//
//  PassValue.swift
//  Async
//
//  Created by Jimmy Arts on 12/09/2019.
//

import Foundation

public enum PassValue: Codable {
    case double(Double)
    case string(String)
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        do {
            self = try .double(container.decode(Double.self))
        } catch DecodingError.typeMismatch {
            do {
                self = try .string(container.decode(String.self))
            } catch DecodingError.typeMismatch {
                throw DecodingError.typeMismatch(PassValue.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Encoded payload not of an expected type"))
            }
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .double(let double):
            try container.encode(double)
        case .string(let string):
            try container.encode(string)
        }
    }
}
