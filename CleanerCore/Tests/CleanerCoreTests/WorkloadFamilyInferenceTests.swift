import Testing

@testable import CleanerCore

/// C6: workload-family inference is broadened beyond four literal labels to
/// case-insensitive substrings (helpers included). It is advisory only — an
/// inferred family never affects cleanup eligibility.
@Suite("Workload family inference")
struct WorkloadFamilyInferenceTests {
    private func family(_ name: String) throws -> LocalWorkloadToolFamily? {
        LocalWorkloadEvidenceProducer.mappedFamily(for: try #require(ProcessDisplayLabel(name)))
    }

    @Test
    func infersFamiliesFromLabelSubstringsIncludingHelpers() throws {
        #expect(try family("ollama") == .ollama)
        #expect(try family("Ollama Helper") == .ollama)
        #expect(try family("LM Studio") == .lmStudio)
        #expect(try family("LM Studio Helper (Renderer)") == .lmStudio)
        #expect(try family("mlx_lm.server") == .mlx)
        #expect(try family("PyTorch") == .mlx)
        #expect(try family("llama-server") == .localInference)
        #expect(try family("com.docker.virtualization") == .localInference)
    }

    @Test
    func caseAndWhitespaceVariantsOfShippedLabelsStillInfer() throws {
        #expect(try family("Ollama") == .ollama)
        #expect(try family("ollama ") == .ollama)
    }

    @Test
    func ollamaWinsOverTheBroaderLlamaAndUnrelatedLabelsInferNothing() throws {
        #expect(try family("ollama") == .ollama)
        #expect(try family("Finder") == nil)
        #expect(try family("python3.11") == nil)
    }
}
