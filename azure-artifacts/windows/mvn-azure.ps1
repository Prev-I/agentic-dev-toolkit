param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$MavenArgs
)

$ErrorActionPreference = 'Stop'
$targetFile = Join-Path $PSScriptRoot 'azure-artifacts-target.txt'
$script:CredentialTarget = if (Test-Path -LiteralPath $targetFile -PathType Leaf) {
    (Get-Content -LiteralPath $targetFile -Raw).Trim()
}
else {
    'agentic-dev-toolkit/AzureArtifacts'
}
Import-Module (Join-Path $PSScriptRoot 'AzureArtifactsCredential.psm1') -Force

function Get-MavenAzurePassword {
    $credential = Get-AzureArtifactsCredential -Target $script:CredentialTarget
    return $credential.GetNetworkCredential().Password
}

function Invoke-MavenAzure {
    param([string[]]$MavenArgs)

    if ($null -eq $MavenArgs) { $MavenArgs = @() }
    $maven = Get-Command mvn.cmd -ErrorAction Stop
    $password = Get-MavenAzurePassword
    try {
        $command = '$arguments=@((ConvertFrom-Json $env:ADT_MAVEN_ARGUMENTS)); & $env:ADT_MAVEN_COMMAND @arguments; exit $LASTEXITCODE'
        $encodedCommand = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
        $process = [Diagnostics.Process]::new()
        $process.StartInfo.FileName = [Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
        $process.StartInfo.Arguments = "-NoProfile -NonInteractive -EncodedCommand $encodedCommand"
        $process.StartInfo.UseShellExecute = $false
        $process.StartInfo.EnvironmentVariables['AZDO_MAVEN_PAT'] = $password
        $process.StartInfo.EnvironmentVariables['ADT_MAVEN_COMMAND'] = $maven.Source
        $process.StartInfo.EnvironmentVariables['ADT_MAVEN_ARGUMENTS'] = ConvertTo-Json @($MavenArgs) -Compress
        $null = $process.Start()
        $process.WaitForExit()
        return $process.ExitCode
    }
    finally { $password = $null }
}

if ($MyInvocation.InvocationName -ne '.') {
    exit (Invoke-MavenAzure -MavenArgs $MavenArgs)
}
