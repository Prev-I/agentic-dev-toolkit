[CmdletBinding(DefaultParameterSetName = 'Interactive')]
param(
    [Parameter(ParameterSetName = 'Stdin')]
    [switch]$PatStdin,

    [string]$SettingsPath = (Join-Path $env:USERPROFILE '.m2\settings.xml'),

    [string]$InstallDirectory = (Join-Path $env:USERPROFILE '.local\bin'),

    [string]$CredentialTarget = 'agentic-dev-toolkit/AzureArtifacts'
)

$ErrorActionPreference = 'Stop'
$userName = 'gewiss-resel'
$sourceDirectory = Join-Path $PSScriptRoot 'windows'
$credentialModuleName = 'AzureArtifactsCredential.psm1'
$wrapperName = 'mvn-azure.ps1'
$targetFileName = 'azure-artifacts-target.txt'

function Get-PlainTextCredential {
    if ($PatStdin) {
        return [Console]::In.ReadToEnd().TrimEnd("`r", "`n")
    }

    $secure = Read-Host 'Azure DevOps Packaging Read PAT' -AsSecureString
    $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try {
        return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer)
    }
    finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer)
    }
}

function Read-MavenSettings {
    param([Parameter(Mandatory = $true)][string]$Path)

    $rawSettings = Get-Content -LiteralPath $Path -Raw
    if ($rawSettings -match '<!DOCTYPE') {
        throw "Maven settings with DOCTYPE are not supported: $Path"
    }

    $document = [System.Xml.XmlDocument]::new()
    $document.XmlResolver = $null
    $document.PreserveWhitespace = $true
    $document.LoadXml($rawSettings)
    $server = @($document.SelectNodes(
        '/*[local-name()="settings"]/*[local-name()="servers"]/*[local-name()="server"][*[local-name()="id" and text()="Foundation"]]'
    ))
    if ($server.Count -ne 1) {
        throw "Expected exactly one Foundation Maven server, found $($server.Count): $Path"
    }
    $passwordNode = @($server[0].SelectNodes('*[local-name()="password"]'))
    if ($passwordNode.Count -ne 1) {
        throw "Expected exactly one Foundation Maven password, found $($passwordNode.Count): $Path"
    }

    return [pscustomobject]@{
        Document = $document
        PasswordNode = $passwordNode[0]
    }
}

function Set-FoundationPasswordReference {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)]$MavenSettings
    )

    $MavenSettings.PasswordNode.InnerText = '${env.AZDO_MAVEN_PAT}'

    $directory = Split-Path -Parent $Path
    $temporary = Join-Path $directory ('.settings.xml.azure-artifacts-' + [Guid]::NewGuid().ToString('N') + '.tmp')
    $backup = "$Path.pre-agentic-dev-toolkit"
    if (Test-Path -LiteralPath $backup) {
        throw "Maven settings rollback file already exists: $backup"
    }
    try {
        $MavenSettings.Document.Save($temporary)
        $validationDocument = [System.Xml.XmlDocument]::new()
        $validationDocument.XmlResolver = $null
        $validationDocument.Load($temporary)
        [IO.File]::Replace($temporary, $Path, $backup)
        return $backup
    }
    finally {
        Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue
    }
}

if (-not (Test-Path -LiteralPath $SettingsPath -PathType Leaf)) {
    throw "Maven settings file does not exist: $SettingsPath"
}
$mavenSettings = Read-MavenSettings -Path $SettingsPath
$settingsHash = (Get-FileHash -LiteralPath $SettingsPath -Algorithm SHA256).Hash

$password = Get-PlainTextCredential
if ([string]::IsNullOrWhiteSpace($password) -or $password -notmatch '^[A-Za-z0-9]+$') {
    throw 'PAT must be a non-empty alphanumeric value'
}
if ([Text.Encoding]::Unicode.GetByteCount($password) -gt 512) {
    throw 'PAT exceeds the Windows Generic Credential size limit'
}

if ((Get-FileHash -LiteralPath $SettingsPath -Algorithm SHA256).Hash -ne $settingsHash) {
    throw "Maven settings changed while waiting for credential input: $SettingsPath"
}

$installDirectoryExisted = Test-Path -LiteralPath $InstallDirectory -PathType Container
$transactionDirectory = Join-Path $env:TEMP ('azure-artifacts-install-' + [Guid]::NewGuid().ToString('N'))
$installedNames = @($credentialModuleName, $wrapperName, $targetFileName)
New-Item -ItemType Directory -Path $transactionDirectory | Out-Null
foreach ($name in $installedNames) {
    $destination = Join-Path $InstallDirectory $name
    if (Test-Path -LiteralPath $destination -PathType Leaf) {
        Copy-Item -LiteralPath $destination -Destination (Join-Path $transactionDirectory $name)
    }
}

try {
    New-Item -ItemType Directory -Path $InstallDirectory -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $sourceDirectory $credentialModuleName) -Destination $InstallDirectory -Force
    Copy-Item -LiteralPath (Join-Path $sourceDirectory $wrapperName) -Destination $InstallDirectory -Force
    Set-Content -LiteralPath (Join-Path $InstallDirectory $targetFileName) -Value $CredentialTarget -NoNewline
    Import-Module (Join-Path $InstallDirectory $credentialModuleName) -Force
    $backup = Set-FoundationPasswordReference -Path $SettingsPath -MavenSettings $mavenSettings
    try {
        Set-AzureArtifactsCredential -Target $CredentialTarget -UserName $userName -Password $password
    }
    catch {
        $discardedSettings = "$SettingsPath.failed-agentic-dev-toolkit"
        [IO.File]::Replace($backup, $SettingsPath, $discardedSettings)
        Remove-Item -LiteralPath $discardedSettings -Force
        foreach ($name in $installedNames) {
            $destination = Join-Path $InstallDirectory $name
            $saved = Join-Path $transactionDirectory $name
            if (Test-Path -LiteralPath $saved -PathType Leaf) {
                Copy-Item -LiteralPath $saved -Destination $destination -Force
            }
            else {
                Remove-Item -LiteralPath $destination -Force -ErrorAction SilentlyContinue
            }
        }
        if (-not $installDirectoryExisted) {
            Remove-Item -LiteralPath $InstallDirectory -Force -ErrorAction SilentlyContinue
        }
        throw
    }
    Remove-Item -LiteralPath $backup -Force
}
finally {
    $password = $null
    Remove-Item -LiteralPath $transactionDirectory -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Output 'Configured Windows-native Maven authentication.'
Write-Output "Run: & `"$InstallDirectory\$wrapperName`" -version"
