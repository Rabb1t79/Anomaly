$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Add-Type -AssemblyName System.Security

$secureKey = $null
$bstr = [IntPtr]::Zero
$keyBytes = [byte[]]::new(64)
$digest = $null
$protectedBytes = $null
$sha = $null

try {
    $secureKey = Read-Host -AsSecureString 'Choose a NEW private 64-character hexadecimal Debug key (input is hidden)'
    if ($secureKey.Length -ne 64) { throw 'The Debug key must contain exactly 64 hexadecimal characters.' }

    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureKey)
    for ($i = 0; $i -lt 64; $i++) {
        $code = [int][Runtime.InteropServices.Marshal]::ReadInt16($bstr, 2 * $i)
        $valid = ($code -ge 48 -and $code -le 57) -or ($code -ge 97 -and $code -le 102) -or ($code -ge 65 -and $code -le 70)
        if (-not $valid) { throw 'The Debug key must contain only hexadecimal characters (0-9, A-F).' }
        $keyBytes[$i] = [byte]$code
    }

    $sha = [System.Security.Cryptography.SHA256]::Create()
    $digest = $sha.ComputeHash($keyBytes)
    $protectedBytes = [System.Security.Cryptography.ProtectedData]::Protect(
        $digest, $null, [System.Security.Cryptography.DataProtectionScope]::CurrentUser)

    $directory = Join-Path $env:LOCALAPPDATA 'Anomaly'
    New-Item -ItemType Directory -Force -Path $directory | Out-Null
    $path = Join-Path $directory 'vehicle-debug-key.dat'
    [System.IO.File]::WriteAllBytes($path, $protectedBytes)

    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $acl = New-Object System.Security.AccessControl.FileSecurity
    $acl.SetAccessRuleProtection($true, $false)
    $rule = [System.Security.AccessControl.FileSystemAccessRule]::new(
        $identity.User,
        [System.Security.AccessControl.FileSystemRights]::FullControl,
        [System.Security.AccessControl.AccessControlType]::Allow)
    $acl.SetAccessRule($rule)
    Set-Acl -LiteralPath $path -AclObject $acl

    Write-Output 'Private DEBUG verifier configured for the current Windows user.'
    Write-Output 'The chosen key and verifier digest were not printed.'
}
finally {
    if ($null -ne $sha) { $sha.Dispose() }
    if ($null -ne $keyBytes) { [Array]::Clear($keyBytes, 0, $keyBytes.Length) }
    if ($null -ne $digest) { [Array]::Clear($digest, 0, $digest.Length) }
    if ($null -ne $protectedBytes) { [Array]::Clear($protectedBytes, 0, $protectedBytes.Length) }
    if ($bstr -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
    if ($null -ne $secureKey) { $secureKey.Dispose() }
}
