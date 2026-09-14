# Voice Group

<!-- from github.com/Roblox/libmp/docs/ALL-SCOPES.md -->
The Voice group contains scopes for the voice chat system: audio capture, processing, mixing, voice transport, device management, stats monitoring, and VoiceChat lifecycle management. Voice work runs on dedicated audio threads and the main thread.

---

## Core Operations

### GenerateAndRunOperations

**Top-level voice operation loop — generates and executes pending voice operations (join, leave, mute, subscribe).**

The main voice chat state machine step. Processes queued operations that transition the voice system between states.

**Performance notes:** Usually fast. Can spike when many players join/leave voice simultaneously.


---

### UpdateRecordedBuffer / RobloxAudioDevice::UpdateRecordedBuffer / RecordingDeviceManager::UpdateRecordedBuffer

**Captures audio from the microphone and buffers it for processing.**

Reads raw audio samples from the recording device into the voice processing pipeline.

**Performance notes:** Runs at the audio callback rate (~10 ms frames). Must complete within the callback period to avoid dropouts.


---

### ClientOperation::run

**Executes one voice client operation (join room, publish stream, subscribe to peer, etc.).**


---

## Audio Processing

### CustomAudioProcessing::ProcessStream

**Processes a voice audio stream — applies noise suppression, echo cancellation, and gain control.**

The audio DSP pipeline for voice: runs voice audio processing modules (AEC, NS, AGC) on captured or received audio.

**Performance notes:** CPU-intensive signal processing. Runs in real-time on audio threads. Should stay under a few milliseconds.


---

### CustomAudioProcessing::writeToAudioSink

**Writes processed captured microphone audio into the capture sink that feeds the voice send/encode pipeline.**


---

### CustomAudioProcessing::CustomAudioProcessing

**Initializes the custom audio processing pipeline.**

One-time setup cost.


---

## Audio Mixing

### CustomAudioMixer::Mix

**Mixes multiple voice streams into the final audio output.**

Routes each active remote participant's decoded audio frame to that participant's own audio sink; spatialization (distance attenuation / panning) is applied downstream by the audio graph. A second step feeds system audio into the frame for echo-cancellation purposes.

**Performance notes:** O(active voice streams). Fast per-stream.


---

### CustomAudioMixer::updateSources

**Updates voice source positions and states for spatial audio mixing.**


---

### AudioDeviceSharedState::OnPostMix / RobloxAudioDevice::OnPostMix / RobloxAudioDevice::OnMidMix

**Audio device callbacks — fire during the audio render pipeline for voice integration.**


---

### NeedMorePlayData / RecordedDataIsAvailable

**Audio device callbacks — signals that the playback device needs data or recording data is ready.**


---

## Recording

### RecordingDeviceManager::ProcessAndDeliverAudioBlock

**Processes a recorded audio block and delivers it to the voice pipeline.**


---

### RecordingDeviceManager::ReadRecordingBuffer

**Reads the recording ring buffer — extracts captured audio samples.**


---

## Transport

### StreamTransactionMessageTransport::receive / StreamTransactionMessageTransport::sendMessage

**Receives/sends voice transport messages over the voice data channel.**


---

## Statistics & Telemetry

### ClientVoiceRtcStatsEmitVoiceRtcStatsState::nextImpl

**Collects and emits voice statistics for voice quality monitoring.**


---

### ClientVoiceRtcStatsMonitorState::emitLegacyCombinedStats / emitSplitStats

**Emits voice chat quality statistics (packet loss, jitter, RTT) for telemetry.**


---

### ClientVoiceRtcStatsSubmitGetStatsAsyncState::nextImpl

**Submits an async request for voice stats from the peer connection.**


---

## VoiceChat Lifecycle

### VoiceChatInternal::VoiceChatInternal()

**VoiceChat system construction and initialization.**


---

### VoiceChatInternal::connectToSoundService / connectToVoiceChatService / disconnectFromVoiceChatService

**Connects/disconnects from the sound system and voice chat backend services.**


---

### VoiceChatInternal::connectToVoiceChatService->onJoined / onLeft / onPublishBegan / onPublishEnded / onSubscribeBegan / onSubscribeEnded

**Voice chat event handlers — triggered when participants join, leave, start/stop publishing, or subscribe/unsubscribe.**


---

### VoiceChatInternal::SoundVoice / SoundVoice->onApiEnrollmentChanged

**Voice service lifecycle handling — wires up (or tears down) VoiceChatService when it is added to or removed from the game; the paired handler tracks voice-API enrollment changes.**


---

## Device Management

### VoiceChatInternal::::DeviceRegistry::add / change / remove / getDevicesFor

**Manages audio input/output device registry — adds, changes, removes, and queries devices.**


---

### VoiceChatInternal::::DeviceRegistry::add->propertyChanged

**Handles an AudioDeviceInput Player-property change — re-maps which player owns a voice input device.**


---

### VoiceChatInternal::createAudioSink / createSystemAudioSinkOutput / createUnboundAudioSink / deleteSystemAudioSinkOutput

**Creates and destroys voice audio sinks. `createAudioSink` / `createUnboundAudioSink` produce per-participant output nodes; `createSystemAudioSinkOutput` / `deleteSystemAudioSinkOutput` attach/detach the system-audio ring buffer used for acoustic echo cancellation (AEC).**


---

### VoiceChatInternal::getAudibilityOf / getAudioDevice / getAudioProcessingSettings / getAndClearCallFailureMessage()

**Queries voice system state — audibility checks, device info, processing settings, error messages.**


---

## Voice System Details

### VoiceChatInternal Queries

- `getChannelId()` / `getGroupId()` / `getSessionId()` / `getSessionState()` — queries voice session state
- `getDm` / `getExposureStats()` / `getInputAudioSink` / `getMicDevices` — queries voice system state
- `getOutputCaptureAudioSink` / `getParticipants()` / `getVoiceExperienceId` — participant and experience info
- `getVoiceExperienceIdFromLua()` / `getVoiceChatApiVersion()` / `getVoiceChatAvailable()` — API queries from Lua
- `isContextVoiceEnabledLua()` / `isPublishPaused()` / `isSubscribePaused()` — state queries
- `isVoiceEnabledForUserIdAsync()` / `isVoiceEnabledForUserIdAsync()->successFunction` — async permission check
- `joinByGroupIdToken()` — joins voice by group token
- `publishPause()` / `publishPauseFromLua()` / `subscribePause()` / `subscribePauseAll()` — pause operations
- `VoiceChatInternal::subscribeBlock` / `VoiceChatInternal::subscribeRetry` / `VoiceChatInternal::subscribeUnblock` — subscription management
- `VoiceChatInternal::resetExposureStats()` / `VoiceChatInternal::synchronizeCallState` / `VoiceChatInternal::toPlayerActivityValueTable()` — utility operations
- `VoiceChatInternal::setMicDevice` / `VoiceChatInternal::setupDeviceRegistry` / `VoiceChatInternal::setupDeviceRegistry->callback` — device configuration
- `~VoiceChatInternal()` — destructor cleanup


---

### ClientVoiceRtcStatsMonitorState::emitSplitStats

**Emits split (per-stream) voice quality statistics.**


<br>
<br>

---
