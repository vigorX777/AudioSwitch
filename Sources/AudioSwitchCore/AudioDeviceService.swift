import Combine
import CoreAudio
import Foundation

@MainActor
package final class AudioDeviceService: ObservableObject {
    @Published package private(set) var inputDevices: [AudioDeviceDescriptor] = []
    @Published package private(set) var outputDevices: [AudioDeviceDescriptor] = []
    @Published package private(set) var defaultInputDeviceID: AudioObjectID?
    @Published package private(set) var defaultOutputDeviceID: AudioObjectID?
    @Published package private(set) var defaultSystemOutputDeviceID: AudioObjectID?
    @Published package private(set) var errorMessage: String?

    private let hardware: AudioHardwareAccess

    package init(
        hardware: AudioHardwareAccess = CoreAudioHardwareAccess(),
        monitorChanges: Bool = true
    ) {
        self.hardware = hardware
        refresh()
        guard monitorChanges else { return }

        do {
            try hardware.startMonitoring { [weak self] in
                Task { @MainActor [weak self] in
                    self?.refresh()
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    package func refresh() {
        do {
            let devices = try hardware.allDevices()
            let inputID = try? hardware.defaultInputDeviceID()
            let outputID = try? hardware.defaultOutputDeviceID()
            let systemOutputID = try? hardware.defaultSystemOutputDeviceID()

            defaultInputDeviceID = inputID
            defaultOutputDeviceID = outputID
            defaultSystemOutputDeviceID = systemOutputID
            inputDevices = AudioDeviceCatalog.sorted(
                devices.filter(\.hasInput),
                currentDeviceID: inputID
            )
            outputDevices = AudioDeviceCatalog.sorted(
                devices.filter(\.hasOutput),
                currentDeviceID: outputID
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    package func selectInput(uid: String) {
        guard let device = inputDevices.first(where: { $0.uid == uid }) else {
            errorMessage = AudioDeviceError.deviceUnavailable.localizedDescription
            refresh()
            return
        }

        performSwitch {
            try AudioDeviceSwitchCoordinator.switchInput(to: device, using: hardware)
        }
    }

    package func selectOutput(uid: String) {
        guard let device = outputDevices.first(where: { $0.uid == uid }) else {
            errorMessage = AudioDeviceError.deviceUnavailable.localizedDescription
            refresh()
            return
        }

        performSwitch {
            try AudioDeviceSwitchCoordinator.switchOutput(to: device, using: hardware)
        }
    }

    package func clearError() {
        errorMessage = nil
    }

    private func performSwitch(_ operation: () throws -> Void) {
        do {
            try operation()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        refresh()
    }
}
