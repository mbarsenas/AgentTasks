#requires -Version 7.2
[CmdletBinding()]param(
    [Parameter(Mandatory)][string]$ConfigPath,
    [Parameter(Mandatory)][string]$Title,
    [Parameter(Mandatory)][string]$Message,
    [Parameter(Mandatory)][string]$TaskName
)
Set-StrictMode -Version Latest;$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'WickedOps.Common.psm1') -Force
$cfg=Get-Content $ConfigPath -Raw|ConvertFrom-Json;$to=[string]$cfg.Alert.EmailTo
if([string]::IsNullOrWhiteSpace($to)){throw 'Alert.EmailTo is empty in BusinessOps.config.json.'}
$secrets=Get-WickedOpsSecrets $ConfigPath;$token=Get-GoogleAccessToken $secrets
$safeTitle=($Title-replace '[\r\n]',' ');$safeMessage=$Message.Trim();$body=@"
WickedOps BusinessOps notification

Task: $TaskName
Computer: $env:COMPUTERNAME
Time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz')

$safeMessage

Logs: C:\WickedAdmin\BusinessOps\Logs
"@
$mime="To: $to`r`nSubject: $safeTitle`r`nMIME-Version: 1.0`r`nContent-Type: text/plain; charset=utf-8`r`n`r`n$body"
$raw=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($mime)).TrimEnd('=').Replace('+','-').Replace('/','_')
Invoke-GoogleApi -Token $token -Uri 'https://gmail.googleapis.com/gmail/v1/users/me/messages/send' -Method Post -Body @{raw=$raw}|Out-Null
Write-Host "Notification sent to $to for $TaskName."
