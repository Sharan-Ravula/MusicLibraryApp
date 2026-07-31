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
        let content = UNMutableNotificationContent()
        content.title = "Now Playing"
        content.body = artist.map { "\(title) — \($0)" } ?? title
        // No sound here — it would layer an alert sound on top of the music itself.

        if let artwork, let attachment = attachment(from: artwork) {
            content.attachments = [attachment]
        }

        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    private func attachment(from image: NSImage) -> UNNotificationAttachment? {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let jpegData = bitmap.representation(using: .jpeg, properties: [:])
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
