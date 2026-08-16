param(
    [string]$Vivado = "",
    [switch]$SkipRtl,
    [switch]$RouteVendor,
    [switch]$ImplementFullDesign
)

$ErrorActionPreference = "Stop"
$sampleDir = $PSScriptRoot

function Invoke-Checked([scriptblock]$Command, [string]$Failure) {
    & $Command
    if ($LASTEXITCODE -ne 0) { throw $Failure }
}

Invoke-Checked { & (Join-Path $sampleDir "test.ps1") } `
    "portable firmware verification failed"

if (-not $SkipRtl) {
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
    if (-not (Test-Path -LiteralPath $Vivado)) {
        throw "Vivado not found at $Vivado"
    }
    Invoke-Checked {
        & $Vivado -mode batch -source (Join-Path $sampleDir "sim\run_xsim.tcl")
    } "foundational RTL simulation failed"
    Invoke-Checked {
        & $Vivado -mode batch -source `
            (Join-Path $sampleDir "sim\run_frontend_xsim.tcl")
    } "AXI front-end RTL simulation failed"
    Invoke-Checked {
        & $Vivado -mode batch -source `
            (Join-Path $sampleDir "sim\run_command_queue_xsim.tcl")
    } "command-queue backpressure RTL simulation failed"
    Invoke-Checked {
        & $Vivado -mode batch -source `
            (Join-Path $sampleDir "sim\run_mute_controller_xsim.tcl")
    } "reset-handshake pending-unmute RTL simulation failed"
    Invoke-Checked {
        & $Vivado -mode batch -source `
            (Join-Path $sampleDir "sim\run_jt51_resampler_xsim.tcl")
    } "JT51 rate-converter RTL simulation failed"
    Invoke-Checked {
        & $Vivado -mode batch -source `
            (Join-Path $sampleDir "sim\run_spectrum_xsim.tcl")
    } "spectrum RTL simulation failed"

    if ($RouteVendor) {
        Invoke-Checked {
            & $Vivado -mode batch -source `
                (Join-Path $sampleDir "vivado\compile_vendor_ooc.tcl")
        } "routed Yamaha vendor-core verification failed"
        Invoke-Checked {
            & $Vivado -mode batch -source `
                (Join-Path $sampleDir "sim\check_spectrum_synth.tcl")
        } "routed spectrum verification failed"
    }
    if ($ImplementFullDesign) {
        Invoke-Checked {
            & (Join-Path $sampleDir "build.ps1") -Vivado $Vivado
        } "full PS/PL implementation failed"
    }
}

Write-Host "RETROFM VERIFICATION PASS"
