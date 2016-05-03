//
// XMLPullParser.swift
// XMLPullitic
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

import Foundation

public class XMLPullParser {
    private var internalParser: InternalXMLParser
    
    public convenience init?(contentsOfURL url: NSURL) {
        guard let parser = NSXMLParser(contentsOfURL:url) else { return nil }
        self.init(xmlParser: parser)
    }
    
    public convenience init(data: NSData) {
        self.init(xmlParser: NSXMLParser(data: data))
    }
    
    public convenience init(stream: NSInputStream) {
        self.init(xmlParser: NSXMLParser(stream: stream))
    }
    
    public convenience init?(string: String) {
        guard let data = (string as NSString).dataUsingEncoding(NSUTF8StringEncoding) else { return nil }
        self.init(data: data)
    }
    
    init(xmlParser: NSXMLParser) {
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

@objc private class InternalXMLParser: NSObject, NSXMLParserDelegate {
    class LockCondition {
        static let Requested: Int = 0
        static let Provided: Int = 1
    }
    
    enum State {
        case NotStarted
        case Parsing
        case Aborted
        case Ended
    }
    
    enum EventOrError {
        case Event(XMLEvent)
        case Error(ErrorType)
    }
    
    let xmlParser: NSXMLParser
    let lock: NSConditionLock
    var currentEventOrError: EventOrError
    var state: State
    var depth: Int
    
    // MARK: methods called on original thread
    
    init(xmlParser: NSXMLParser) {
        self.xmlParser = xmlParser
        self.lock = NSConditionLock(condition: LockCondition.Requested)
        self.currentEventOrError = EventOrError.Event(XMLEvent.StartDocument)
        self.state = .NotStarted
        self.depth = 0
        
        super.init()
    }

    func abortParsing() {
        guard state == .Parsing else { return }
        
        state = .Aborted
        
        // awake wating parser
        lock.unlockWithCondition(LockCondition.Requested)
        
        // wait for aborting
        lock.lockWhenCondition(LockCondition.Provided)
        lock.unlock()
    }
    
    func requestEvent() throws -> XMLEvent {
        switch state {
        case .NotStarted:
            state = .Parsing
            xmlParser.delegate = self
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)) {
                self.lock.lockWhenCondition(LockCondition.Requested)
                self.xmlParser.parse()
            }
        case .Parsing:
            lock.unlockWithCondition(LockCondition.Requested)
            
        case .Aborted:
            return XMLEvent.EndDocument
            
        case .Ended:
            return XMLEvent.EndDocument
        }
        
        lock.lockWhenCondition(LockCondition.Provided)
        switch currentEventOrError {
        case .Error(let error):
            state = .Ended
            lock.unlock()
            throw error
        case .Event(XMLEvent.EndDocument):
            state = .Ended
            lock.unlock()
            return XMLEvent.EndDocument
        case .Event(let event):
            return event
        }
    }

    // MARK: methods called on background thread
    
    func provide(eventOrError: EventOrError) {
        currentEventOrError = eventOrError
        lock.unlockWithCondition(LockCondition.Provided)
    }
    
    func waitForNextRequest() {
        lock.lockWhenCondition(LockCondition.Requested)
        if (state == .Aborted) {
            xmlParser.abortParsing()
            xmlParser.delegate = nil
            lock.unlockWithCondition(LockCondition.Provided)
        }
    }

    @objc func parserDidStartDocument(parser: NSXMLParser) {
        provide(.Event(.StartDocument))
        waitForNextRequest()
    }
    
    @objc func parser(parser: NSXMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String]) {
        depth += 1
        let element = XMLElement(name: elementName, namespaceURI: namespaceURI, qualifiedName: qName, attributes: attributeDict)
        provide(.Event(.StartElement(name: elementName, namespaceURI: namespaceURI, element: element)))
        waitForNextRequest()
    }
    
    @objc func parser(parser: NSXMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        provide(.Event(.EndElement(name: elementName, namespaceURI: namespaceURI)))
        waitForNextRequest()
        depth -= 1
    }
    
    @objc func parser(parser: NSXMLParser, foundCharacters string: String) {
        provide(.Event(.Characters(string)))
        waitForNextRequest()
    }
    
    @objc func parserDidEndDocument(parser: NSXMLParser) {
        provide(.Event(.EndDocument))
    }
    
    @objc func parser(parser: NSXMLParser, parseErrorOccurred parseError: NSError) {
        provide(.Error(XMLPullParserError.ParseError(innerError: parseError)))
    }
}
