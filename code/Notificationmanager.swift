import Foundation
import UserNotifications
import AppKit

/// Posts a system notification whenever a new song starts playing. Shows
/// the song's artwork if there is any; falls back to the app icon otherwise
/// (that's just what happens when a notification has no attachment).
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, error in
            if let error {
                print("Notification permission error: \(error)")
            }
        }
    }

    func notifyNowPlaying(title: String, artist: String? = nil, artwork: NSImage? = nil) {
        // Encoding artwork into a notification attachment means a full
        // TIFF->JPEG re-encode (of the same full-resolution image used for
        // on-screen display) plus a disk write — done synchronously on the
        // main thread, this was a real CPU spike/hitch every time a song
        // changed. None of it needs to block playback, so it all moves to a
        // background task.
        Task.detached(priority: .utility) {
            let content = UNMutableNotificationContent()
            content.title = "Now Playing"
            content.body = artist.map { "\(title) — \($0)" } ?? title
            // No sound here — it would layer an alert sound on top of the music itself.

            if let artwork, let attachment = Self.attachment(from: artwork) {
                content.attachments = [attachment]
            }

            let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
            try? await UNUserNotificationCenter.current().add(request)
        }
    }

    private static func attachment(from image: NSImage) -> UNNotificationAttachment? {
        // The notification banner only ever shows this at thumbnail size —
        // downscaling before encoding cuts the JPEG encode and disk-write
        // cost regardless of the original artwork's resolution.
        let maxDimension: CGFloat = 200
        let scale = min(1, maxDimension / max(image.size.width, image.size.height, 1))
        let targetSize = NSSize(width: image.size.width * scale, height: image.size.height * scale)

        let thumbnail = NSImage(size: targetSize)
        thumbnail.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: targetSize))
        thumbnail.unlockFocus()

        guard let tiffData = thumbnail.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let jpegData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.8])
        else { return nil }

        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("jpg")

        do {
            try jpegData.write(to: fileURL)
            return try UNNotificationAttachment(identifier: UUID().uuidString, url: fileURL, options: nil)
        } catch {
            return nil
        }
    }

    // Without this, macOS suppresses the banner while the app is frontmost.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
