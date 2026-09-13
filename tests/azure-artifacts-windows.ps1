$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$configurator = Join-Path $repositoryRoot 'azure-artifacts\configure-windows.ps1'
$sourceModule = Join-Path $repositoryRoot 'azure-artifacts\windows\AzureArtifactsCredential.psm1'
$sourceWrapper = Join-Path $repositoryRoot 'azure-artifacts\windows\mvn-azure.ps1'
$temporary = Join-Path $env:TEMP ('azure-artifacts-windows-test-' + [Guid]::NewGuid().ToString('N'))
$settings = Join-Path $temporary 'settings.xml'
$installDirectory = Join-Path $temporary 'bin'
$credentialTarget = 'agentic-dev-toolkit/AzureArtifacts-test-' + [Guid]::NewGuid().ToString('N')
$invalidSettings = Join-Path $temporary 'invalid-settings.xml'
$invalidInstallDirectory = Join-Path $temporary 'invalid-bin'
$invalidCredentialTarget = $credentialTarget + '-invalid'
$doctypeSettings = Join-Path $temporary 'doctype-settings.xml'
$doctypeInstallDirectory = Join-Path $temporary 'doctype-bin'
$doctypeCredentialTarget = $credentialTarget + '-doctype'
$writeFailureSettings = Join-Path $temporary 'write-failure-settings.xml'
$writeFailureInstallDirectory = Join-Path $temporary 'write-failure-bin'
$powershell = (Get-Command powershell.exe -ErrorAction Stop).Source

New-Item -ItemType Directory -Path $temporary | Out-Null
@'
<?xml version="1.0" encoding="UTF-8"?>
<settings><servers><server><id>Foundation</id><username>test</username><password>oldSyntheticValue</password></server></servers></settings>
'@ | Set-Content -LiteralPath $settings -Encoding UTF8
@'
<?xml version="1.0" encoding="UTF-8"?>
<settings><servers></servers></settings>
'@ | Set-Content -LiteralPath $invalidSettings -Encoding UTF8
@'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE settings [<!ENTITY test "synthetic">]>
<settings><servers><server><id>Foundation</id><username>test</username><password>&test;</password></server></servers></settings>
'@ | Set-Content -LiteralPath $doctypeSettings -Encoding UTF8
Copy-Item -LiteralPath $settings -Destination $writeFailureSettings

try {
    $process = [Diagnostics.Process]::new()
    $process.StartInfo.FileName = $powershell
    $process.StartInfo.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$configurator`" -PatStdin -SettingsPath `"$settings`" -InstallDirectory `"$installDirectory`" -CredentialTarget `"$credentialTarget`""
    $process.StartInfo.UseShellExecute = $false
    $process.StartInfo.RedirectStandardInput = $true
    $process.StartInfo.RedirectStandardOutput = $true
    $process.StartInfo.RedirectStandardError = $true
    $null = $process.Start()
    $process.StandardInput.Write('newSyntheticValue')
    $process.StandardInput.Close()
    $standardOutput = $process.StandardOutput.ReadToEnd()
    $standardError = $process.StandardError.ReadToEnd()
    $process.WaitForExit()
    if ($process.ExitCode -ne 0) { throw "Configurator failed: $standardError" }
    if ($standardOutput -notmatch 'Configured Windows-native Maven authentication') {
        throw 'Configurator success output is missing'
    }

    [xml]$document = Get-Content -LiteralPath $settings -Raw
    if ($document.settings.servers.server.password -ne '${env.AZDO_MAVEN_PAT}') {
        throw 'Windows Maven settings did not receive the environment reference'
    }
    if (-not (Test-Path -LiteralPath (Join-Path $installDirectory 'mvn-azure.ps1') -PathType Leaf)) {
        throw 'Windows Maven wrapper was not installed'
    }
    if ((Get-Content -LiteralPath (Join-Path $installDirectory 'azure-artifacts-target.txt') -Raw) -ne $credentialTarget) {
        throw 'Installed wrapper credential target does not match the configured target'
    }
    if (Test-Path -LiteralPath "$settings.pre-agentic-dev-toolkit") {
        throw 'Successful migration retained a plaintext rollback file'
    }

    Import-Module $sourceModule -Force
    $credential = Get-AzureArtifactsCredential -Target $credentialTarget
    if ($credential.UserName -ne 'gewiss-resel') { throw 'Credential username did not round-trip' }
    if ($credential.GetNetworkCredential().Password -ne 'newSyntheticValue') {
        throw 'Credential password did not round-trip'
    }

    @'
@echo off
if not "%AZDO_MAVEN_PAT%"=="newSyntheticValue" exit /b 42
echo WRAPPER_OUTPUT:%*
exit /b 23
'@ | Set-Content -LiteralPath (Join-Path $installDirectory 'mvn.cmd') -Encoding ASCII
    $wrapperProcess = [Diagnostics.Process]::new()
    $wrapperProcess.StartInfo.FileName = (Get-Command powershell.exe -ErrorAction Stop).Source
    $wrapperProcess.StartInfo.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$(Join-Path $installDirectory 'mvn-azure.ps1')`" -B -version"
    $wrapperProcess.StartInfo.UseShellExecute = $false
    $wrapperProcess.StartInfo.RedirectStandardOutput = $true
    $wrapperProcess.StartInfo.RedirectStandardError = $true
    $wrapperProcess.StartInfo.EnvironmentVariables['PATH'] = "$installDirectory;$($wrapperProcess.StartInfo.EnvironmentVariables['PATH'])"
    $wrapperProcess.StartInfo.EnvironmentVariables.Remove('AZDO_MAVEN_PAT')
    $userCredentialBefore = [Environment]::GetEnvironmentVariable('AZDO_MAVEN_PAT', 'User')
    $machineCredentialBefore = [Environment]::GetEnvironmentVariable('AZDO_MAVEN_PAT', 'Machine')
    $null = $wrapperProcess.Start()
    $wrapperOutput = $wrapperProcess.StandardOutput.ReadToEnd()
    $wrapperError = $wrapperProcess.StandardError.ReadToEnd()
    $wrapperProcess.WaitForExit()
    if ($wrapperProcess.ExitCode -ne 23) { throw "Expected Maven exit 23, got $($wrapperProcess.ExitCode): $wrapperError" }
    if ($wrapperOutput -notmatch 'WRAPPER_OUTPUT:-B -version') { throw 'Installed wrapper did not preserve Maven output or arguments' }
    if ([Environment]::GetEnvironmentVariable('AZDO_MAVEN_PAT', 'User') -ne $userCredentialBefore) {
        throw 'Wrapper changed the persistent user environment'
    }
    if ([Environment]::GetEnvironmentVariable('AZDO_MAVEN_PAT', 'Machine') -ne $machineCredentialBefore) {
        throw 'Wrapper changed the persistent machine environment'
    }

    $zeroArgumentProcess = [Diagnostics.Process]::new()
    $zeroArgumentProcess.StartInfo.FileName = (Get-Command powershell.exe -ErrorAction Stop).Source
    $zeroArgumentProcess.StartInfo.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$(Join-Path $installDirectory 'mvn-azure.ps1')`""
    $zeroArgumentProcess.StartInfo.UseShellExecute = $false
    $zeroArgumentProcess.StartInfo.RedirectStandardOutput = $true
    $zeroArgumentProcess.StartInfo.RedirectStandardError = $true
    $zeroArgumentProcess.StartInfo.EnvironmentVariables['PATH'] = "$installDirectory;$($zeroArgumentProcess.StartInfo.EnvironmentVariables['PATH'])"
    $null = $zeroArgumentProcess.Start()
    $zeroArgumentOutput = $zeroArgumentProcess.StandardOutput.ReadToEnd()
    $zeroArgumentError = $zeroArgumentProcess.StandardError.ReadToEnd()
    $zeroArgumentProcess.WaitForExit()
    if ($zeroArgumentProcess.ExitCode -ne 23) { throw "Zero-argument wrapper exited $($zeroArgumentProcess.ExitCode): $zeroArgumentError" }
    if ($zeroArgumentOutput.Trim() -ne 'WRAPPER_OUTPUT:') { throw 'Zero-argument wrapper passed a spurious Maven argument' }

    $invalidProcess = [Diagnostics.Process]::new()
    $invalidProcess.StartInfo.FileName = $powershell
    $invalidProcess.StartInfo.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$configurator`" -PatStdin -SettingsPath `"$invalidSettings`" -InstallDirectory `"$invalidInstallDirectory`" -CredentialTarget `"$invalidCredentialTarget`""
    $invalidProcess.StartInfo.UseShellExecute = $false
    $invalidProcess.StartInfo.RedirectStandardInput = $true
    $invalidProcess.StartInfo.RedirectStandardOutput = $true
    $invalidProcess.StartInfo.RedirectStandardError = $true
    $null = $invalidProcess.Start()
    $invalidProcess.StandardInput.Write('newSyntheticValue')
    $invalidProcess.StandardInput.Close()
    $null = $invalidProcess.StandardOutput.ReadToEnd()
    $null = $invalidProcess.StandardError.ReadToEnd()
    $invalidProcess.WaitForExit()
    if ($invalidProcess.ExitCode -eq 0) { throw 'Invalid Maven settings must fail configuration' }
    if (Test-Path -LiteralPath $invalidInstallDirectory) { throw 'Preflight failure installed Windows scripts' }
    try {
        $null = Get-AzureArtifactsCredential -Target $invalidCredentialTarget
        throw 'Preflight failure stored a Windows credential'
    }
    catch [ComponentModel.Win32Exception] {
        if ($_.Exception.NativeErrorCode -ne 1168) { throw }
    }

    $writeFailureOriginalHash = (Get-FileHash -LiteralPath $writeFailureSettings -Algorithm SHA256).Hash
    $writeFailureProcess = [Diagnostics.Process]::new()
    $writeFailureProcess.StartInfo.FileName = $powershell
    $writeFailureProcess.StartInfo.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$configurator`" -PatStdin -SettingsPath `"$writeFailureSettings`" -InstallDirectory `"$writeFailureInstallDirectory`" -CredentialTarget `"`""
    $writeFailureProcess.StartInfo.UseShellExecute = $false
    $writeFailureProcess.StartInfo.RedirectStandardInput = $true
    $writeFailureProcess.StartInfo.RedirectStandardOutput = $true
    $writeFailureProcess.StartInfo.RedirectStandardError = $true
    $null = $writeFailureProcess.Start()
    $writeFailureProcess.StandardInput.Write('newSyntheticValue')
    $writeFailureProcess.StandardInput.Close()
    $null = $writeFailureProcess.StandardOutput.ReadToEnd()
    $null = $writeFailureProcess.StandardError.ReadToEnd()
    $writeFailureProcess.WaitForExit()
    if ($writeFailureProcess.ExitCode -eq 0) { throw 'Credential write failure must fail configuration' }
    $writeFailureRestoredHash = (Get-FileHash -LiteralPath $writeFailureSettings -Algorithm SHA256).Hash
    if ($writeFailureRestoredHash -ne $writeFailureOriginalHash) {
        throw "Credential-write failure did not restore Maven settings: before=$writeFailureOriginalHash after=$writeFailureRestoredHash"
    }
    if (Test-Path -LiteralPath $writeFailureInstallDirectory) {
        throw 'Credential-write failure installed Windows scripts'
    }
    if (Test-Path -LiteralPath "$writeFailureSettings.pre-agentic-dev-toolkit") {
        throw 'Credential-write failure retained a plaintext rollback file'
    }

    $doctypeProcess = [Diagnostics.Process]::new()
    $doctypeProcess.StartInfo.FileName = (Get-Command powershell.exe -ErrorAction Stop).Source
    $doctypeProcess.StartInfo.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$configurator`" -PatStdin -SettingsPath `"$doctypeSettings`" -InstallDirectory `"$doctypeInstallDirectory`" -CredentialTarget `"$doctypeCredentialTarget`""
    $doctypeProcess.StartInfo.UseShellExecute = $false
    $doctypeProcess.StartInfo.RedirectStandardInput = $true
    $doctypeProcess.StartInfo.RedirectStandardOutput = $true
    $doctypeProcess.StartInfo.RedirectStandardError = $true
    $null = $doctypeProcess.Start()
    $doctypeProcess.StandardInput.Write('newSyntheticValue')
    $doctypeProcess.StandardInput.Close()
    $null = $doctypeProcess.StandardOutput.ReadToEnd()
    $null = $doctypeProcess.StandardError.ReadToEnd()
    $doctypeProcess.WaitForExit()
    if ($doctypeProcess.ExitCode -eq 0) { throw 'DOCTYPE Maven settings must fail configuration' }
    if (Test-Path -LiteralPath $doctypeInstallDirectory) { throw 'DOCTYPE preflight installed Windows scripts' }
    try {
        $null = Get-AzureArtifactsCredential -Target $doctypeCredentialTarget
        throw 'DOCTYPE preflight stored a Windows credential'
    }
    catch [ComponentModel.Win32Exception] {
        if ($_.Exception.NativeErrorCode -ne 1168) { throw }
    }

    'PASS: Windows Azure Artifacts tests'
}
finally {
    Remove-Item Env:AZDO_MAVEN_PAT -ErrorAction SilentlyContinue
    Import-Module $sourceModule -Force
    Remove-AzureArtifactsCredential -Target $credentialTarget -ErrorAction SilentlyContinue
    Remove-AzureArtifactsCredential -Target $invalidCredentialTarget -ErrorAction SilentlyContinue
    Remove-AzureArtifactsCredential -Target $doctypeCredentialTarget -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $temporary -Recurse -Force -ErrorAction SilentlyContinue
}
