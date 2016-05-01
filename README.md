# XMLPullitic

[![CI Status](http://img.shields.io/travis/hironytic/XMLPullitic.svg?style=flat)](https://travis-ci.org/hironytic/XMLPullitic)
[![Version](https://img.shields.io/cocoapods/v/XMLPullitic.svg?style=flat)](http://cocoapods.org/pods/XMLPullitic)
[![License](https://img.shields.io/cocoapods/l/XMLPullitic.svg?style=flat)](http://cocoapods.org/pods/XMLPullitic)
[![Platform](https://img.shields.io/cocoapods/p/XMLPullitic.svg?style=flat)](http://cocoapods.org/pods/XMLPullitic)
[![Carthage compatible](https://img.shields.io/badge/Carthage-compatible-4BC51D.svg?style=flat)](https://github.com/Carthage/Carthage)

XML pull parser for Swift

## Usage

```swift
let xml = "<?xml version=\"1.0\" encoding=\"UTF-8\" ?><foo>Hello World!</foo>"
if let parser = XMLPullParser(string: xml) {
    do {
        parsing: while true {
            switch try parser.next() {
            case .StartDocument:
                print("start document")
            case .StartElement(let name, _, _):
                print("start element: \(name)")
            case .Characters(let text):
                print("text: \(text)")
            case .EndElement(let name, _):
                print("end element: \(name)")
            case .EndDocument:
                print("end document")
                break parsing
            }
        }
    } catch let error {
        print("error: \(error)")
    }
}
```

## Requirements

- iOS 8.0+

## Installation

### CocoaPods

XMLPullitic is available through [CocoaPods](http://cocoapods.org).
To install it, simply add the following lines to your Podfile:

```ruby
use_frameworks!
pod "XMLPullitic"
```

### Carthage

XMLPullitic is available through [Carthage](https://github.com/Carthage/Carthage).
To install it, simply add the following line to your Cartfile:

```
github "hironytic/XMLPullitic"
```

## Author

Hironori Ichimiya, hiron@hironytic.com

## License

XMLPullitic is available under the MIT license. See the LICENSE file for more info.
