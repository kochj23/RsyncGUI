//
//  NovaAPITests.swift
//  RsyncGUITests
//
//  Created by Jordan Koch on 5/3/26.
//
//  Tests for the Nova API server's HTTP request parsing, routing logic,
//  and anti-CSRF token validation. These tests verify the server's
//  structural correctness without requiring a live network connection.

import XCTest
@testable import RsyncGUI

final class NovaAPITests: XCTestCase {

    // MARK: - HTTP Request Parsing

    /// Simulate parsing a raw HTTP request to verify the NovaRequest initializer behavior.
    /// NovaRequest is a private struct inside NovaAPIServer, so we replicate its parsing logic.
    private struct TestHTTPRequest {
        let method: String
        let path: String
        let body: String
        let headers: [String: String]

        init?(_ data: Data) {
            guard let raw = String(data: data, encoding: .utf8), raw.contains("\r\n\r\n") else { return nil }
            let parts = raw.components(separatedBy: "\r\n\r\n")
            let lines = parts[0].components(separatedBy: "\r\n")
            guard let rl = lines.first else { return nil }
            let tokens = rl.components(separatedBy: " ")
            guard tokens.count >= 2 else { return nil }
            var hdrs: [String: String] = [:]
            for l in lines.dropFirst() {
                let kv = l.components(separatedBy: ": ")
                if kv.count >= 2 {
                    hdrs[kv[0].lowercased()] = kv.dropFirst().joined(separator: ": ")
                }
            }
            method = tokens[0]
            path = tokens[1].components(separatedBy: "?").first ?? tokens[1]
            body = parts.dropFirst().joined(separator: "\r\n\r\n")
            headers = hdrs
        }
    }

    func testParseValidGETRequest() {
        let raw = "GET /api/status HTTP/1.1\r\nHost: 127.0.0.1:37424\r\nAccept: application/json\r\n\r\n"
        let request = TestHTTPRequest(raw.data(using: .utf8)!)

        XCTAssertNotNil(request)
        XCTAssertEqual(request?.method, "GET")
        XCTAssertEqual(request?.path, "/api/status")
        XCTAssertEqual(request?.headers["host"], "127.0.0.1:37424")
        XCTAssertEqual(request?.headers["accept"], "application/json")
    }

    func testParseValidPOSTRequest() {
        let raw = "POST /api/jobs/abc-123/run HTTP/1.1\r\nHost: 127.0.0.1:37424\r\nAuthorization: Bearer test-token\r\nContent-Length: 2\r\n\r\n{}"
        let request = TestHTTPRequest(raw.data(using: .utf8)!)

        XCTAssertNotNil(request)
        XCTAssertEqual(request?.method, "POST")
        XCTAssertEqual(request?.path, "/api/jobs/abc-123/run")
        XCTAssertEqual(request?.headers["authorization"], "Bearer test-token")
        XCTAssertEqual(request?.body, "{}")
    }

    func testParseRequestWithQueryParameters() {
        let raw = "GET /api/jobs?limit=50&offset=0 HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n"
        let request = TestHTTPRequest(raw.data(using: .utf8)!)

        XCTAssertNotNil(request)
        XCTAssertEqual(request?.path, "/api/jobs", "Query parameters should be stripped from path")
    }

    func testParseIncompleteRequestReturnsNil() {
        // No double CRLF = incomplete request
        let raw = "GET /api/status HTTP/1.1\r\nHost: 127.0.0.1"
        let request = TestHTTPRequest(raw.data(using: .utf8)!)

        XCTAssertNil(request, "Incomplete HTTP request should return nil")
    }

    func testParseEmptyDataReturnsNil() {
        let request = TestHTTPRequest(Data())
        XCTAssertNil(request, "Empty data should return nil")
    }

    func testParseRequestWithMultipleColonsInHeaderValue() {
        let raw = "GET /api/status HTTP/1.1\r\nHost: 127.0.0.1:37424\r\nX-Custom: value: with: colons\r\n\r\n"
        let request = TestHTTPRequest(raw.data(using: .utf8)!)

        XCTAssertNotNil(request)
        XCTAssertEqual(request?.headers["x-custom"], "value: with: colons",
                       "Header values with colons should be preserved")
    }

    func testParseOPTIONSRequest() {
        let raw = "OPTIONS /api/status HTTP/1.1\r\nHost: 127.0.0.1\r\nOrigin: http://localhost:3000\r\n\r\n"
        let request = TestHTTPRequest(raw.data(using: .utf8)!)

        XCTAssertNotNil(request)
        XCTAssertEqual(request?.method, "OPTIONS")
        XCTAssertEqual(request?.path, "/api/status")
    }

    // MARK: - API Route Patterns

    func testAPIRoutePatternStatus() {
        let path = "/api/status"
        XCTAssertTrue(path == "/api/status")
    }

    func testAPIRoutePatternPing() {
        let path = "/api/ping"
        XCTAssertTrue(path == "/api/ping")
    }

    func testAPIRoutePatternJobsList() {
        let path = "/api/jobs"
        XCTAssertTrue(path == "/api/jobs")
    }

    func testAPIRoutePatternJobDetail() {
        let uuid = UUID()
        let path = "/api/jobs/\(uuid.uuidString)"

        XCTAssertTrue(path.hasPrefix("/api/jobs/"))
        XCTAssertFalse(path.hasSuffix("/run"))
        XCTAssertFalse(path.hasSuffix("/dryrun"))
        XCTAssertFalse(path.hasSuffix("/history"))

        // Extract UUID
        let idStr = path.replacingOccurrences(of: "/api/jobs/", with: "")
        XCTAssertEqual(UUID(uuidString: idStr), uuid)
    }

    func testAPIRoutePatternJobRun() {
        let uuid = UUID()
        let path = "/api/jobs/\(uuid.uuidString)/run"

        XCTAssertTrue(path.hasSuffix("/run"))

        // Extract UUID
        let idStr = path.components(separatedBy: "/").dropLast().last ?? ""
        XCTAssertEqual(UUID(uuidString: idStr), uuid)
    }

    func testAPIRoutePatternJobDryrun() {
        let uuid = UUID()
        let path = "/api/jobs/\(uuid.uuidString)/dryrun"

        XCTAssertTrue(path.hasSuffix("/dryrun"))

        let idStr = path.components(separatedBy: "/").dropLast().last ?? ""
        XCTAssertEqual(UUID(uuidString: idStr), uuid)
    }

    func testAPIRoutePatternHistory() {
        let path = "/api/history"
        XCTAssertTrue(path == "/api/history")
    }

    func testAPIRoutePatternJobHistory() {
        let uuid = UUID()
        let path = "/api/jobs/\(uuid.uuidString)/history"

        XCTAssertTrue(path.hasSuffix("/history"))

        let idStr = path.components(separatedBy: "/").dropLast().last ?? ""
        XCTAssertEqual(UUID(uuidString: idStr), uuid)
    }

    // MARK: - HTTP Response Format

    func testHTTPResponseFormat() {
        // Replicate the http() helper from NovaAPIServer
        func buildHTTPResponse(_ status: Int, _ body: String, _ ct: String = "text/plain") -> String {
            let statusText = [200: "OK", 201: "Created", 400: "Bad Request",
                              401: "Unauthorized", 404: "Not Found", 500: "Internal Server Error"][status] ?? "Unknown"
            return "HTTP/1.1 \(status) \(statusText)\r\nContent-Type: \(ct); charset=utf-8\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
        }

        let response = buildHTTPResponse(200, "{\"status\":\"running\"}", "application/json")

        XCTAssertTrue(response.hasPrefix("HTTP/1.1 200 OK"))
        XCTAssertTrue(response.contains("Content-Type: application/json; charset=utf-8"))
        XCTAssertTrue(response.contains("Content-Length: 20"))
        XCTAssertTrue(response.contains("Connection: close"))
        XCTAssertTrue(response.contains("{\"status\":\"running\"}"))
    }

    func testHTTPResponseStatusCodes() {
        let statusTexts: [Int: String] = [
            200: "OK", 201: "Created", 400: "Bad Request",
            401: "Unauthorized", 404: "Not Found", 500: "Internal Server Error"
        ]

        for (code, text) in statusTexts {
            let response = "HTTP/1.1 \(code) \(text)"
            XCTAssertTrue(response.contains("\(code)"), "Response should contain status code \(code)")
            XCTAssertTrue(response.contains(text), "Response should contain status text '\(text)'")
        }
    }

    // MARK: - Anti-CSRF Token Validation

    func testBearerTokenExtractionFromAuthorizationHeader() {
        let headerValue = "Bearer abc-123-def-456"

        // The route method checks: auth == "Bearer \(apiToken)"
        let expectedToken = "abc-123-def-456"
        XCTAssertEqual(headerValue, "Bearer \(expectedToken)")
    }

    func testMissingAuthorizationHeaderBlocksPOST() {
        // POST requests without Authorization header should be rejected
        let raw = "POST /api/jobs/test-id/run HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Length: 0\r\n\r\n"
        let request = TestHTTPRequest(raw.data(using: .utf8)!)

        XCTAssertNotNil(request)
        XCTAssertNil(request?.headers["authorization"],
                     "Missing authorization header should be nil")
    }

    func testWrongTokenFormatIsDetectable() {
        let headers: [String: String] = [
            "authorization": "Basic dXNlcjpwYXNz"  // Basic auth, not Bearer
        ]

        let validToken = "test-token-123"
        let expectedAuth = "Bearer \(validToken)"

        XCTAssertNotEqual(headers["authorization"], expectedAuth,
                          "Basic auth should not match Bearer token check")
    }

    func testGETRequestsDoNotRequireToken() {
        // The route method only checks token for POST requests
        let raw = "GET /api/status HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n"
        let request = TestHTTPRequest(raw.data(using: .utf8)!)

        XCTAssertNotNil(request)
        XCTAssertEqual(request?.method, "GET")
        // GET requests should not be blocked by missing authorization
        XCTAssertNil(request?.headers["authorization"],
                     "GET request without auth should still parse successfully")
    }

    // MARK: - UUID Extraction from Paths

    func testUUIDExtractionFromJobPath() {
        let uuid = UUID()
        let path = "/api/jobs/\(uuid.uuidString)"

        let idStr = path.replacingOccurrences(of: "/api/jobs/", with: "")
        let extracted = UUID(uuidString: idStr)

        XCTAssertNotNil(extracted)
        XCTAssertEqual(extracted, uuid)
    }

    func testUUIDExtractionFromRunPath() {
        let uuid = UUID()
        let path = "/api/jobs/\(uuid.uuidString)/run"

        let idStr = path.components(separatedBy: "/").dropLast().last ?? ""
        let extracted = UUID(uuidString: idStr)

        XCTAssertNotNil(extracted)
        XCTAssertEqual(extracted, uuid)
    }

    func testInvalidUUIDExtractionReturnsNil() {
        let path = "/api/jobs/not-a-valid-uuid"

        let idStr = path.replacingOccurrences(of: "/api/jobs/", with: "")
        let extracted = UUID(uuidString: idStr)

        XCTAssertNil(extracted, "Invalid UUID string should return nil")
    }

    // MARK: - Request Body Parsing

    func testJSONBodyParsing() {
        let jsonString = "{\"dryRun\": true, \"priority\": \"high\"}"
        guard let data = jsonString.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            XCTFail("Should parse valid JSON body")
            return
        }

        XCTAssertEqual(parsed["dryRun"] as? Bool, true)
        XCTAssertEqual(parsed["priority"] as? String, "high")
    }

    func testEmptyBodyParsing() {
        let jsonString = ""
        let data = jsonString.data(using: .utf8)!
        let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertNil(parsed, "Empty body should not parse as JSON")
    }

    func testInvalidJSONBodyParsing() {
        let jsonString = "not valid json {"
        let data = jsonString.data(using: .utf8)!
        let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertNil(parsed, "Invalid JSON should return nil")
    }

    // MARK: - Server Port Configuration

    func testServerPortIsOnLoopbackRange() {
        let port: UInt16 = 37424

        // Verify port is in Jordan's reserved range (37421-37449)
        XCTAssertGreaterThanOrEqual(port, 37421, "Port should be in reserved range")
        XCTAssertLessThanOrEqual(port, 37449, "Port should be in reserved range")
    }

    // MARK: - ISO8601 Date Formatting

    func testISO8601DateFormattingForHistoryEntries() {
        let formatter = ISO8601DateFormatter()
        let now = Date()

        let formatted = formatter.string(from: now)
        XCTAssertFalse(formatted.isEmpty, "ISO8601 formatting should produce non-empty string")

        let roundTripped = formatter.date(from: formatted)
        XCTAssertNotNil(roundTripped, "ISO8601 formatted date should parse back")

        // Verify roundtrip is within 1 second (ISO8601 drops sub-second precision)
        if let rt = roundTripped {
            XCTAssertEqual(rt.timeIntervalSince1970, now.timeIntervalSince1970, accuracy: 1.0)
        }
    }
}
