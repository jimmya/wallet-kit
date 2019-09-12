//
//  PassBarcodeFormat.swift
//  Async
//
//  Created by Jimmy Arts on 12/09/2019.
//

import Foundation

public enum PassBarcodeFormat: String, Codable {
    case qr = "PKBarcodeFormatQR"
    case pdf = "PKBarcodeFormatPDF417"
    case aztec = "PKBarcodeFormatAztec"
    case code128 = "PKBarcodeFormatCode128"
}
