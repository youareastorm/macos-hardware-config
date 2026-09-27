import Foundation
import IOKit
import IOKit.usb

/// Detects USB disconnects via IOKit's own service-lifecycle notifications on `IOUSBHostDevice`
/// (`IOServiceAddMatchingNotification`/`IOServiceAddInterestNotification`), instead of pattern-
/// matching unified-log text (the previous approach, `KernelLogUSBPowerFaultDetector`).
///
/// Verified live on real hardware, physically unplugging and replugging a drive while a
/// standalone proof-of-concept (a small C program using the same IOKit calls) was running:
///   - Unplug produced, in order: a `kIOTerminatedNotification` for the device, then on its
///     interest notification `kIOMessageDeviceWillPowerOff` (0x210) and `kIOMessageServiceIsTerminated`
///     (0x010) — immediate, unambiguous, and scoped to that exact device.
///   - Replug produced a fresh `kIOMatchedNotification` and normal traffic resumed.
///   - The routine `kIOMessageServiceIsAttemptingOpen`/`kIOMessageServiceWasClosed` (0x101/0x110)
///     pair fires roughly once a second per device from ordinary disk-arbitration housekeeping —
///     real noise, deliberately not recorded as an incident.
/// This is strictly better than the log-text approach: it's scoped to exactly the right IOKit
/// class, so it can't be confused by unrelated subsystems the way a keyword match can (the log
/// approach had a real false-positive risk from DisplayPort/Thunderbolt housekeeping lines that
/// happen to contain the word "terminat").
public final class IOKitUSBPowerFaultDetector: USBPowerFaultDetecting {
    private struct TimestampedIncident {
        let date: Date
        let incident: USBPowerIncident
    }

    private let lock = NSLock()
    private var incidents: [TimestampedIncident] = []
    /// How long a recorded incident is kept around, independent of any caller's query window —
    /// just a cap so this doesn't grow forever across a long-running app session.
    private static let retention: TimeInterval = 60 * 60

    private let notifyPort: IONotificationPortRef
    private var matchedIterator: io_iterator_t = 0
    private var terminatedIterator: io_iterator_t = 0
    private var interestNotifications: [io_object_t] = []

    private static let kIOMessageServiceIsTerminated = iokitCommonMsg(0x010)
    private static let kIOMessageDeviceWillPowerOff = iokitCommonMsg(0x210)

    private static func iokitCommonMsg(_ code: UInt32) -> UInt32 {
        (0x38 << 24) | code
    }

    public init() {
        notifyPort = IONotificationPortCreate(kIOMainPortDefault)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), IONotificationPortGetRunLoopSource(notifyPort).takeUnretainedValue(), .commonModes)

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        IOServiceAddMatchingNotification(notifyPort, kIOMatchedNotification, IOServiceMatching("IOUSBHostDevice"),
            { refcon, iterator in
                guard let refcon else { return }
                Unmanaged<IOKitUSBPowerFaultDetector>.fromOpaque(refcon).takeUnretainedValue().drainMatched(iterator)
            }, selfPtr, &matchedIterator)
        drainMatched(matchedIterator)

        IOServiceAddMatchingNotification(notifyPort, kIOTerminatedNotification, IOServiceMatching("IOUSBHostDevice"),
            { refcon, iterator in
                guard let refcon else { return }
                Unmanaged<IOKitUSBPowerFaultDetector>.fromOpaque(refcon).takeUnretainedValue().drainTerminated(iterator)
            }, selfPtr, &terminatedIterator)
        drainTerminated(terminatedIterator)
    }

    deinit {
        for notification in interestNotifications { IOObjectRelease(notification) }
        if matchedIterator != 0 { IOObjectRelease(matchedIterator) }
        if terminatedIterator != 0 { IOObjectRelease(terminatedIterator) }
        IONotificationPortDestroy(notifyPort)
    }

    public func recentPowerIncidents(within window: TimeInterval) -> [USBPowerIncident] {
        let cutoff = Date().addingTimeInterval(-window)
        lock.lock()
        defer { lock.unlock() }
        return incidents.filter { $0.date >= cutoff }.map(\.incident)
    }

    private func record(_ line: String) {
        lock.lock()
        let now = Date()
        incidents.append(TimestampedIncident(date: now, incident: USBPowerIncident(line: line)))
        let cutoff = now.addingTimeInterval(-Self.retention)
        incidents.removeAll { $0.date < cutoff }
        lock.unlock()
    }

    private func deviceName(_ service: io_service_t) -> String {
        var name = [CChar](repeating: 0, count: 128)
        guard IORegistryEntryGetName(service, &name) == KERN_SUCCESS else { return "Appareil USB" }
        return String(cString: name)
    }

    private func drainMatched(_ iterator: io_iterator_t) {
        while case let service = IOIteratorNext(iterator), service != 0 {
            var notification: io_object_t = 0
            IOServiceAddInterestNotification(notifyPort, service, kIOGeneralInterest, { refcon, service, messageType, _ in
                guard let refcon else { return }
                let detector = Unmanaged<IOKitUSBPowerFaultDetector>.fromOpaque(refcon).takeUnretainedValue()
                detector.handleInterest(service: service, messageType: messageType)
            }, Unmanaged.passUnretained(self).toOpaque(), &notification)
            interestNotifications.append(notification)
            IOObjectRelease(service)
        }
    }

    private func drainTerminated(_ iterator: io_iterator_t) {
        while case let service = IOIteratorNext(iterator), service != 0 {
            record("\(deviceName(service)) : déconnecté")
            IOObjectRelease(service)
        }
    }

    private func handleInterest(service: io_service_t, messageType: UInt32) {
        guard messageType == Self.kIOMessageDeviceWillPowerOff || messageType == Self.kIOMessageServiceIsTerminated else { return }
        let name = deviceName(service)
        let what = messageType == Self.kIOMessageDeviceWillPowerOff ? "coupure d'alimentation" : "arrêt de service"
        record("\(name) : \(what)")
    }
}
