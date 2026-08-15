#!/usr/bin/env swift

import CoreFoundation
import Foundation

private let resources = URL(fileURLWithPath: "/System/Library/PrivateFrameworks/CoreEmoji.framework/Versions/A/Resources")
private let model = resources.appendingPathComponent("SearchModel-en")
private let namesURL = resources.appendingPathComponent("en.lproj/AppleName.strings")
private let documentsURL = model.appendingPathComponent("document_index.plist")

private func readPropertyList(at url: URL) throws -> Any {
    let data = try Data(contentsOf: url)
    return try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
}

private func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data(("error: \(message)\n").utf8))
    exit(1)
}

typealias CreateLocaleData = @convention(c) (CFLocaleIdentifier) -> CFTypeRef
typealias CreateTokenWithIndex = @convention(c) (CFIndex, CFTypeRef) -> CFTypeRef?
typealias GetTokenString = @convention(c) (CFTypeRef) -> CFString

private func loadSymbol<T>(_ handle: UnsafeMutableRawPointer, _ name: String, as type: T.Type) -> T {
    guard let pointer = dlsym(handle, name) else { fail("CoreEmoji has no \(name) symbol") }
    return unsafeBitCast(pointer, to: type)
}

let outputURL = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "emoji-search.json")

guard FileManager.default.fileExists(atPath: documentsURL.path),
      FileManager.default.fileExists(atPath: namesURL.path) else {
    fail("Apple's English CoreEmoji search resources are unavailable on this macOS version")
}

guard dlopen("/System/Library/PrivateFrameworks/CoreEmoji.framework/CoreEmoji", RTLD_NOW) != nil,
      let processHandle = dlopen(nil, RTLD_NOW) else {
    fail("could not load Apple's private CoreEmoji framework")
}

guard let documents = try readPropertyList(at: documentsURL) as? [String: [String: [String: NSNumber]]],
      let names = try readPropertyList(at: namesURL) as? [String: String] else {
    fail("unexpected CoreEmoji property-list shape")
}

let createLocaleData = loadSymbol(processHandle, "CEMCreateEmojiLocaleData", as: CreateLocaleData.self)
let createToken = loadSymbol(processHandle, "CEMEmojiTokenCreateWithIndex", as: CreateTokenWithIndex.self)
let getTokenString = loadSymbol(processHandle, "CEMEmojiTokenGetString", as: GetTokenString.self)
let localeData = createLocaleData(CFLocaleGetIdentifier(CFLocaleCopyCurrent()))

var emojiEntries: [String: [String: Any]] = [:]

func name(for emoji: String) -> String {
    if let exact = names[emoji] { return exact }
    let baseScalars = emoji.unicodeScalars.filter { !(0x1F3FB...0x1F3FF).contains(Int($0.value)) }
    return names[String(String.UnicodeScalarView(baseScalars))] ?? emoji
}

for documentID in documents.keys.compactMap(Int.init).sorted() {
    guard let document = documents[String(documentID)],
          let token = createToken(documentID, localeData) else {
        fail("could not resolve CoreEmoji document \(documentID)")
    }

    let emoji = getTokenString(token) as String
    guard !emoji.isEmpty else { fail("CoreEmoji document \(documentID) resolved to an empty string") }

    var weights = (emojiEntries[emoji]?["terms"] as? [String: NSNumber]) ?? [:]
    for (term, attributes) in document {
        guard let weight = attributes["w"] else { fail("term \(term) in document \(documentID) has no weight") }
        if weights[term] == nil || weight.int64Value > weights[term]!.int64Value {
            weights[term] = weight
        }
    }

    emojiEntries[emoji] = [
        "name": name(for: emoji),
        "terms": weights,
    ]
}

let output: [String: Any] = [
    "_meta": [
        "format": 1,
        "locale": "en",
        "source": "CoreEmoji SearchModel-en/document_index.plist",
        "system": ProcessInfo.processInfo.operatingSystemVersionString,
    ],
    "emoji": emojiEntries,
]

let json = try JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
try json.write(to: outputURL, options: .atomic)
print("Exported \(emojiEntries.count) weighted emoji entries to \(outputURL.path)")
