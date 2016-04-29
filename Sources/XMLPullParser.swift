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
    
    public func next() -> XMLEvent {
        return internalParser.requestEvent()
    }

    public func abortParsing() {
        internalParser.abortParsing()
    }
}

// MARK: -

@objc private class InternalXMLParser: NSObject, NSXMLParserDelegate {
    enum LockCondition: Int {
        case Requested = 0
        case Provided = 1
    }
    
    enum State {
        case NotStarted
        case Parsing
        case Aborted
        case Ended
    }
    
    let xmlParser: NSXMLParser
    let lock: NSConditionLock
    var currentEvent: XMLEvent
    var state: State
    var depth: Int
    
    // MARK: methods called on original thread
    
    init(xmlParser: NSXMLParser) {
        self.xmlParser = xmlParser
        self.lock = NSConditionLock(condition: LockCondition.Requested.rawValue)
        self.currentEvent = XMLEvent.StartDocument
        self.state = .NotStarted
        self.depth = 0
        
        super.init()
    }

    func abortParsing() {
        guard state == .Parsing else { return }
        
        state = .Aborted
        
        // awake wating parser
        lock.unlockWithCondition(LockCondition.Requested.rawValue)
        
        // wait for aborting
        lock.lockWhenCondition(LockCondition.Provided.rawValue)
        lock.unlock()
    }
    
    func requestEvent() -> XMLEvent {
        switch state {
        case .NotStarted:
            state = .Parsing
            xmlParser.delegate = self
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)) {
                self.lock.lockWhenCondition(LockCondition.Requested.rawValue)
                self.xmlParser.parse()
            }
        case .Parsing:
            lock.unlockWithCondition(LockCondition.Requested.rawValue)
            
        case .Aborted:
            return XMLEvent.EndDocument
            
        case .Ended:
            return XMLEvent.EndDocument
        }
        
        lock.lockWhenCondition(LockCondition.Provided.rawValue)
        switch currentEvent {
        case .EndDocument:
            state = .Ended
        default:
            break
        }
        return currentEvent
    }

    // MARK: methods called on background thread
    
    func provideEvent(event: XMLEvent) {
        currentEvent = event
        lock.unlockWithCondition(LockCondition.Provided.rawValue)
    }
    
    func waitForNextRequest() {
        lock.lockWhenCondition(LockCondition.Requested.rawValue)
        if (state == .Aborted) {
            xmlParser.abortParsing()
            xmlParser.delegate = nil
            lock.unlockWithCondition(LockCondition.Provided.rawValue)
        }
    }

    @objc func parserDidStartDocument(parser: NSXMLParser) {
        provideEvent(XMLEvent.StartDocument)
        waitForNextRequest()
    }
    
    @objc func parser(parser: NSXMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String]) {
        depth += 1
        let element = XMLElement(name: elementName, namespaceURI: namespaceURI, qualifiedName: qName, attributes: attributeDict)
        provideEvent(XMLEvent.StartElement(elementName, namespaceURI, element))
        waitForNextRequest()
    }
    
    @objc func parser(parser: NSXMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        provideEvent(XMLEvent.EndElement(elementName, namespaceURI))
        depth -= 1
        waitForNextRequest()
    }
    
    @objc func parser(parser: NSXMLParser, foundCharacters string: String) {
        provideEvent(XMLEvent.Characters(string))
        waitForNextRequest()
    }
    
    @objc func parserDidEndDocument(parser: NSXMLParser) {
        provideEvent(XMLEvent.EndDocument)
    }
}
