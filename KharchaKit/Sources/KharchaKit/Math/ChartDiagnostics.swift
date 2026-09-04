import Foundation
import os

/// Tracing for the History chart's window and scale.
///
/// The header describing a different span than the bars has been diagnosed and
/// re-diagnosed from screenshots, three times, and each reading of the evidence
/// was wrong in a different way. This prints the values the screenshots can only
/// be used to infer: which window was chosen, what the chart says it is drawing,
/// and what the marks are scaled against.
///
/// Debug builds only, and every line is emitted at most once per distinct value —
/// the chart lays out many times a second, and a log that floods is a log nobody
/// reads.
@MainActor
public enum ChartDiagnostics {
    private static let logger = Logger(subsystem: "com.kharcha.app", category: "chart")
    private static var lastByPrefix: [String: String] = [:]

    public static func log(_ message: @autoclosure () -> String) {
        #if DEBUG
        let text = message()
        let prefix = text.split(separator: " ", maxSplits: 1).first.map(String.init) ?? text
        guard lastByPrefix[prefix] != text else { return }
        lastByPrefix[prefix] = text
        logger.debug("\(text, privacy: .public)")
        print("[chart] \(text)")
        #endif
    }
}
