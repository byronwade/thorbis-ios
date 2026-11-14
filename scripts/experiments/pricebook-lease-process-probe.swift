// Test-only macOS process probe. This is not linked into Thorbis.
import Foundation
import Security
import Darwin

let args = CommandLine.arguments
guard args.count == 4, args[2].hasPrefix("com.thorbis.field.test-only-process-lease.") else { exit(64) }
let mode = args[1], service = args[2], directory = args[3]
let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                            kSecAttrService as String: service, kSecAttrAccount as String: "synthetic-scope"]
if mode == "cleanup" { SecItemDelete(query as CFDictionary); exit(0) }
let fd = open("\(directory)/scope.lock", O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
guard fd >= 0 else { exit(70) }
// Keep the per-scope lock for the entire operation, including the simulated request.
if flock(fd, LOCK_EX | LOCK_NB) != 0 {
    if errno == EWOULDBLOCK { exit(75) }
    exit(73)
}
if mode == "owner" {
    var item = query
    item[kSecValueData as String] = Data("dirty".utf8)
    item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { exit(71) }
    try Data("ready".utf8).write(to: URL(fileURLWithPath: "\(directory)/ready"), options: .atomic)
    while true { sleep(1) }
}
if mode == "probe" {
    var lookup = query; lookup[kSecReturnData as String] = true
    var result: CFTypeRef?
    let status = SecItemCopyMatching(lookup as CFDictionary, &result)
    guard status == errSecSuccess, result as? Data == Data("dirty".utf8) else { exit(72) }
    exit(0)
}
exit(64)
