import Foundation
import GRDB
import Testing

@testable import CapKit

/// The interactive-search budget from the design doc, held against a library two orders of
/// magnitude past the dogfood corpus: 10k captures, p95 under 10ms per query.
@Suite("Search performance")
struct SearchPerformanceTests {
    private static let captureCount = 10_000
    private static let queryCount = 200

    /// Latency from an unoptimized build gates nothing, so the budget is only asserted
    /// where it means something; CI runs this suite again with `-c release`.
    private static var isOptimizedBuild: Bool {
        #if DEBUG
            false
        #else
            true
        #endif
    }

    @Test(
        "p95 search latency stays under 10ms at 10k captures",
        .enabled(if: isOptimizedBuild),
        .timeLimit(.minutes(3)))
    func p95UnderTenMilliseconds() throws {
        try withTemporaryPaths { paths in
            let store = try Store(paths: paths)
            try Self.seedLibrary(store)
            let service = SearchService(store: store)

            let queries = Self.queries()
            // Warm SQLite's page cache the way a resident app's would be.
            for query in queries.prefix(20) {
                _ = try service.search(query)
            }

            let clock = ContinuousClock()
            var durations: [Duration] = []
            var totalHits = 0
            for query in queries {
                // Best of three: a query's cost is its fastest run; the slower ones are
                // scheduler noise, which on a busy CI host would otherwise gate the build.
                var best = Duration.seconds(1)
                for _ in 0..<3 {
                    var hits: [SearchHit] = []
                    let elapsed = try clock.measure {
                        hits = try service.search(query)
                    }
                    best = min(best, elapsed)
                    totalHits += hits.count
                }
                durations.append(best)
            }

            // The queries are seeded from the same word pool, so silence would mean the
            // fixture measured 200 empty scans instead of real searches.
            #expect(totalHits > Self.queryCount)

            let sorted = durations.sorted()
            let p95 = sorted[sorted.count * 95 / 100 - 1]
            print(
                "search perf at \(Self.captureCount): p50 \(sorted[sorted.count / 2]), p95 \(p95)")
            #expect(p95 < .milliseconds(10), "p95 was \(p95)")
        }
    }

    /// Deterministic pseudo-prose: pool words follow a Zipf-ish spread through the corpus,
    /// and each capture carries one rare slug only it holds.
    private static func seedLibrary(_ store: Store) throws {
        var rng = SplitMix64(seed: 0x5EED_CAFE)
        let pool = wordPool()
        let base = Date(timeIntervalSince1970: 1_750_000_000)

        try store.dbPool.write { db in
            for index in 0..<captureCount {
                let host = "host\(index % 50).example"
                let title = (0..<6).map { _ in pool[Int(rng.next() % 120)] }
                    .joined(separator: " ")
                let body =
                    (0..<80).map { _ in pool[Int(rng.next() % UInt64(pool.count))] }
                    .joined(separator: " ") + " slug\(index)"

                var capture = Capture(
                    kind: .link,
                    url: "https://\(host)/p/\(index)",
                    host: host,
                    title: title,
                    body: body,
                    enrichmentState: .ok,
                    createdAt: base.addingTimeInterval(Double(index) * 60)
                )
                try capture.insert(db)
            }
        }
    }

    /// A rotation of the shapes the search field actually sees: one word, an AND pair,
    /// a needle-in-haystack rare word, and a filtered query.
    private static func queries() -> [String] {
        let pool = wordPool()
        return (0..<queryCount).map { index in
            switch index % 4 {
            case 0: pool[index % 120]
            case 1: "\(pool[index % 120]) \(pool[(index + 7) % 120])"
            case 2: "slug\((index * 49) % captureCount)"
            default: "site:host\(index % 50).example \(pool[index % 120])"
            }
        }
    }

    /// 400 pronounceable two-syllable words, so the porter stemmer and prefix matching see
    /// realistic tokens rather than serial numbers.
    private static func wordPool() -> [String] {
        let syllables = [
            "ba", "co", "di", "fu", "ga", "hi", "jo", "ka", "lu", "me",
            "no", "pa", "qui", "ro", "su", "ta", "ve", "wi", "xo", "zu",
        ]
        return syllables.flatMap { first in
            syllables.map { second in first + second }
        }
    }
}

private struct SplitMix64 {
    var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

private func withTemporaryPaths(_ body: (StoragePaths) throws -> Void) throws {
    let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent("cap-perf-tests-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try body(StoragePaths(root: root))
}
