#!/usr/bin/env swift
import Foundation
import Vision

let defaultDataYAML = "ml/datasets/fruit_dataset_26/data.yaml"
let defaultOutput = "ml/audit_reports/dataset_semantic_image_review.csv"
let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "bmp", "webp"]
let fruitSignals: Set<String> = [
    "fruit", "food", "plant", "foliage", "branch", "apple", "orange", "pear",
    "peach", "grape", "persimmon", "strawberry", "coconut", "citrus_fruit",
    "apricot", "berry", "mango", "kiwi"
]
let nonFruitSignals: Set<String> = [
    "animal", "art", "balloon", "bedding", "clothing", "computer", "decoration",
    "document", "furniture", "housewares", "monitor", "room", "screen", "text",
    "underwear", "vehicle"
]
let strongNonFruitSignals: Set<String> = [
    "animal", "bedding", "clothing", "computer", "document", "monitor", "screen",
    "underwear", "vehicle"
]

struct Arguments {
    var dataYAML = defaultDataYAML
    var output = defaultOutput
    var peopleThreshold: Float = 0.45
}

struct ReviewRow {
    let imagePath: String
    let currentClass: String
    let issueType: String
    let confidence: String
    let recommendedAction: String
    let notes: String
}

func usage() {
    print("""
    Usage: audit_dataset_semantic_images.swift [options]

    Read a YOLO dataset with Apple Vision and write semantic review candidates.
    Vision signals always produce manual_review; this tool never changes images,
    labels, or data.yaml.

    Options:
      --data-yaml PATH       YOLO data.yaml (default: \(defaultDataYAML))
      --output PATH          CSV output (default: \(defaultOutput))
      --people-threshold N   Vision people signal threshold (default: 0.45)
      --help                 Show this help
    """)
}

func parseArguments() throws -> Arguments {
    var args = Arguments()
    var index = 1
    let values = CommandLine.arguments
    while index < values.count {
        let value = values[index]
        switch value {
        case "--help", "-h":
            usage()
            exit(0)
        case "--data-yaml", "--output", "--people-threshold":
            guard index + 1 < values.count else {
                throw NSError(domain: "DatasetSemanticAudit", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing value for \(value)"])
            }
            let next = values[index + 1]
            switch value {
            case "--data-yaml": args.dataYAML = next
            case "--output": args.output = next
            case "--people-threshold":
                guard let threshold = Float(next), threshold >= 0, threshold <= 1 else {
                    throw NSError(domain: "DatasetSemanticAudit", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid people threshold: \(next)"])
                }
                args.peopleThreshold = threshold
            default: break
            }
            index += 2
        default:
            throw NSError(domain: "DatasetSemanticAudit", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unknown option: \(value)"])
        }
    }
    return args
}

func repositoryURL(_ value: String) -> URL {
    let url = URL(fileURLWithPath: value)
    if value.hasPrefix("/") {
        return url.standardizedFileURL
    }
    return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent(value)
        .standardizedFileURL
}

func displayPath(_ url: URL) -> String {
    let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).standardizedFileURL.path
    let path = url.standardizedFileURL.path
    if path.hasPrefix(root + "/") {
        return String(path.dropFirst(root.count + 1))
    }
    return path
}

func loadDataYAML(_ url: URL) throws -> (datasetRoot: URL, names: [String], splitPaths: [String: String]) {
    let text = try String(contentsOf: url, encoding: .utf8)
    var dataPath: String?
    var nc: Int?
    var namesByIndex: [Int: String] = [:]
    var splitPaths: [String: String] = [:]
    var inNames = false

    for rawLine in text.components(separatedBy: .newlines) {
        let line = rawLine.components(separatedBy: "#").first ?? ""
        if line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            continue
        }
        if inNames && line.hasPrefix(" ") {
            let item = line.trimmingCharacters(in: .whitespaces)
            let parts = item.split(
                separator: ":",
                maxSplits: 1,
                omittingEmptySubsequences: false
            ).map(String.init)
            if parts.count == 2, let index = Int(parts[0].trimmingCharacters(in: .whitespaces)) {
                namesByIndex[index] = parts[1].trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            }
            continue
        }
        inNames = false
        let parts = line.split(
            separator: ":",
            maxSplits: 1,
            omittingEmptySubsequences: false
        ).map(String.init)
        guard parts.count == 2 else { continue }
        let key = parts[0].trimmingCharacters(in: .whitespaces)
        let value = parts[1].trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        switch key {
        case "path": dataPath = value
        case "nc": nc = Int(value)
        case "train", "val", "test": splitPaths[key] = value
        case "names": inNames = value.isEmpty
        default: break
        }
    }

    guard let nc, nc > 0 else {
        throw NSError(domain: "DatasetSemanticAudit", code: 1, userInfo: [NSLocalizedDescriptionKey: "data.yaml has no valid nc"])
    }
    let names = (0..<nc).map { namesByIndex[$0] ?? "" }
    guard names.allSatisfy({ !$0.isEmpty }) else {
        throw NSError(domain: "DatasetSemanticAudit", code: 1, userInfo: [NSLocalizedDescriptionKey: "data.yaml has incomplete names"])
    }
    let rawRoot = dataPath ?? url.deletingLastPathComponent().path
    let root = rawRoot.hasPrefix("/")
        ? URL(fileURLWithPath: rawRoot)
        : URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(rawRoot)
    return (root.standardizedFileURL, names, splitPaths)
}

func labelDirectory(for imageDirectory: URL, datasetRoot: URL) throws -> URL {
    let relative = imageDirectory.standardizedFileURL.path.replacingOccurrences(of: datasetRoot.path + "/", with: "")
    let parts = relative.split(separator: "/").map(String.init)
    guard let imagesIndex = parts.firstIndex(of: "images") else {
        throw NSError(domain: "DatasetSemanticAudit", code: 1, userInfo: [NSLocalizedDescriptionKey: "Image directory is not under images/: \(imageDirectory.path)"])
    }
    var labelParts = parts
    labelParts[imagesIndex] = "labels"
    return labelParts.reduce(datasetRoot) { $0.appendingPathComponent($1) }
}

func classesForLabel(_ url: URL, names: [String]) -> String {
    guard let text = try? String(contentsOf: url, encoding: .utf8) else { return "unknown" }
    var ids = Set<Int>()
    for line in text.components(separatedBy: .newlines) {
        let fields = line.split(separator: " ")
        guard let first = fields.first, let value = Double(first), value.rounded() == value else { continue }
        let id = Int(value)
        if names.indices.contains(id) { ids.insert(id) }
    }
    let values = ids.sorted().map { names[$0] }
    return values.isEmpty ? "unknown" : values.joined(separator: "|")
}

func csvCell(_ value: String) -> String {
    if value.contains(",") || value.contains("\"") || value.contains("\n") {
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
    return value
}

func score(_ identifier: String, in observations: [VNClassificationObservation]) -> Float {
    observations.first(where: { $0.identifier == identifier })?.confidence ?? 0
}

func topObservations(_ observations: [VNClassificationObservation]) -> String {
    observations.prefix(5).map { observation in
        "\(observation.identifier)=\(String(format: "%.3f", observation.confidence))"
    }.joined(separator: "; ")
}

func semanticCandidate(
    imageURL: URL,
    currentClass: String,
    observations: [VNClassificationObservation],
    peopleThreshold: Float
) -> ReviewRow? {
    let people = max(score("people", in: observations), score("person", in: observations))
    let fruit = observations.filter { fruitSignals.contains($0.identifier) }.map(\.confidence).max() ?? 0
    let strongestNonFruit = observations.filter { nonFruitSignals.contains($0.identifier) }.max { $0.confidence < $1.confidence }
    let expected = Set(currentClass.split(separator: "|").map(String.init))
    let namedFruit = observations.filter { observation in
        ["apple", "orange", "pear", "peach", "grape", "persimmon", "strawberry", "coconut", "mango", "kiwi"].contains(observation.identifier)
    }.max { $0.confidence < $1.confidence }
    let notes = "Vision top labels: \(topObservations(observations))"

    if people >= peopleThreshold && fruit < 0.25 {
        return ReviewRow(
            imagePath: displayPath(imageURL),
            currentClass: currentClass,
            issueType: "vision_people_without_fruit_signal",
            confidence: String(format: "vision_people_%.3f", people),
            recommendedAction: "manual_review",
            notes: notes
        )
    }
    if let nonFruit = strongestNonFruit, nonFruit.confidence >= 0.55, fruit < 0.25 {
        let strongEvidence = strongNonFruitSignals.contains(nonFruit.identifier)
            && nonFruit.confidence >= 0.85
        return ReviewRow(
            imagePath: displayPath(imageURL),
            currentClass: currentClass,
            issueType: "vision_nonfruit_signal",
            confidence: String(format: "vision_\(nonFruit.identifier)_%.3f", nonFruit.confidence),
            recommendedAction: strongEvidence ? "exclude_from_training" : "manual_review",
            notes: notes
        )
    }
    if let namedFruit, namedFruit.confidence >= 0.75, !expected.contains(namedFruit.identifier) {
        return ReviewRow(
            imagePath: displayPath(imageURL),
            currentClass: currentClass,
            issueType: "vision_fruit_class_disagreement",
            confidence: String(format: "vision_\(namedFruit.identifier)_%.3f", namedFruit.confidence),
            recommendedAction: "manual_review",
            notes: notes
        )
    }
    return nil
}

func inspectImage(
    imageURL: URL,
    labelURL: URL,
    names: [String],
    peopleThreshold: Float
) -> ReviewRow? {
    let request = VNClassifyImageRequest()
    let handler = VNImageRequestHandler(url: imageURL)
    do {
        try handler.perform([request])
        return semanticCandidate(
            imageURL: imageURL,
            currentClass: classesForLabel(labelURL, names: names),
            observations: request.results ?? [],
            peopleThreshold: peopleThreshold
        )
    } catch {
        return ReviewRow(
            imagePath: displayPath(imageURL),
            currentClass: classesForLabel(labelURL, names: names),
            issueType: "vision_classification_failure",
            confidence: "low_runtime_failure",
            recommendedAction: "manual_review",
            notes: "Vision could not classify the image: \(error.localizedDescription)"
        )
    }
}

do {
    let args = try parseArguments()
    let dataYAML = repositoryURL(args.dataYAML)
    let output = repositoryURL(args.output)
    let dataset = try loadDataYAML(dataYAML)
    var rows: [ReviewRow] = []
    var scanned = 0

    for split in ["train", "val", "test"] {
        guard let configuredPath = dataset.splitPaths[split] else { continue }
        let imageDirectory = configuredPath.hasPrefix("/")
            ? URL(fileURLWithPath: configuredPath)
            : dataset.datasetRoot.appendingPathComponent(configuredPath)
        let labelDirectory = try labelDirectory(for: imageDirectory, datasetRoot: dataset.datasetRoot)
        let enumerator = FileManager.default.enumerator(
            at: imageDirectory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        var imageURLs: [URL] = []
        while let url = enumerator?.nextObject() as? URL {
            guard imageExtensions.contains(url.pathExtension.lowercased()) else { continue }
            imageURLs.append(url)
        }
        for imageURL in imageURLs.sorted(by: { $0.path < $1.path }) {
            let relativePath = imageURL.path.replacingOccurrences(of: imageDirectory.path + "/", with: "")
            let labelURL = labelDirectory.appendingPathComponent(relativePath).deletingPathExtension().appendingPathExtension("txt")
            let candidate = autoreleasepool(invoking: {
                inspectImage(
                    imageURL: imageURL,
                    labelURL: labelURL,
                    names: dataset.names,
                    peopleThreshold: args.peopleThreshold
                )
            })
            if let candidate { rows.append(candidate) }
            scanned += 1
            if scanned.isMultiple(of: 250) {
                FileHandle.standardError.write(Data("Scanned \(scanned) images\n".utf8))
            }
        }
    }

    try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
    let header = "image_path,current_class,issue_type,confidence,recommended_action,notes\n"
    let body = rows.sorted { $0.imagePath < $1.imagePath }.map { row in
        [row.imagePath, row.currentClass, row.issueType, row.confidence, row.recommendedAction, row.notes]
            .map(csvCell)
            .joined(separator: ",")
    }.joined(separator: "\n")
    try (header + body + (body.isEmpty ? "" : "\n")).write(to: output, atomically: true, encoding: .utf8)
    let issues = Dictionary(grouping: rows, by: \.issueType).mapValues(\.count)
    let issueSummary = issues.keys.sorted().map { "\($0)=\(issues[$0] ?? 0)" }.joined(separator: ", ")
    print("Scanned images: \(scanned)")
    print("Semantic review rows: \(rows.count)")
    print("Issues: \(issueSummary.isEmpty ? "none" : issueSummary)")
    print("Report written: \(displayPath(output))")
} catch {
    FileHandle.standardError.write(Data("ERROR: \(error.localizedDescription)\n".utf8))
    exit(2)
}
