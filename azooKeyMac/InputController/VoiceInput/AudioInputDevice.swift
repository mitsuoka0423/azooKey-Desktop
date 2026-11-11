import AudioToolbox
import AVFoundation
import CoreAudio

/// 録音に使う入力機器（マイク）を、録音を始めるたびに今の既定の機器に合わせる。
///
/// IME はずっと動き続けるプロセスなので、使っていたイヤホンや外付けマイクを外したあとも、
/// AVAudioEngine が古い機器の番号を既定のまま使い、録音を始められないことがあった
/// （ログに `no device with given ID` と `input hw format invalid` が出る）。
enum AudioInputDevice {
    /// 機器の変化の知らせを、CoreAudio 自身のスレッドで受け取るようにする。
    /// 既定ではメインのランループで受け取るが、IME のメインのランループでは届かないことがあり、
    /// 既定の機器が古いまま残る
    static func receiveChangesOnOwnThread() {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyRunLoop,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var runLoop: CFRunLoop?
        AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            UInt32(MemoryLayout<CFRunLoop?>.size),
            &runLoop
        )
    }

    /// 今の既定の入力機器を、`engine` の録音に使うと明示する。使える機器がなければ失敗を投げる
    static func useCurrentDefault(for engine: AVAudioEngine) throws {
        guard let deviceID = Self.defaultInputDevice(), Self.isAlive(deviceID), Self.hasInput(deviceID) else {
            throw VoiceRecognitionFailure(failure: .microphoneUnavailable)
        }
        guard let unit = engine.inputNode.audioUnit else {
            throw VoiceRecognitionFailure(failure: .microphoneUnavailable)
        }
        var device = deviceID
        let status = AudioUnitSetProperty(
            unit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &device,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
        guard status == noErr else {
            throw VoiceRecognitionFailure(failure: .microphoneUnavailable)
        }
    }

    private static func defaultInputDevice() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID)
        guard status == noErr, deviceID != kAudioObjectUnknown else {
            return nil
        }
        return deviceID
    }

    private static func isAlive(_ deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsAlive,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var alive: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &alive)
        return status == noErr && alive != 0
    }

    /// 入力のチャンネルを持つ機器か
    private static func hasInput(_ deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size) == noErr, size > 0 else {
            return false
        }
        let bufferList = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { bufferList.deallocate() }
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, bufferList) == noErr else {
            return false
        }
        let buffers = UnsafeMutableAudioBufferListPointer(bufferList.assumingMemoryBound(to: AudioBufferList.self))
        return buffers.contains { $0.mNumberChannels > 0 }
    }
}
