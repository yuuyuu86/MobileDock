//
//  FileService.swift
//  MobileDock for Mac — files pushed from the device, and the Finder selection
//  pulled the other way.
//

import Foundation
import AppKit

@MainActor
final class FileService {

    struct Incoming {
        var name: String
        var total: Int
        var parts: [Int: Data] = [:]
    }

    static let chunkBytes = 512 * 1024

    private var transfers: [String: Incoming] = [:]

    /// Returns the saved file's path once the last chunk lands.
    func receive(_ chunk: FileChunk) -> (name: String, path: String)? {
        var transfer = transfers[chunk.transferID] ?? Incoming(name: chunk.name, total: chunk.total)
        transfer.parts[chunk.index] = chunk.data
        transfers[chunk.transferID] = transfer

        guard transfer.parts.count == transfer.total else { return nil }
        transfers.removeValue(forKey: chunk.transferID)

        var data = Data()
        for index in 0..<transfer.total {
            guard let part = transfer.parts[index] else { return nil }
            data.append(part)
        }

        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Downloads")
        let url = uniqueURL(in: downloads, name: transfer.name)
        do {
            try data.write(to: url)
        } catch {
            NSLog("MobileDock: could not save \(transfer.name) — \(error.localizedDescription)")
            return nil
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
        return (transfer.name, url.path)
    }

    private func uniqueURL(in directory: URL, name: String) -> URL {
        let fm = FileManager.default
        var candidate = directory.appendingPathComponent(name)
        guard fm.fileExists(atPath: candidate.path) else { return candidate }

        let base = candidate.deletingPathExtension().lastPathComponent
        let ext = candidate.pathExtension
        var index = 2
        repeat {
            let suffixed = ext.isEmpty ? "\(base) \(index)" : "\(base) \(index).\(ext)"
            candidate = directory.appendingPathComponent(suffixed)
            index += 1
        } while fm.fileExists(atPath: candidate.path)
        return candidate
    }

    /// Whatever is selected in Finder right now, ready to stream to the device.
    func finderSelection(maxBytes: Int = 12 * 1024 * 1024) -> [(name: String, data: Data)] {
        let script = """
        tell application "Finder"
            if (count of (selection as list)) is 0 then return ""
            set output to ""
            repeat with item_ in (selection as list)
                set output to output & POSIX path of (item_ as alias) & linefeed
            end repeat
            return output
        end tell
        """
        guard let raw = Shell.run("/usr/bin/osascript", ["-e", script]) else { return [] }
        let paths = raw.split(separator: "\n").map(String.init).filter { !$0.isEmpty }

        var files: [(String, Data)] = []
        for path in paths.prefix(5) {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
                  !isDirectory.boolValue,
                  let data = FileManager.default.contents(atPath: path),
                  data.count <= maxBytes else { continue }
            files.append(((path as NSString).lastPathComponent, data))
        }
        return files
    }
}
