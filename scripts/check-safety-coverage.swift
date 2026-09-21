#!/usr/bin/swift

import Foundation

private enum CoverageGateError: Error {
    case invalidArguments
    case invalidMinimum
    case unreadableSourceRoot
    case missingProductionSource
    case malformedCoverage
    case missingCoverage
    case duplicateCoverage
    case invalidLineCounts
    case zeroExecutableLines
    case arithmeticOverflow
    case belowMinimum
}

private struct Arguments {
    let input: URL
    let sourceRoot: URL
    let minimum: Int
}

private struct LineCounts {
    let executable: Int
    let covered: Int
}

private func fail(_ error: CoverageGateError) -> Never {
    let rule: String

    switch error {
    case .invalidArguments:
        rule = "SC-COVERAGE-ARGUMENTS"
    case .invalidMinimum:
        rule = "SC-COVERAGE-MINIMUM"
    case .unreadableSourceRoot:
        rule = "SC-COVERAGE-SOURCE-ROOT"
    case .missingProductionSource:
        rule = "SC-COVERAGE-PRODUCTION-SOURCE"
    case .malformedCoverage:
        rule = "SC-COVERAGE-MALFORMED"
    case .missingCoverage:
        rule = "SC-COVERAGE-MISSING-SOURCE"
    case .duplicateCoverage:
        rule = "SC-COVERAGE-DUPLICATE-SOURCE"
    case .invalidLineCounts:
        rule = "SC-COVERAGE-LINE-COUNTS"
    case .zeroExecutableLines:
        rule = "SC-COVERAGE-ZERO-LINES"
    case .arithmeticOverflow:
        rule = "SC-COVERAGE-ARITHMETIC"
    case .belowMinimum:
        rule = "SC-COVERAGE-BELOW-MINIMUM"
    }

    FileHandle.standardError.write(Data("\(rule)\n".utf8))
    exit(1)
}

private func canonicalURL(for path: String, relativeTo workingDirectory: URL) -> URL {
    let url: URL
    if path.hasPrefix("/") {
        url = URL(fileURLWithPath: path)
    } else {
        url = workingDirectory.appendingPathComponent(path)
    }
    return url.standardizedFileURL.resolvingSymlinksInPath()
}

private func parseArguments() throws -> Arguments {
    let values = Array(CommandLine.arguments.dropFirst())
    guard values.count == 6 else {
        throw CoverageGateError.invalidArguments
    }

    var inputPath: String?
    var sourceRootPath: String?
    var minimumText: String?
    var index = 0

    while index < values.count {
        let option = values[index]
        let value = values[index + 1]
        switch option {
        case "--input" where inputPath == nil:
            inputPath = value
        case "--source-root" where sourceRootPath == nil:
            sourceRootPath = value
        case "--minimum" where minimumText == nil:
            minimumText = value
        default:
            throw CoverageGateError.invalidArguments
        }
        index += 2
    }

    guard
        let inputPath,
        let sourceRootPath,
        let minimumText,
        let minimum = Int(minimumText),
        (1...100).contains(minimum)
    else {
        throw CoverageGateError.invalidMinimum
    }

    let workingDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
    return Arguments(
        input: canonicalURL(for: inputPath, relativeTo: workingDirectory),
        sourceRoot: canonicalURL(for: sourceRootPath, relativeTo: workingDirectory),
        minimum: minimum
    )
}

private func productionSources(in sourceRoot: URL) throws -> Set<String> {
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: sourceRoot.path, isDirectory: &isDirectory), isDirectory.boolValue else {
        throw CoverageGateError.unreadableSourceRoot
    }

    guard let enumerator = FileManager.default.enumerator(
        at: sourceRoot,
        includingPropertiesForKeys: [.isRegularFileKey],
        options: [.skipsHiddenFiles]
    ) else {
        throw CoverageGateError.unreadableSourceRoot
    }

    var sources = Set<String>()
    for case let fileURL as URL in enumerator {
        let resourceValues = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
        guard resourceValues.isRegularFile == true, fileURL.pathExtension == "swift" else {
            continue
        }
        sources.insert(fileURL.standardizedFileURL.resolvingSymlinksInPath().path)
    }

    guard !sources.isEmpty else {
        throw CoverageGateError.missingProductionSource
    }
    return sources
}

private func integerCount(from value: Any?) throws -> Int {
    guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else {
        throw CoverageGateError.invalidLineCounts
    }

    guard let count = Int(number.stringValue), count >= 0 else {
        throw CoverageGateError.invalidLineCounts
    }
    return count
}

private func checkedAdd(_ lhs: Int, _ rhs: Int) throws -> Int {
    let result = lhs.addingReportingOverflow(rhs)
    guard !result.overflow else {
        throw CoverageGateError.arithmeticOverflow
    }
    return result.partialValue
}

private func checkedMultiply(_ lhs: Int, _ rhs: Int) throws -> Int {
    let result = lhs.multipliedReportingOverflow(by: rhs)
    guard !result.overflow else {
        throw CoverageGateError.arithmeticOverflow
    }
    return result.partialValue
}

private func coverageCounts(from input: URL, sources: Set<String>) throws -> [String: LineCounts] {
    guard let data = try? Data(contentsOf: input) else {
        throw CoverageGateError.malformedCoverage
    }
    guard
        let payload = try? JSONSerialization.jsonObject(with: data),
        let root = payload as? [String: Any],
        let dataSets = root["data"] as? [[String: Any]],
        !dataSets.isEmpty
    else {
        throw CoverageGateError.malformedCoverage
    }

    let workingDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
    var countsBySource: [String: LineCounts] = [:]
    for dataSet in dataSets {
        guard let files = dataSet["files"] as? [[String: Any]] else {
            throw CoverageGateError.malformedCoverage
        }

        for file in files {
            guard let filename = file["filename"] as? String else {
                throw CoverageGateError.malformedCoverage
            }
            let sourcePath = canonicalURL(for: filename, relativeTo: workingDirectory).path
            guard sources.contains(sourcePath) else {
                continue
            }
            guard countsBySource[sourcePath] == nil else {
                throw CoverageGateError.duplicateCoverage
            }
            guard
                let summary = file["summary"] as? [String: Any],
                let lines = summary["lines"] as? [String: Any]
            else {
                throw CoverageGateError.malformedCoverage
            }

            let executable = try integerCount(from: lines["count"])
            let covered = try integerCount(from: lines["covered"])
            guard executable > 0 else {
                throw CoverageGateError.zeroExecutableLines
            }
            guard covered <= executable else {
                throw CoverageGateError.invalidLineCounts
            }
            countsBySource[sourcePath] = LineCounts(executable: executable, covered: covered)
        }
    }

    guard countsBySource.keys.count == sources.count else {
        throw CoverageGateError.missingCoverage
    }
    return countsBySource
}

do {
    let arguments = try parseArguments()
    let sources = try productionSources(in: arguments.sourceRoot)
    let countsBySource = try coverageCounts(from: arguments.input, sources: sources)
    let executable = try countsBySource.values.reduce(0) { partial, counts in
        try checkedAdd(partial, counts.executable)
    }
    let covered = try countsBySource.values.reduce(0) { partial, counts in
        try checkedAdd(partial, counts.covered)
    }

    guard executable > 0 else {
        fail(.zeroExecutableLines)
    }
    let scaledCovered = try checkedMultiply(covered, 100)
    let scaledMinimum = try checkedMultiply(executable, arguments.minimum)
    guard scaledCovered >= scaledMinimum else {
        fail(.belowMinimum)
    }

    let percent = scaledCovered / executable
    print("SAFETY-COVERAGE: PASS \(covered)/\(executable) (\(percent)%)")
} catch let error as CoverageGateError {
    fail(error)
} catch {
    fail(.malformedCoverage)
}
