# Sound Group

<!-- from github.com/Roblox/libmp/docs/ALL-SCOPES.md -->
The Sound group contains scopes for audio processing: audio engine updates, spatial audio panning and occlusion, instance stepping, reverb, and speech-to-text encoding. While some per-frame tasks run on the main thread - such as passing spatial position info from the datamodel to the audio engine - core processing is handled by a few dedicated threads, including the mixer and asset loading threads.

---

## Audio Engine Core

### updateFmod

**Ticks the audio engine — passes pending datamodel changes into FMOD.**

The main audio engine update that passes information from the datamodel into FMOD, such as 3D positions and play/stop commands. Audio mixing and output submission happen outside this scope.

**Performance notes:** Cost primarily depends on the number of active `Sound` instances or `AudioPlayer`s. Can spike when many sounds start simultaneously.

**What game creators can do:**
- Reduce the number of simultaneously playing sounds
- Use SoundGroups with volume limits
- Set `RollOffMaxDistance` to cull distant sounds
- Avoid starting many sounds on the same frame


---

### updatePanning

**Updates 3D spatial panning for all active sound emitters based on listener position.**

Computes the spatial positioning (left/right panning, distance attenuation, Doppler) for each active 3D sound relative to the listener (camera or AudioListener).

**Performance notes:** O(active 3D sounds). Usually fast. Can be noticeable with hundreds of simultaneous spatial sounds.


---

### stepInstances / stepInstances_Parallel

**Steps all active sound instances — advances their state machines and checks for completion.**

Updates each playing sound's state: checks if it finished, handles looping, and updates properties that changed from Lua.

**Performance notes:** O(active Sound instances).

**What game creators can do:**
- Reduce the amount of sounds in active playback


---

### updateReverb

**Updates reverb parameters based on the listener's environment.**

Computes environmental reverb settings by sampling the acoustic environment around the listener. May involve raycasts for room-size estimation.

**Performance notes:** Usually fast. Can be expensive if acoustic simulation is enabled with high-quality settings.


---

### calculateTrace

**Computes an audio occlusion trace between a sound source and the listener — traces the path through the scene to work out how much the sound is blocked or muffled by geometry.**

Runs for spatially-simulated sounds that use audio occlusion; on the synchronized path it reads the current occlusion state of the world. It fires per source–listener pair, so cost scales with the number of occlusion-simulated sounds.

**Performance notes:** Can widen when many spatial sounds use occlusion simulation at once.

**What game creators can do:**
- Limit how many sounds use audio occlusion / spatial simulation simultaneously.
- Lower occlusion/acoustic simulation quality where full fidelity isn't needed.


---

### FMOD::Output::mix

**Evaluates the audio DSP graph — mixes all audio producers and effects into a final buffer for the soundcard.**

The workhorse of the audio engine. Running on a dedicated mixer thread rather than per-frame, it topologically sorts all DSP nodes in the audio graph, applies pending parameter changes, and walks the graph front-to-back to sum the results into an output buffer delivered to the hardware.

**Performance notes:** Scales with the number of active audio producers and DSP effects, as well as the volume of property changes since the last mix. Because the soundcard reads from the output buffer on a strict hardware timer regardless of whether it is full, taking too long in this scope causes buffer underruns — heard in-game as audio crackling or sputtering.

**What game creators can do:**
- Limit the number of simultaneously active audio producers and DSP effects


---

## Audio Channel Operations

### release

**Releases a sound resource — frees the underlying FMOD sound object.**

Called when a Sound instance is destroyed or its asset changes. One-time cleanup cost.

**Performance notes:** Negligible per-call. Batch releases (destroying many sounds at once) can spike.


---

### FMODPlaybackChannel::createFMODChannel_

**Creates a playback channel — initializes a hardware channel for a sound to play on.**

Called when a Sound starts playing. Allocates an audio channel and configures it with the sound's properties.

**Performance notes:** Moderate per-call (involves audio channel allocation). Avoid starting hundreds of sounds simultaneously.


---

### FMODPlaybackChannel::setPlaying

**Starts/stops playback on an audio channel.**

Transitions a sound to the playing or stopped state.


---

### FMODPlaybackChannel::setTimePosition

**Seeks an audio channel to a specific time position.**

Sets the playback cursor. Can involve decoder seek operations for compressed audio.


---

## Speech-to-Text (SpeechEncoder)

These scopes fire when using voice input or speech-to-text features. They encode captured audio and send it to the STT service.

### SpeechEncoder::beginEncode

**Begins a speech encoding session — initializes the encoder for capturing speech.**


---

### SpeechEncoder::encode

**Encodes one chunk of audio data for speech-to-text processing.**

**Performance notes:** Runs only while voice input / speech-to-text is active. It executes on the **Sound** job — it drains microphone audio that was captured for speech-to-text and encodes it — so it appears on the Sound job's timeline, not on the real-time audio thread. Cost is CPU work proportional to the amount of speech captured.


---

### SpeechEncoder::endEncode

**Ends the speech encoding session — finalizes the encoded audio stream.**


---

### SpeechEncoder::encodeSpeech_DEPRECATED

**Alternate speech encoding path (retained for compatibility).**


---

### SpeechEncoder::makeRequestBody

**Constructs the HTTP request body for the STT API call.**


---

### SpeechEncoder::makeCallback

**Creates the response callback for the STT API request.**


---

### SpeechEncoder::makeAndSendQuery

**Sends the encoded speech to the speech-to-text server.**


<br>
<br>

---
