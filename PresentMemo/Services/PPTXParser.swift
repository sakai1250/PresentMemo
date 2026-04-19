import Foundation
import CoreGraphics
import ImageIO
import Vision

/// Parses a .pptx file (which is a ZIP archive of XML files).
/// Extracts slide body text and speaker notes without external dependencies
/// by using the built-in libcompression / raw ZIP local-file-header parsing.
class PPTXParser {

    struct Slide {
        var bodyText: String
        var notes: String
    }

    func parse(url: URL) throws -> [Slide] {
        let data = try Data(contentsOf: url)
        let entries = try ZIPReader.entries(from: data)
        let entryMap = Dictionary(uniqueKeysWithValues: entries.map { ($0.name, $0.data) })

        // Collect slide and notes entries, sorted by slide number
        let slideEntries = entries
            .filter { $0.name.hasPrefix("ppt/slides/slide") && $0.name.hasSuffix(".xml") && !$0.name.contains("_rels") }
            .sorted { slideNumber($0.name) < slideNumber($1.name) }

        let notesEntries = entries
            .filter { $0.name.hasPrefix("ppt/notesSlides/notesSlide") && $0.name.hasSuffix(".xml") && !$0.name.contains("_rels") }
            .sorted { slideNumber($0.name) < slideNumber($1.name) }

        var slides: [Slide] = []
        for (i, entry) in slideEntries.enumerated() {
            let body = extractText(from: entry.data)
            let imageOCRText = extractImageText(forSlidePath: entry.name, entryMap: entryMap)
            let notes: String
            if i < notesEntries.count {
                notes = extractText(from: notesEntries[i].data)
            } else {
                notes = ""
            }
            let mergedBody = [body, imageOCRText]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            slides.append(Slide(bodyText: mergedBody, notes: notes))
        }
        return slides
    }

    private func slideNumber(_ name: String) -> Int {
        let digits = name.components(separatedBy: CharacterSet.decimalDigits.inverted)
            .filter { !$0.isEmpty }
            .compactMap { Int($0) }
        return digits.last ?? 0
    }

    /// Extract all <a:t> text runs from OOXML
    private func extractText(from data: Data) -> String {
        OOXMLTextExtractor.extract(from: data)
    }

    private func extractImageText(forSlidePath slidePath: String, entryMap: [String: Data]) -> String {
        let relsPath = relationshipsPath(for: slidePath)
        guard let relsData = entryMap[relsPath] else { return "" }

        let imageTargets = OOXMLImageRelationshipExtractor.extractImageTargets(from: relsData)
        guard !imageTargets.isEmpty else { return "" }

        var texts: [String] = []
        for target in imageTargets {
            let resolved = resolveOOXMLPath(target: target, relativeTo: slidePath)
            guard let data = entryMap[resolved], let image = cgImage(from: data) else { continue }
            let text = recognizeText(from: image)
            if !text.isEmpty {
                texts.append(text)
            }
        }
        return texts.joined(separator: " ")
    }

    private func relationshipsPath(for slidePath: String) -> String {
        let fileName = (slidePath as NSString).lastPathComponent
        let dir = (slidePath as NSString).deletingLastPathComponent
        return "\(dir)/_rels/\(fileName).rels"
    }

    private func resolveOOXMLPath(target: String, relativeTo basePath: String) -> String {
        let baseDir = (basePath as NSString).deletingLastPathComponent
        let joined = "\(baseDir)/\(target)"
        let standardized = (joined as NSString).standardizingPath
        return standardized.hasPrefix("/") ? String(standardized.dropFirst()) : standardized
    }

    private func cgImage(from data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    private func recognizeText(from image: CGImage) -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["en-US", "ja-JP"]

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
            let lines = (request.results ?? [])
                .compactMap { $0.topCandidates(1).first?.string }
            return lines.joined(separator: " ")
        } catch {
            return ""
        }
    }
}

// MARK: - Minimal ZIP reader (no external dependencies)

private enum ZIPReader {
    struct Entry {
        let name: String
        let data: Data
    }

    enum ZIPError: Error { case invalid, unsupportedCompression }

    private struct CentralDirectoryEntry {
        let name: String
        let compression: UInt16
        let compressedSize: Int
        let uncompressedSize: Int
        let localHeaderOffset: Int
    }

    static func entries(from archive: Data) throws -> [Entry] {
        let bytes = [UInt8](archive)
        let centralEntries = try readCentralDirectory(bytes: bytes)
        var entries: [Entry] = []
        entries.reserveCapacity(centralEntries.count)

        for cde in centralEntries where !cde.name.isEmpty && !cde.name.hasSuffix("/") {
            let localOffset = cde.localHeaderOffset
            guard localOffset + 30 <= bytes.count else { continue }
            guard readUInt32(bytes, localOffset) == 0x04034B50 else { continue } // local file header

            let nameLen = Int(readUInt16(bytes, localOffset + 26))
            let extraLen = Int(readUInt16(bytes, localOffset + 28))
            let dataStart = localOffset + 30 + nameLen + extraLen
            let dataEnd = dataStart + cde.compressedSize
            guard dataStart >= 0, dataEnd <= bytes.count, dataStart <= dataEnd else { continue }

            let compressedData = Data(bytes[dataStart..<dataEnd])
            let fileData: Data
            switch cde.compression {
            case 0:
                fileData = compressedData
            case 8:
                fileData = (try? compressedData.decompressDeflate(expectedSize: cde.uncompressedSize)) ?? Data()
            default:
                fileData = Data()
            }

            entries.append(Entry(name: cde.name, data: fileData))
        }
        return entries
    }

    private static func readCentralDirectory(bytes: [UInt8]) throws -> [CentralDirectoryEntry] {
        let eocdOffset = try findEOCD(bytes: bytes)
        let totalEntries = Int(readUInt16(bytes, eocdOffset + 10))
        let centralDirSize = Int(readUInt32(bytes, eocdOffset + 12))
        let centralDirOffset = Int(readUInt32(bytes, eocdOffset + 16))

        guard centralDirOffset >= 0, centralDirSize >= 0, centralDirOffset + centralDirSize <= bytes.count else {
            throw ZIPError.invalid
        }

        var entries: [CentralDirectoryEntry] = []
        entries.reserveCapacity(totalEntries)

        var offset = centralDirOffset
        while offset + 46 <= bytes.count, entries.count < totalEntries {
            guard readUInt32(bytes, offset) == 0x02014B50 else { break } // central dir header

            let compression = readUInt16(bytes, offset + 10)
            let compressedSize = Int(readUInt32(bytes, offset + 20))
            let uncompressedSize = Int(readUInt32(bytes, offset + 24))
            let nameLen = Int(readUInt16(bytes, offset + 28))
            let extraLen = Int(readUInt16(bytes, offset + 30))
            let commentLen = Int(readUInt16(bytes, offset + 32))
            let localHeaderOffset = Int(readUInt32(bytes, offset + 42))

            let nameStart = offset + 46
            let nameEnd = nameStart + nameLen
            guard nameEnd <= bytes.count else { break }
            let name = String(bytes: bytes[nameStart..<nameEnd], encoding: .utf8) ?? ""

            entries.append(
                CentralDirectoryEntry(
                    name: name,
                    compression: compression,
                    compressedSize: compressedSize,
                    uncompressedSize: uncompressedSize,
                    localHeaderOffset: localHeaderOffset
                )
            )

            offset = nameEnd + extraLen + commentLen
        }

        return entries
    }

    private static func findEOCD(bytes: [UInt8]) throws -> Int {
        // EOCD can be located in the last 65,557 bytes.
        let minSearch = Swift.max(0, bytes.count - 65_557)
        let signature: UInt32 = 0x06054B50
        guard bytes.count >= 22 else { throw ZIPError.invalid }

        var i = bytes.count - 22
        while i >= minSearch {
            if readUInt32(bytes, i) == signature {
                return i
            }
            i -= 1
        }
        throw ZIPError.invalid
    }

    private static func readUInt16(_ bytes: [UInt8], _ offset: Int) -> UInt16 {
        UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8)
    }

    private static func readUInt32(_ bytes: [UInt8], _ offset: Int) -> UInt32 {
        UInt32(bytes[offset]) |
        (UInt32(bytes[offset + 1]) << 8) |
        (UInt32(bytes[offset + 2]) << 16) |
        (UInt32(bytes[offset + 3]) << 24)
    }
}

// MARK: - Raw DEFLATE decompression via zlib

import Compression

private extension Data {
    func decompressDeflate(expectedSize: Int) throws -> Data {
        // Apple's Compression framework supports ZLIB (which wraps DEFLATE).
        // We prepend a zlib header (0x78 0x9C) so the algorithm can decode it.
        var src = Data([0x78, 0x9C]) + self
        var dst = Data(count: Swift.max(expectedSize, 1024))
        let written = src.withUnsafeMutableBytes { srcBuf in
            dst.withUnsafeMutableBytes { dstBuf in
                compression_decode_buffer(
                    dstBuf.baseAddress!.assumingMemoryBound(to: UInt8.self),
                    dstBuf.count,
                    srcBuf.baseAddress!.assumingMemoryBound(to: UInt8.self),
                    srcBuf.count,
                    nil,
                    COMPRESSION_ZLIB
                )
            }
        }
        guard written > 0 else { return Data() }
        return dst.prefix(written)
    }
}

private final class OOXMLTextExtractor: NSObject, XMLParserDelegate {
    private var collected: [String] = []
    private var currentText = ""
    private var isInTextNode = false

    static func extract(from data: Data) -> String {
        let extractor = OOXMLTextExtractor()
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true
        parser.delegate = extractor
        _ = parser.parse()

        return extractor.collected
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    func parser(_ parser: XMLParser,
                didStartElement elementName: String,
                namespaceURI: String?,
                qualifiedName qName: String?,
                attributes attributeDict: [String : String] = [:]) {
        if elementName == "t" || qName == "a:t" {
            isInTextNode = true
            currentText = ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard isInTextNode else { return }
        currentText += string
    }

    func parser(_ parser: XMLParser,
                didEndElement elementName: String,
                namespaceURI: String?,
                qualifiedName qName: String?) {
        if elementName == "t" || qName == "a:t" {
            if !currentText.isEmpty {
                collected.append(currentText)
            }
            currentText = ""
            isInTextNode = false
        }
    }
}

private final class OOXMLImageRelationshipExtractor: NSObject, XMLParserDelegate {
    private var targets: [String] = []

    static func extractImageTargets(from data: Data) -> [String] {
        let extractor = OOXMLImageRelationshipExtractor()
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true
        parser.delegate = extractor
        _ = parser.parse()
        return extractor.targets
    }

    func parser(_ parser: XMLParser,
                didStartElement elementName: String,
                namespaceURI: String?,
                qualifiedName qName: String?,
                attributes attributeDict: [String : String] = [:]) {
        let name = qName ?? elementName
        guard name.hasSuffix("Relationship") || elementName == "Relationship" else { return }

        let type = attributeDict["Type"] ?? ""
        let target = attributeDict["Target"] ?? ""
        guard type.contains("/image"), !target.isEmpty else { return }
        targets.append(target)
    }
}
