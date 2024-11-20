import Foundation
import AVFoundation

public final class AudioEngineFromVideo {
    private var player: AVPlayer
    private var playerItem: AVPlayerItem
    private var audioFormat: AVAudioFormat? = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)

    @SCNObservable public internal(set) var error: Swift.Error?

    public weak var recorder: BaseRecorder? {
        didSet {
            oldValue?.audioInput.audioFormat = nil
            guard let recorder = recorder else {
                removeAudioTap()
                return
            }
            
            recorder.audioInput.audioFormat = audioFormat
            
            guard oldValue == nil else { return }
            removeAudioTap()
            setupAudioTap()
        }
    }
    
    public init(player: AVPlayer) {
        self.player = player
        guard let currentItem = player.currentItem else {
            fatalError("Player item is not initialized.")
        }
        self.playerItem = currentItem
    }
    
    private func setupAudioTap() {
        // Create an AVMutableAudioMix
        let audioMix = AVMutableAudioMix()

        // Get the first audio track
        guard let audioTrack = playerItem.asset.tracks(withMediaType: .audio).first else {
            print("No audio track found")
            return
        }

        // Create AVMutableAudioMixInputParameters for the track
        let inputParams = AVMutableAudioMixInputParameters(track: audioTrack)

        // Install tap
        inputParams.setVolume(1.0, at: .zero)
        inputParams.audioTapProcessor = createAudioTapProcessor()

        audioMix.inputParameters = [inputParams]

        // Set the audio mix to the player item
        playerItem.audioMix = audioMix
    }
    
    private func removeAudioTap() {
        playerItem.audioMix = nil
    }
    
    private func createAudioTapProcessor() -> MTAudioProcessingTap {
        var callbacks = MTAudioProcessingTapCallbacks(
            version: kMTAudioProcessingTapCallbacksVersion_0,
            clientInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
            init: tapInitCallback,
            finalize: tapFinalizeCallback,
            prepare: tapPrepareCallback,
            unprepare: tapUnprepareCallback,
            process: tapProcessCallback
        )
        
        var tap: Unmanaged<MTAudioProcessingTap>?
        let status = MTAudioProcessingTapCreate(kCFAllocatorDefault, &callbacks, kMTAudioProcessingTapCreationFlag_PostEffects, &tap)
        
        if status != noErr {
            print("Error creating MTAudioProcessingTap: \(status)")
        }
        
        return tap!.takeRetainedValue()
    }

    // Define the TapContext class
    class TapContext {
        var processingFormat: AVAudioFormat?
        weak var selfInstance: AudioEngineFromVideo?
    }

    // MTAudioProcessingTap callbacks
    private let tapInitCallback: MTAudioProcessingTapInitCallback = { (tap, clientInfo, tapStorageOut) in
        // Initialization code
        let context = TapContext()
        context.selfInstance = Unmanaged<AudioEngineFromVideo>.fromOpaque(clientInfo!).takeUnretainedValue()
        tapStorageOut.pointee = Unmanaged.passRetained(context).toOpaque()
    }
    
    private let tapFinalizeCallback: MTAudioProcessingTapFinalizeCallback = { (tap) in
        // Finalization code
        let storage = MTAudioProcessingTapGetStorage(tap)
        Unmanaged<TapContext>.fromOpaque(storage).release()
    }
    
    private let tapPrepareCallback: MTAudioProcessingTapPrepareCallback = { (tap, maxFrames, processingFormat) in
        // Prepare code
        let storage = MTAudioProcessingTapGetStorage(tap)
        let context = Unmanaged<TapContext>.fromOpaque(storage).takeUnretainedValue()
        // Save the processing format
        var asbd = processingFormat.pointee
        context.processingFormat = AVAudioFormat(streamDescription: &asbd)
    }
    
    private let tapUnprepareCallback: MTAudioProcessingTapUnprepareCallback = { (tap) in
        // Unprepare code if needed
    }
    
  private let tapProcessCallback: MTAudioProcessingTapProcessCallback = { (tap, numberFrames, flags, bufferListInOut, numberFramesOut, flagsOut) in
      let storage = MTAudioProcessingTapGetStorage(tap)
      let context = Unmanaged<TapContext>.fromOpaque(storage).takeUnretainedValue()
      guard let selfInstance = context.selfInstance else {
          print("Self instance not available")
          return
      }
      
      var status = noErr
      var tapFlags: MTAudioProcessingTapFlags = 0
      var numFrames = numberFrames
      var timeStamp = CMTimeRange()
      
      // Get source audio and timestamp
      status = MTAudioProcessingTapGetSourceAudio(tap, numberFrames, bufferListInOut, &tapFlags, &timeStamp, &numFrames)
      if status != noErr {
          print("Error getting source audio: \(status)")
          return
      }
      
      // **Set the number of frames and flags for output**
      numberFramesOut.pointee = numFrames
      flagsOut.pointee = tapFlags
      
      // Convert AudioTimeStamp to AVAudioTime
      guard let processingFormat = context.processingFormat else {
          print("Processing format not available")
          return
      }
      
      let sampleRate = processingFormat.sampleRate
      let audioTime = AVAudioTime(hostTime: mach_absolute_time())
      
      // Process audio bufferListInOut
      let bufferListPtr = UnsafeMutableAudioBufferListPointer(bufferListInOut)
      // Now you can access audio samples from bufferListPtr
      
      // Create an AVAudioPCMBuffer and pass it to the recorder
      if let pcmBuffer = AVAudioPCMBuffer(pcmFormat: processingFormat, frameCapacity: AVAudioFrameCount(numFrames)) {
          pcmBuffer.frameLength = AVAudioFrameCount(numFrames)
          for i in 0..<Int(bufferListPtr.count) {
              let mBuffers = bufferListPtr[i]
              memcpy(pcmBuffer.floatChannelData?[i], mBuffers.mData, Int(mBuffers.mDataByteSize))
          }
          
          do {
              let sampleBuffer = try AudioEngine.createAudioSampleBuffer(from: pcmBuffer, time: audioTime)
              selfInstance.recorder?.audioInput.audioEngine(didOutputAudioSampleBuffer: sampleBuffer)
          } catch let error {
              print("ERROR: error creating audio sample buffer: \(error)")
              selfInstance.error = error
          }
      }
  }

  

    func startPlayback() {
        player.play()
    }
    
    func stopAudioTap() {
        removeAudioTap()
        player.pause()
    }
}
