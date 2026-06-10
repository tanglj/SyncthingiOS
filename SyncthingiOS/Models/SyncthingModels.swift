import Foundation

struct SyncthingSnapshot: Equatable {
    var baseURL: URL
    var apiKey: String

    static let `default` = SyncthingSnapshot(
        baseURL: URL(string: "http://127.0.0.1:8384")!,
        apiKey: ""
    )
}

struct SyncthingOverview: Equatable {
    var version: SystemVersion? = nil
    var status: SystemStatus? = nil
    var config: SyncthingConfig? = nil
    var connections: Connections? = nil

    var hasData: Bool {
        version != nil || status != nil || config != nil || connections != nil
    }
}

struct SystemVersion: Decodable, Equatable {
    let version: String
    let os: String?
    let arch: String?
}

struct SystemStatus: Decodable, Equatable {
    let myID: String?
    let goroutines: Int?
    let uptime: Int?
    let pathSeparator: String?
    let discoveryEnabled: Bool?
    let startTime: String?

    enum CodingKeys: String, CodingKey {
        case myID
        case goroutines
        case uptime
        case pathSeparator
        case discoveryEnabled
        case startTime
    }
}

struct SyncthingConfig: Decodable, Equatable {
    let version: Int?
    let devices: [Device]
    let folders: [Folder]
    let gui: GUIConfig?
}

struct GUIConfig: Decodable, Equatable {
    let enabled: Bool?
    let address: String?
    let user: String?
    let useTLS: Bool?
    let apiKey: String?
}

struct Folder: Decodable, Identifiable, Equatable {
    let id: String
    let label: String?
    let path: String?
    let type: String?
    let paused: Bool?
    let devices: [SharedDevice]?

    var displayName: String {
        guard let label, !label.isEmpty else { return id }
        return label
    }

    var sharedDeviceCount: Int {
        devices?.count ?? 0
    }
}

struct SharedDevice: Decodable, Equatable {
    let deviceID: String?
    let introducedBy: String?
}

struct Device: Decodable, Identifiable, Equatable {
    let deviceID: String
    let name: String?
    let addresses: [String]?
    let compression: String?
    let paused: Bool?
    let introducer: Bool?

    var id: String { deviceID }

    var displayName: String {
        guard let name, !name.isEmpty else {
            return String(deviceID.prefix(7))
        }
        return name
    }
}

struct Connections: Decodable, Equatable {
    let connections: [String: DeviceConnection]
    let total: TotalConnectionStats?
}

struct DeviceConnection: Decodable, Equatable {
    let connected: Bool?
    let paused: Bool?
    let address: String?
    let clientVersion: String?
    let inBytesTotal: Int64?
    let outBytesTotal: Int64?
}

struct TotalConnectionStats: Decodable, Equatable {
    let inBytesTotal: Int64?
    let outBytesTotal: Int64?
}

extension DeviceConnection {
    var stateText: String {
        if paused == true { return "已暂停" }
        return connected == true ? "已连接" : "未连接"
    }
}

extension Int {
    var durationText: String {
        let days = self / 86_400
        let hours = (self % 86_400) / 3_600
        let minutes = (self % 3_600) / 60

        if days > 0 { return "\(days)天 \(hours)小时" }
        if hours > 0 { return "\(hours)小时 \(minutes)分钟" }
        return "\(minutes)分钟"
    }
}

extension Int64 {
    var byteCountText: String {
        ByteCountFormatter.string(fromByteCount: self, countStyle: .file)
    }
}
