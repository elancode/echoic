import Foundation

/// Retry logic with exponential backoff and jitter.
/// Critical Rule #9: Max 5 min between retries, 3 attempts, never retry without backoff.
enum RetryHandler {
    struct Config {
        var maxAttempts: Int = 3
        var initialDelay: TimeInterval = 1.0
        var maxDelay: TimeInterval = 300.0 // 5 minutes
        var backoffMultiplier: Double = 2.0
        var jitterFraction: Double = 0.25
    }

    /// Executes an async operation with retry logic.
    /// - Parameters:
    ///   - config: Retry configuration.
    ///   - operation: The async operation to retry.
    /// - Returns: The operation result.
    static func withRetry<T>(
        config: Config = Config(),
        operation: () async throws -> T
    ) async throws -> T {
        var lastError: Error?
        var delay = config.initialDelay

        for attempt in 1...config.maxAttempts {
            do {
                return try await operation()
            } catch {
                lastError = error

                // Don't retry on non-retryable errors
                guard isRetryable(error) else { throw error }

                // Don't delay after last attempt
                guard attempt < config.maxAttempts else { break }

                // Apply jitter
                let jitter = delay * config.jitterFraction * Double.random(in: -1...1)
                let actualDelay = min(delay + jitter, config.maxDelay)

                try await Task.sleep(nanoseconds: UInt64(actualDelay * 1_000_000_000))

                // Exponential backoff
                delay = min(delay * config.backoffMultiplier, config.maxDelay)
            }
        }

        throw lastError ?? AnthropicError.serverError
    }

    /// Determines if an error is retryable.
    private static func isRetryable(_ error: Error) -> Bool {
        if let anthropicError = error as? AnthropicError {
            switch anthropicError {
            case .httpError(let statusCode, _):
                // Retry on 429 (rate limit), 500, 502, 503, 529
                return [429, 500, 502, 503, 529].contains(statusCode)
            case .rateLimited:
                return true
            case .serverError:
                return true
            default:
                return false
            }
        }

        // Retry on network errors
        if let urlError = error as? URLError {
            return [.timedOut, .networkConnectionLost, .notConnectedToInternet].contains(urlError.code)
        }

        return false
    }
}
