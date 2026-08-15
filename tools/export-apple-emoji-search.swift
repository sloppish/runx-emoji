#!/usr/bin/env swift

import CoreFoundation
import Foundation

private let resources = URL(fileURLWithPath: "/System/Library/PrivateFrameworks/CoreEmoji.framework/Versions/A/Resources")
private let model = resources.appendingPathComponent("SearchModel-en")
private let namesURL = resources.appendingPathComponent("en.lproj/AppleName.strings")
private let documentsURL = model.appendingPathComponent("document_index.plist")
private let isoCodesURL = URL(fileURLWithPath: "/usr/share/zoneinfo/iso3166.tab")

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
      FileManager.default.fileExists(atPath: namesURL.path),
      FileManager.default.fileExists(atPath: isoCodesURL.path) else {
    fail("required CoreEmoji or ISO country-code resources are unavailable on this macOS version")
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
let countryCodeWeight = NSNumber(value: Int64(200_000_000_000))
let isoCountryCodes = Set(
    try String(contentsOf: isoCodesURL, encoding: .utf8)
        .split(separator: "\n")
        .filter { !$0.hasPrefix("#") }
        .compactMap { $0.split(separator: "\t").first?.lowercased() }
)

guard isoCountryCodes.count > 200,
      isoCountryCodes.allSatisfy({ code in
          code.utf8.count == 2 && code.utf8.allSatisfy({ (0x61...0x7A).contains($0) })
      }) else {
    fail("unexpected ISO 3166-1 alpha-2 country-code data")
}

func name(for emoji: String) -> String {
    if let exact = names[emoji] { return exact }
    let baseScalars = emoji.unicodeScalars.filter { !(0x1F3FB...0x1F3FF).contains(Int($0.value)) }
    return names[String(String.UnicodeScalarView(baseScalars))] ?? emoji
}

func flag(for countryCode: String) -> String {
    let scalars = countryCode.uppercased().utf8.map {
        UnicodeScalar(0x1F1E6 + Int($0) - 0x41)!
    }
    return String(String.UnicodeScalarView(scalars))
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

for code in isoCountryCodes.sorted() {
    let emoji = flag(for: code)
    var weights = (emojiEntries[emoji]?["terms"] as? [String: NSNumber]) ?? [:]
    weights[code] = countryCodeWeight
    emojiEntries[emoji] = [
        "name": name(for: emoji),
        "terms": weights,
    ]
}

for (code, emoji) in ["nl": "🇳🇱", "at": "🇦🇹", "au": "🇦🇺"] {
    let terms = emojiEntries[emoji]?["terms"] as? [String: NSNumber]
    guard terms?[code] == countryCodeWeight else {
        fail("country-code shortcut \(code) did not resolve to \(emoji)")
    }
}

let output: [String: Any] = [
    "_meta": [
        "format": 1,
        "locale": "en",
        "source": "CoreEmoji SearchModel-en/document_index.plist",
        "country_codes": "/usr/share/zoneinfo/iso3166.tab",
        "system": ProcessInfo.processInfo.operatingSystemVersionString,
    ],
    "emoji": emojiEntries,
]

let json = try JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
try json.write(to: outputURL, options: .atomic)
print("Exported \(emojiEntries.count) weighted emoji entries to \(outputURL.path)")
