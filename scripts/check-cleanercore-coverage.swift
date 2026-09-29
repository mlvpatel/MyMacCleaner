#!/usr/bin/swift

import Foundation

private enum CoverageGateError: Error {
    case invalidArguments
    case invalidMinimum
    case unreadableInput
    case unreadableSourceRoot
    case missingProductionSource
    case declarationOnlyDrift(String)
    case unknownTarget
    case symbolicLink
    case malformedCoverage
    case missingCoverage(String)
    case duplicateCoverage
    case invalidLineCounts
    case zeroExecutableLines(String)
    case arithmeticOverflow
    case belowMinimum
    case belowTargetMinimum(String, covered: Int, executable: Int, minimum: Int)
}

private struct Arguments {
    let input: URL
    let sourceRoot: URL
    let minimum: Int
}

private struct LineCounts: Equatable {
    let executable: Int
    let covered: Int
}

private enum ProductionTarget: String, CaseIterable {
    case cleanerCore = "CleanerCore"
    case cleanerCoreFoundation = "CleanerCoreFoundation"
    case cleanerCoreDarwin = "CleanerCoreDarwin"
    case cleanerCoreContentAdapter = "CleanerCoreContentAdapter"
}

private struct ProductionScope {
    let sourceRoot: String
    let sources: [String: ProductionTarget]
    let requiredSources: [String: ProductionTarget]
}

// LLVM omits files that contain declarations but no executable regions. Keep
// this list exact and validate the file grammar so executable drift cannot hide.
private let declarationOnlySources: Set<String> = [
    "CleanerCoreDarwin/DarwinMemorySystem.swift",
]

private func fail(_ error: CoverageGateError) -> Never {
    let rule: String

    switch error {
    case .invalidArguments:
        rule = "CC-COVERAGE-ARGUMENTS"
    case .invalidMinimum:
        rule = "CC-COVERAGE-MINIMUM"
    case .unreadableInput:
        rule = "CC-COVERAGE-INPUT"
    case .unreadableSourceRoot:
        rule = "CC-COVERAGE-SOURCE-ROOT"
    case .missingProductionSource:
        rule = "CC-COVERAGE-PRODUCTION-SOURCE"
    case .declarationOnlyDrift(let target):
        rule = "CC-COVERAGE-DECLARATION-DRIFT: \(target)"
    case .unknownTarget:
        rule = "CC-COVERAGE-UNKNOWN-TARGET"
    case .symbolicLink:
        rule = "CC-COVERAGE-SYMLINK"
    case .malformedCoverage:
        rule = "CC-COVERAGE-MALFORMED"
    case .missingCoverage(let target):
        rule = "CC-COVERAGE-MISSING-SOURCE: \(target)"
    case .duplicateCoverage:
        rule = "CC-COVERAGE-DUPLICATE-SOURCE"
    case .invalidLineCounts:
        rule = "CC-COVERAGE-LINE-COUNTS"
    case .zeroExecutableLines(let target):
        rule = "CC-COVERAGE-ZERO-LINES: \(target)"
    case .arithmeticOverflow:
        rule = "CC-COVERAGE-ARITHMETIC"
    case .belowMinimum:
        rule = "CC-COVERAGE-BELOW-MINIMUM"
    case let .belowTargetMinimum(target, covered, executable, minimum):
        rule = "CC-COVERAGE-BELOW-MINIMUM: \(target) \(covered)/\(executable) required=\(minimum).00%"
    }

    FileHandle.standardError.write(Data("\(rule)\n".utf8))
    exit(1)
}

private func standardURL(for path: String, relativeTo workingDirectory: URL) -> URL {
    let url: URL
    if path.hasPrefix("/") {
        url = URL(fileURLWithPath: path)
    } else {
        url = workingDirectory.appendingPathComponent(path)
    }
    return url.standardizedFileURL
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
        input: standardURL(for: inputPath, relativeTo: workingDirectory),
        sourceRoot: standardURL(for: sourceRootPath, relativeTo: workingDirectory),
        minimum: minimum
    )
}

private func productionTargets(in sourceRoot: URL) throws -> [(ProductionTarget, URL)] {
    var targets: [(ProductionTarget, URL)] = []
    for targetName in ProductionTarget.allCases {
        let target = sourceRoot.appendingPathComponent(targetName.rawValue, isDirectory: true)
        let resourceValues: URLResourceValues
        do {
            resourceValues = try target.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        } catch {
            throw CoverageGateError.missingProductionSource
        }
        guard resourceValues.isSymbolicLink != true else {
            throw CoverageGateError.symbolicLink
        }
        guard resourceValues.isDirectory == true else {
            throw CoverageGateError.missingProductionSource
        }
        targets.append((targetName, target))
    }
    return targets
}

private func shouldCountProductionSource(_ fileURL: URL, sourceRoot: URL) -> Bool {
    let rootComponents = sourceRoot.pathComponents
    let fileComponents = fileURL.pathComponents
    guard fileComponents.count > rootComponents.count,
          Array(fileComponents.prefix(rootComponents.count)) == rootComponents
    else {
        return false
    }
    guard fileURL.pathExtension == "swift" else {
        return false
    }

    let relativeComponents = Array(fileComponents.dropFirst(rootComponents.count))
    guard let target = relativeComponents.first,
          ProductionTarget(rawValue: target) != nil
    else {
        return false
    }

    let excludedDirectories: Set<String> = [".build", "Generated", "Tests", "generated"]
    guard relativeComponents.dropFirst().allSatisfy({ !excludedDirectories.contains($0) }) else {
        return false
    }
    return !fileURL.lastPathComponent.hasSuffix(".generated.swift")
}

private func relativeSourcePath(_ fileURL: URL, sourceRoot: URL) -> String? {
    let rootComponents = sourceRoot.pathComponents
    let fileComponents = fileURL.pathComponents
    guard fileComponents.count > rootComponents.count,
          Array(fileComponents.prefix(rootComponents.count)) == rootComponents
    else {
        return nil
    }
    return fileComponents.dropFirst(rootComponents.count).joined(separator: "/")
}

private func validateDeclarationOnlySource(
    _ fileURL: URL,
    target: ProductionTarget
) throws {
    guard let contents = try? String(contentsOf: fileURL, encoding: .utf8) else {
        throw CoverageGateError.unreadableSourceRoot
    }

    var declarationDepth = 0
    var functionParentheses = 0
    var isFunctionDeclaration = false
    for rawLine in contents.split(separator: "\n", omittingEmptySubsequences: false) {
        let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        if line.isEmpty || line.hasPrefix("//") {
            continue
        }
        if isFunctionDeclaration {
            guard !line.contains("{"), !line.contains("=") else {
                throw CoverageGateError.declarationOnlyDrift(target.rawValue)
            }
            functionParentheses += line.filter { $0 == "(" }.count
            functionParentheses -= line.filter { $0 == ")" }.count
            guard functionParentheses >= 0 else {
                throw CoverageGateError.declarationOnlyDrift(target.rawValue)
            }
            isFunctionDeclaration = functionParentheses > 0
            continue
        }
        if line == "import CleanerCore" {
            continue
        }
        if line.hasPrefix("public protocol ") || line.hasPrefix("protocol ")
            || line.hasPrefix("enum ") || line.hasPrefix("struct ") {
            guard line.hasSuffix("{"), !line.dropLast().contains("{"), !line.contains("=") else {
                throw CoverageGateError.declarationOnlyDrift(target.rawValue)
            }
            declarationDepth += 1
            continue
        }
        if line == "}" {
            declarationDepth -= 1
            guard declarationDepth >= 0 else {
                throw CoverageGateError.declarationOnlyDrift(target.rawValue)
            }
            continue
        }
        if line.hasPrefix("associatedtype ") || line.hasPrefix("case ")
            || line.hasPrefix("let ") {
            guard declarationDepth > 0, !line.contains("{"), !line.contains("=") else {
                throw CoverageGateError.declarationOnlyDrift(target.rawValue)
            }
            continue
        }
        if line.hasPrefix("func ") {
            guard declarationDepth > 0, !line.contains("{"), !line.contains("=") else {
                throw CoverageGateError.declarationOnlyDrift(target.rawValue)
            }
            functionParentheses = line.filter { $0 == "(" }.count - line.filter { $0 == ")" }.count
            guard functionParentheses >= 0 else {
                throw CoverageGateError.declarationOnlyDrift(target.rawValue)
            }
            isFunctionDeclaration = functionParentheses > 0
            continue
        }
        throw CoverageGateError.declarationOnlyDrift(target.rawValue)
    }

    guard declarationDepth == 0, functionParentheses == 0, !isFunctionDeclaration else {
        throw CoverageGateError.declarationOnlyDrift(target.rawValue)
    }
}

private func productionScope(in sourceRoot: URL) throws -> ProductionScope {
    let sourceRootValues: URLResourceValues
    do {
        sourceRootValues = try sourceRoot.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
    } catch {
        throw CoverageGateError.unreadableSourceRoot
    }
    guard sourceRootValues.isSymbolicLink != true else {
        throw CoverageGateError.symbolicLink
    }
    guard sourceRootValues.isDirectory == true else {
        throw CoverageGateError.unreadableSourceRoot
    }

    let canonicalSourceRoot = sourceRoot.standardizedFileURL.resolvingSymlinksInPath()
    let targets = try productionTargets(in: sourceRoot)
    var sources: [String: ProductionTarget] = [:]
    var requiredSources: [String: ProductionTarget] = [:]
    for (targetName, target) in targets {
        var enumerationFailed = false
        guard let enumerator = FileManager.default.enumerator(
            at: target,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: [],
            errorHandler: { _, _ in
                enumerationFailed = true
                return false
            }
        ) else {
            throw CoverageGateError.unreadableSourceRoot
        }

        var targetSources = Set<String>()
        for case let fileURL as URL in enumerator {
            let resourceValues: URLResourceValues
            do {
                resourceValues = try fileURL.resourceValues(
                    forKeys: [.isRegularFileKey, .isSymbolicLinkKey]
                )
            } catch {
                throw CoverageGateError.unreadableSourceRoot
            }
            guard resourceValues.isSymbolicLink != true else {
                throw CoverageGateError.symbolicLink
            }
            guard resourceValues.isRegularFile == true else {
                continue
            }
            let normalized = fileURL.standardizedFileURL.resolvingSymlinksInPath()
            guard shouldCountProductionSource(normalized, sourceRoot: canonicalSourceRoot) else {
                continue
            }
            targetSources.insert(normalized.path)
        }
        guard !enumerationFailed else {
            throw CoverageGateError.unreadableSourceRoot
        }
        guard !targetSources.isEmpty else {
            throw CoverageGateError.missingProductionSource
        }
        for source in targetSources {
            sources[source] = targetName
            let sourceURL = URL(fileURLWithPath: source)
            guard let relative = relativeSourcePath(sourceURL, sourceRoot: canonicalSourceRoot) else {
                throw CoverageGateError.unreadableSourceRoot
            }
            if declarationOnlySources.contains(relative) {
                try validateDeclarationOnlySource(sourceURL, target: targetName)
            } else {
                requiredSources[source] = targetName
            }
        }
    }

    guard !sources.isEmpty else {
        throw CoverageGateError.missingProductionSource
    }
    return ProductionScope(
        sourceRoot: canonicalSourceRoot.path,
        sources: sources,
        requiredSources: requiredSources
    )
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

private func pathComponents(_ path: String, below root: String) -> [String]? {
    let rootComponents = URL(fileURLWithPath: root, isDirectory: true).pathComponents
    let pathComponents = URL(fileURLWithPath: path).pathComponents
    guard pathComponents.count > rootComponents.count,
          Array(pathComponents.prefix(rootComponents.count)) == rootComponents
    else {
        return nil
    }
    return Array(pathComponents.dropFirst(rootComponents.count))
}

private func isExcludedCoveragePath(_ relativeComponents: [String], path: String) -> Bool {
    let excludedDirectories: Set<String> = [".build", "Generated", "Tests", "generated"]
    return relativeComponents.dropFirst().contains(where: excludedDirectories.contains)
        || URL(fileURLWithPath: path).lastPathComponent.hasSuffix(".generated.swift")
}

private func coverageCounts(from input: URL, scope: ProductionScope) throws -> [String: LineCounts] {
    var inputIsDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: input.path, isDirectory: &inputIsDirectory),
          !inputIsDirectory.boolValue
    else {
        throw CoverageGateError.unreadableInput
    }
    let inputValues: URLResourceValues
    do {
        inputValues = try input.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
    } catch {
        throw CoverageGateError.unreadableInput
    }
    guard inputValues.isSymbolicLink != true else {
        throw CoverageGateError.symbolicLink
    }
    guard inputValues.isRegularFile == true, let data = try? Data(contentsOf: input) else {
        throw CoverageGateError.unreadableInput
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
            guard let filename = file["filename"] as? String, !filename.isEmpty else {
                throw CoverageGateError.malformedCoverage
            }
            let standardSourceURL = standardURL(for: filename, relativeTo: workingDirectory)
            if let sourceValues = try? standardSourceURL.resourceValues(forKeys: [.isSymbolicLinkKey]),
               sourceValues.isSymbolicLink == true {
                throw CoverageGateError.symbolicLink
            }
            let sourcePath = standardSourceURL.resolvingSymlinksInPath().path
            guard let productionTarget = scope.sources[sourcePath] else {
                guard let relativeComponents = pathComponents(sourcePath, below: scope.sourceRoot) else {
                    continue
                }
                guard URL(fileURLWithPath: sourcePath).pathExtension == "swift" else {
                    continue
                }
                guard let targetComponent = relativeComponents.first,
                      ProductionTarget(rawValue: targetComponent) != nil
                else {
                    throw CoverageGateError.unknownTarget
                }
                if isExcludedCoveragePath(relativeComponents, path: sourcePath) {
                    continue
                }
                throw CoverageGateError.missingProductionSource
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
                throw CoverageGateError.zeroExecutableLines(productionTarget.rawValue)
            }
            guard covered <= executable else {
                throw CoverageGateError.invalidLineCounts
            }

            countsBySource[sourcePath] = LineCounts(executable: executable, covered: covered)
        }
    }

    for (source, target) in scope.requiredSources where countsBySource[source] == nil {
        throw CoverageGateError.missingCoverage(target.rawValue)
    }
    for target in ProductionTarget.allCases {
        guard countsBySource.keys.contains(where: { scope.sources[$0] == target }) else {
            throw CoverageGateError.missingCoverage(target.rawValue)
        }
    }
    return countsBySource
}

private func totals(
    for target: ProductionTarget?,
    countsBySource: [String: LineCounts],
    scope: ProductionScope
) throws -> LineCounts {
    var executable = 0
    var covered = 0
    for (source, counts) in countsBySource {
        if let target, scope.sources[source] != target {
            continue
        }
        executable = try checkedAdd(executable, counts.executable)
        covered = try checkedAdd(covered, counts.covered)
    }
    return LineCounts(executable: executable, covered: covered)
}

private func percentage(_ counts: LineCounts) -> String {
    let value = Double(counts.covered) * 100.0 / Double(counts.executable)
    return String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), value)
}

private func requireMinimum(
    _ counts: LineCounts,
    minimum: Int,
    target: ProductionTarget?
) throws {
    let label = target?.rawValue ?? "aggregate"
    guard counts.executable > 0 else {
        throw CoverageGateError.zeroExecutableLines(label)
    }
    let scaledCovered = try checkedMultiply(counts.covered, 100)
    let scaledMinimum = try checkedMultiply(counts.executable, minimum)
    guard scaledCovered >= scaledMinimum else {
        if let target {
            throw CoverageGateError.belowTargetMinimum(
                target.rawValue,
                covered: counts.covered,
                executable: counts.executable,
                minimum: minimum
            )
        }
        throw CoverageGateError.belowMinimum
    }
}

do {
    let arguments = try parseArguments()
    let scope = try productionScope(in: arguments.sourceRoot)
    let countsBySource = try coverageCounts(from: arguments.input, scope: scope)
    let aggregate = try totals(for: nil, countsBySource: countsBySource, scope: scope)
    try requireMinimum(aggregate, minimum: arguments.minimum, target: nil)

    var targetReports: [(ProductionTarget, LineCounts)] = []
    for target in ProductionTarget.allCases {
        let targetCounts = try totals(for: target, countsBySource: countsBySource, scope: scope)
        try requireMinimum(targetCounts, minimum: arguments.minimum, target: target)
        targetReports.append((target, targetCounts))
    }

    print(
        "CLEANERCORE-COVERAGE: PASS aggregate \(aggregate.covered)/\(aggregate.executable) "
            + "(\(percentage(aggregate))%)"
    )
    for (target, counts) in targetReports {
        print(
            "CLEANERCORE-COVERAGE: \(target.rawValue) \(counts.covered)/\(counts.executable) "
                + "(\(percentage(counts))%)"
        )
    }
} catch let error as CoverageGateError {
    fail(error)
} catch {
    fail(.malformedCoverage)
}
