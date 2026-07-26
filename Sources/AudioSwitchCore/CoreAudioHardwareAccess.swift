import CoreAudio
import Foundation

package final class CoreAudioHardwareAccess: AudioHardwareAccess, @unchecked Sendable {
    private let systemObjectID = AudioObjectID(kAudioObjectSystemObject)
    private let listenerQueue = DispatchQueue(label: "com.vigor.AudioSwitch.core-audio-listeners")
    private var systemListeners: [PropertyListener] = []
    private var outputListeners: [PropertyListener] = []
    private var monitoringCallback: (@Sendable () -> Void)?

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

    package func outputVolumeState() throws -> OutputVolumeState {
        let deviceID = try defaultOutputDeviceID()
        let mutePropertyAddress = muteAddress()
        return OutputVolumeState(
            volume: readOutputVolume(deviceID: deviceID),
            isMuted: readOutputMute(deviceID: deviceID),
            isVolumeAdjustable: !writableVolumeAddresses(deviceID: deviceID).isEmpty,
            isMuteAdjustable: hasProperty(deviceID: deviceID, address: mutePropertyAddress)
                && isSettable(deviceID: deviceID, address: mutePropertyAddress)
        )
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

    package func setOutputVolume(_ volume: Float) throws {
        let deviceID = try defaultOutputDeviceID()
        let addresses = writableVolumeAddresses(deviceID: deviceID)
        guard !addresses.isEmpty else {
            throw AudioDeviceError.unsupportedOutputVolume
        }

        let oldValues = try addresses.map { address in
            try readScalar(
                objectID: deviceID,
                address: address,
                operation: "读取当前音量"
            ) as Float32
        }
        let newValue = Float32(min(max(volume, 0), 1))

        do {
            for address in addresses {
                try writeScalar(
                    newValue,
                    objectID: deviceID,
                    address: address,
                    operation: "设置输出音量"
                )
            }
        } catch {
            for (address, oldValue) in zip(addresses, oldValues) {
                try? writeScalar(
                    oldValue,
                    objectID: deviceID,
                    address: address,
                    operation: "恢复输出音量"
                )
            }
            throw error
        }
    }

    package func setOutputMuted(_ isMuted: Bool) throws {
        let deviceID = try defaultOutputDeviceID()
        let address = muteAddress()
        guard hasProperty(deviceID: deviceID, address: address), isSettable(deviceID: deviceID, address: address) else {
            throw AudioDeviceError.unsupportedOutputMute
        }
        try writeScalar(
            UInt32(isMuted ? 1 : 0),
            objectID: deviceID,
            address: address,
            operation: "设置输出静音"
        )
    }

    package func startMonitoring(_ onChange: @escaping @Sendable () -> Void) throws {
        stopMonitoring()
        monitoringCallback = onChange

        let selectors: [AudioObjectPropertySelector] = [
            kAudioHardwarePropertyDevices,
            kAudioHardwarePropertyDefaultInputDevice,
            kAudioHardwarePropertyDefaultOutputDevice,
            kAudioHardwarePropertyDefaultSystemOutputDevice,
        ]

        do {
            for selector in selectors {
                let address = propertyAddress(selector)
                let listener: AudioObjectPropertyListenerBlock = { _, _ in
                    if selector == kAudioHardwarePropertyDefaultOutputDevice {
                        self.refreshOutputListeners()
                    }
                    onChange()
                }
                try addListener(
                    objectID: systemObjectID,
                    address: address,
                    listener: listener,
                    to: &systemListeners
                )
            }
            refreshOutputListeners()
        } catch {
            stopMonitoring()
            throw error
        }
    }

    package func stopMonitoring() {
        removeListeners(&systemListeners)
        removeListeners(&outputListeners)
        monitoringCallback = nil
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

    private func readOutputVolume(deviceID: AudioObjectID) -> Float? {
        let values = volumeAddresses(deviceID: deviceID).compactMap { address in
            try? readScalar(
                objectID: deviceID,
                address: address,
                operation: "读取输出音量"
            ) as Float32
        }
        guard !values.isEmpty else {
            return nil
        }
        return Float(values.reduce(0, +) / Float32(values.count))
    }

    private func readOutputMute(deviceID: AudioObjectID) -> Bool? {
        let address = muteAddress()
        guard hasProperty(deviceID: deviceID, address: address),
              let value: UInt32 = try? readScalar(
                  objectID: deviceID,
                  address: address,
                  operation: "读取输出静音"
              )
        else {
            return nil
        }
        return value != 0
    }

    private func volumeAddresses(deviceID: AudioObjectID) -> [AudioObjectPropertyAddress] {
        let masterAddress = volumeAddress(element: kAudioObjectPropertyElementMain)
        if hasProperty(deviceID: deviceID, address: masterAddress) {
            return [masterAddress]
        }

        return (1 ... outputChannelCount(deviceID: deviceID)).compactMap { channel in
            let address = volumeAddress(element: AudioObjectPropertyElement(channel))
            return hasProperty(deviceID: deviceID, address: address) ? address : nil
        }
    }

    private func writableVolumeAddresses(deviceID: AudioObjectID) -> [AudioObjectPropertyAddress] {
        let masterAddress = volumeAddress(element: kAudioObjectPropertyElementMain)
        if hasProperty(deviceID: deviceID, address: masterAddress), isSettable(deviceID: deviceID, address: masterAddress) {
            return [masterAddress]
        }

        return (1 ... outputChannelCount(deviceID: deviceID)).compactMap { channel in
            let address = volumeAddress(element: AudioObjectPropertyElement(channel))
            return hasProperty(deviceID: deviceID, address: address) && isSettable(deviceID: deviceID, address: address)
                ? address
                : nil
        }
    }

    private func outputChannelCount(deviceID: AudioObjectID) -> Int {
        let address = propertyAddress(kAudioDevicePropertyStreamConfiguration, scope: kAudioDevicePropertyScopeOutput)
        guard let channelCount = try? readOutputChannelCount(
            objectID: deviceID,
            address: address,
            operation: "读取输出声道"
        )
        else {
            return 0
        }
        return channelCount
    }

    private func volumeAddress(element: AudioObjectPropertyElement) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: element
        )
    }

    private func muteAddress() -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private func hasProperty(deviceID: AudioObjectID, address originalAddress: AudioObjectPropertyAddress) -> Bool {
        var address = originalAddress
        return AudioObjectHasProperty(deviceID, &address)
    }

    private func isSettable(deviceID: AudioObjectID, address originalAddress: AudioObjectPropertyAddress) -> Bool {
        var address = originalAddress
        var settable = DarwinBoolean(false)
        return AudioObjectIsPropertySettable(deviceID, &address, &settable) == noErr && settable.boolValue
    }

    private func refreshOutputListeners() {
        removeListeners(&outputListeners)
        guard let callback = monitoringCallback,
              let deviceID = try? defaultOutputDeviceID()
        else {
            return
        }

        let addresses = volumeAddresses(deviceID: deviceID) + [muteAddress()]
        for address in addresses where hasProperty(deviceID: deviceID, address: address) {
            let listener: AudioObjectPropertyListenerBlock = { _, _ in callback() }
            try? addListener(
                objectID: deviceID,
                address: address,
                listener: listener,
                to: &outputListeners
            )
        }
    }

    private func addListener(
        objectID: AudioObjectID,
        address originalAddress: AudioObjectPropertyAddress,
        listener: @escaping AudioObjectPropertyListenerBlock,
        to listeners: inout [PropertyListener]
    ) throws {
        var address = originalAddress
        try check(
            AudioObjectAddPropertyListenerBlock(objectID, &address, listenerQueue, listener),
            operation: "监听音频设备变化"
        )
        listeners.append(PropertyListener(objectID: objectID, address: address, listener: listener))
    }

    private func removeListeners(_ listeners: inout [PropertyListener]) {
        for storedListener in listeners {
            var address = storedListener.address
            AudioObjectRemovePropertyListenerBlock(
                storedListener.objectID,
                &address,
                listenerQueue,
                storedListener.listener
            )
        }
        listeners.removeAll()
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

    private func writeScalar<T>(
        _ value: T,
        objectID: AudioObjectID,
        address originalAddress: AudioObjectPropertyAddress,
        operation: String
    ) throws {
        var address = originalAddress
        var value = value
        let status = withUnsafePointer(to: &value) { pointer in
            AudioObjectSetPropertyData(
                objectID,
                &address,
                0,
                nil,
                UInt32(MemoryLayout<T>.size),
                pointer
            )
        }
        try check(status, operation: operation)
    }

    private func readOutputChannelCount(
        objectID: AudioObjectID,
        address originalAddress: AudioObjectPropertyAddress,
        operation: String
    ) throws -> Int {
        var address = originalAddress
        var size: UInt32 = 0
        try check(
            AudioObjectGetPropertyDataSize(objectID, &address, 0, nil, &size),
            operation: operation
        )
        let rawPointer = UnsafeMutableRawPointer.allocate(
            byteCount: Int(size),
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { rawPointer.deallocate() }
        var mutableAddress = originalAddress
        try check(
            AudioObjectGetPropertyData(objectID, &mutableAddress, 0, nil, &size, rawPointer),
            operation: operation
        )
        let list = UnsafeMutableAudioBufferListPointer(rawPointer.assumingMemoryBound(to: AudioBufferList.self))
        return list.reduce(0) { $0 + Int($1.mNumberChannels) }
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

private struct PropertyListener {
    let objectID: AudioObjectID
    let address: AudioObjectPropertyAddress
    let listener: AudioObjectPropertyListenerBlock
}
