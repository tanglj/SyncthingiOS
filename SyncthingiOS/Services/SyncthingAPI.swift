import Foundation

enum SyncthingAPIError: LocalizedError, Equatable {
    case missingAPIKey
    case invalidBaseURL
    case invalidResponse
    case decodingFailed(String)
    case httpStatus(Int)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Enter the Syncthing API key from Actions > Settings > GUI."
        case .invalidBaseURL:
            return "Enter a valid Syncthing GUI address."
        case .invalidResponse:
            return "Syncthing returned an invalid response."
        case .decodingFailed(let details):
            return "Syncthing returned data this app could not read: \(details)"
        case .httpStatus(let status):
            return "Syncthing returned HTTP \(status)."
        }
    }
}

struct SyncthingAPI {
    var snapshot: SyncthingSnapshot
    var session: URLSession = .shared

    func overview() async throws -> SyncthingOverview {
        try validate()

        async let version: SystemVersion? = optionalGet("/rest/system/version")
        async let status: SystemStatus? = optionalGet("/rest/system/status")
        async let config: SyncthingConfig? = optionalGet("/rest/config")
        async let connections: Connections? = optionalGet("/rest/system/connections")

        let overview = try await SyncthingOverview(
            version: version,
            status: status,
            config: config,
            connections: connections
        )
        guard overview.hasData else {
            throw SyncthingAPIError.invalidResponse
        }
        return overview
    }

    func restart() async throws {
        try validate()
        try await post("/rest/system/restart")
    }

    func rescan(folderID: String? = nil) async throws {
        try validate()
        var queryItems: [URLQueryItem] = []
        if let folderID, !folderID.isEmpty {
            queryItems.append(URLQueryItem(name: "folder", value: folderID))
        }
        try await post("/rest/db/scan", queryItems: queryItems)
    }

    private func get<T: Decodable>(_ path: String) async throws -> T {
        let data = try await request(path, method: "GET")
        let decoder = JSONDecoder()
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw SyncthingAPIError.decodingFailed("\(path): \(error.localizedDescription)")
        }
    }

    private func optionalGet<T: Decodable>(_ path: String) async throws -> T? {
        do {
            return try await get(path)
        } catch let error as SyncthingAPIError {
            switch error {
            case .httpStatus, .invalidResponse:
                throw error
            case .missingAPIKey, .invalidBaseURL, .decodingFailed:
                return nil
            }
        } catch {
            return nil
        }
    }

    private func post(_ path: String, queryItems: [URLQueryItem] = []) async throws {
        _ = try await request(path, method: "POST", queryItems: queryItems)
    }

    private func request(
        _ path: String,
        method: String,
        queryItems: [URLQueryItem] = []
    ) async throws -> Data {
        guard !snapshot.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SyncthingAPIError.missingAPIKey
        }

        guard var components = URLComponents(url: snapshot.baseURL, resolvingAgainstBaseURL: false) else {
            throw SyncthingAPIError.invalidResponse
        }
        let basePath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.path = ([basePath, path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))])
            .filter { !$0.isEmpty }
            .joined(separator: "/")
        components.path = "/" + components.path
        components.queryItems = queryItems.isEmpty ? nil : queryItems

        guard let url = components.url else {
            throw SyncthingAPIError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(snapshot.apiKey, forHTTPHeaderField: "X-API-Key")
        request.timeoutInterval = 20

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SyncthingAPIError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw SyncthingAPIError.httpStatus(httpResponse.statusCode)
        }
        return data
    }

    private func validate() throws {
        guard !snapshot.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SyncthingAPIError.missingAPIKey
        }
        guard let scheme = snapshot.baseURL.scheme,
              ["http", "https"].contains(scheme),
              snapshot.baseURL.host != nil else {
            throw SyncthingAPIError.invalidBaseURL
        }
    }
}
