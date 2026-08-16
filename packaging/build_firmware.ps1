param(
    [string]$Xsa = "$PSScriptRoot\..\build\vivado\retrofm_player\retrofm_player.xsa",
    [string]$Xsct = "",
    [string]$Bootgen = "",
    [string]$BuildDirectory = "$PSScriptRoot\..\build\vitis",
    [string]$HardwareBaseMacro = "AUTO",
    [string]$InterruptMacro = "AUTO",
    [switch]$SkipPackage,
    [switch]$IncludePrototypeMdx
)

$ErrorActionPreference = "Stop"
if (-not $IncludePrototypeMdx) {
    throw "Target firmware build is blocked: portable_mdx/MXDRV/X68Sound remains prototype-only. Supply -IncludePrototypeMdx only for explicitly private, non-redistributable output."
}
$sampleDir = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))

function Resolve-ToolPath(
    [string]$ExplicitPath,
    [string[]]$CommandNames,
    [string]$Label,
    [switch]$Optional
) {
    if (-not [string]::IsNullOrWhiteSpace($ExplicitPath)) {
        return (Resolve-Path -LiteralPath $ExplicitPath -ErrorAction Stop).Path
    }
    foreach ($commandName in $CommandNames) {
        $command = Get-Command $commandName -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if ($null -ne $command) {
            if (-not [string]::IsNullOrWhiteSpace($command.Source)) {
                return $command.Source
            }
            return $command.Definition
        }
    }
    if ($Optional) {
        return $null
    }
    throw "$Label was not found on PATH; pass the corresponding explicit path"
}

$allowedBuildRoot = [System.IO.Path]::GetFullPath((Join-Path $sampleDir "build"))
$buildDir = [System.IO.Path]::GetFullPath($BuildDirectory)
$allowedPrefix = $allowedBuildRoot.TrimEnd('\') + '\'
if (-not $buildDir.StartsWith($allowedPrefix,
        [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "BuildDirectory must remain below $allowedBuildRoot"
}
if ($buildDir -eq $allowedBuildRoot) {
    throw "BuildDirectory must name a child of $allowedBuildRoot"
}

$xsaPath = (Resolve-Path -LiteralPath $Xsa).Path
$xsctPath = Resolve-ToolPath -ExplicitPath $Xsct `
    -CommandNames @("xsct.bat", "xsct") -Label "XSCT"
if (-not $SkipPackage) {
    $bootgenPath = Resolve-ToolPath -ExplicitPath $Bootgen `
        -CommandNames @("bootgen.bat", "bootgen") -Label "Bootgen"
}

$lockPath = Join-Path $sampleDir "third_party.lock.json"
$lock = Get-Content -LiteralPath $lockPath -Raw | ConvertFrom-Json
foreach ($property in $lock.dependencies.PSObject.Properties) {
    $dependency = $property.Value
    if ($dependency.commit -like "REPLACE_*") {
        throw "Dependency $($property.Name) is not pinned"
    }
    $dependencyPath = (Resolve-Path -LiteralPath `
        (Join-Path $sampleDir $dependency.destination)).Path
    $safeDirectory = $dependencyPath.Replace('\', '/')
    $gitOutput = @(& git -c "safe.directory=$safeDirectory" `
        -C $dependencyPath rev-parse HEAD)
    if ($LASTEXITCODE -ne 0 -or $gitOutput.Count -ne 1) {
        throw "Could not inspect dependency $($property.Name)"
    }
    $actual = $gitOutput[0].Trim()
    if ($actual -ne $dependency.commit) {
        throw "Dependency $($property.Name) is $actual, expected $($dependency.commit)"
    }
}

if (Test-Path -LiteralPath $buildDir) {
    Remove-Item -LiteralPath $buildDir -Recurse -Force
}
$workspaceDir = Join-Path $buildDir "workspace"
$sourceDir = Join-Path $buildDir "source"
$artifactDir = Join-Path $buildDir "artifacts"
New-Item -ItemType Directory -Force -Path $workspaceDir, $sourceDir, $artifactDir |
    Out-Null

$sourceSets = @(
    (Join-Path $sampleDir "firmware\core\include\*.h"),
    (Join-Path $sampleDir "firmware\core\src\*.c"),
    (Join-Path $sampleDir "firmware\core\src\*.h"),
    (Join-Path $sampleDir "firmware\core\vendor\mdxtools\*.c"),
    (Join-Path $sampleDir "firmware\core\vendor\mdxtools\*.h"),
    (Join-Path $sampleDir "firmware\target\retrofm_*.c"),
    (Join-Path $sampleDir "firmware\target\retrofm_*.cpp"),
    (Join-Path $sampleDir "firmware\target\retrofm_*.h"),
    (Join-Path $sampleDir "firmware\target\vendor\lgfx_font_japan_gothic_12.c")
)
foreach ($sourceSet in $sourceSets) {
    Copy-Item -Path $sourceSet -Destination $sourceDir
}

$portableMdxDir = Join-Path $sampleDir $lock.dependencies.portable_mdx.destination
$portableMdxSourceSets = @(
    (Join-Path $portableMdxDir "include\*.h"),
    (Join-Path $portableMdxDir "src\mdx_util.c"),
    (Join-Path $portableMdxDir "src\mxdrv\*.cpp"),
    (Join-Path $portableMdxDir "src\mxdrv\*.h"),
    (Join-Path $portableMdxDir "src\x68sound\*.cpp"),
    (Join-Path $portableMdxDir "src\x68sound\*.h"),
    (Join-Path $portableMdxDir "src\x68sound\*.dat")
)
foreach ($sourceSet in $portableMdxSourceSets) {
    Copy-Item -Path $sourceSet -Destination $sourceDir
}
# Keep MXDRV/X68Sound's original timer, command, register, and envelope paths,
# but compile out its operator/output block. JT51 receives the exact interposed
# register writes; only ADPCM/PCM8 is sent to the PL PCM FIFO.
$stagedOpm = Join-Path $sourceDir "x68sound_opm.cpp"
$opmText = [System.IO.File]::ReadAllText($stagedOpm)
$lineBreak = if ($opmText.Contains("`r`n")) { "`r`n" } else { "`n" }
$opmStart = "`t`t`t`t`t{$lineBreak`t`t`t`t`t`tlfo.Update();"
$opmEnd62 = "`t`t`t}`t// UseOpmFlag$lineBreak$lineBreak" +
    "`t`t`tif (UseAdpcmFlag) {"
$opmEnd22 = "`t`t}$lineBreak$lineBreak`t`tif (UseAdpcmFlag) {"
$opmText = $opmText.Replace(
    $opmStart,
    "#if !defined(RETROFM_SUPPRESS_SOFTWARE_FM)$lineBreak$opmStart")
$opmText = $opmText.Replace($opmEnd62, "#endif$lineBreak$opmEnd62")
$opmText = $opmText.Replace($opmEnd22, "#endif$lineBreak$opmEnd22")
$opmGuardCount = [regex]::Matches(
    $opmText, "RETROFM_SUPPRESS_SOFTWARE_FM").Count
if ($opmGuardCount -ne 2) {
    throw "Expected two pinned portable_mdx OPM synthesis blocks"
}
[System.IO.File]::WriteAllText(
    $stagedOpm,
    $opmText,
    [System.Text.UTF8Encoding]::new($false))

# portable_mdx uses std::mutex only to protect calls made by threaded desktop
# audio backends. This application calls it synchronously in one bare-metal
# context, while Vitis' freestanding libstdc++ intentionally has no mutex.
foreach ($mutexHeaderName in "mxdrv_context.internal.h", "x68sound_opm.h") {
    $mutexHeader = Join-Path $sourceDir $mutexHeaderName
    $mutexText = [System.IO.File]::ReadAllText($mutexHeader)
    if (-not $mutexText.Contains("#include <mutex>") -or
        -not $mutexText.Contains("std::mutex")) {
        throw "Pinned portable_mdx mutex markers changed in $mutexHeaderName"
    }
    $mutexText = $mutexText.Replace(
        "#include <mutex>", '#include "retrofm_null_mutex.h"').Replace(
        "std::mutex", "retrofm_null_mutex")
    [System.IO.File]::WriteAllText(
        $mutexHeader, $mutexText, [System.Text.UTF8Encoding]::new($false))
}
$mxdrvContextSource = Join-Path $sourceDir "mxdrv_context.cpp"
$mxdrvContextText = [System.IO.File]::ReadAllText($mxdrvContextSource)
if (-not $mxdrvContextText.Contains("std::mutex();") -or
    -not $mxdrvContextText.Contains("m_mtx.~mutex();")) {
    throw "Pinned portable_mdx mutex destructor marker changed"
}
[System.IO.File]::WriteAllText(
    $mxdrvContextSource,
    $mxdrvContextText.Replace(
        "std::mutex();", "retrofm_null_mutex();").Replace(
        "m_mtx.~mutex();", "m_mtx.~retrofm_null_mutex();"),
    [System.Text.UTF8Encoding]::new($false))
Copy-Item -LiteralPath (Join-Path $sampleDir "firmware\target\xilinx\main.c") `
    -Destination $sourceDir

$minizDir = Join-Path $sampleDir $lock.dependencies.miniz.destination
foreach ($name in "miniz.h", "miniz_common.h", "miniz_tdef.h", `
        "miniz_tinfl.h", "miniz_tinfl.c", "miniz_zip.h") {
    Copy-Item -LiteralPath (Join-Path $minizDir $name) -Destination $sourceDir
}
$minizExport = @"
#ifndef MINIZ_EXPORT_H
#define MINIZ_EXPORT_H
#define MINIZ_EXPORT
#endif
"@
[System.IO.File]::WriteAllText(
    (Join-Path $sourceDir "miniz_export.h"),
    $minizExport,
    [System.Text.UTF8Encoding]::new($false))

$tcl = Join-Path $PSScriptRoot "build_vitis.tcl"
& $xsctPath $tcl $xsaPath $workspaceDir $sourceDir $artifactDir `
    $HardwareBaseMacro $InterruptMacro
if ($LASTEXITCODE -ne 0) {
    throw "XSCT standalone build failed"
}

$applicationElf = Join-Path $artifactDir "retrofm_app.elf"
$fsblElf = Join-Path $artifactDir "retrofm_fsbl.elf"
$linkerScript = Join-Path $artifactDir "retrofm_app.ld"
$selectionPath = Join-Path $artifactDir "xparameters-selection.txt"
$selection = [ordered]@{}
foreach ($line in Get-Content -LiteralPath $selectionPath) {
    $parts = $line.Split('=', 2)
    if ($parts.Count -eq 2) {
        $selection[$parts[0]] = $parts[1]
    }
}
$bspRoot = Join-Path $workspaceDir `
    "retrofm_platform\export\retrofm_platform\sw\retrofm_platform\retrofm_app_domain"
$bspInclude = Join-Path $bspRoot "bspinclude\include"
$bspLibrary = Join-Path $bspRoot "bsplib\lib"
foreach ($required in $bspInclude, $bspLibrary, $linkerScript, $fsblElf) {
    if (-not (Test-Path -LiteralPath $required)) {
        throw "Generated platform artifact is missing: $required"
    }
}

$vitisRoot = Split-Path (Split-Path $xsctPath)
$gccPath = Join-Path $vitisRoot `
    "gnu\aarch32\nt\gcc-arm-none-eabi\bin\arm-none-eabi-gcc.exe"
$gxxPath = Join-Path $vitisRoot `
    "gnu\aarch32\nt\gcc-arm-none-eabi\bin\arm-none-eabi-g++.exe"
if (-not (Test-Path -LiteralPath $gccPath)) {
    throw "Vitis ARM GCC not found at $gccPath"
}
if (-not (Test-Path -LiteralPath $gxxPath)) {
    throw "Vitis ARM G++ not found at $gxxPath"
}

$objectDir = Join-Path $buildDir "objects"
New-Item -ItemType Directory -Force -Path $objectDir | Out-Null
$commonFlags = @(
    "-mcpu=cortex-a9", "-mfpu=vfpv3", "-mfloat-abi=hard",
    "-O2", "-g0", "-std=c11", "-Wall", "-Wextra", "-Werror",
    "-ffunction-sections", "-fdata-sections", "-I$sourceDir", "-I$bspInclude"
)
$objects = @()
$forcedBuildConfig = Join-Path $sourceDir "retrofm_build_config.h"
if (-not (Test-Path -LiteralPath $forcedBuildConfig)) {
    throw "XSCT did not generate the target build configuration"
}
$commonFlags += "-include", $forcedBuildConfig
foreach ($source in Get-ChildItem -LiteralPath $sourceDir -File -Filter "*.c" |
        Sort-Object Name) {
    $object = Join-Path $objectDir ($source.BaseName + ".o")
    & $gccPath @commonFlags -c $source.FullName -o $object
    if ($LASTEXITCODE -ne 0) {
        throw "ARM compilation failed for $($source.Name)"
    }
    $objects += $object
}
$cxxFlags = @(
    "-mcpu=cortex-a9", "-mfpu=vfpv3", "-mfloat-abi=hard",
    "-O2", "-g0", "-std=gnu++17", "-Wall", "-Wextra",
    "-fno-exceptions", "-fno-rtti", "-ffunction-sections",
    "-fdata-sections", "-I$sourceDir", "-I$bspInclude",
    "-include", $forcedBuildConfig
)
foreach ($source in Get-ChildItem -LiteralPath $sourceDir -File -Filter "*.cpp" |
        Sort-Object Name) {
    $object = Join-Path $objectDir ($source.BaseName + ".o")
    $sourceFlags = @($cxxFlags)
    if ($source.Name -eq "retrofm_mxdrv.cpp") {
        $sourceFlags += "-Werror"
    } elseif ($source.Name -eq "sound_iocs.cpp") {
        $sourceFlags += "-D_iocs_opmset=retrofm_portable_iocs_opmset_internal"
    } elseif ($source.Name -eq "x68sound.cpp") {
        $sourceFlags += "-DX68Sound_StartPcm=retrofm_portable_x68sound_start_pcm_internal"
    } elseif ($source.Name -eq "x68sound_opm.cpp") {
        $sourceFlags += "-DRETROFM_SUPPRESS_SOFTWARE_FM=1"
    }
    & $gxxPath @sourceFlags -c $source.FullName -o $object
    if ($LASTEXITCODE -ne 0) {
        throw "ARM C++ compilation failed for $($source.Name)"
    }
    $objects += $object
}

$linkFlags = @(
    "-mcpu=cortex-a9", "-mfpu=vfpv3", "-mfloat-abi=hard",
    "-specs=$(Join-Path $PSScriptRoot 'Xilinx.spec')",
    "-Wl,-build-id=none", "-Wl,--gc-sections",
    "-Wl,--defsym=_HEAP_SIZE=0x01000000",
    "-Wl,-Map=$(Join-Path $artifactDir 'retrofm_app.map')", "-T$linkerScript",
    "-L$bspLibrary", "-Wl,--start-group", "-lxilffs", "-lxil", "-lgcc",
    "-lstdc++", "-lsupc++", "-lc", "-lm", "-Wl,--end-group"
)
& $gccPath -o $applicationElf @objects @linkFlags
if ($LASTEXITCODE -ne 0) {
    throw "Direct Vitis ARM GCC link failed"
}
$sizePath = $gccPath.Replace("gcc.exe", "size.exe")
$sizeOutput = @(& $sizePath $applicationElf)
if ($LASTEXITCODE -ne 0) {
    throw "Could not measure the application ELF"
}
$sizeOutput | Set-Content -LiteralPath `
    (Join-Path $artifactDir "retrofm_app.size.txt") -Encoding ascii

foreach ($artifact in $applicationElf, $fsblElf) {
    if (-not (Test-Path -LiteralPath $artifact) -or
        (Get-Item -LiteralPath $artifact).Length -eq 0) {
        throw "Expected build artifact is missing or empty: $artifact"
    }
}

$manifest = [ordered]@{
    schema = 1
    xsa = $xsaPath
    xsa_sha256 = (Get-FileHash -LiteralPath $xsaPath -Algorithm SHA256).Hash.ToLowerInvariant()
    compiler = (& $gccPath --version | Select-Object -First 1)
    arm_size = ($sizeOutput -join "`n")
    application_elf = $applicationElf
    application_sha256 = (Get-FileHash -LiteralPath $applicationElf -Algorithm SHA256).Hash.ToLowerInvariant()
    fsbl_elf = $fsblElf
    fsbl_sha256 = (Get-FileHash -LiteralPath $fsblElf -Algorithm SHA256).Hash.ToLowerInvariant()
    xparameters = $selection
    packaged = (-not $SkipPackage)
}

if (-not $SkipPackage) {
    $xsaExtractDir = Join-Path $buildDir "xsa"
    New-Item -ItemType Directory -Force -Path $xsaExtractDir | Out-Null
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [System.IO.Compression.ZipFile]::ExtractToDirectory($xsaPath, $xsaExtractDir)
    $bitstreams = @(Get-ChildItem -LiteralPath $xsaExtractDir -Recurse -File `
        -Filter "*.bit")
    if ($bitstreams.Count -ne 1) {
        throw "Expected exactly one bitstream inside the XSA; found $($bitstreams.Count)"
    }

    $sdDir = Join-Path $buildDir "sd"
    & (Join-Path $sampleDir "packaging\package.ps1") `
        -Fsbl $fsblElf `
        -Bitstream $bitstreams[0].FullName `
        -Application $applicationElf `
        -Bootgen $bootgenPath `
        -OutputDirectory $sdDir `
        -AllowPrivatePrototype
    if ($LASTEXITCODE -ne 0) {
        throw "BOOT.BIN packaging failed"
    }
    $bootBin = Join-Path $sdDir "BOOT.BIN"
    if (-not (Test-Path -LiteralPath $bootBin) -or
        (Get-Item -LiteralPath $bootBin).Length -eq 0) {
        throw "BOOT.BIN was not produced"
    }

    $generatedTestdataDir = Join-Path $sampleDir "testdata\generated"
    $testdataManifestPath = Join-Path $generatedTestdataDir "manifest.json"
    $testdataManifest = Get-Content -LiteralPath $testdataManifestPath -Raw |
        ConvertFrom-Json
    $musicDir = Join-Path $sdDir "music"
    $testdataMetadataDir = Join-Path $sdDir "testdata"
    New-Item -ItemType Directory -Force -Path $musicDir, $testdataMetadataDir |
        Out-Null
    $musicReceipt = [ordered]@{}
    foreach ($fileProperty in $testdataManifest.files.PSObject.Properties) {
        $name = $fileProperty.Name
        if ([System.IO.Path]::GetExtension($name).ToLowerInvariant() -notin
            ".mdx", ".pdx", ".vgm", ".vgz") {
            throw "Generated testdata manifest contains unexpected file: $name"
        }
        $source = Join-Path $generatedTestdataDir $name
        $actualHash = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($actualHash -ne $fileProperty.Value.sha256) {
            throw "Generated testdata hash mismatch for $name"
        }
        Copy-Item -LiteralPath $source -Destination $musicDir
        $musicReceipt[$name] = [ordered]@{
            bytes = (Get-Item -LiteralPath $source).Length
            sha256 = $actualHash
            license = $testdataManifest.license
        }
    }
    Copy-Item -LiteralPath $testdataManifestPath `
        -Destination (Join-Path $testdataMetadataDir "generated-manifest.json")
    Copy-Item -LiteralPath (Join-Path $sampleDir "testdata\README.md") `
        -Destination (Join-Path $testdataMetadataDir "README.md")

    $manifest.boot_bin = $bootBin
    $manifest.boot_bin_sha256 =
        (Get-FileHash -LiteralPath $bootBin -Algorithm SHA256).Hash.ToLowerInvariant()
    $manifest.music = $musicReceipt
    $manifest.testdata_license = $testdataManifest.license
}

$manifestPath = Join-Path $artifactDir "build-manifest.json"
$manifestJson = $manifest | ConvertTo-Json -Depth 4
[System.IO.File]::WriteAllText(
    $manifestPath,
    $manifestJson,
    [System.Text.UTF8Encoding]::new($false))
if (-not $SkipPackage) {
    Copy-Item -LiteralPath $manifestPath `
        -Destination (Join-Path $sdDir "BUILD-MANIFEST.json")
}

Write-Host "RetroFM standalone build complete"
Write-Host "  Application: $applicationElf"
Write-Host "  FSBL:        $fsblElf"
if (-not $SkipPackage) {
    Write-Host "  BOOT.BIN:    $(Join-Path $buildDir 'sd\BOOT.BIN')"
}
Write-Host "  Manifest:    $manifestPath"
