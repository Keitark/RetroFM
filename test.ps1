param(
    [string]$Configuration = "Release"
)

$ErrorActionPreference = "Stop"
$sampleDir = $PSScriptRoot
$buildDir = Join-Path $sampleDir "build\host-tests"
$targetBuildDir = Join-Path $sampleDir "build\host-target-tests"

# Codex Desktop can supply both PATH and Path in the native environment. The
# .NET Framework MSBuild launcher treats those as duplicate dictionary keys.
# Re-create one canonical entry before invoking CMake/MSBuild.
$savedPath = $env:PATH
Remove-Item Env:PATH
$env:Path = $savedPath

cmake -S (Join-Path $sampleDir "firmware\core") -B $buildDir `
    -G "Visual Studio 17 2022" -A x64
if ($LASTEXITCODE -ne 0) { throw "CMake configure failed" }

cmake --build $buildDir --config $Configuration
if ($LASTEXITCODE -ne 0) { throw "Host build failed" }

ctest --test-dir $buildDir -C $Configuration --output-on-failure
if ($LASTEXITCODE -ne 0) { throw "Host tests failed" }

cmake -S (Join-Path $sampleDir "firmware\target") -B $targetBuildDir `
    -G "Visual Studio 17 2022" -A x64
if ($LASTEXITCODE -ne 0) { throw "Target-support CMake configure failed" }

cmake --build $targetBuildDir --config $Configuration
if ($LASTEXITCODE -ne 0) { throw "Target-support host build failed" }

ctest --test-dir $targetBuildDir -C $Configuration --output-on-failure
if ($LASTEXITCODE -ne 0) { throw "Target-support host tests failed" }
