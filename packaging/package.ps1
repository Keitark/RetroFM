param(
    [Parameter(Mandatory = $true)][string]$Fsbl,
    [Parameter(Mandatory = $true)][string]$Bitstream,
    [Parameter(Mandatory = $true)][string]$Application,
    [string]$Bootgen = "",
    [string]$OutputDirectory = "$PSScriptRoot\..\build\sd",
    [switch]$AllowPrivatePrototype
)

$ErrorActionPreference = "Stop"
$bootgenCommand = $null
if ([string]::IsNullOrWhiteSpace($Bootgen)) {
    $bootgenCommand = Get-Command bootgen.bat -ErrorAction SilentlyContinue
    if ($null -eq $bootgenCommand) {
        $bootgenCommand = Get-Command bootgen -ErrorAction SilentlyContinue
    }
    if ($null -eq $bootgenCommand) {
        throw "Bootgen was not found on PATH; pass -Bootgen <path-to-bootgen>"
    }
    $Bootgen = if (-not [string]::IsNullOrWhiteSpace($bootgenCommand.Source)) {
        $bootgenCommand.Source
    } else {
        $bootgenCommand.Definition
    }
}
if (-not (Test-Path -LiteralPath $Bootgen)) {
    throw "Bootgen not found at $Bootgen"
}
$sampleDir = Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")
$lock = Get-Content -LiteralPath (Join-Path $sampleDir "third_party.lock.json") -Raw |
    ConvertFrom-Json

foreach ($property in $lock.dependencies.PSObject.Properties) {
    if ($property.Value.commit -like "REPLACE_*") {
        throw "Release blocked: $($property.Name) is not pinned"
    }
}
if (-not $AllowPrivatePrototype) {
    throw "Binary packaging is blocked: portable_mdx/MXDRV/X68Sound remains prototype-only. Supply -AllowPrivatePrototype only for explicitly private, non-redistributable output."
}
if (-not (Test-Path -LiteralPath (Join-Path $sampleDir "COPYING"))) {
    throw "Release blocked: install the complete GPL-3.0-only text as COPYING"
}

$fsblPath = (Resolve-Path -LiteralPath $Fsbl).Path
$bitPath = (Resolve-Path -LiteralPath $Bitstream).Path
$appPath = (Resolve-Path -LiteralPath $Application).Path
New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
$bifPath = Join-Path $OutputDirectory "boot.bif"
$template = Get-Content -LiteralPath (Join-Path $PSScriptRoot "boot.bif.in") -Raw
$template = $template.Replace("@FSBL@", $fsblPath)
$template = $template.Replace("@BITSTREAM@", $bitPath)
$template = $template.Replace("@APPLICATION@", $appPath)
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
[System.IO.File]::WriteAllText($bifPath, $template, $utf8NoBom)

& $Bootgen -arch zynq -image $bifPath -o (Join-Path $OutputDirectory "BOOT.BIN") -w on
if ($LASTEXITCODE -ne 0) { throw "bootgen failed" }
