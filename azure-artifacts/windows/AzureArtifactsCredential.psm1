$ErrorActionPreference = 'Stop'

if (-not ('AzureArtifacts.NativeCredentialManager' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

namespace AzureArtifacts {
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct NativeCredential {
        public UInt32 Flags;
        public UInt32 Type;
        public string TargetName;
        public string Comment;
        public System.Runtime.InteropServices.ComTypes.FILETIME LastWritten;
        public UInt32 CredentialBlobSize;
        public IntPtr CredentialBlob;
        public UInt32 Persist;
        public UInt32 AttributeCount;
        public IntPtr Attributes;
        public string TargetAlias;
        public string UserName;
    }

    public static class NativeCredentialManager {
        [DllImport("advapi32.dll", EntryPoint = "CredWriteW", CharSet = CharSet.Unicode, SetLastError = true)]
        public static extern bool CredWrite(ref NativeCredential credential, UInt32 flags);

        [DllImport("advapi32.dll", EntryPoint = "CredReadW", CharSet = CharSet.Unicode, SetLastError = true)]
        public static extern bool CredRead(string target, UInt32 type, UInt32 flags, out IntPtr credential);

        [DllImport("advapi32.dll", EntryPoint = "CredDeleteW", CharSet = CharSet.Unicode, SetLastError = true)]
        public static extern bool CredDelete(string target, UInt32 type, UInt32 flags);

        [DllImport("advapi32.dll", SetLastError = true)]
        public static extern void CredFree(IntPtr buffer);
    }
}
'@
}

function Set-AzureArtifactsCredential {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Target,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password
    )

    $blobSize = [Text.Encoding]::Unicode.GetByteCount($Password)
    if ($blobSize -gt 512) {
        throw 'Credential exceeds the Windows Generic Credential size limit'
    }
    $blob = [Runtime.InteropServices.Marshal]::StringToCoTaskMemUni($Password)
    try {
        $credential = [AzureArtifacts.NativeCredential]@{
            Type = 1
            TargetName = $Target
            CredentialBlobSize = $blobSize
            CredentialBlob = $blob
            Persist = 2
            UserName = $UserName
        }
        if (-not [AzureArtifacts.NativeCredentialManager]::CredWrite([ref]$credential, 0)) {
            throw [ComponentModel.Win32Exception]::new([Runtime.InteropServices.Marshal]::GetLastWin32Error())
        }
    }
    finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeCoTaskMemUnicode($blob)
    }
}

function Get-AzureArtifactsCredential {
    [CmdletBinding()]
    param([string]$Target = 'agentic-dev-toolkit/AzureArtifacts')

    $pointer = [IntPtr]::Zero
    if (-not [AzureArtifacts.NativeCredentialManager]::CredRead($Target, 1, 0, [ref]$pointer)) {
        throw [ComponentModel.Win32Exception]::new([Runtime.InteropServices.Marshal]::GetLastWin32Error())
    }
    try {
        $credential = [Runtime.InteropServices.Marshal]::PtrToStructure(
            $pointer,
            [type][AzureArtifacts.NativeCredential]
        )
        if ($credential.CredentialBlobSize % 2 -ne 0) {
            throw 'Credential blob has an invalid UTF-16 byte length'
        }
        $plainText = [Runtime.InteropServices.Marshal]::PtrToStringUni(
            $credential.CredentialBlob,
            [int]($credential.CredentialBlobSize / 2)
        )
        try {
            $securePassword = ConvertTo-SecureString $plainText -AsPlainText -Force
            return [Management.Automation.PSCredential]::new($credential.UserName, $securePassword)
        }
        finally {
            $plainText = $null
        }
    }
    finally {
        [AzureArtifacts.NativeCredentialManager]::CredFree($pointer)
    }
}

function Remove-AzureArtifactsCredential {
    [CmdletBinding()]
    param([string]$Target = 'agentic-dev-toolkit/AzureArtifacts')

    if (-not [AzureArtifacts.NativeCredentialManager]::CredDelete($Target, 1, 0)) {
        $errorCode = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
        if ($errorCode -ne 1168) {
            throw [ComponentModel.Win32Exception]::new($errorCode)
        }
    }
}

Export-ModuleMember -Function Set-AzureArtifactsCredential, Get-AzureArtifactsCredential, Remove-AzureArtifactsCredential
