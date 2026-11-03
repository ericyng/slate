import Foundation
import CoreServices

/// Recursive change notifications for the vault directory.
final class FSEventsWatcher {
    private var stream: FSEventStreamRef?
    private let url: URL
    private let handler: ([String]) -> Void

    init(url: URL, handler: @escaping ([String]) -> Void) {
        self.url = url
        self.handler = handler
        start()
    }

    deinit { stop() }

    func stop() {
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            self.stream = nil
        }
    }

    private func start() {
        let context = UnsafeMutablePointer<FSEventStreamContext>.allocate(capacity: 1)
        context.initialize(to: FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        ))

        // The batch of changed paths is passed through so the store can ignore
        // its own metadata writes instead of rescanning the whole vault.
        // UseCFTypes makes eventPaths a CFArray of CFString; without that flag
        // it is a C string array and reading it as CFArray segfaults.
        let callback: FSEventStreamCallback = { _, info, numEvents, eventPaths, _, _ in
            guard let info, numEvents > 0 else { return }
            let watcher = Unmanaged<FSEventsWatcher>.fromOpaque(info).takeUnretainedValue()
            let array = Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue()
            var paths: [String] = []
            let count = CFArrayGetCount(array)
            paths.reserveCapacity(count)
            for i in 0..<count {
                guard let raw = CFArrayGetValueAtIndex(array, i) else { continue }
                let path = Unmanaged<CFString>.fromOpaque(raw).takeUnretainedValue()
                paths.append(path as String)
            }
            DispatchQueue.main.async { watcher.handler(paths) }
        }

        let paths = [url.path] as CFArray
        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            context,
            paths,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.4,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents
                                     | kFSEventStreamCreateFlagNoDefer
                                     | kFSEventStreamCreateFlagUseCFTypes)
        ) else {
            context.deinitialize(count: 1)
            context.deallocate()
            return
        }

        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, DispatchQueue.main)
        FSEventStreamStart(stream)
    }
}
