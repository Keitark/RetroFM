param(
    [string]$Vivado = ""
)

$ErrorActionPreference = "Stop"
$sampleDir = $PSScriptRoot

if ([string]::IsNullOrWhiteSpace($Vivado)) {
    $vivadoCommand = @(
        (Get-Command vivado.bat -ErrorAction SilentlyContinue),
        (Get-Command vivado -ErrorAction SilentlyContinue)
    ) | Where-Object { $null -ne $_ } | Select-Object -First 1
    if ($null -eq $vivadoCommand) {
        throw "Vivado was not found on PATH; pass -Vivado <path-to-vivado.bat>"
    }
    $Vivado = if (-not [string]::IsNullOrWhiteSpace($vivadoCommand.Source)) {
        $vivadoCommand.Source
    } else {
        $vivadoCommand.Definition
    }
}

$lock = Get-Content -LiteralPath (Join-Path $sampleDir "third_party.lock.json") -Raw |
    ConvertFrom-Json

foreach ($property in $lock.dependencies.PSObject.Properties) {
    if ($property.Name -eq "portable_mdx") {
        continue
    }
    if ($property.Value.commit -like "REPLACE_*") {
        throw "Dependency $($property.Name) has not passed its pinned-commit audit"
    }
    $dependencyPath = Join-Path $sampleDir $property.Value.destination
    if (-not (Test-Path -LiteralPath $dependencyPath)) {
        throw "Missing dependency $($property.Name); run fetch_dependencies.ps1"
    }
}

if (-not (Test-Path -LiteralPath $Vivado)) {
    throw "Vivado not found at $Vivado"
}

& $Vivado -mode batch -source (Join-Path $sampleDir "vivado\create_project.tcl")
if ($LASTEXITCODE -ne 0) { throw "Vivado implementation failed" }

# The implementation Tcl uses an in-process synth/place/route flow. Vivado
# 2024.2 cannot attach its BIT to an XSA through write_hw_platform in that same
# process because there is no implementation-run object. Reopen the signed
# routed checkpoint, repeat every timing/CDC/I/O gate, and export the XSA in a
# separate process. This also ensures a packaging failure is never reported as
# a successful one-command build.
& $Vivado -mode batch -source (Join-Path $sampleDir "vivado\package_routed.tcl")
if ($LASTEXITCODE -ne 0) { throw "Vivado routed-checkpoint packaging failed" }
