import Foundation

#if canImport(llama)
import llama

enum LlamaError: Error {
    case couldNotInitializeContext
}

private func llama_batch_clear(_ batch: inout llama_batch) {
    batch.n_tokens = 0
}

private func llama_batch_add(_ batch: inout llama_batch,
                             _ id: llama_token,
                             _ pos: llama_pos,
                             _ seq_ids: [llama_seq_id],
                             _ logits: Bool) {
    let index = Int(batch.n_tokens)
    batch.token[index] = id
    batch.pos[index] = pos
    batch.n_seq_id[index] = Int32(seq_ids.count)
    guard let seqIDSlot = batch.seq_id[index] else {
        return
    }
    for i in 0..<seq_ids.count {
        seqIDSlot[Int(i)] = seq_ids[i]
    }
    batch.logits[index] = logits ? 1 : 0
    batch.n_tokens += 1
}

actor LlamaExtractionService {
    static let shared = LlamaExtractionService()

    private var context: LlamaContext?
    private var loadedModelPath = ""

    private init() {}

    func generate(modelPath: String, prompt: String, maxTokens: Int32 = 512) async -> String {
        do {
            if context == nil || loadedModelPath != modelPath {
                context = try LlamaContext.createContext(path: modelPath)
                loadedModelPath = modelPath
            }

            guard let context else { return "" }
            context.clear()
            context.nLen = maxTokens
            context.completionInit(text: prompt)

            var output = ""
            var sawJSONArrayStart = false
            while !context.isDone {
                let next = context.completionLoop()
                output += next
                if !sawJSONArrayStart, output.contains("[") {
                    sawJSONArrayStart = true
                }
                if sawJSONArrayStart, output.contains("]") {
                    break
                }
                if output.count > 16000 { break }
            }
            print("llama output length:", output.count)
            print("llama output preview:", output.prefix(200))
            return output
        } catch {
            return ""
        }
    }
}

private final class LlamaContext {
    private let batchCapacity = 2048
    private var model: OpaquePointer
    private var context: OpaquePointer
    private var vocab: OpaquePointer
    private var sampling: UnsafeMutablePointer<llama_sampler>
    private var batch: llama_batch

    private var tokensList: [llama_token] = []
    private var temporaryInvalidCChars: [CChar] = []

    var isDone = false
    var nLen: Int32 = 512
    private var nCur: Int32 = 0
    private var generatedCount: Int32 = 0
    private var maxGenerateCount: Int32 = 0

    init(model: OpaquePointer, context: OpaquePointer) {
        self.model = model
        self.context = context
        self.batch = llama_batch_init(Int32(batchCapacity), 0, 1)
        let sparams = llama_sampler_chain_default_params()
        self.sampling = llama_sampler_chain_init(sparams)
        llama_sampler_chain_add(self.sampling, llama_sampler_init_greedy())
        self.vocab = llama_model_get_vocab(model)
    }

    deinit {
        llama_sampler_free(sampling)
        llama_batch_free(batch)
        llama_model_free(model)
        llama_free(context)
        llama_backend_free()
    }

    static func createContext(path: String) throws -> LlamaContext {
        llama_backend_init()
        var modelParams = llama_model_default_params()

#if targetEnvironment(simulator)
        modelParams.n_gpu_layers = 0
#endif
        guard let model = llama_model_load_from_file(path, modelParams) else {
            throw LlamaError.couldNotInitializeContext
        }

        let nThreads = max(1, min(8, ProcessInfo.processInfo.processorCount - 2))
        var ctxParams = llama_context_default_params()
        ctxParams.n_ctx = 2048
        ctxParams.n_threads = Int32(nThreads)
        ctxParams.n_threads_batch = Int32(nThreads)

        guard let ctx = llama_init_from_model(model, ctxParams) else {
            throw LlamaError.couldNotInitializeContext
        }

        return LlamaContext(model: model, context: ctx)
    }

    func clear() {
        tokensList.removeAll()
        temporaryInvalidCChars.removeAll()
        isDone = false
        nCur = 0
        generatedCount = 0
        maxGenerateCount = 0
        llama_memory_clear(llama_get_memory(context), true)
    }

    func completionInit(text: String) {
        tokensList = tokenize(text: text, addBos: true)
        if tokensList.count >= batchCapacity {
            tokensList = Array(tokensList.prefix(batchCapacity - 1))
        }
        temporaryInvalidCChars.removeAll()
        isDone = false
        generatedCount = 0

        llama_batch_clear(&batch)
        for i in 0..<tokensList.count {
            llama_batch_add(&batch, tokensList[i], Int32(i), [0], false)
        }

        if batch.n_tokens > 0 {
            batch.logits[Int(batch.n_tokens) - 1] = 1
        }

        if llama_decode(context, batch) != 0 {
            isDone = true
        }

        nCur = batch.n_tokens
        let contextLimit = Int32(llama_n_ctx(context))
        let available = max(Int32(0), contextLimit - nCur)
        maxGenerateCount = min(nLen, available)
    }

    func completionLoop() -> String {
        if isDone { return "" }

        let newTokenID = llama_sampler_sample(sampling, context, batch.n_tokens - 1)
        if llama_vocab_is_eog(vocab, newTokenID) || generatedCount >= maxGenerateCount || nCur >= Int32(llama_n_ctx(context)) {
            isDone = true
            let tail = String(cString: temporaryInvalidCChars + [0])
            temporaryInvalidCChars.removeAll()
            return tail
        }

        let newTokenCChars = tokenToPiece(token: newTokenID)
        temporaryInvalidCChars.append(contentsOf: newTokenCChars)

        let newTokenStr: String
        if let valid = String(validatingUTF8: temporaryInvalidCChars + [0]) {
            temporaryInvalidCChars.removeAll()
            newTokenStr = valid
        } else {
            newTokenStr = ""
        }

        llama_batch_clear(&batch)
        llama_batch_add(&batch, newTokenID, nCur, [0], true)
        nCur += 1
        generatedCount += 1

        if llama_decode(context, batch) != 0 {
            isDone = true
        }

        return newTokenStr
    }

    private func tokenize(text: String, addBos: Bool) -> [llama_token] {
        let utf8Count = text.utf8.count
        let nTokens = utf8Count + (addBos ? 1 : 0) + 1
        let tokens = UnsafeMutablePointer<llama_token>.allocate(capacity: nTokens)
        defer { tokens.deallocate() }

        let tokenCount = llama_tokenize(vocab, text, Int32(utf8Count), tokens, Int32(nTokens), addBos, false)
        guard tokenCount > 0 else { return [] }

        var swiftTokens: [llama_token] = []
        swiftTokens.reserveCapacity(Int(tokenCount))
        for i in 0..<tokenCount {
            swiftTokens.append(tokens[Int(i)])
        }
        return swiftTokens
    }

    // - note: Result doesn't include null terminator.
    private func tokenToPiece(token: llama_token) -> [CChar] {
        let result = UnsafeMutablePointer<Int8>.allocate(capacity: 8)
        result.initialize(repeating: Int8(0), count: 8)
        defer { result.deallocate() }

        let n = llama_token_to_piece(vocab, token, result, 8, 0, false)
        if n < 0 {
            let newResult = UnsafeMutablePointer<Int8>.allocate(capacity: Int(-n))
            newResult.initialize(repeating: Int8(0), count: Int(-n))
            defer { newResult.deallocate() }
            let nNew = llama_token_to_piece(vocab, token, newResult, -n, 0, false)
            let buffer = UnsafeBufferPointer(start: newResult, count: Int(nNew))
            return Array(buffer)
        } else {
            let buffer = UnsafeBufferPointer(start: result, count: Int(n))
            return Array(buffer)
        }
    }
}

#else

actor LlamaExtractionService {
    static let shared = LlamaExtractionService()
    private init() {}

    func generate(modelPath: String, prompt: String, maxTokens: Int32 = 512) async -> String {
        ""
    }
}

#endif
