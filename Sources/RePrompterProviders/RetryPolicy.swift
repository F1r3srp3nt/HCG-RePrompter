import Foundation

/// Retry policy for transient provider failures (rate limits, overload,
/// server errors, timeouts, network drops). Enhancement requests are
/// read-only, so repeating them is safe.
public struct RetryPolicy: Sendable, Equatable {
    public var maxAttempts: Int
    public var baseDelay: Double
    public var maxDelay: Double

    public init(maxAttempts: Int = 3, baseDelay: Double = 1.5, maxDelay: Double = 20) {
        self.maxAttempts = max(1, maxAttempts)
        self.baseDelay = baseDelay
        self.maxDelay = maxDelay
    }

    public static let standard = RetryPolicy()
    public static let none = RetryPolicy(maxAttempts: 1)

    /// The delay before retrying after `failures` failed attempts, or nil if
    /// the request should not be retried.
    public func delay(afterFailures failures: Int, error: ProviderError) -> Double? {
        guard error.isRetryable, failures < maxAttempts else { return nil }
        if case let .rateLimited(retryAfter?) = error {
            // Do not wait longer than the policy allows; surface the error instead.
            return retryAfter <= maxDelay ? max(0, retryAfter) : nil
        }
        return min(baseDelay * pow(2, Double(failures - 1)), maxDelay)
    }
}
