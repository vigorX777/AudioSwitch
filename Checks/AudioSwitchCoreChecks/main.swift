import AudioSwitchCore
import CoreAudio
import Foundation

@main
@MainActor
struct AudioSwitchCoreChecks {
    static func main() {
        let runner = CheckRunner()

        runner.run("设备类型映射") {
            runner.expect(AudioTransportType(coreAudioValue: kAudioDeviceTransportTypeBuiltIn) == .builtIn)
            runner.expect(AudioTransportType(coreAudioValue: kAudioDeviceTransportTypeBluetooth) == .bluetooth)
            runner.expect(AudioTransportType(coreAudioValue: kAudioDeviceTransportTypeUSB) == .usb)
            runner.expect(AudioTransportType(coreAudioValue: kAudioDeviceTransportTypeHDMI) == .display)
            runner.expect(AudioTransportType(coreAudioValue: kAudioDeviceTransportTypeAirPlay) == .airPlay)
            runner.expect(AudioTransportType(coreAudioValue: kAudioDeviceTransportTypeVirtual) == .virtual)
            runner.expect(AudioTransportType(coreAudioValue: 0) == .other)
        }

        runner.run("设备能力判断") {
            let device = makeDevice(canBeDefaultSystemOutput: false)
            runner.expect(device.canSwitchInput)
            runner.expect(!device.canSwitchOutputWithSystemSounds)
        }

        runner.run("当前设备排序优先") {
            let builtInB = makeDevice(id: 2, uid: "built-in-b", name: "B", transport: .builtIn)
            let builtInA = makeDevice(id: 1, uid: "built-in-a", name: "A", transport: .builtIn)
            let bluetooth = makeDevice(id: 3, uid: "bluetooth", name: "耳机", transport: .bluetooth)
            let sorted = AudioDeviceCatalog.sorted(
                [bluetooth, builtInB, builtInA],
                currentDeviceID: bluetooth.audioObjectID
            )
            runner.expect(sorted.map(\.uid) == ["bluetooth", "built-in-a", "built-in-b"])
        }

        runner.run("输出同步切换") {
            let hardware = MockAudioHardware(outputID: 1, systemOutputID: 1)
            try AudioDeviceSwitchCoordinator.switchOutput(
                to: makeDevice(id: 2, uid: "target"),
                using: hardware
            )
            runner.expect(hardware.outputID == 2)
            runner.expect(hardware.systemOutputID == 2)
            runner.expect(hardware.writes == [.output(2), .systemOutput(2)])
        }

        runner.run("系统提示音写入失败后回滚") {
            let hardware = MockAudioHardware(outputID: 1, systemOutputID: 1)
            hardware.failNextSystemOutputWrite = true
            do {
                try AudioDeviceSwitchCoordinator.switchOutput(
                    to: makeDevice(id: 2, uid: "target"),
                    using: hardware
                )
                runner.fail("预期切换失败")
            } catch {
                runner.expect(hardware.outputID == 1)
                runner.expect(hardware.systemOutputID == 1)
                runner.expect(
                    hardware.writes == [.output(2), .systemOutput(2), .output(1), .systemOutput(1)]
                )
            }
        }

        runner.run("输入切换不修改输出") {
            let hardware = MockAudioHardware(inputID: 1)
            try AudioDeviceSwitchCoordinator.switchInput(
                to: makeDevice(id: 2, uid: "target"),
                using: hardware
            )
            runner.expect(hardware.inputID == 2)
            runner.expect(hardware.writes == [.input(2)])
        }

        runner.run("服务状态映射") {
            let input = makeDevice(
                id: 1,
                uid: "input",
                hasOutput: false,
                canBeDefaultOutput: false,
                canBeDefaultSystemOutput: false
            )
            let output = makeDevice(
                id: 2,
                uid: "output",
                hasInput: false,
                canBeDefaultInput: false
            )
            let hardware = MockAudioHardware(
                devices: [output, input],
                inputID: 1,
                outputID: 2,
                systemOutputID: 2
            )
            let service = AudioDeviceService(hardware: hardware, monitorChanges: false)
            runner.expect(service.inputDevices.map(\.uid) == ["input"])
            runner.expect(service.outputDevices.map(\.uid) == ["output"])
            runner.expect(service.defaultInputDeviceID == 1)
            runner.expect(service.defaultOutputDeviceID == 2)
            runner.expect(service.defaultSystemOutputDeviceID == 2)
        }

        runner.run("Core Audio 设备枚举与监听") {
            let hardware = CoreAudioHardwareAccess()
            let devices = try hardware.allDevices()
            runner.expect(!devices.isEmpty)
            let deviceIDs = Set(devices.map(\.audioObjectID))
            let defaultInput = try hardware.defaultInputDeviceID()
            let defaultOutput = try hardware.defaultOutputDeviceID()
            let defaultSystemOutput = try hardware.defaultSystemOutputDeviceID()
            runner.expect(deviceIDs.contains(defaultInput))
            runner.expect(deviceIDs.contains(defaultOutput))
            runner.expect(deviceIDs.contains(defaultSystemOutput))
            try hardware.startMonitoring {}
            hardware.stopMonitoring()
        }

        runner.run("Core Audio 当前设备原值重写") {
            let hardware = CoreAudioHardwareAccess()
            let devices = try hardware.allDevices()
            let inputID = try hardware.defaultInputDeviceID()
            let outputID = try hardware.defaultOutputDeviceID()
            let systemOutputID = try hardware.defaultSystemOutputDeviceID()

            guard let input = devices.first(where: { $0.audioObjectID == inputID }),
                  let output = devices.first(where: { $0.audioObjectID == outputID })
            else {
                throw CheckFailure.currentDeviceMissing
            }

            try AudioDeviceSwitchCoordinator.switchInput(to: input, using: hardware)
            if outputID == systemOutputID {
                try AudioDeviceSwitchCoordinator.switchOutput(to: output, using: hardware)
            }
        }

        runner.finish()
    }
}

private final class CheckRunner {
    private(set) var failures: [String] = []

    func run(_ name: String, operation: () throws -> Void) {
        let countBefore = failures.count
        do {
            try operation()
        } catch {
            failures.append("\(name)：\(error.localizedDescription)")
        }
        if failures.count == countBefore {
            print("PASS  \(name)")
        } else {
            print("FAIL  \(name)")
        }
    }

    func expect(_ condition: @autoclosure () -> Bool, _ message: String = "断言失败") {
        if !condition() {
            failures.append(message)
        }
    }

    func fail(_ message: String) {
        failures.append(message)
    }

    func finish() -> Never {
        if failures.isEmpty {
            print("\n全部检查通过。")
            Foundation.exit(EXIT_SUCCESS)
        }

        print("\n检查失败：")
        failures.forEach { print("- \($0)") }
        Foundation.exit(EXIT_FAILURE)
    }
}

private func makeDevice(
    id: AudioObjectID = 1,
    uid: String = "device",
    name: String = "Device",
    transport: AudioTransportType = .builtIn,
    hasInput: Bool = true,
    hasOutput: Bool = true,
    canBeDefaultInput: Bool = true,
    canBeDefaultOutput: Bool = true,
    canBeDefaultSystemOutput: Bool = true
) -> AudioDeviceDescriptor {
    AudioDeviceDescriptor(
        audioObjectID: id,
        uid: uid,
        name: name,
        transportType: transport,
        hasInput: hasInput,
        hasOutput: hasOutput,
        canBeDefaultInput: canBeDefaultInput,
        canBeDefaultOutput: canBeDefaultOutput,
        canBeDefaultSystemOutput: canBeDefaultSystemOutput
    )
}

private enum MockFailure: LocalizedError {
    case requested

    var errorDescription: String? { "模拟写入失败" }
}

private enum CheckFailure: LocalizedError {
    case currentDeviceMissing

    var errorDescription: String? { "当前默认设备不在枚举结果中" }
}

private enum HardwareWrite: Equatable {
    case input(AudioObjectID)
    case output(AudioObjectID)
    case systemOutput(AudioObjectID)
}

private final class MockAudioHardware: AudioHardwareAccess {
    var devices: [AudioDeviceDescriptor]
    var inputID: AudioObjectID
    var outputID: AudioObjectID
    var systemOutputID: AudioObjectID
    var writes: [HardwareWrite] = []
    var failNextSystemOutputWrite = false

    init(
        devices: [AudioDeviceDescriptor] = [],
        inputID: AudioObjectID = 1,
        outputID: AudioObjectID = 1,
        systemOutputID: AudioObjectID = 1
    ) {
        self.devices = devices
        self.inputID = inputID
        self.outputID = outputID
        self.systemOutputID = systemOutputID
    }

    func allDevices() throws -> [AudioDeviceDescriptor] { devices }
    func defaultInputDeviceID() throws -> AudioObjectID { inputID }
    func defaultOutputDeviceID() throws -> AudioObjectID { outputID }
    func defaultSystemOutputDeviceID() throws -> AudioObjectID { systemOutputID }

    func setDefaultInputDeviceID(_ deviceID: AudioObjectID) throws {
        writes.append(.input(deviceID))
        inputID = deviceID
    }

    func setDefaultOutputDeviceID(_ deviceID: AudioObjectID) throws {
        writes.append(.output(deviceID))
        outputID = deviceID
    }

    func setDefaultSystemOutputDeviceID(_ deviceID: AudioObjectID) throws {
        writes.append(.systemOutput(deviceID))
        if failNextSystemOutputWrite {
            failNextSystemOutputWrite = false
            throw MockFailure.requested
        }
        systemOutputID = deviceID
    }

    func startMonitoring(_ onChange: @escaping @Sendable () -> Void) throws {}
    func stopMonitoring() {}
}
