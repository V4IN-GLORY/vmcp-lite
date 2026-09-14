# Video Group

<!-- from github.com/Roblox/libmp/docs/ALL-SCOPES.md -->
The Video group contains scopes for video playback and processing: codec decode/encode, stream handling, format conversion, and video-frame rendering. These scopes run on dedicated media threads and occasionally on the main thread.

---

## Codec Operations (Decode & Encode)

### MediaCodecDecoder::receiveFrame / MediaCodecDecoder::sendPacket

**Android MediaCodec hardware decoder — sends encoded packets and receives decoded frames.**


---

### AlphaVideoMediaCodecDecoder::receiveFrame / AlphaVideoMediaCodecDecoder::sendPacket

**Android alpha-channel video decoder (transparent video).**


---

### MediaFoundationCodec::receiveFrameInternal / sendFrameInternal / receivePacketInternal / sendPacketInternal

**Windows Media Foundation codec — hardware-accelerated encode/decode on Windows.**


---

### MvtDecoder::receiveFrameInternal / sendPacketInternal / releaseFrame / decoderCallback / MvtEncoder::encoderCallback / receivePacketInternal / sendFrame

**MVT (Apple VideoToolbox) codec — Apple hardware encode/decode.**


---

### PS4VideoDec2Decoder::receiveFrameInternal / sendPacketInternal / releaseFrame

**PlayStation 4 hardware video decoder.**


---

### Av1SoftwareCodec::receiveFrameInternal / sendPacketInternal

**AV1 software codec — CPU-based AV1 decode.**

**Performance notes:** Software decoding is CPU-intensive. Used when hardware decode isn't available.


---

### OpusSoftwareCodec::receiveFrameInternal / receivePacketInternal

**Opus audio codec — encodes and decodes Opus audio for voice/audio streaming.**


---

### MediaCodecEncoder::receivePacket / MediaCodecEncoder::sendFrame

**Android hardware video encoder — feeds video frames to the platform encoder and dequeues the encoded packets.**


---

### McaEncoder::receivePacketInternal / McaEncoder::sendFrame

**Apple/Mac AAC audio encoder (Core Audio) — encodes PCM audio into AAC packets and dequeues them. (This is audio, even though it appears under the `Video` profiler group.)**


---

### VorbisSoftwareCodec::receivePacketInternal

**Vorbis software audio codec — encodes PCM audio into Vorbis packets (encoder output step).**


---

### VpxSoftwareCodec::receiveFrameInternal / sendFrameInternal / sendPacketInternal

**VP8/VP9 software codec — CPU-based VP8/VP9 encode/decode.**


---

### WinCodecDriver::receiveFrameInternal / receivePacketInternal / sendFrameInternal / sendPacketInternal

**Windows codec driver — dispatches encode/decode to the platform codec.**


---

### WebmInputFormat::readPacket

**Reads packets from a WebM container (demuxing).**


---

### Codec sub-operations

Lower-level codec I/O shared across the codecs above:
- `copyFromPacket` / `copyFromPacketAlpha` / `copyToFrame` / `copyToFrameAlpha` — packet/frame data copy
- `decodeAudio` / `decodeVideo` — decode entry points
- `vpx_buffer_copy` / `vpx_codec_encode` — VP8/VP9 decoded-frame buffer copy (decode path) and encode operation


---

## Codec Wrapper (RvCodec)

### RvCodecReceive / RvCodecSend

**High-level codec receive/send — wraps the platform-specific codec for the Rv (Roblox Video) pipeline.**

Receives decoded frames from the codec or sends raw frames to the encoder.

**Performance notes:** One call per video frame. Cost depends on the underlying codec (hardware = fast, software = slow).


---

## Playback & Stream

### VideoFeatureControl::save

**Saves video feature control settings.**


---

### VideoManager::incrementCounter

**Increments video system counters for telemetry.**


---

### VideoStream::renderStep

**Per-frame video stream update — delivers decoded frames for rendering.**


---

### convertToPng

**Converts a video frame to PNG format (for screenshots/thumbnails).**


---

### processPendingRequests / step

**Processes pending video requests and advances the video system state.**


---

### loadVideoCallback / onAssetLoaded / onReadAudio / readPacket

**Video asset loading and packet reading during playback.**


---

## Video Support Utilities

### RVScale::rvsScale

**Video frame scaling — resizes frames for different resolution targets.**


---

### RvSchedulerService::runCallbacks

**Dispatches scheduled video callbacks to a thread pool for asynchronous execution.**


---

### ScreenDensity::getCurrentScreenDensity

**Queries the current screen density for appropriate resolution selection.**


---

### CanvasGroupHandle

**Handles CanvasGroup video texture rendering.**


---

## Video Frame Rendering

Turning decoded video frames into on-screen textures (distinct from the 3D scene Render group).

### VideoManager

- `VideoManager::convertNV12FrameToR8Texture` / `VideoManager::convertNV12FrameToR8Texture:YuvToNv12` / `VideoManager::convertYUVFrameToR8Texture` / `VideoManager::processVideoSourceTexture` — video frame format conversion operations


---

### Frame output operations

- `bindHardwareBufferToVideoTexture` — binds hardware buffer for zero-copy video
- `doRenderVideo` / `flushRenderBuffers` / `renderFrameWithExternalBuffer` / `renderImage` — video rendering operations
- `libyuv::H420ToABGR` / `libyuv::I420AlphaToARGB` / `libyuv::NV12ToABGR` — color space conversion (libyuv)
- `getVisibilityIsViewUnBlocked` / `getVisibilityStatus` — visibility checks for video surfaces


<br>
<br>

---
