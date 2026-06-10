import CoreAudio
import Foundation

package enum AudioTransportType: String, CaseIterable, Sendable {
    case builtIn
    case bluetooth
    case bluetoothLE
    case usb
    case display
    case airPlay
    case virtual
    case aggregate
    case other

    package init(coreAudioValue: UInt32) {
        switch coreAudioValue {
        case kAudioDeviceTransportTypeBuiltIn:
            self = .builtIn
        case kAudioDeviceTransportTypeBluetooth:
            self = .bluetooth
        case kAudioDeviceTransportTypeBluetoothLE:
            self = .bluetoothLE
        case kAudioDeviceTransportTypeUSB:
            self = .usb
        case kAudioDeviceTransportTypeHDMI, kAudioDeviceTransportTypeDisplayPort:
            self = .display
        case kAudioDeviceTransportTypeAirPlay:
            self = .airPlay
        case kAudioDeviceTransportTypeVirtual:
            self = .virtual
        case kAudioDeviceTransportTypeAggregate, kAudioDeviceTransportTypeAutoAggregate:
            self = .aggregate
        default:
            self = .other
        }
    }

    package var displayName: String {
        switch self {
        case .builtIn: "内置"
        case .bluetooth: "蓝牙"
        case .bluetoothLE: "蓝牙 LE"
        case .usb: "USB"
        case .display: "显示器"
        case .airPlay: "AirPlay"
        case .virtual: "虚拟"
        case .aggregate: "聚合"
        case .other: "其他"
        }
    }

    package var systemImageName: String {
        switch self {
        case .builtIn: "laptopcomputer"
        case .bluetooth, .bluetoothLE: "airpodsmax"
        case .usb: "cable.connector"
        case .display: "display"
        case .airPlay: "airplayaudio"
        case .virtual: "waveform.path"
        case .aggregate: "square.stack.3d.up"
        case .other: "speaker.wave.2"
        }
    }

    fileprivate var sortOrder: Int {
        switch self {
        case .builtIn: 0
        case .bluetooth, .bluetoothLE: 1
        case .usb: 2
        case .display: 3
        case .airPlay: 4
        case .virtual: 5
        case .aggregate: 6
        case .other: 7
        }
    }
}

package struct AudioDeviceDescriptor: Identifiable, Equatable, Sendable {
    package let audioObjectID: AudioObjectID
    package let uid: String
    package let name: String
    package let transportType: AudioTransportType
    package let hasInput: Bool
    package let hasOutput: Bool
    package let canBeDefaultInput: Bool
    package let canBeDefaultOutput: Bool
    package let canBeDefaultSystemOutput: Bool

    package var id: String { uid }

    package var canSwitchInput: Bool {
        hasInput && canBeDefaultInput
    }

    package var canSwitchOutputWithSystemSounds: Bool {
        hasOutput && canBeDefaultOutput && canBeDefaultSystemOutput
    }

    package init(
        audioObjectID: AudioObjectID,
        uid: String,
        name: String,
        transportType: AudioTransportType,
        hasInput: Bool,
        hasOutput: Bool,
        canBeDefaultInput: Bool,
        canBeDefaultOutput: Bool,
        canBeDefaultSystemOutput: Bool
    ) {
        self.audioObjectID = audioObjectID
        self.uid = uid
        self.name = name
        self.transportType = transportType
        self.hasInput = hasInput
        self.hasOutput = hasOutput
        self.canBeDefaultInput = canBeDefaultInput
        self.canBeDefaultOutput = canBeDefaultOutput
        self.canBeDefaultSystemOutput = canBeDefaultSystemOutput
    }
}

package enum AudioDeviceCatalog {
    package static func sorted(
        _ devices: [AudioDeviceDescriptor],
        currentDeviceID: AudioObjectID?
    ) -> [AudioDeviceDescriptor] {
        devices.sorted { lhs, rhs in
            let lhsIsCurrent = lhs.audioObjectID == currentDeviceID
            let rhsIsCurrent = rhs.audioObjectID == currentDeviceID
            if lhsIsCurrent != rhsIsCurrent {
                return lhsIsCurrent
            }
            if lhs.transportType.sortOrder != rhs.transportType.sortOrder {
                return lhs.transportType.sortOrder < rhs.transportType.sortOrder
            }
            let nameComparison = lhs.name.localizedStandardCompare(rhs.name)
            if nameComparison != .orderedSame {
                return nameComparison == .orderedAscending
            }
            return lhs.uid < rhs.uid
        }
    }
}
