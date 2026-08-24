import Foundation
import FoundationModels

/// On-device (Apple Intelligence) rephrasing of a monthly-plan summary. It is given
/// the exact, engine-computed sentence and asked only to make it warmer and more
/// natural — never to compute or alter any figure. Returns nil when the model is
/// unavailable or errors, so callers fall back to the deterministic summary.
///
/// Numbers stay authoritative: the prompt forbids changing amounts, currency
/// symbols, names, or dates, so a hallucinated figure can't reach the user.
public enum PlanAdvisor {

    /// Whether the on-device model can run right now.
    public static var isAvailable: Bool {
        SystemLanguageModel.default.isAvailable
    }

    public static func rephrase(_ summary: String) async -> String? {
        guard SystemLanguageModel.default.isAvailable else { return nil }
        do {
            let session = LanguageModelSession()
            let prompt = """
            Rewrite the personal-finance summary below so it sounds warm, encouraging, \
            and easy to read — like a helpful friend. Keep it to two or three short \
            sentences. You MUST NOT change, add, or remove any number, currency symbol, \
            name, or date — copy every figure exactly as written. Do not invent advice \
            that isn't supported by the summary.

            Summary:
            \(summary)
            """
            let response = try await session.respond(to: prompt)
            let text = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : text
        } catch {
            return nil
        }
    }
}
