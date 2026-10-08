# Build Anomaly.Core.dll from a source tree that already contains the validated
# NTE Vehicle and NTE Attack Input host changes.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$adapter = 'src/game/ue5/ue5_nte_adapter.cpp'
$ntePath = 'include/anomaly/sdk/services/nte.h'
$policyPath = 'src/plugin/plugin_capability_policy.cpp'

foreach ($path in @($adapter, $ntePath, $policyPath)) {
    if (-not (Test-Path $path)) { throw "Missing source file: $path" }
}

$adapterText = Get-Content $adapter -Raw
$nteText = Get-Content $ntePath -Raw
$policyText = Get-Content $policyPath -Raw

foreach ($needle in @(
    'AnomalyNteVehicleServiceV1',
    'NteVehicleProfileAvailable',
    'AnomalyNteAttackInputServiceV1',
    'ANOMALY_NTE_ATTACK_INPUT_SERVICE_V1_ID',
    'ActivateMeleeInput',
    'ActivateAbilityFromID',
    'ReleaseAbilityFromID',
    'anomaly.nte.vehicle',
    'anomaly.nte.attack-input',
    '"nte-vehicle"',
    '"nte-attack-input"'
)) {
    if (($adapterText + $nteText + $policyText) -notmatch [regex]::Escape($needle)) {
        throw "Merged Core source is missing: $needle"
    }
}

Write-Host "Merged Core source sanity check passed."
Write-Host ("Adapter bytes: " + $adapterText.Length)
Write-Host ("NTE header bytes: " + $nteText.Length)
Write-Host ("Capability policy bytes: " + $policyText.Length)

$zip = Join-Path $env:RUNNER_TEMP 'llvm-mingw-20260922-msvcrt-x86_64.zip'
$root = Join-Path $env:RUNNER_TEMP 'llvm-mingw'
$url = 'https://github.com/mstorsjo/llvm-mingw/releases/download/20260922/llvm-mingw-20260922-msvcrt-x86_64.zip'
$expected = '1E936A4A694FC27F9625E3311F5EC5D6D99ABFEAA514FD41C52A4F8347145D1A'
Invoke-WebRequest -Uri $url -OutFile $zip
$actual = (Get-FileHash -Algorithm SHA256 $zip).Hash.ToUpperInvariant()
if ($actual -ne $expected) { throw "LLVM-MinGW SHA256 mismatch: $actual" }
if (Test-Path $root) { Remove-Item $root -Recurse -Force }
Expand-Archive -Path $zip -DestinationPath $root -Force
$top = Get-ChildItem $root -Directory | Select-Object -First 1
if ($null -eq $top) { throw 'LLVM-MinGW archive root not found.' }
$bin = Join-Path $top.FullName 'bin'
$env:PATH = $bin + ';' + $env:PATH

$build = Join-Path $env:GITHUB_WORKSPACE '.build/core-llvm'
if (Test-Path $build) { Remove-Item $build -Recurse -Force }

Write-Host "Configuring Core with native LLVM-MinGW."
cmake -S . -B $build -G 'MinGW Makefiles' -DCMAKE_BUILD_TYPE=RelWithDebInfo -DCMAKE_C_COMPILER="$bin/clang.exe" -DCMAKE_CXX_COMPILER="$bin/clang++.exe" -DCMAKE_ASM_MASM_COMPILER="$bin/llvm-ml.exe" -DCMAKE_RC_COMPILER="$bin/llvm-rc.exe" -DCMAKE_C_COMPILER_TARGET=x86_64-w64-windows-gnu -DCMAKE_CXX_COMPILER_TARGET=x86_64-w64-windows-gnu -DANOMALY_BUILD_SDK_EXAMPLES=OFF -DANOMALY_BUILD_BUILTIN_PLUGINS=OFF -DANOMALY_BUILD_TEST_PLUGINS=OFF -DANOMALY_BUILD_TEST_FIXTURES=OFF -DANOMALY_BUILD_SYMBOLS=OFF
if ($LASTEXITCODE -ne 0) { throw 'CMake configure failed.' }

Write-Host "Building anomaly_core."
cmake --build $build --target anomaly_core --parallel 2
if ($LASTEXITCODE -ne 0) { throw 'anomaly_core build failed.' }

$core = Get-ChildItem $build -Recurse -Filter 'Anomaly.Core.dll' -File | Select-Object -First 1 -ExpandProperty FullName
if ($null -eq $core) { throw 'Anomaly.Core.dll was not produced.' }
$size = (Get-Item $core).Length
if ($size -lt 1000000) { throw "Anomaly.Core.dll is unexpectedly small: $size bytes" }

$strings = & "$bin/llvm-strings.exe" $core
foreach ($needle in @('anomaly.nte.vehicle','anomaly.nte.attack-input')) {
    if (-not ($strings -contains $needle)) { throw "Service string missing from Core DLL: $needle" }
}

$hash = (Get-FileHash -Algorithm SHA256 $core).Hash
$out = Join-Path $env:GITHUB_WORKSPACE 'artifact'
New-Item -ItemType Directory -Path $out -Force | Out-Null
Copy-Item $core (Join-Path $out 'Anomaly.Core.dll') -Force
"$hash  Anomaly.Core.dll" | Set-Content (Join-Path $out 'SHA256SUMS.txt') -Encoding ascii

Write-Host "Anomaly.Core.dll: $core"
Write-Host "Size: $size"
Write-Host "SHA256: $hash"
