import CoreServices
import Foundation

/// Watches application folders. Replays FSEvents since the last saved event id so a launch
/// with no installs or deletions can skip the directory walk.
final class AppCatalogueMonitor {
    private let box = AppWatchBox()
    private var stream: FSEventStreamRef?

    func start(paths: [String], since eventID: UInt64?, onHistory: @escaping @Sendable (Bool) -> Void, onChange: @escaping @Sendable () -> Void) {
        stop()
        let existing = paths.filter { FileManager.default.fileExists(atPath: $0) }
        guard !existing.isEmpty else {
            onHistory(true)
            return
        }

        box.onHistory = onHistory
        box.onChange = onChange
        box.sawChange = false
        box.historyDelivered = false

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(box).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let flags = FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes)
            | FSEventStreamCreateFlags(kFSEventStreamCreateFlagNoDefer)
            | FSEventStreamCreateFlags(kFSEventStreamCreateFlagIgnoreSelf)
        let since = eventID.map { FSEventStreamEventId($0) } ?? FSEventStreamEventId(kFSEventStreamEventIdSinceNow)
        guard let created = FSEventStreamCreate(
            nil,
            appCatalogueEventCallback,
            &context,
            existing as CFArray,
            since,
            0.4,
            flags
        ) else {
            onHistory(true)
            return
        }
        stream = created
        FSEventStreamSetDispatchQueue(created, .main)
        if !FSEventStreamStart(created) {
            stop()
            onHistory(true)
        }
    }

    func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
        box.onHistory = nil
        box.onChange = nil
    }

    deinit {
        stop()
    }
}

private final class AppWatchBox {
    var sawChange = false
    var historyDelivered = false
    var onHistory: (@Sendable (Bool) -> Void)?
    var onChange: (@Sendable () -> Void)?
}

private let appCatalogueEventCallback: FSEventStreamCallback = { _, info, numEvents, _, eventFlags, _ in
    guard let info, numEvents > 0 else { return }
    let box = Unmanaged<AppWatchBox>.fromOpaque(info).takeUnretainedValue()
    let historyBit = FSEventStreamEventFlags(kFSEventStreamEventFlagHistoryDone)
    var historyDone = false
    for index in 0..<numEvents {
        let flag = eventFlags[index]
        if flag & historyBit != 0 { historyDone = true }
        if flag == 0 || flag & ~historyBit != 0 { box.sawChange = true }
    }
    if historyDone {
        let changed = box.sawChange
        box.sawChange = false
        box.historyDelivered = true
        box.onHistory?(changed)
    } else if box.historyDelivered && box.sawChange {
        box.sawChange = false
        box.onChange?()
    }
}
