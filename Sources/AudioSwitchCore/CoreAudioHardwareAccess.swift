import CoreAudio
import Foundation

package final class CoreAudioHardwareAccess: AudioHardwareAccess, @unchecked Sendable {
    private let systemObjectID = AudioObjectID(kAudioObjectSystemObject)
    private let listenerQueue = DispatchQueue(label: "com.vigor.AudioSwitch.core-audio-listeners")
    private var listeners: [(AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []

    package init() {}

    deinit {
        stopMonitoring()
    }

    package func allDevices() throws -> [AudioDeviceDescriptor] {
        let address = propertyAddress(kAudioHardwarePropertyDevices)
        let deviceIDs: [AudioObjectID] = try readArray(
            objectID: systemObjectID,
            address: address,
            operation: "读取音频设备列表"
        )

        var descriptors: [AudioDeviceDescriptor] = []
        var lastError: Error?
        for deviceID in deviceIDs {
            do {
                descriptors.append(try makeDescriptor(deviceID: deviceID))
            } catch {
                // A device may disappear while Core Audio is enumerating after a hot unplug.
                lastError = error
            }
        }
        if descriptors.isEmpty, let lastError {
            throw lastError
        }
        return descriptors
    }

    package func defaultInputDeviceID() throws -> AudioObjectID {
        try readDefaultDevice(selector: kAudioHardwarePropertyDefaultInputDevice, operation: "读取默认输入设备")
    }

    package func defaultOutputDeviceID() throws -> AudioObjectID {
        try readDefaultDevice(selector: kAudioHardwarePropertyDefaultOutputDevice, operation: "读取默认输出设备")
    }

    package func defaultSystemOutputDeviceID() throws -> AudioObjectID {
        try readDefaultDevice(selector: kAudioHardwarePropertyDefaultSystemOutputDevice, operation: "读取系统提示音输出设备")
    }

    package func setDefaultInputDeviceID(_ deviceID: AudioObjectID) throws {
        try writeDefaultDevice(
            deviceID,
            selector: kAudioHardwarePropertyDefaultInputDevice,
            operation: "设置默认输入设备"
        )
    }

    package func setDefaultOutputDeviceID(_ deviceID: AudioObjectID) throws {
        try writeDefaultDevice(
            deviceID,
            selector: kAudioHardwarePropertyDefaultOutputDevice,
            operation: "设置默认输出设备"
        )
    }

    package func setDefaultSystemOutputDeviceID(_ deviceID: AudioObjectID) throws {
        try writeDefaultDevice(
            deviceID,
            selector: kAudioHardwarePropertyDefaultSystemOutputDevice,
            operation: "设置系统提示音输出设备"
        )
    }

    package func startMonitoring(_ onChange: @escaping @Sendable () -> Void) throws {
        stopMonitoring()

        let selectors: [AudioObjectPropertySelector] = [
            kAudioHardwarePropertyDevices,
            kAudioHardwarePropertyDefaultInputDevice,
            kAudioHardwarePropertyDefaultOutputDevice,
            kAudioHardwarePropertyDefaultSystemOutputDevice,
        ]

        do {
            for selector in selectors {
                var address = propertyAddress(selector)
                let listener: AudioObjectPropertyListenerBlock = { _, _ in
                    onChange()
                }
                let status = AudioObjectAddPropertyListenerBlock(
                    systemObjectID,
                    &address,
                    listenerQueue,
                    listener
                )
                try check(status, operation: "监听音频设备变化")
                listeners.append((address, listener))
            }
        } catch {
            stopMonitoring()
            throw error
        }
    }

    package func stopMonitoring() {
        for (storedAddress, listener) in listeners {
            var address = storedAddress
            AudioObjectRemovePropertyListenerBlock(
                systemObjectID,
                &address,
                listenerQueue,
                listener
            )
        }
        listeners.removeAll()
    }

    private func makeDescriptor(deviceID: AudioObjectID) throws -> AudioDeviceDescriptor {
        let name = try readString(
            objectID: deviceID,
            address: propertyAddress(kAudioObjectPropertyName),
            operation: "读取设备名称"
        )
        let uid = try readString(
            objectID: deviceID,
            address: propertyAddress(kAudioDevicePropertyDeviceUID),
            operation: "读取设备 UID"
        )
        let transportValue: UInt32 = try readScalar(
            objectID: deviceID,
            address: propertyAddress(kAudioDevicePropertyTransportType),
            operation: "读取设备连接类型"
        )
        let hasInput = try hasStreams(deviceID: deviceID, scope: kAudioDevicePropertyScopeInput)
        let hasOutput = try hasStreams(deviceID: deviceID, scope: kAudioDevicePropertyScopeOutput)

        return AudioDeviceDescriptor(
            audioObjectID: deviceID,
            uid: uid,
            name: name,
            transportType: AudioTransportType(coreAudioValue: transportValue),
            hasInput: hasInput,
            hasOutput: hasOutput,
            canBeDefaultInput: hasInput && readBooleanIfAvailable(
                objectID: deviceID,
                selector: kAudioDevicePropertyDeviceCanBeDefaultDevice,
                scope: kAudioDevicePropertyScopeInput
            ),
            canBeDefaultOutput: hasOutput && readBooleanIfAvailable(
                objectID: deviceID,
                selector: kAudioDevicePropertyDeviceCanBeDefaultDevice,
                scope: kAudioDevicePropertyScopeOutput
            ),
            canBeDefaultSystemOutput: hasOutput && readBooleanIfAvailable(
                objectID: deviceID,
                selector: kAudioDevicePropertyDeviceCanBeDefaultSystemDevice,
                scope: kAudioDevicePropertyScopeOutput
            )
        )
    }

    private func hasStreams(deviceID: AudioObjectID, scope: AudioObjectPropertyScope) throws -> Bool {
        let address = propertyAddress(kAudioDevicePropertyStreams, scope: scope)
        let streamIDs: [AudioStreamID] = try readArray(
            objectID: deviceID,
            address: address,
            operation: "读取设备音频流"
        )
        return !streamIDs.isEmpty
    }

    private func readBooleanIfAvailable(
        objectID: AudioObjectID,
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope
    ) -> Bool {
        var address = propertyAddress(selector, scope: scope)
        guard AudioObjectHasProperty(objectID, &address) else {
            return false
        }
        do {
            let value: UInt32 = try readScalar(
                objectID: objectID,
                address: address,
                operation: "读取设备默认能力"
            )
            return value != 0
        } catch {
            return false
        }
    }

    private func readDefaultDevice(
        selector: AudioObjectPropertySelector,
        operation: String
    ) throws -> AudioObjectID {
        try readScalar(
            objectID: systemObjectID,
            address: propertyAddress(selector),
            operation: operation
        )
    }

    private func writeDefaultDevice(
        _ deviceID: AudioObjectID,
        selector: AudioObjectPropertySelector,
        operation: String
    ) throws {
        var address = propertyAddress(selector)
        var value = deviceID
        let status = withUnsafePointer(to: &value) { pointer in
            AudioObjectSetPropertyData(
                systemObjectID,
                &address,
                0,
                nil,
                UInt32(MemoryLayout<AudioObjectID>.size),
                pointer
            )
        }
        try check(status, operation: operation)
    }

    private func readString(
        objectID: AudioObjectID,
        address originalAddress: AudioObjectPropertyAddress,
        operation: String
    ) throws -> String {
        var address = originalAddress
        var value: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        let status = withUnsafeMutablePointer(to: &value) { pointer in
            AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, pointer)
        }
        try check(status, operation: operation)
        return value as String
    }

    private func readScalar<T>(
        objectID: AudioObjectID,
        address originalAddress: AudioObjectPropertyAddress,
        operation: String
    ) throws -> T {
        var address = originalAddress
        var size = UInt32(MemoryLayout<T>.size)
        let pointer = UnsafeMutableRawPointer.allocate(
            byteCount: MemoryLayout<T>.size,
            alignment: MemoryLayout<T>.alignment
        )
        defer { pointer.deallocate() }
        let status = AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, pointer)
        try check(status, operation: operation)
        return pointer.load(as: T.self)
    }

    private func readArray<T>(
        objectID: AudioObjectID,
        address originalAddress: AudioObjectPropertyAddress,
        operation: String
    ) throws -> [T] {
        var address = originalAddress
        var size: UInt32 = 0
        try check(
            AudioObjectGetPropertyDataSize(objectID, &address, 0, nil, &size),
            operation: operation
        )
        guard size > 0 else {
            return []
        }

        let count = Int(size) / MemoryLayout<T>.stride
        let pointer = UnsafeMutablePointer<T>.allocate(capacity: count)
        defer { pointer.deallocate() }
        try check(
            AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, pointer),
            operation: operation
        )
        return Array(UnsafeBufferPointer(start: pointer, count: count))
    }

    private func propertyAddress(
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private func check(_ status: OSStatus, operation: String) throws {
        guard status == noErr else {
            throw AudioDeviceError.coreAudio(operation: operation, status: status)
        }
    }
}
