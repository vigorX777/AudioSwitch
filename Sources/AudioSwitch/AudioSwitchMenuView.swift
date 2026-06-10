import AppKit
import AudioSwitchCore
import CoreAudio
import SwiftUI

struct AudioSwitchMenuView: View {
    @ObservedObject var audioDeviceService: AudioDeviceService
    @StateObject private var launchAtLogin = LaunchAtLoginController()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    outputSection
                    inputSection
                }
                .padding(12)
            }
            // MenuBarExtra windows may collapse a flexible ScrollView to zero height.
            .frame(height: deviceListHeight)

            if let errorMessage = combinedErrorMessage {
                errorBanner(errorMessage)
            }

            Divider()
            footer
        }
        .frame(width: 360)
        .onAppear {
            audioDeviceService.refresh()
            launchAtLogin.refresh()
        }
    }

    private var deviceListHeight: CGFloat {
        let visibleRows = audioDeviceService.inputDevices.count + audioDeviceService.outputDevices.count
        let estimatedHeight = CGFloat(visibleRows * 52 + 100)
        return min(460, max(260, estimatedHeight))
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "speaker.wave.2.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.tint)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 6) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("AudioSwitch")
                        .font(.headline)
                    Text("快速切换输入与输出设备")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 6) {
                    Text("v\(appVersion)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(.quaternary, in: Capsule())

                    Button {
                        launchAtLogin.setEnabled(!launchAtLogin.isEnabled)
                    } label: {
                        HStack(spacing: 5) {
                            Circle()
                                .fill(launchAtLogin.isEnabled ? Color.green : Color.secondary)
                                .frame(width: 6, height: 6)
                            Text(launchAtLogin.isEnabled ? "自启已开启" : "自启未开启")
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(.quaternary, in: Capsule())
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .help(launchAtLogin.isEnabled ? "点击关闭开机启动" : "点击开启开机启动")
                    .accessibilityLabel(launchAtLogin.isEnabled ? "关闭开机启动" : "开启开机启动")
                }
            }

            Spacer()

            Button {
                audioDeviceService.refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("刷新设备")
        }
        .padding(12)
    }

    private var outputSection: some View {
        deviceSection(
            title: "输出设备",
            systemImage: "speaker.wave.2",
            devices: audioDeviceService.outputDevices,
            selectedDeviceID: audioDeviceService.defaultOutputDeviceID,
            isEnabled: { $0.canSwitchOutputWithSystemSounds },
            disabledReason: { device in
                device.canBeDefaultOutput
                    ? "不能同时用于系统提示音"
                    : "不能设为默认输出"
            },
            action: { audioDeviceService.selectOutput(uid: $0.uid) },
            note: outputSynchronizationNote
        )
    }

    private var inputSection: some View {
        deviceSection(
            title: "输入设备",
            systemImage: "mic",
            devices: audioDeviceService.inputDevices,
            selectedDeviceID: audioDeviceService.defaultInputDeviceID,
            isEnabled: { $0.canSwitchInput },
            disabledReason: { _ in "不能设为默认输入" },
            action: { audioDeviceService.selectInput(uid: $0.uid) }
        )
    }

    @ViewBuilder
    private func deviceSection(
        title: String,
        systemImage: String,
        devices: [AudioDeviceDescriptor],
        selectedDeviceID: AudioObjectID?,
        isEnabled: @escaping (AudioDeviceDescriptor) -> Bool,
        disabledReason: @escaping (AudioDeviceDescriptor) -> String,
        action: @escaping (AudioDeviceDescriptor) -> Void,
        note: String? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))

            if let note {
                Label(note, systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if devices.isEmpty {
                Text("没有可用设备")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 4) {
                    ForEach(devices) { device in
                        DeviceRow(
                            device: device,
                            isSelected: device.audioObjectID == selectedDeviceID,
                            isEnabled: isEnabled(device),
                            disabledReason: disabledReason(device),
                            action: { action(device) }
                        )
                    }
                }
            }
        }
    }

    private var outputSynchronizationNote: String? {
        guard let outputID = audioDeviceService.defaultOutputDeviceID,
              let systemOutputID = audioDeviceService.defaultSystemOutputDeviceID,
              outputID != systemOutputID
        else {
            return nil
        }
        return "当前主输出与系统提示音输出不同；选择设备后会同步。"
    }

    private var combinedErrorMessage: String? {
        audioDeviceService.errorMessage ?? launchAtLogin.errorMessage
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            Text(message)
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Button {
                audioDeviceService.clearError()
                launchAtLogin.clearError()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
        }
        .padding(10)
        .background(Color.red.opacity(0.08))
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("退出 AudioSwitch", systemImage: "power")
            }
            .font(.caption)
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.3"
    }
}

private struct DeviceRow: View {
    let device: AudioDeviceDescriptor
    let isSelected: Bool
    let isEnabled: Bool
    let disabledReason: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: device.transportType.systemImageName)
                    .frame(width: 20)
                    .foregroundStyle(isEnabled ? Color.accentColor : Color.secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(device.name)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Text(device.transportType.displayName)
                        if !isEnabled {
                            Text("· \(disabledReason)")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark")
                        .fontWeight(.semibold)
                        .foregroundStyle(.tint)
                }
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.62)
    }
}
