// Copyright 2026 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     https://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import CoreGraphics
import XCTest
@testable import JotCore

final class HotkeyEdgeDetectorTests: XCTestCase {
    private let ctrl = CGEventFlags(rawValue: 0x2000)
    private let opt = CGEventFlags(rawValue: 0x40)
    private let both = CGEventFlags(rawValue: 0x2040)

    func testEitherKeyPressesAndReleases() {
        var d = HotkeyEdgeDetector(keys: [.rightControl, .rightOption])
        XCTAssertEqual(d.edge(keyCode: 62, flags: ctrl), true)
        XCTAssertEqual(d.edge(keyCode: 62, flags: []), false)
        XCTAssertEqual(d.edge(keyCode: 61, flags: opt), true)
        XCTAssertEqual(d.edge(keyCode: 61, flags: []), false)
        XCTAssertNil(d.edge(keyCode: 54, flags: CGEventFlags(rawValue: 0x10)))
    }

    func testSecondKeyNeitherRestartsNorEndsTheHold() {
        var d = HotkeyEdgeDetector(keys: [.rightControl, .rightOption])
        XCTAssertEqual(d.edge(keyCode: 62, flags: ctrl), true)
        XCTAssertNil(d.edge(keyCode: 61, flags: both))
        XCTAssertNil(d.edge(keyCode: 61, flags: ctrl))
        XCTAssertEqual(d.edge(keyCode: 62, flags: []), false)
    }

    func testAddingAKeyMidHoldKeepsTheRelease() {
        var d = HotkeyEdgeDetector(keys: [.rightControl])
        XCTAssertEqual(d.edge(keyCode: 62, flags: ctrl), true)
        d.setKeys([.rightControl, .rightOption])
        XCTAssertEqual(d.edge(keyCode: 62, flags: []), false)
    }
}
