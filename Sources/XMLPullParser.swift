//
// XMLPullParser.swift
// XMLPullitic
//
// Copyright (c) 2016-2019 Hironori Ichimiya <hiron@hironytic.com>
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

import Foundation

public class XMLPullParser {
    private var internalParser: InternalXMLParser
    
    public convenience init?(contentsOfURL url: URL) {
        guard let parser = XMLParser(contentsOf:url) else { return nil }
        self.init(xmlParser: parser)
    }
    
    public convenience init(data: Data) {
        self.init(xmlParser: XMLParser(data: data))
    }
    
    public convenience init(stream: InputStream) {
        self.init(xmlParser: XMLParser(stream: stream))
    }
    
    public convenience init?(string: String) {
        guard let data = (string as NSString).data(using: String.Encoding.utf8.rawValue) else { return nil }
        self.init(data: data)
    }
    
    init(xmlParser: XMLParser) {
        self.internalParser = InternalXMLParser(xmlParser: xmlParser)
    }
    
    deinit {
        abortParsing()
    }

    public var shouldProcessNamespaces: Bool {
        get {
            return self.internalParser.xmlParser.shouldProcessNamespaces
        }
        set(value) {
            self.internalParser.xmlParser.shouldProcessNamespaces = value
        }
    }
    
    public var lineNumber: Int {
        get {
            return self.internalParser.xmlParser.lineNumber
        }
    }
    
    public var columnNumber: Int {
        get {
            return self.internalParser.xmlParser.columnNumber
        }
    }
    
    public var depth: Int {
        get {
            return self.internalParser.depth
        }
    }
    
    public func next() throws -> XMLEvent {
        return try internalParser.requestEvent()
    }

    public func abortParsing() {
        internalParser.abortParsing()
    }
}

// MARK: -

@objc private class InternalXMLParser: NSObject, XMLParserDelegate {
    class LockCondition {
        static let Requested: Int = 0
        static let Provided: Int = 1
    }
    
    enum State {
        case notStarted
        case parsing
        case aborted
        case ended
    }
    
    enum EventOrError {
        case event(XMLEvent)
        case error(Error)
    }
    
    let xmlParser: XMLParser
    let lock: NSConditionLock
    var currentEventOrError: EventOrError
    var state: State
    var depth: Int
    var accumulatedChars: String?
    
    // MARK: methods called on original thread
    
    init(xmlParser: XMLParser) {
        self.xmlParser = xmlParser
        self.lock = NSConditionLock(condition: LockCondition.Requested)
        self.currentEventOrError = EventOrError.event(XMLEvent.startDocument)
        self.state = .notStarted
        self.depth = 0
        
        super.init()
    }

    func abortParsing() {
        guard state == .parsing else { return }
        
        state = .aborted
        
        // awake wating parser
        lock.unlock(withCondition: LockCondition.Requested)
    }
    
    func requestEvent() throws -> XMLEvent {
        switch state {
        case .notStarted:
            state = .parsing
            xmlParser.delegate = self
            DispatchQueue.global(qos: .default).async {
                self.lock.lock(whenCondition: LockCondition.Requested)
                self.xmlParser.parse()
            }
        case .parsing:
            lock.unlock(withCondition: LockCondition.Requested)
            
        case .aborted:
            return XMLEvent.endDocument
            
        case .ended:
            return XMLEvent.endDocument
        }
        
        lock.lock(whenCondition: LockCondition.Provided)
        switch currentEventOrError {
        case .error(let error):
            state = .ended
            lock.unlock()
            throw error
        case .event(XMLEvent.endDocument):
            state = .ended
            lock.unlock()
            return XMLEvent.endDocument
        case .event(let event):
            return event
        }
    }

    // MARK: methods called on background thread
    
    func provide(_ eventOrError: EventOrError) {
        if let chars = accumulatedChars {
            accumulatedChars = nil
            provide(.event(.characters(chars)))
            waitForNextRequest()
        }
        
        if (state == .parsing) {
            currentEventOrError = eventOrError
            lock.unlock(withCondition: LockCondition.Provided)
        }
    }
    
    func waitForNextRequest() {
        guard state == .parsing else {
            if (state == .aborted && xmlParser.delegate != nil) {
                xmlParser.delegate = nil
                xmlParser.abortParsing()
            }
            return
        }
        
        lock.lock(whenCondition: LockCondition.Requested)
        if (state == .aborted) {
            xmlParser.delegate = nil
            xmlParser.abortParsing()
            lock.unlock()
        }
    }
    
    func accumulate(characters chars: String) {
        accumulatedChars = (accumulatedChars ?? "") + chars
    }
    
    @objc func parserDidStartDocument(_ parser: XMLParser) {
        provide(.event(.startDocument))
        waitForNextRequest()
    }
    
    @objc func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String]) {
        depth += 1
        let element = XMLElement(name: elementName, namespaceURI: namespaceURI, qualifiedName: qName, attributes: attributeDict)
        provide(.event(.startElement(name: elementName, namespaceURI: namespaceURI, element: element)))
        waitForNextRequest()
    }
    
    @objc func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        provide(.event(.endElement(name: elementName, namespaceURI: namespaceURI)))
        waitForNextRequest()
        depth -= 1
    }
    
    @objc func parser(_ parser: XMLParser, foundCharacters string: String) {
        accumulate(characters: string)
    }
    
    @objc func parserDidEndDocument(_ parser: XMLParser) {
        provide(.event(.endDocument))
    }
    
    @objc func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        provide(.error(XMLPullParserError.parseError(innerError: parseError)))
    }
    
    @objc func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        if let text = NSString(data: CDATABlock, encoding: String.Encoding.utf8.rawValue) {
            accumulate(characters: text as String)
        }
    }
}
