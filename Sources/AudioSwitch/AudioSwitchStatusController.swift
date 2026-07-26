import AppKit
import AudioSwitchCore
import SwiftUI

@MainActor
final class AudioSwitchStatusController: NSObject, NSPopoverDelegate {
    private let audioDeviceService = AudioDeviceService()
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let statusButton = StatusItemInteractionButton()
    private let menuPopover = NSPopover()
    private let volumeFeedbackPanel = NSPanel(
        contentRect: .zero,
        styleMask: [.borderless, .nonactivatingPanel],
        backing: .buffered,
        defer: false
    )
    private var volumePopoverDismissTimer: Timer?
    private var outsideClickMonitor: Any?
    private var resignActiveObserver: NSObjectProtocol?

    override init() {
        super.init()
        configureStatusItem()
        configureMenuPopover()
        configureVolumeFeedbackPanel()
    }

    private func configureStatusItem() {
        let image = NSImage(systemSymbolName: "speaker.wave.2", accessibilityDescription: "AudioSwitch")
        image?.isTemplate = true
        statusButton.frame = NSRect(origin: .zero, size: NSSize(width: NSStatusItem.squareLength, height: NSStatusItem.squareLength))
        statusButton.image = image
        statusButton.imagePosition = .imageOnly
        statusButton.isBordered = false
        statusButton.toolTip = "AudioSwitch"
        statusButton.onClick = { [weak self] in
            self?.toggleMenuPopover()
        }
        statusButton.onScroll = { [weak self] event in
            self?.adjustVolume(for: event)
        }
        statusItem.view = statusButton
        statusItem.autosaveName = "com.vigor.AudioSwitch.status-item"
        statusItem.isVisible = true
    }

    private func configureMenuPopover() {
        menuPopover.behavior = .transient
        menuPopover.delegate = self
        menuPopover.contentViewController = NSHostingController(
            rootView: AudioSwitchMenuView(audioDeviceService: audioDeviceService)
        )
    }

    private func configureVolumeFeedbackPanel() {
        volumeFeedbackPanel.isOpaque = false
        volumeFeedbackPanel.backgroundColor = .clear
        volumeFeedbackPanel.hasShadow = false
        volumeFeedbackPanel.level = .statusBar
        volumeFeedbackPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        volumeFeedbackPanel.ignoresMouseEvents = true
    }

    private func toggleMenuPopover() {
        dismissVolumePopover()
        if menuPopover.isShown {
            menuPopover.performClose(nil)
            return
        }
        audioDeviceService.refresh()
        menuPopover.show(relativeTo: statusButton.bounds, of: statusButton, preferredEdge: .minY)
        beginMenuDismissObservation()
    }

    private func adjustVolume(for event: NSEvent?) {
        guard let event, event.scrollingDeltaY != 0 else { return }
        audioDeviceService.adjustOutputVolume(by: event.scrollingDeltaY > 0 ? 0.05 : -0.05)
        guard !menuPopover.isShown else { return }
        showVolumePopover()
    }

    private func showVolumePopover() {
        volumeFeedbackPanel.contentViewController = NSHostingController(
            rootView: VolumeFeedbackView(
                volumeState: audioDeviceService.outputVolumeState,
                errorMessage: audioDeviceService.errorMessage
            )
        )
        let panelSize = NSSize(width: 152, height: 44)
        volumeFeedbackPanel.setContentSize(panelSize)
        positionVolumeFeedbackPanel(with: panelSize)
        volumeFeedbackPanel.orderFrontRegardless()
        volumePopoverDismissTimer?.invalidate()
        volumePopoverDismissTimer = Timer.scheduledTimer(withTimeInterval: 1.2, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.dismissVolumePopover()
            }
        }
    }

    private func dismissVolumePopover() {
        volumePopoverDismissTimer?.invalidate()
        volumePopoverDismissTimer = nil
        if volumeFeedbackPanel.isVisible {
            volumeFeedbackPanel.orderOut(nil)
        }
    }

    private func positionVolumeFeedbackPanel(with panelSize: NSSize) {
        let statusButtonFrame = statusButton.window?.convertToScreen(
            statusButton.convert(statusButton.bounds, to: nil)
        )
        let screen = statusButtonFrame.flatMap { buttonFrame in
            NSScreen.screens.first { $0.frame.intersects(buttonFrame) }
        } ?? NSScreen.main
        guard let screen else { return }

        let visibleFrame = screen.visibleFrame
        let buttonMidX = statusButtonFrame?.midX ?? visibleFrame.midX
        let originX = min(
            max(buttonMidX - panelSize.width / 2, visibleFrame.minX + 8),
            visibleFrame.maxX - panelSize.width - 8
        )
        let originY = (statusButtonFrame?.minY ?? visibleFrame.maxY) - panelSize.height - 6
        volumeFeedbackPanel.setFrameOrigin(NSPoint(x: originX, y: originY))
    }

    private func beginMenuDismissObservation() {
        endMenuDismissObservation()
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.closeMenuIfClickIsOutside()
            }
        }
        resignActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: NSApplication.shared,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.menuPopover.performClose(nil)
            }
        }
    }

    private func closeMenuIfClickIsOutside() {
        guard menuPopover.isShown else { return }
        let location = NSEvent.mouseLocation
        let statusButtonFrame = statusButton.window?.convertToScreen(
            statusButton.convert(statusButton.bounds, to: nil)
        ) ?? .zero
        let popoverFrame = menuPopover.contentViewController?.view.window?.frame ?? .zero
        guard !statusButtonFrame.contains(location), !popoverFrame.contains(location) else {
            return
        }
        menuPopover.performClose(nil)
    }

    private func endMenuDismissObservation() {
        if let outsideClickMonitor {
            NSEvent.removeMonitor(outsideClickMonitor)
            self.outsideClickMonitor = nil
        }
        if let resignActiveObserver {
            NotificationCenter.default.removeObserver(resignActiveObserver)
            self.resignActiveObserver = nil
        }
    }

    func popoverDidClose(_ notification: Notification) {
        endMenuDismissObservation()
    }
}

private final class StatusItemInteractionButton: NSButton {
    var onClick: (() -> Void)?
    var onScroll: ((NSEvent) -> Void)?

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }

    override func scrollWheel(with event: NSEvent) {
        onScroll?(event)
    }
}

private struct VolumeFeedbackView: View {
    let volumeState: OutputVolumeState
    let errorMessage: String?

    var body: some View {
        Group {
            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let volume = volumeState.volume {
                HStack(spacing: 7) {
                    Image(systemName: volumeState.isMuted == true ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.body)
                    Text(volumeState.isMuted == true ? "静音" : "\(Int((volume * 100).rounded()))%")
                        .font(.body.monospacedDigit().weight(.semibold))
                    Capsule()
                        .fill(.primary.opacity(0.16))
                        .frame(width: 54, height: 5)
                        .overlay(alignment: .leading) {
                            Capsule()
                                .fill(.primary.opacity(0.8))
                                .frame(width: max(5, 54 * CGFloat(volume)), height: 5)
                        }
                }
            } else {
                Label("当前输出设备不支持音量调节", systemImage: "speaker.slash")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 11)
        .frame(width: 152, height: 44)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 7, y: 3)
    }
}
