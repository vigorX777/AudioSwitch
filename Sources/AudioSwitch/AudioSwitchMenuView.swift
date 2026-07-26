import AppKit
import AudioSwitchCore
import CoreAudio
import SwiftUI

struct AudioSwitchMenuView: View {
    @ObservedObject var audioDeviceService: AudioDeviceService
    @StateObject private var launchAtLogin = LaunchAtLoginController()
    @State private var didRefreshDevices = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Divider()
            volumeSection

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
        .background(glassBacking)
        .foregroundStyle(primaryForeground)
        .onAppear {
            audioDeviceService.refresh()
            launchAtLogin.refresh()
        }
    }

    private var primaryForeground: Color {
        colorScheme == .dark ? .white : .black
    }

    private var secondaryForeground: Color {
        primaryForeground.opacity(colorScheme == .dark ? 0.72 : 0.66)
    }

    private var glassBacking: Color {
        colorScheme == .dark ? .black.opacity(0.36) : .white.opacity(0.52)
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
                        .foregroundStyle(secondaryForeground)
                }

                HStack(spacing: 6) {
                    Text("v\(appVersion)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(secondaryForeground)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(.quaternary, in: Capsule())

                    Button {
                        launchAtLogin.setEnabled(!launchAtLogin.isEnabled)
                    } label: {
                        HStack(spacing: 5) {
                            Circle()
                                .fill(launchAtLogin.isEnabled ? Color.green : secondaryForeground)
                                .frame(width: 6, height: 6)
                            Text(launchAtLogin.isEnabled ? "自启已开启" : "自启未开启")
                        }
                        .font(.caption2)
                        .foregroundStyle(secondaryForeground)
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
                didRefreshDevices = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    didRefreshDevices = false
                }
            } label: {
                Image(systemName: didRefreshDevices ? "checkmark" : "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help(didRefreshDevices ? "已刷新设备" : "刷新设备")
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

    private var volumeSection: some View {
        let state = audioDeviceService.outputVolumeState
        let volume = Binding<Double>(
            get: { Double(state.volume ?? 0) },
            set: { audioDeviceService.setOutputVolume(Float($0)) }
        )

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("音量", systemImage: state.isMuted == true ? "speaker.slash" : "speaker.wave.2")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(volumeText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(secondaryForeground)
            }

            HStack(spacing: 10) {
                VolumeSlider(value: volume, isEnabled: state.supportsVolume) { event in
                    guard event.scrollingDeltaY != 0 else { return }
                    audioDeviceService.adjustOutputVolume(
                        by: event.scrollingDeltaY > 0 ? 0.05 : -0.05
                    )
                }

                Button {
                    audioDeviceService.setOutputMuted(!(state.isMuted ?? false))
                } label: {
                    Image(systemName: state.isMuted == true ? "speaker.slash.fill" : "speaker.wave.2.fill")
                }
                .buttonStyle(.borderless)
                .disabled(!state.supportsMute)
                .help(state.supportsMute ? "静音/取消静音" : "当前输出设备不支持静音")
            }

            if !state.supportsVolume {
                Text("当前输出设备不支持音量调节")
                    .font(.caption)
                    .foregroundStyle(secondaryForeground)
            }
        }
        .padding(12)
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
                    .foregroundStyle(secondaryForeground)
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

    private var volumeText: String {
        let state = audioDeviceService.outputVolumeState
        guard let volume = state.volume else {
            return "不可调"
        }
        return state.isMuted == true ? "静音" : "\(Int((volume * 100).rounded()))%"
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
            .foregroundStyle(secondaryForeground)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.2.0"
    }
}

private struct DeviceRow: View {
    let device: AudioDeviceDescriptor
    let isSelected: Bool
    let isEnabled: Bool
    let disabledReason: String
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    private var secondaryForeground: Color {
        colorScheme == .dark ? .white.opacity(0.72) : .black.opacity(0.66)
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: device.transportType.systemImageName)
                    .frame(width: 20)
                    .foregroundStyle(isEnabled ? Color.accentColor : secondaryForeground)

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
                    .foregroundStyle(secondaryForeground)
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
