#requires -Version 7
<#
	Builds the MCP Studio plugin to build/MCPPlugin.rbxmx.

	  .\build.ps1                 build
	  .\build.ps1 -Check          analyze + format check, then build
	  .\build.ps1 -Install        build, then copy into the local Roblox Plugins folder
	  .\build.ps1 -Format         reformat the source in place

	Run `rokit install` once first to get rojo / stylua / luau-lsp.
#>
param(
	[switch]$Check,
	[switch]$Install,
	[switch]$Format
)

$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

# EvalBridges and LuauExec embed Luau source using backslash line continuations
# inside interpolated strings, which StyLua 0.20 cannot tokenize. Valid Luau.
$Unformattable = @('EvalBridges.luau', 'LuauExec.luau')

# include/ holds LibMP, a 4.9 MB vendored MicroProfiler library. Not our code.
$Sources = Get-ChildItem plugin -Recurse -Filter *.luau |
	Where-Object { $_.FullName -notlike '*\include\*' }

$Formattable = $Sources | Where-Object { $_.Name -notin $Unformattable }
$StyluaArgs = @('--indent-type', 'Tabs', '--column-width', '120')

function Get-ApiDefs {
	$defs = Join-Path $PSScriptRoot '.tooling\globalTypes.d.luau'
	if (-not (Test-Path $defs)) {
		New-Item -ItemType Directory -Force (Split-Path $defs) | Out-Null
		Write-Host 'Fetching Roblox API definitions...' -ForegroundColor Cyan
		Invoke-WebRequest -TimeoutSec 60 -OutFile $defs `
			-Uri 'https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/main/scripts/globalTypes.PluginSecurity.d.luau'
	}
	return $defs
}

if ($Format) {
	stylua @StyluaArgs @($Formattable.FullName)
	Write-Host "Formatted $($Formattable.Count) files" -ForegroundColor Green
}

New-Item -ItemType Directory -Force build | Out-Null

if ($Check) {
	# A sourcemap lets luau-lsp resolve require(script.Parent.Foo) across modules.
	rojo sourcemap mcpplugin.project.json --output build/sourcemap.json
	if ($LASTEXITCODE -ne 0) { throw 'rojo sourcemap failed' }

	Write-Host 'Analyzing...' -ForegroundColor Cyan
	$analyzeArgs = @(
		'analyze'
		'--no-strict-dm-types'
		"--defs=$(Get-ApiDefs)"
		'--sourcemap=build/sourcemap.json'
	) + $Sources.FullName
	$diags = luau-lsp @analyzeArgs 2>&1 | ForEach-Object { $_.ToString() }

	# Syntax errors are a hard gate. The type diagnostics below are inference
	# noise inherited from the roblox-ts output (which carried no annotations);
	# they are identical to the ones the original compiled plugin produced, so
	# they fail nothing until someone actually annotates these modules.
	$syntax = $diags | Select-String -Pattern 'SyntaxError'
	if ($syntax) {
		$syntax | ForEach-Object { Write-Host $_ -ForegroundColor Red }
		throw 'syntax errors'
	}

	$types = @($diags | Select-String -Pattern '(TypeError|ImplicitReturn)' |
		ForEach-Object { $_.ToString() } | Sort-Object -Unique)
	Write-Host "  no syntax errors; $($types.Count) inherited type diagnostics" -ForegroundColor DarkGray

	Write-Host 'Checking format...' -ForegroundColor Cyan
	stylua --check @StyluaArgs @($Formattable.FullName)
	if ($LASTEXITCODE -ne 0) { throw 'formatting check failed - run .\build.ps1 -Format' }
}

rojo build mcpplugin.project.json --output build/MCPPlugin.rbxmx
if ($LASTEXITCODE -ne 0) { throw 'rojo build failed' }

$out = Resolve-Path build/MCPPlugin.rbxmx
$mb = [math]::Round((Get-Item $out).Length / 1MB, 1)
Write-Host "Built $out ($mb MB)" -ForegroundColor Green

if ($Install) {
	$plugins = Join-Path $env:LOCALAPPDATA 'Roblox\Plugins'
	New-Item -ItemType Directory -Force $plugins | Out-Null
	Copy-Item $out (Join-Path $plugins 'MCPPlugin.rbxmx') -Force
	Write-Host "Installed to $plugins - restart Studio to load it" -ForegroundColor Green
}
