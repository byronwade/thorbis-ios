import Darwin
import Foundation

// Darwin also imports a struct named `flock`; bind the POSIX function.
@_silgen_name("flock") private func posixFlock(_ descriptor: Int32, _ operation: Int32) -> Int32

enum BoundTapProcessLeaseError: Error { case unavailable, busy }
protocol BoundTapLease: AnyObject { func close() }

/// Cooperative exclusion using the OS-managed app-group directory itself.
/// Its identity must remain stable and all payment participants must cooperate.
/// This is a held prototype, not a release qualification.
final class BoundTapProcessLease: BoundTapLease, @unchecked Sendable {
    private let mutex = NSLock()
    private var descriptor: Int32

    private init(descriptor: Int32) { self.descriptor = descriptor }

    var isHeld: Bool {
        mutex.lock()
        defer { mutex.unlock() }
        return descriptor >= 0
    }

    static func acquire(path: String) throws -> BoundTapProcessLease {
        guard path.hasPrefix("/"), !path.utf8.contains(0) else { throw BoundTapProcessLeaseError.unavailable }
        let fd = path.withCString { Darwin.open($0, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW) }
        guard fd >= 0 else { throw BoundTapProcessLeaseError.unavailable }
        var information = stat()
        guard fstat(fd, &information) == 0,
              information.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR),
              information.st_uid == getuid() else {
            Darwin.close(fd)
            throw BoundTapProcessLeaseError.unavailable
        }
        guard posixFlock(fd, LOCK_EX | LOCK_NB) == 0 else {
            let code = errno
            Darwin.close(fd)
            if code == EWOULDBLOCK || code == EAGAIN { throw BoundTapProcessLeaseError.busy }
            throw BoundTapProcessLeaseError.unavailable
        }
        var lockedInformation = stat()
        var pathInformation = stat()
        let pathStatus = path.withCString { Darwin.lstat($0, &pathInformation) }
        guard fstat(fd, &lockedInformation) == 0, pathStatus == 0,
              pathInformation.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR),
              lockedInformation.st_dev == pathInformation.st_dev,
              lockedInformation.st_ino == pathInformation.st_ino else {
            Darwin.close(fd)
            throw BoundTapProcessLeaseError.unavailable
        }
        return BoundTapProcessLease(descriptor: fd)
    }

    func close() {
        mutex.lock()
        defer { mutex.unlock() }
        if descriptor >= 0 {
            Darwin.close(descriptor)
            descriptor = -1
        }
    }

    deinit { close() }
}
