//
//  PassField.swift
//  Async
//
//  Created by Jimmy Arts on 12/09/2019.
//

import Foundation

public struct PassField: Codable {
    /// Attributed value of the field.
    /// The value may contain HTML markup for links. Only the <a> tag and its href attribute are supported.
    /// For example, the following is key-value pair specifies a link with the text “Edit my profile”: "attributedValue": "<a href='http://example.com/customers/123'>Edit my profile</a>"
    /// This key’s value overrides the text specified by the value key.
    /// Available in iOS 7.0.
    public var attributedValue: PassValue?
    /// Format string for the alert text that is displayed when the pass is updated. The format string must contain the escape %@, which is replaced with the field’s new value. For example, “Gate changed to %@.”
    /// If you don’t specify a change message, the user isn’t notified when the field changes.
    public var changeMessage: String?
    /// Data detectors that are applied to the field’s value.
    /// The default value is all data detectors. Provide an empty array to use no data detectors.
    /// Data detectors are applied only to back fields.
    public var dataDetectorTypes: [PassDataDetectorType]?
    /// The key must be unique within the scope of the entire pass. For example, “departure-gate.”
    public var key: String
    /// Label text for the field.
    public var label: String?
    /// Alignment for the field’s contents.
    /// The default value is natural alignment, which aligns the text appropriately based on its script direction.
    /// This key is not allowed for primary fields or back fields.
    public var textAligment: PassTextAlignment?
    /// Value of the field, for example, 42.
    public var value: PassValue?
}
