param(
    [switch]$AllowUnpinned,
    [switch]$IncludePrototypeMdx
)

$ErrorActionPreference = "Stop"
$sampleDir = $PSScriptRoot
$lockPath = Join-Path $sampleDir "third_party.lock.json"
$lock = Get-Content -LiteralPath $lockPath -Raw | ConvertFrom-Json

foreach ($property in $lock.dependencies.PSObject.Properties) {
    $name = $property.Name
    $dependency = $property.Value

    if ($name -eq "portable_mdx" -and -not $IncludePrototypeMdx) {
        Write-Warning "Skipping portable_mdx: it remains a private prototype dependency pending rights review. Re-run with -IncludePrototypeMdx only for an explicitly private prototype checkout."
        continue
    }
    if ($name -eq "portable_mdx" -and $IncludePrototypeMdx) {
        Write-Warning "Including portable_mdx prototype at the caller's explicit request; its source and all resulting binaries remain private and non-redistributable pending rights review."
    }

    $destination = Join-Path $sampleDir $dependency.destination

    if ($dependency.commit -like "REPLACE_*") {
        if (-not $AllowUnpinned) {
            throw "$name has not yet passed the commit/license audit; refusing an unpinned fetch"
        }
        Write-Warning "$name is unpinned and is for audit only"
    }

    if (-not (Test-Path -LiteralPath $destination)) {
        New-Item -ItemType Directory -Force -Path (Split-Path $destination) | Out-Null
        git clone --filter=blob:none $dependency.url $destination
        if ($LASTEXITCODE -ne 0) { throw "git clone failed for $name" }
    }

    if ($dependency.commit -notlike "REPLACE_*") {
        git -C $destination fetch --depth 1 origin $dependency.commit
        if ($LASTEXITCODE -ne 0) { throw "git fetch failed for $name" }
        git -C $destination checkout --detach $dependency.commit
        if ($LASTEXITCODE -ne 0) { throw "git checkout failed for $name" }
        $actual = (git -C $destination rev-parse HEAD).Trim()
        if ($actual -ne $dependency.commit) {
            throw "$name checkout is $actual, expected $($dependency.commit)"
        }
    }
}
