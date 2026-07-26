import CoreAudio
import Foundation

package protocol AudioHardwareAccess: AnyObject {
    func allDevices() throws -> [AudioDeviceDescriptor]
    func defaultInputDeviceID() throws -> AudioObjectID
    func defaultOutputDeviceID() throws -> AudioObjectID
    func defaultSystemOutputDeviceID() throws -> AudioObjectID
    func outputVolumeState() throws -> OutputVolumeState
    func setDefaultInputDeviceID(_ deviceID: AudioObjectID) throws
    func setDefaultOutputDeviceID(_ deviceID: AudioObjectID) throws
    func setDefaultSystemOutputDeviceID(_ deviceID: AudioObjectID) throws
    func setOutputVolume(_ volume: Float) throws
    func setOutputMuted(_ isMuted: Bool) throws
    func startMonitoring(_ onChange: @escaping @Sendable () -> Void) throws
    func stopMonitoring()
}

package struct OutputVolumeState: Equatable, Sendable {
    package let volume: Float?
    package let isMuted: Bool?
    package let isVolumeAdjustable: Bool
    package let isMuteAdjustable: Bool

    package init(
        volume: Float?,
        isMuted: Bool?,
        isVolumeAdjustable: Bool? = nil,
        isMuteAdjustable: Bool? = nil
    ) {
        self.volume = volume
        self.isMuted = isMuted
        self.isVolumeAdjustable = isVolumeAdjustable ?? (volume != nil)
        self.isMuteAdjustable = isMuteAdjustable ?? (isMuted != nil)
    }

    package var supportsVolume: Bool { volume != nil && isVolumeAdjustable }
    package var supportsMute: Bool { isMuted != nil && isMuteAdjustable }
}

package enum AudioDeviceError: LocalizedError {
    case coreAudio(operation: String, status: OSStatus)
    case deviceUnavailable
    case unsupportedInput(String)
    case unsupportedSynchronizedOutput(String)
    case unsupportedOutputVolume
    case unsupportedOutputMute
    case stateVerificationFailed(String)
    case switchFailed(primary: String, rollback: [String])

    package var errorDescription: String? {
        switch self {
        case let .coreAudio(operation, status):
            return "\(operation)失败（Core Audio 错误 \(status)）"
        case .deviceUnavailable:
            return "所选设备已不可用，请刷新后重试。"
        case let .unsupportedInput(name):
            return "设备“\(name)”不能设为默认输入设备。"
        case let .unsupportedSynchronizedOutput(name):
            return "设备“\(name)”不能同时设为默认输出和系统提示音输出。"
        case .unsupportedOutputVolume:
            return "当前输出设备不支持音量调节。"
        case .unsupportedOutputMute:
            return "当前输出设备不支持静音。"
        case let .stateVerificationFailed(message):
            return message
        case let .switchFailed(primary, rollback):
            if rollback.isEmpty {
                return "切换失败：\(primary)。原设备设置已恢复。"
            }
            return "切换失败：\(primary)。恢复原设备时也发生错误：\(rollback.joined(separator: "；"))"
        }
    }
}

package enum AudioDeviceSwitchCoordinator {
    package static func switchInput(
        to device: AudioDeviceDescriptor,
        using hardware: AudioHardwareAccess
    ) throws {
        guard device.canSwitchInput else {
            throw AudioDeviceError.unsupportedInput(device.name)
        }

        let oldInput = try hardware.defaultInputDeviceID()
        do {
            try hardware.setDefaultInputDeviceID(device.audioObjectID)
            guard try hardware.defaultInputDeviceID() == device.audioObjectID else {
                throw AudioDeviceError.stateVerificationFailed("系统未确认新的默认输入设备。")
            }
        } catch {
            var rollbackErrors: [String] = []
            do {
                try hardware.setDefaultInputDeviceID(oldInput)
            } catch {
                rollbackErrors.append(error.localizedDescription)
            }
            throw AudioDeviceError.switchFailed(
                primary: error.localizedDescription,
                rollback: rollbackErrors
            )
        }
    }

    package static func switchOutput(
        to device: AudioDeviceDescriptor,
        using hardware: AudioHardwareAccess
    ) throws {
        guard device.canSwitchOutputWithSystemSounds else {
            throw AudioDeviceError.unsupportedSynchronizedOutput(device.name)
        }

        let oldOutput = try hardware.defaultOutputDeviceID()
        let oldSystemOutput = try hardware.defaultSystemOutputDeviceID()

        do {
            try hardware.setDefaultOutputDeviceID(device.audioObjectID)
            try hardware.setDefaultSystemOutputDeviceID(device.audioObjectID)

            let confirmedOutput = try hardware.defaultOutputDeviceID()
            let confirmedSystemOutput = try hardware.defaultSystemOutputDeviceID()
            guard confirmedOutput == device.audioObjectID,
                  confirmedSystemOutput == device.audioObjectID
            else {
                throw AudioDeviceError.stateVerificationFailed("系统未确认新的输出设备设置。")
            }
        } catch {
            var rollbackErrors: [String] = []
            do {
                try hardware.setDefaultOutputDeviceID(oldOutput)
            } catch {
                rollbackErrors.append("默认输出：\(error.localizedDescription)")
            }
            do {
                try hardware.setDefaultSystemOutputDeviceID(oldSystemOutput)
            } catch {
                rollbackErrors.append("系统提示音：\(error.localizedDescription)")
            }
            throw AudioDeviceError.switchFailed(
                primary: error.localizedDescription,
                rollback: rollbackErrors
            )
        }
    }
}
