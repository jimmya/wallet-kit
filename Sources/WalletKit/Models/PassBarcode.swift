//
//  PassBarcode.swift
//  Async
//
//  Created by Jimmy Arts on 12/09/2019.
//

import Foundation

public struct PassBarcode: Codable {
    /// Text displayed near the barcode. For example, a human-readable version of the barcode data in case the barcode doesn’t scan.
    public var altText: String?
    /// Barcode format.
    public var format: PassBarcodeFormat
    /// Message or payload to be displayed as a barcode.
    public var message: String
    /// Text encoding that is used to convert the message from the string representation to a data representation to render the barcode. The value is typically iso-8859-1, but you may use another encoding that is supported by your barcode scanning infrastructure.
    public var messageEncoding: PassCharacterEncoding?
}
