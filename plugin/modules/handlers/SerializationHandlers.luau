local PeerRole = require(script.Parent.Parent.PeerRole)
local Utils = require(script.Parent.Parent.Utils)
local Recording = require(script.Parent.Parent.Recording)
-- SerializationService:SerializeInstancesAsync / DeserializeInstancesAsync were
-- added in engine v668 and are PluginSecurity. They are not in @rbxts/types yet,
-- so we resolve the service through an untyped GetService cast and treat the
-- methods as opaque (buffer in / buffer out).
local SerializationService = game:GetService("SerializationService")
-- EncodingService:Base64Encode / Base64Decode take and return `buffer` (not
-- `string`). The signature is in @rbxts/types under None.d.ts so a normal
-- GetService("EncodingService") would already give correct types, but @rbxts
-- generates a per-service nominal interface and roblox.d.ts doesn't re-export
-- EncodingService from the services barrel module - so the typed cast below
-- matches what GetService would give us if it did.
local EncodingService = game:GetService("EncodingService")
local binding = Utils
local getInstanceByPath = binding.getInstanceByPath
local getInstancePath = binding.getInstancePath
local binding_1 = Recording
local beginRecording = binding_1.beginRecording
local finishRecording = binding_1.finishRecording
local function exportRbxm(requestData)
	local instancePaths = requestData.instance_paths
	if not instancePaths or not (type(instancePaths) == "table") or #instancePaths == 0 then
		return {
			error = "instance_paths must be a non-empty array",
		}
	end
	local instances = {}
	for _, p in instancePaths do
		local inst = getInstanceByPath(p)
		if not inst then
			return {
				error = `instance not found: {p}`,
			}
		end
		table.insert(instances, inst)
	end
	local serializeOk, serializeResult = pcall(function()
		return SerializationService:SerializeInstancesAsync(instances)
	end)
	if not serializeOk then
		return {
			error = `SerializeInstancesAsync failed: {tostring(serializeResult)}`,
		}
	end
	local buf = serializeResult
	local encodeOk, encodeResult = pcall(function()
		return EncodingService:Base64Encode(buf)
	end)
	if not encodeOk then
		return {
			error = `EncodingService:Base64Encode failed: {tostring(encodeResult)}`,
		}
	end
	-- Base64Encode returns a buffer of ASCII bytes; convert to a Lua string so
	-- HttpService:JSONEncode (called by the harness in Communication.ts) accepts
	-- it. Base64 is by definition pure ASCII so this round-trips cleanly.
	local base64Str = buffer.tostring(encodeResult)
	return {
		base64 = base64Str,
		instance_count = #instances,
	}
end
local function importRbxm(requestData)
	local b64 = requestData.base64
	local parentPath = requestData.parent_path
	local condition = requestData.source_label
	if condition == nil then
		condition = "unknown"
	end
	local sourceLabel = condition
	if not (b64 ~= "" and b64) or not (type(b64) == "string") then
		return {
			error = "base64 payload is required",
		}
	end
	if not (parentPath ~= "" and parentPath) or not (type(parentPath) == "string") then
		return {
			error = "parent_path is required",
		}
	end
	local parentInstance = getInstanceByPath(parentPath)
	if not parentInstance then
		return {
			error = `parent instance not found: {parentPath}`,
		}
	end
	-- b64 is an ASCII-only Lua string from the wire; lift it into a buffer for
	-- EncodingService:Base64Decode, which returns a buffer of raw rbxm bytes
	-- ready for DeserializeInstancesAsync.
	local b64BufOk, b64BufResult = pcall(function()
		return buffer.fromstring(b64)
	end)
	if not b64BufOk then
		return {
			error = `buffer.fromstring(base64) failed: {tostring(b64BufResult)}`,
		}
	end
	local decodeOk, decodeResult = pcall(function()
		return EncodingService:Base64Decode(b64BufResult)
	end)
	if not decodeOk then
		return {
			error = `EncodingService:Base64Decode failed: {tostring(decodeResult)}`,
		}
	end
	local buf = decodeResult
	local deserOk, deserResult = pcall(function()
		return SerializationService:DeserializeInstancesAsync(buf)
	end)
	if not deserOk then
		return {
			error = `DeserializeInstancesAsync failed: {tostring(deserResult)}`,
		}
	end
	local deserialized = deserResult
	-- All-or-nothing parenting. Track every instance we've attached and roll back
	-- (unparent + Destroy) if any later one fails - partial imports leave the DM
	-- in a worse state than failing cleanly.
	local isEdit = PeerRole.detect() == "edit"
	local recordingId = if isEdit then beginRecording(`Import rbxm`) else nil
	local attached = {}
	local failureMessage
	for _, inst in deserialized do
		local parentOk, parentErr = pcall(function()
			inst.Parent = parentInstance
		end)
		if not parentOk then
			failureMessage = `failed to parent {inst.Name} ({inst.ClassName}) under {parentPath}: {tostring(parentErr)}`
			break
		end
		table.insert(attached, inst)
	end
	if failureMessage ~= nil then
		for _, inst in attached do
			pcall(function()
				inst.Parent = nil
				inst:Destroy()
			end)
		end
		-- Also destroy any unparented deserialized instances so they don't leak.
		for _, inst in deserialized do
			if inst.Parent == nil then
				pcall(function()
					return inst:Destroy()
				end)
			end
		end
		finishRecording(recordingId, false)
		return {
			error = failureMessage,
		}
	end
	local names = {}
	local paths = {}
	for _, inst in attached do
		table.insert(names, inst.Name)
		local arg0 = getInstancePath(inst)
		table.insert(paths, arg0)
	end
	-- The recording shows "MCP: Import rbxm" in Studio's undo stack -
	-- ChangeHistoryService doesn't expose a way to set a richer displayName
	-- after TryBeginRecording, so the count/source only land in the JSON response.
	finishRecording(recordingId, true)
	return {
		instance_count = #attached,
		instance_names = names,
		instance_paths = paths,
		parent_path = parentPath,
		source = sourceLabel,
	}
end
return {
	exportRbxm = exportRbxm,
	importRbxm = importRbxm,
}
