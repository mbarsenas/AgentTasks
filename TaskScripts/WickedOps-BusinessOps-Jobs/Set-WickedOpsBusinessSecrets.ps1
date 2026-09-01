#requires -Version 7.2
#requires -RunAsAdministrator
param([string]$BusinessOpsRoot='C:\WickedAdmin\BusinessOps')
Set-StrictMode -Version Latest;$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'WickedOps.Common.psm1') -Force
function Read-PlainSecret([string]$Prompt){$s=Read-Host $Prompt -AsSecureString;$b=[Runtime.InteropServices.Marshal]::SecureStringToBSTR($s);try{[Runtime.InteropServices.Marshal]::PtrToStringBSTR($b)}finally{[Runtime.InteropServices.Marshal]::ZeroFreeBSTR($b)}}
$clientId=Read-Host 'Google OAuth desktop-app Client ID'
$clientSecret=Read-PlainSecret 'Google OAuth Client Secret'
$refreshToken=Read-PlainSecret 'Google OAuth Refresh Token (Gmail + Search Console scopes)'
foreach($pair in @{GoogleClientId=$clientId;GoogleClientSecret=$clientSecret;GoogleRefreshToken=$refreshToken}.GetEnumerator()){if([string]::IsNullOrWhiteSpace($pair.Value)){throw "$($pair.Key) cannot be empty."}}
$dir=Join-Path $BusinessOpsRoot 'Secrets';New-Item $dir -ItemType Directory -Force|Out-Null;$path=Join-Path $dir 'BusinessOpsSecrets.json'
[ordered]@{FormatVersion=1;Scope='LocalMachine';CreatedUtc=[DateTime]::UtcNow.ToString('o');Values=[ordered]@{GoogleClientId=Protect-WickedOpsValue $clientId;GoogleClientSecret=Protect-WickedOpsValue $clientSecret;GoogleRefreshToken=Protect-WickedOpsValue $refreshToken}}|ConvertTo-Json -Depth 5|Set-Content $path -Encoding utf8
$svc="$env:COMPUTERNAME\WickedOpsSvc";& icacls.exe $dir /inheritance:r|Out-Null;& icacls.exe $dir /grant:r 'SYSTEM:(OI)(CI)F' 'BUILTIN\Administrators:(OI)(CI)F' "${svc}:(OI)(CI)RX" /T /C|Out-Null
if($LASTEXITCODE -ne 0){throw 'Failed to secure the BusinessOps Secrets directory.'}
Write-Host "Encrypted OAuth secrets saved to $path" -ForegroundColor Green
