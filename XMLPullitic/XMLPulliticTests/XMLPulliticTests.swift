//
// XMLPulliticTests.swift
// XMLPulliticTests
//
// Copyright (c) 2016 Hironori Ichimiya <hiron@hironytic.com>
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.
//

import XCTest
@testable import XMLPullitic

class XMLPulliticTests: XCTestCase {
    
    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
    
    func testMinimal() {
        let xml = "<?xml version=\"1.0\" encoding=\"UTF-8\" ?><hoge aa=\"11\" bb=\"22\">foo</hoge>"
        let parser = XMLPullParser(string: xml)
        XCTAssertNotNil(parser)
        if let parser = parser {
            do {
                let event1 = try parser.next()
                switch event1 {
                case .StartDocument:
                    break
                default:
                    XCTFail("event1 should be .StartDocument")
                }
                
                let event2 = try parser.next()
                switch event2 {
                case .StartElement(let name, let namespaceURI, let element):
                    XCTAssertEqual(name, "hoge")
                    XCTAssertNil(namespaceURI)
                    XCTAssertEqual(element.name, "hoge")
                    XCTAssertNil(element.namespaceURI)
                    XCTAssertNil(element.qualifiedName)
                    XCTAssertEqual(element.attributes.count, 2)
                    XCTAssertEqual(element.attributes["aa"], "11")
                    XCTAssertEqual(element.attributes["bb"], "22")
                default:
                    XCTFail("event2 should be .StartElement")
                }
                
                let event3 = try parser.next()
                switch event3 {
                case .Characters(let chars):
                    XCTAssertEqual(chars, "foo")
                default:
                    XCTFail("event3 should be .Characters")
                }
                
                let event4 = try parser.next()
                switch event4 {
                case .EndElement(let name, let namespaceURI):
                    XCTAssertEqual(name, "hoge")
                    XCTAssertNil(namespaceURI)
                default:
                    XCTFail("event4 should be .EndElement")
                }
                
                let event5 = try parser.next()
                switch event5 {
                case .EndDocument:
                    break
                default:
                    XCTFail("event5 should be .EndDocument")
                }
            } catch {
                XCTFail("error should not be occured")
            }
        }
    }
    
    func testParseError() {
        let xml = "<?xml version=\"1.0\" encoding=\"UTF-8\" ?>\n<hoge>\nfoo\n<</hoge>"
        let parser = XMLPullParser(string: xml)
        if let parser = parser {
            XCTAssertNotNil(parser)
            do {
                parsing: while true {
                    switch try parser.next() {
                    case .EndDocument:
                        break parsing
                    default:
                        break
                    }
                }
                XCTFail("parse error should be occured")
            } catch XMLPullParserError.ParseError(_) {
                XCTAssertEqual(parser.lineNumber, 4)
                XCTAssertEqual(parser.columnNumber, 2)
            } catch {
                XCTFail("another error should not be occured")
            }
        }
    }
}
