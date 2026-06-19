//
//  NotificationManager.swift
//  ORB
//
//  Banner notifications + optional spoken result.
//

import Foundation
import UserNotifications
import AVFoundation

@MainActor
final class NotificationManager {
    static let shared = NotificationManager()
    private let synth = AVSpeechSynthesizer()

    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func banner(title: String, body: String, sound: Bool) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        if sound { content.sound = .default }
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }

    func speak(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = 0.5
        synth.speak(utterance)
    }
}
