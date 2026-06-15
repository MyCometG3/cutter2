//
//  DateFormatter+Factory.swift
//  cutter2
//
//  Copyright © 2018-2026 MyCometG3. All rights reserved.
//

import Foundation

extension DateFormatter {
    static func logFormatter(format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = format
        return formatter
    }
}
