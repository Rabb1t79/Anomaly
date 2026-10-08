# Build the Anomaly Core DLL with the validated NTE Vehicle and Attack Input host changes.
# This script runs on the Windows 2022 GitHub runner only; it does not access private dumps.

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

Write-Host "== source =="
git rev-parse HEAD

$adapter = 'src/game/ue5/ue5_nte_adapter.cpp'
$ntePath = 'include/anomaly/sdk/services/nte.h'
$policyPath = 'src/plugin/plugin_capability_policy.cpp'

foreach ($path in @($adapter, $ntePath, $policyPath)) {
    if (-not (Test-Path $path)) { throw "Missing source file: $path" }
}

Write-Host "== patch adapter =="
$adapterPatches = @(
    'build_patches/vehicle.patch',
    'build_patches/attack_ab434.patch',
    'build_patches/attack_4a.patch',
    'build_patches/attack_e9.patch',
    'build_patches/attack_343e.patch'
)
foreach ($patch in $adapterPatches) {
    if (-not (Test-Path $patch)) { throw "Missing patch: $patch" }
    git apply --check $patch
    if ($LASTEXITCODE -ne 0) { throw "Patch check failed: $patch" }
    git apply $patch
    if ($LASTEXITCODE -ne 0) { throw "Patch apply failed: $patch" }
}

Write-Host "== insert ABI =="
$nte = Get-Content $ntePath -Raw

if ($nte -notmatch [regex]::Escape('AnomalyNteVehicleServiceV1')) {
    if ($nte -notmatch [regex]::Escape('ANOMALY_NTE_VEHICLE_SERVICE_V1_ID')) {
        $anchor = '#define ANOMALY_NTE_PICKUP_SERVICE_V1_VERSION 1u'
        if (-not $nte.Contains($anchor)) { throw 'Vehicle service ID anchor not found.' }
        $text = @'
#define ANOMALY_NTE_VEHICLE_SERVICE_V1_ID "anomaly.nte.vehicle"
#define ANOMALY_NTE_VEHICLE_SERVICE_V1_VERSION 1u
'@
        $nte = $nte.Replace($anchor, $anchor + [Environment]::NewLine + $text.TrimEnd())
    }

    $anchor = '} AnomalyNteNavigationServiceV1;'
    if (-not $nte.Contains($anchor)) { throw 'Vehicle service struct anchor not found.' }
    $text = @'
// Host-owned UE5 vehicle bridge. The Host resolves the current driving vehicle
// and validates reflected function/property metadata before any mutation. No UE
// object pointer crosses the plugin ABI. Mutations are Game-thread operations.
typedef uint32_t AnomalyNteVehicleFlagsV1;
#define ANOMALY_NTE_VEHICLE_V1_VALID (1u << 0u)
#define ANOMALY_NTE_VEHICLE_V1_HAS_SPEED (1u << 1u)
#define ANOMALY_NTE_VEHICLE_V1_HAS_TOP_SPEED_RATIO (1u << 2u)
#define ANOMALY_NTE_VEHICLE_V1_HAS_WHEEL_FRICTION (1u << 3u)
#define ANOMALY_NTE_VEHICLE_V1_HAS_SUMMON (1u << 4u)

typedef struct AnomalyNteVehicleSnapshotV1 {
    uint32_t struct_size;
    uint32_t flags;
    AnomalyGenerationHandleV1 vehicle;
    double speed_kmh;
    float top_speed_ratio;
    uint32_t wheel_friction_enabled;
} AnomalyNteVehicleSnapshotV1;

typedef struct AnomalyNteVehicleServiceV1 {
    uint32_t struct_size; uint32_t service_version; void* user;
    AnomalyStatusV1 (ANOMALY_CALL *snapshot)(
        void* user, AnomalyNteVehicleSnapshotV1* snapshot);
    AnomalyStatusV1 (ANOMALY_CALL *set_top_speed_ratio)(
        void* user, float ratio);
    AnomalyStatusV1 (ANOMALY_CALL *set_wheel_friction_enabled)(
        void* user, uint32_t enabled);
    AnomalyStatusV1 (ANOMALY_CALL *reset)(void* user);
    AnomalyStatusV1 (ANOMALY_CALL *summon_vehicle)(void* user);
    AnomalyStatusV1 (ANOMALY_CALL *vehicle_id_count)(void* user, uint32_t* count);
    AnomalyStatusV1 (ANOMALY_CALL *vehicle_id_at)(
        void* user, uint32_t index, char* destination, size_t* inout_size);
    AnomalyStatusV1 (ANOMALY_CALL *set_summon_vehicle_id)(
        void* user, AnomalyStringViewV1 vehicle_id);
} AnomalyNteVehicleServiceV1;
'@
    $nte = $nte.Replace($anchor, $anchor + [Environment]::NewLine + $text.TrimEnd())
}

if ($nte -notmatch [regex]::Escape('AnomalyNteAttackInputServiceV1')) {
    $anchor = '#define ANOMALY_NTE_SKILL_INVOCATION_SERVICE_V1_VERSION 1u'
    if (-not $nte.Contains($anchor)) { throw 'Attack input service anchor not found.' }
    $text = @'
#define ANOMALY_NTE_ATTACK_INPUT_SERVICE_V1_ID "anomaly.nte.attack-input"
#define ANOMALY_NTE_ATTACK_INPUT_SERVICE_V1_VERSION 1u
typedef struct AnomalyNteAttackInputServiceV1 {
    uint32_t struct_size; uint32_t service_version; void* user;
    // Host-side bridge validated against the HTPlayerController attack-input ABI.
    AnomalyStatusV1 (ANOMALY_CALL *activate_melee)(void* user);
} AnomalyNteAttackInputServiceV1;
'@
    $nte = $nte.Replace($anchor, $anchor + [Environment]::NewLine + $text.TrimEnd())
}

Set-Content $ntePath $nte -NoNewline -Encoding utf8

Write-Host "== insert capability policy =="
$policy = Get-Content $policyPath -Raw
if ($policy -notmatch [regex]::Escape('"nte-vehicle"')) {
    $policy = $policy.Replace(
        'constexpr std::array<std::string_view, 44> kKnownCapabilities',
        'constexpr std::array<std::string_view, 45> kKnownCapabilities')
    $policy = $policy.Replace(
        'constexpr std::array<ServiceCapabilityMapping, 44> kServiceCapabilities',
        'constexpr std::array<ServiceCapabilityMapping, 45> kServiceCapabilities')
    $policy = $policy.Replace(
        '    "nte-navigation",',
        '    "nte-navigation",' + [Environment]::NewLine + '    "nte-vehicle",')
    $policy = $policy.Replace(
        '    {"anomaly.nte.navigation", "nte-navigation"},',
        '    {"anomaly.nte.navigation", "nte-navigation"},' + [Environment]::NewLine + '    {"anomaly.nte.vehicle", "nte-vehicle"},')
}
if ($policy -notmatch [regex]::Escape('"nte-attack-input"')) {
    $policy = $policy.Replace(
        'constexpr std::array<std::string_view, 45> kKnownCapabilities',
        'constexpr std::array<std::string_view, 46> kKnownCapabilities')
    $policy = $policy.Replace(
        'constexpr std::array<ServiceCapabilityMapping, 45> kServiceCapabilities',
        'constexpr std::array<ServiceCapabilityMapping, 46> kServiceCapabilities')
    $policy = $policy.Replace(
        '    "nte-skill-invocation",',
        '    "nte-skill-invocation",' + [Environment]::NewLine + '    "nte-attack-input",')
    $policy = $policy.Replace(
        '    {"anomaly.nte.skill-invocation", "nte-skill-invocation"},',
        '    {"anomaly.nte.skill-invocation", "nte-skill-invocation"},' + [Environment]::NewLine + '    {"anomaly.nte.attack-input", "nte-attack-input"},')
}
if ($policy -notmatch [regex]::Escape('"nte-vehicle"')) { throw 'Vehicle capability was not inserted.' }
if ($policy -notmatch [regex]::Escape('"nte-attack-input"')) { throw 'Attack capability was not inserted.' }
Set-Content $policyPath $policy -NoNewline -Encoding utf8

Write-Host "== source sanity =="
$all = (Get-Content $adapter -Raw) + $nte + $policy
foreach ($needle in @(
    'AnomalyNteVehicleServiceV1',
    'ANOMALY_NTE_ATTACK_INPUT_SERVICE_V1_ID',
    'ActivateAbilityFromID',
    'ReleaseAbilityFromID',
    'ActivateMeleeInput',
    'NteVehicleProfileAvailable',
    'anomaly.nte.attack-input'
)) {
    if ($all -notmatch [regex]::Escape($needle)) { throw "Missing expected symbol: $needle" }
}

Write-Host "== LLVM-MinGW 20260922 =="
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

Write-Host "== configure =="
$build = Join-Path $env:GITHUB_WORKSPACE '.build/core-llvm'
if (Test-Path $build) { Remove-Item $build -Recurse -Force }
cmake -S . -B $build -G 'MinGW Makefiles' -DCMAKE_BUILD_TYPE=RelWithDebInfo -DCMAKE_C_COMPILER="$bin/clang.exe" -DCMAKE_CXX_COMPILER="$bin/clang++.exe" -DCMAKE_ASM_MASM_COMPILER="$bin/llvm-ml.exe" -DCMAKE_RC_COMPILER="$bin/llvm-rc.exe" -DCMAKE_C_COMPILER_TARGET=x86_64-w64-windows-gnu -DCMAKE_CXX_COMPILER_TARGET=x86_64-w64-windows-gnu -DANOMALY_BUILD_SDK_EXAMPLES=OFF -DANOMALY_BUILD_BUILTIN_PLUGINS=OFF -DANOMALY_BUILD_TEST_PLUGINS=OFF -DANOMALY_BUILD_TEST_FIXTURES=OFF -DANOMALY_BUILD_SYMBOLS=OFF
if ($LASTEXITCODE -ne 0) { throw 'CMake configure failed.' }

Write-Host "== build Core =="
cmake --build $build --target anomaly_core --parallel 2
if ($LASTEXITCODE -ne 0) { throw 'Core build failed.' }

Write-Host "== validate Core =="
$core = Get-ChildItem $build -Recurse -Filter 'Anomaly.Core.dll' -File | Select-Object -First 1 -ExpandProperty FullName
if ($null -eq $core) { throw 'Anomaly.Core.dll was not produced.' }
$size = (Get-Item $core).Length
if ($size -lt 1000000) { throw "Core DLL is unexpectedly small: $size bytes" }
$strings = & "$bin/llvm-strings.exe" $core
foreach ($needle in @('anomaly.nte.vehicle','anomaly.nte.attack-input')) {
    if (-not ($strings -contains $needle)) { throw "Core DLL is missing service string: $needle" }
}
$hash = (Get-FileHash -Algorithm SHA256 $core).Hash
$out = Join-Path $env:GITHUB_WORKSPACE 'artifact'
New-Item -ItemType Directory -Path $out -Force | Out-Null
Copy-Item $core (Join-Path $out 'Anomaly.Core.dll') -Force
"$hash  Anomaly.Core.dll" | Set-Content (Join-Path $out 'SHA256SUMS.txt') -Encoding ascii
Write-Host "Core DLL: $core"
Write-Host "Core size: $size"
Write-Host "Core SHA256: $hash"
