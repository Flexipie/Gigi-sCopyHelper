//
//  main.swift
//  GigiCopyNMHost
//
//  Created by Felix Westin on 2025-09-05.
//

import Foundation

// Native Messaging host for Chrome: com.gigi.copytool
// Protocol: 4-byte little-endian length + UTF-8 JSON

struct Clip: Codable {
    let id: String
    let text: String
    let app: String
    let createdAt: Date
}

struct OutgoingClip: Codable {
    let type: String = "clip"
    let id: String
    let text: String
    let app: String
    let createdAt: TimeInterval
}

// MARK: - Paths
let helperBundleId = "Flexipie.GigiCopyHelper" // matches your menubar app bundle ID

func queueURLCandidates() -> [URL] {
    let fm = FileManager.default
    let home = fm.homeDirectoryForCurrentUser

    // Non-sandbox path
    let nonSandbox = home
        .appendingPathComponent("Library")
        .appendingPathComponent("Application Support")
        .appendingPathComponent("GigiCopyHelper")
        .appendingPathComponent("queue.json")

    // Sandboxed app container path (when App Sandbox is enabled)
    let sandbox = home
        .appendingPathComponent("Library")
        .appendingPathComponent("Containers")
        .appendingPathComponent(helperBundleId)
        .appendingPathComponent("Data")
        .appendingPathComponent("Library")
        .appendingPathComponent("Application Support")
        .appendingPathComponent("GigiCopyHelper")
        .appendingPathComponent("queue.json")

    return [sandbox, nonSandbox]
}

func locateQueue() -> URL {
    let fm = FileManager.default
    for url in queueURLCandidates() {
        if fm.fileExists(atPath: url.path) {
            return url
        }
    }
    // Fallback: create non-sandbox tree
    let fallbackDir = fm.homeDirectoryForCurrentUser
        .appendingPathComponent("Library")
        .appendingPathComponent("Application Support")
        .appendingPathComponent("GigiCopyHelper")
    try? fm.createDirectory(at: fallbackDir, withIntermediateDirectories: true)
    return fallbackDir.appendingPathComponent("queue.json")
}

// MARK: - Native Messaging IO
func readNMMessage() -> [String: Any]? {
    let stdinHandle = FileHandle.standardInput
    guard let lenData = try? stdinHandle.read(upToCount: 4), lenData.count == 4 else {
        return nil
    }
    let length = lenData.withUnsafeBytes { ptr -> UInt32 in
        ptr.load(as: UInt32.self).littleEndian
    }
    let toRead = Int(length)
    guard toRead > 0, let payload = try? stdinHandle.read(upToCount: toRead), payload.count == toRead else {
        return nil
    }
    if let obj = try? JSONSerialization.jsonObject(with: payload, options: []), let dict = obj as? [String: Any] {
        return dict
    }
    return nil
}

func writeNM<T: Encodable>(_ value: T) {
    let enc = JSONEncoder()
    enc.dateEncodingStrategy = .secondsSince1970
    guard let data = try? enc.encode(value) else { return }
    var length = UInt32(data.count)
    let out = withUnsafeBytes(of: &length) { Data($0) } + data
    _ = try? FileHandle.standardOutput.write(out)
}

// MARK: - Drain logic
func drainQueue() {
    let url = locateQueue()
    let fm = FileManager.default
    guard let data = try? Data(contentsOf: url) else { return }
    let decoder = JSONDecoder()
    if let clips = try? decoder.decode([Clip].self, from: data) {
        for c in clips {
            let oc = OutgoingClip(id: c.id, text: c.text, app: c.app, createdAt: c.createdAt.timeIntervalSince1970)
            writeNM(oc)
        }
        // Truncate the queue after successful send
        if fm.fileExists(atPath: url.path) {
            try? Data("[]".utf8).write(to: url)
        }
    }
}

// Entry point: wait for a message (e.g., {"type":"drain"}), then drain and exit.
_ = readNMMessage()
drainQueue()

