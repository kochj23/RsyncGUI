//
//  ConnectionTest.swift
//  RsyncGUI
//
//  Created by Jordan Koch on 1/14/26.
//

import Foundation

/// Result of connection testing
struct TestConnectionResult {
    var checks: [ConnectionCheck]
    var overallSuccess: Bool

    var summary: String {
        let passed = checks.filter { $0.passed }.count
        let total = checks.count
        return "\(passed) / \(total) checks passed"
    }
}

/// Individual connection check
struct ConnectionCheck: Identifiable {
    var id = UUID()
    var name: String
    var passed: Bool
    var message: String
}
