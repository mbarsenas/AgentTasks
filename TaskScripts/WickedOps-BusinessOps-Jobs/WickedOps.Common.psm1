Set-StrictMode -Version Latest

function Write-WickedOpsLog {
    param([Parameter(Mandatory)][string]$LogPath,[Parameter(Mandatory)][string]$Message,[ValidateSet('INFO','WARN','ERROR')][string]$Level='INFO')
    $line = '{0:o} [{1}] {2}' -f (Get-Date),$Level,$Message
    Add-Content -LiteralPath $LogPath -Value $line -Encoding utf8
    Write-Host $line
}

function Get-WickedOpsRoot { param([string]$ConfigPath) Split-Path -Parent $ConfigPath }

function Protect-WickedOpsValue {
    param([Parameter(Mandatory)][string]$Value)
    $plain=[Text.Encoding]::UTF8.GetBytes($Value); $entropy=[Text.Encoding]::UTF8.GetBytes('WickedOpsBusinessOps/v1')
    try { [Convert]::ToBase64String([Security.Cryptography.ProtectedData]::Protect($plain,$entropy,[Security.Cryptography.DataProtectionScope]::LocalMachine)) }
    finally { [Array]::Clear($plain,0,$plain.Length) }
}

function Unprotect-WickedOpsValue {
    param([Parameter(Mandatory)][string]$Value)
    $cipher=[Convert]::FromBase64String($Value); $entropy=[Text.Encoding]::UTF8.GetBytes('WickedOpsBusinessOps/v1'); $plain=$null
    try { $plain=[Security.Cryptography.ProtectedData]::Unprotect($cipher,$entropy,[Security.Cryptography.DataProtectionScope]::LocalMachine); [Text.Encoding]::UTF8.GetString($plain) }
    finally { if($plain){[Array]::Clear($plain,0,$plain.Length)}; [Array]::Clear($cipher,0,$cipher.Length) }
}

function Get-WickedOpsSecrets {
    param([Parameter(Mandatory)][string]$ConfigPath)
    $path=Join-Path (Get-WickedOpsRoot $ConfigPath) 'Secrets\BusinessOpsSecrets.json'
    if(-not(Test-Path -LiteralPath $path)){ throw "BusinessOps OAuth secrets are not configured. Run Set-WickedOpsBusinessSecrets.ps1 as Administrator." }
    $doc=Get-Content -LiteralPath $path -Raw|ConvertFrom-Json
    $out=@{}
    foreach($p in $doc.Values.PSObject.Properties){ $out[$p.Name]=Unprotect-WickedOpsValue ([string]$p.Value) }
    $out
}

function Get-GoogleAccessToken {
    param([Parameter(Mandatory)][hashtable]$Secrets)
    foreach($name in 'GoogleClientId','GoogleClientSecret','GoogleRefreshToken'){if([string]::IsNullOrWhiteSpace($Secrets[$name])){throw "Missing encrypted secret: $name"}}
    $body=@{client_id=$Secrets.GoogleClientId;client_secret=$Secrets.GoogleClientSecret;refresh_token=$Secrets.GoogleRefreshToken;grant_type='refresh_token'}
    (Invoke-RestMethod -Method Post -Uri 'https://oauth2.googleapis.com/token' -Body $body -TimeoutSec 45).access_token
}

function Invoke-GoogleApi {
    param([Parameter(Mandatory)][string]$Token,[Parameter(Mandatory)][string]$Uri,[ValidateSet('Get','Post')][string]$Method='Get',$Body)
    $args=@{Method=$Method;Uri=$Uri;Headers=@{Authorization="Bearer $Token"};TimeoutSec=60}
    if($null -ne $Body){$args.ContentType='application/json';$args.Body=($Body|ConvertTo-Json -Depth 8 -Compress)}
    Invoke-RestMethod @args
}

Export-ModuleMember -Function *
