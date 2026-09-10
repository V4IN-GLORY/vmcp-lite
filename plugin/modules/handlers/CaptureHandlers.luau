local RenderMonitor = require(script.Parent.Parent.RenderMonitor)
local CaptureService = game:GetService("CaptureService")
local AssetService = game:GetService("AssetService")
local MAX_TILE_SIZE = 1024
local MAX_RAW_PIXEL_BYTES = 36 * 1024 * 1024
local MAX_CREATED_IMAGE_DIM = 2048
local BASE64_CHARS = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local PAD_BYTE = (string.byte("="))
local B64 = {}
for i = 0, 63 do
	B64[i + 1] = (string.byte(BASE64_CHARS, i + 1))
end
local function encodeBase64(buf)
	local len = buffer.len(buf)
	local fullTriples = math.floor(len / 3)
	local remaining = len - fullTriples * 3
	local outLen = (fullTriples + (if remaining > 0 then 1 else 0)) * 4
	local out = buffer.create(outLen)
	local si = 0
	local di = 0
	for t = 0, fullTriples - 1 do
		local b0 = buffer.readu8(buf, si)
		local b1 = buffer.readu8(buf, si + 1)
		local b2 = buffer.readu8(buf, si + 2)
		buffer.writeu8(out, di, B64[bit32.rshift(b0, 2) + 1])
		buffer.writeu8(out, di + 1, B64[bit32.bor(bit32.lshift(bit32.band(b0, 3), 4), bit32.rshift(b1, 4)) + 1])
		buffer.writeu8(out, di + 2, B64[bit32.bor(bit32.lshift(bit32.band(b1, 15), 2), bit32.rshift(b2, 6)) + 1])
		buffer.writeu8(out, di + 3, B64[bit32.band(b2, 63) + 1])
		si += 3
		di += 4
	end
	if remaining == 2 then
		local b0 = buffer.readu8(buf, si)
		local b1 = buffer.readu8(buf, si + 1)
		buffer.writeu8(out, di, B64[bit32.rshift(b0, 2) + 1])
		buffer.writeu8(out, di + 1, B64[bit32.bor(bit32.lshift(bit32.band(b0, 3), 4), bit32.rshift(b1, 4)) + 1])
		buffer.writeu8(out, di + 2, B64[bit32.lshift(bit32.band(b1, 15), 2) + 1])
		buffer.writeu8(out, di + 3, PAD_BYTE)
	elseif remaining == 1 then
		local b0 = buffer.readu8(buf, si)
		buffer.writeu8(out, di, B64[bit32.rshift(b0, 2) + 1])
		buffer.writeu8(out, di + 1, B64[bit32.lshift(bit32.band(b0, 3), 4) + 1])
		buffer.writeu8(out, di + 2, PAD_BYTE)
		buffer.writeu8(out, di + 3, PAD_BYTE)
	end
	return buffer.tostring(out)
end
local function readPixelsTiled(img, w, h)
	local BYTES_PER_PIXEL = 4
	local fullBuf = buffer.create(w * h * BYTES_PER_PIXEL)
	local fullRowBytes = w * BYTES_PER_PIXEL
	do
		local ty = 0
		local shouldIncrement = false
		while true do
			if shouldIncrement then
				ty += MAX_TILE_SIZE
			else
				shouldIncrement = true
			end
			if not (ty < h) then
				break
			end
			local tileH = math.min(MAX_TILE_SIZE, h - ty)
			do
				local tx = 0
				local shouldIncrement_1 = false
				while true do
					if shouldIncrement_1 then
						tx += MAX_TILE_SIZE
					else
						shouldIncrement_1 = true
					end
					if not (tx < w) then
						break
					end
					local tileW = math.min(MAX_TILE_SIZE, w - tx)
					local tileBuf = img:ReadPixelsBuffer(Vector2.new(tx, ty), Vector2.new(tileW, tileH))
					local tileRowBytes = tileW * BYTES_PER_PIXEL
					do
						local row = 0
						local shouldIncrement_2 = false
						while true do
							if shouldIncrement_2 then
								row += 1
							else
								shouldIncrement_2 = true
							end
							if not (row < tileH) then
								break
							end
							buffer.copy(
								fullBuf,
								(ty + row) * fullRowBytes + tx * BYTES_PER_PIXEL,
								tileBuf,
								row * tileRowBytes,
								tileRowBytes
							)
						end
					end
				end
			end
		end
	end
	return fullBuf
end
-- Triggers CaptureService:CaptureScreenshot and waits for the temporary
-- content id. Works in any DM, including the play CLIENT (where reading the
-- pixels back is blocked, but capturing is not). The returned rbxtemp:// id is
-- a process-scoped handle: it can be dereferenced from a DIFFERENT, more
-- privileged DM (the edit DM) — see captureRead.
local function doCaptureScreenshot()
	-- Fast-fail with a clear reason if the window isn't rendering — otherwise
	-- CaptureScreenshot's callback never fires and we'd block for the full 10s.
	local notRendering = RenderMonitor.notRenderingReason()
	if notRendering ~= nil then
		return {
			error = notRendering,
		}
	end
	local contentId
	CaptureService:CaptureScreenshot(function(id)
		contentId = id
	end)
	local startTime = tick()
	while contentId == nil do
		if tick() - startTime > 10 then
			return {
				error = "Screenshot capture timed out (CaptureScreenshot callback never fired). The Studio window is likely minimized or occluded — restore it so the viewport renders. (Known Roblox bug: capture can also fail if the viewport renders a solid color.)",
			}
		end
		task.wait(0.1)
	end
	return {
		contentId = contentId,
	}
end
-- Promotes a CaptureScreenshot content id into an EditableImage and reads its
-- RGBA pixels. MUST run in the edit/plugin context: the running game VM lacks
-- the privilege to create an EditableImage from a temporary texture id (errors
-- "cannot currently create editable image from temporary texture id"), while
-- the edit DM can — even for an id captured in the play client DM.
local function readContentToBase64(contentId)
	local editableOk, editableResult = pcall(function()
		return AssetService:CreateEditableImageAsync(Content.fromUri(contentId))
	end)
	if not editableOk then
		return {
			error = `Failed to create EditableImage from screenshot. Enable EditableImage API: Game Settings > Security > 'Allow Mesh / Image APIs'. ({tostring(
				editableResult
			)})`,
		}
	end
	local sourceImage = editableResult
	local imgSize = sourceImage.Size
	local nativeW = math.floor(imgSize.X)
	local nativeH = math.floor(imgSize.Y)
	local w = nativeW
	local h = nativeH
	if nativeW * nativeH * 4 > MAX_RAW_PIXEL_BYTES then
		local scale = math.min(
			math.sqrt(MAX_RAW_PIXEL_BYTES / (nativeW * nativeH * 4)),
			MAX_CREATED_IMAGE_DIM / math.max(nativeW, nativeH)
		)
		w = math.max(1, math.floor(nativeW * scale))
		h = math.max(1, math.floor(nativeH * scale))
		local scaleOk, scaledResult = pcall(function()
			local target = AssetService:CreateEditableImage({
				Size = Vector2.new(w, h),
			})
			target:DrawImageTransformed(Vector2.new(0, 0), Vector2.new(w / nativeW, h / nativeH), 0, sourceImage, {
				CombineType = Enum.ImageCombineType.AlphaBlend,
				SamplingMode = Enum.ResamplerMode.Default,
				PivotPoint = Vector2.new(0, 0),
			})
			return target
		end)
		sourceImage:Destroy()
		if not scaleOk then
			return {
				error = `Screenshot is {nativeW}x{nativeH} (too large to transfer raw) and downscaling failed: {tostring(
					scaledResult
				)}`,
			}
		end
		sourceImage = scaledResult
	end
	local readOk, pixelBuffer = pcall(function()
		return readPixelsTiled(sourceImage, w, h)
	end)
	sourceImage:Destroy()
	if not readOk then
		return {
			error = `Failed to read pixel data: {tostring(pixelBuffer)}`,
		}
	end
	local base64Data = encodeBase64(pixelBuffer)
	return {
		success = true,
		width = w,
		height = h,
		data = base64Data,
		nativeWidth = nativeW,
		nativeHeight = nativeH,
	}
end
-- Edit-mode single shot: capture and read back in the same (edit) context.
local function captureScreenshotData()
	local cap = doCaptureScreenshot()
	if cap.error ~= nil then
		return cap
	end
	return readContentToBase64(cap.contentId)
end
local function captureScreenshot()
	return captureScreenshotData()
end
-- Play-mode step 1 (run on the CLIENT): capture only, return the temp id.
local function captureBegin()
	return doCaptureScreenshot()
end
-- Play-mode step 2 (run on EDIT): read pixels from a temp id captured elsewhere.
local function captureRead(requestData)
	local contentId = requestData.contentId
	if not (contentId ~= "" and contentId) then
		return {
			error = "contentId is required",
		}
	end
	return readContentToBase64(contentId)
end
return {
	captureScreenshotData = captureScreenshotData,
	captureScreenshot = captureScreenshot,
	captureBegin = captureBegin,
	captureRead = captureRead,
}
