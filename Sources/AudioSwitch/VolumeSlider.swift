import AppKit
import SwiftUI

struct VolumeSlider: NSViewRepresentable {
    @Binding var value: Double
    let isEnabled: Bool
    let onScroll: (NSEvent) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> ScrollWheelSlider {
        let slider = ScrollWheelSlider(value: value, minValue: 0, maxValue: 1, target: context.coordinator, action: #selector(Coordinator.valueChanged))
        slider.isContinuous = true
        slider.onScroll = onScroll
        slider.setAccessibilityLabel("输出音量")
        return slider
    }

    func updateNSView(_ slider: ScrollWheelSlider, context: Context) {
        if slider.doubleValue != value {
            slider.doubleValue = value
        }
        slider.isEnabled = isEnabled
        slider.onScroll = onScroll
    }

    @MainActor
    final class Coordinator: NSObject {
        private let parent: VolumeSlider

        init(_ parent: VolumeSlider) {
            self.parent = parent
        }

        @objc func valueChanged(_ sender: NSSlider) {
            parent.value = sender.doubleValue
        }
    }
}

final class ScrollWheelSlider: NSSlider {
    var onScroll: ((NSEvent) -> Void)?

    override func scrollWheel(with event: NSEvent) {
        onScroll?(event)
    }
}
