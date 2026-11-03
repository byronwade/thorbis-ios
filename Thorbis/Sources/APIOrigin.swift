import Foundation

/// Shared API trust and identity rules. A persisted payment hold must use the
/// same origin acceptance rules as the client that actually sends requests.
enum APIOrigin {
    static func validated(_ raw: String) -> URLComponents? {
        guard let components = URLComponents(string: raw),
              let host = components.host?.lowercased(),
              components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil,
              components.path.isEmpty || components.path == "/"
        else { return nil }
        if components.scheme == "https", host == "app.thorbis.com", components.port == nil {
            return components
        }
        #if DEBUG
        if components.scheme == "http", ["127.0.0.1", "localhost", "[::1]"].contains(host) {
            return components
        }
        #endif
        return nil
    }

    static func normalized(_ raw: String) -> String? {
        guard var origin = validated(raw) else { return nil }
        origin.host = origin.host?.lowercased()
        origin.path = ""
        return origin.string
    }
}
