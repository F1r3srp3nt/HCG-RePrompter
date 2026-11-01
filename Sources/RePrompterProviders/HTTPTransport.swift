import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Abstraction over HTTP so providers can be tested without network access.
public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

/// URLSession-backed transport. Uses an ephemeral session (no disk cache,
/// no cookies) and refuses non-HTTPS URLs.
public final class URLSessionTransport: HTTPTransport, @unchecked Sendable {
    // URLSession is thread-safe; the class holds no other mutable state.
    private let session: URLSession

    public init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        #if canImport(Darwin)
        configuration.tlsMinimumSupportedProtocolVersion = .TLSv12
        #endif
        session = URLSession(configuration: configuration)
    }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        guard request.url?.scheme?.lowercased() == "https" else { throw ProviderError.insecureEndpoint }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ProviderError.malformedResponse("Not an HTTP response.")
        }
        return (data, http)
    }
}
