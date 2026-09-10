local function countInstances(instances)
	local count = 0
	for _, _instance in instances do
		count += 1
	end
	return count
end
local function scanForbiddenImportedInstances(root)
	local scripts = {}
	local packageLinks = {}
	local function inspect(instance)
		-- IsA("LuaSourceContainer") covers Script, LocalScript, ModuleScript,
		-- and any future script-bearing subclass. Names, source, creator,
		-- reputation, and hierarchy depth are deliberately irrelevant.
		if instance:IsA("LuaSourceContainer") then
			table.insert(scripts, instance)
		end
		if instance:IsA("PackageLink") then
			table.insert(packageLinks, instance)
		end
	end
	inspect(root)
	-- GetDescendants performs an engine-level, unlimited-depth traversal.
	-- Never replace this security scan with a depth-limited tree walk.
	for _, descendant in root:GetDescendants() do
		inspect(descendant)
	end
	return {
		scripts = scripts,
		packageLinks = packageLinks,
	}
end
local function sanitizeLoadedAsset(root, operations)
	if not operations.forceUnparent(root) then
		operations.destroy(root)
		return {
			success = false,
			removedScriptCount = 0,
			removedPackageLinkCount = 0,
			remainingScriptCount = 0,
			remainingPackageLinkCount = 0,
			error = "Loaded asset could not be kept unparented for sanitization.",
		}
	end
	local firstScan = scanForbiddenImportedInstances(root)
	local firstScriptCount = countInstances(firstScan.scripts)
	local firstPackageLinkCount = countInstances(firstScan.packageLinks)
	-- A forbidden root cannot be removed while preserving an import wrapper.
	-- Destroy the whole load and fail closed.
	if root:IsA("LuaSourceContainer") or root:IsA("PackageLink") then
		local rootWasScript = root:IsA("LuaSourceContainer")
		local rootWasPackageLink = root:IsA("PackageLink")
		operations.destroy(root)
		return {
			success = false,
			removedScriptCount = firstScriptCount,
			removedPackageLinkCount = firstPackageLinkCount,
			remainingScriptCount = if rootWasScript then 1 else 0,
			remainingPackageLinkCount = if rootWasPackageLink then 1 else 0,
			error = "Loaded asset root is a forbidden executable or package-link instance.",
		}
	end
	local removedScriptCount = 0
	for _, scriptInstance in firstScan.scripts do
		if operations.destroy(scriptInstance) then
			removedScriptCount += 1
		end
	end
	local removedPackageLinkCount = 0
	for _, packageLink in firstScan.packageLinks do
		if operations.destroy(packageLink) then
			removedPackageLinkCount += 1
		end
	end
	-- Mandatory second unlimited-depth scan. If any forbidden instance
	-- survived, destroy the entire imported root and insert nothing.
	local verificationScan = scanForbiddenImportedInstances(root)
	local remainingScriptCount = countInstances(verificationScan.scripts)
	local remainingPackageLinkCount = countInstances(verificationScan.packageLinks)
	if remainingScriptCount > 0 or remainingPackageLinkCount > 0 then
		operations.destroy(root)
		return {
			success = false,
			removedScriptCount = removedScriptCount,
			removedPackageLinkCount = removedPackageLinkCount,
			remainingScriptCount = remainingScriptCount,
			remainingPackageLinkCount = remainingPackageLinkCount,
			error = "Asset sanitization verification failed; the entire imported asset was destroyed.",
		}
	end
	return {
		success = true,
		removedScriptCount = removedScriptCount,
		removedPackageLinkCount = removedPackageLinkCount,
		remainingScriptCount = 0,
		remainingPackageLinkCount = 0,
	}
end
return {
	scanForbiddenImportedInstances = scanForbiddenImportedInstances,
	sanitizeLoadedAsset = sanitizeLoadedAsset,
}
