import AppKit
import AudioSwitchCore
import SwiftUI

@main
@MainActor
struct AudioSwitchApp: App {
    @StateObject private var audioDeviceService: AudioDeviceService

    init() {
        NSApplication.shared.setActivationPolicy(.accessory)
        _audioDeviceService = StateObject(wrappedValue: AudioDeviceService())
    }

    var body: some Scene {
        MenuBarExtra("AudioSwitch", systemImage: "speaker.wave.2") {
            AudioSwitchMenuView(audioDeviceService: audioDeviceService)
        }
        .menuBarExtraStyle(.window)
    }
}
