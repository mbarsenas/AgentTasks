#requires -Version 7.2
#requires -RunAsAdministrator
[CmdletBinding()]param([string]$BusinessOpsRoot='C:\WickedAdmin\BusinessOps')
Set-StrictMode -Version Latest;$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'WickedOps.Common.psm1') -Force
function Read-PlainSecret([string]$Prompt){$s=Read-Host $Prompt -AsSecureString;$b=[Runtime.InteropServices.Marshal]::SecureStringToBSTR($s);try{[Runtime.InteropServices.Marshal]::PtrToStringBSTR($b)}finally{[Runtime.InteropServices.Marshal]::ZeroFreeBSTR($b)}}
function Encode([string]$Value){[uri]::EscapeDataString($Value)}
$clientId=Read-Host 'Google OAuth Desktop client ID'
$clientSecret=Read-PlainSecret 'Google OAuth Desktop client secret'
if([string]::IsNullOrWhiteSpace($clientId) -or [string]::IsNullOrWhiteSpace($clientSecret)){throw 'Client ID and secret are required.'}
$tcp=[Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback,0);$tcp.Start();$port=([Net.IPEndPoint]$tcp.LocalEndpoint).Port;$tcp.Stop()
$redirect="http://127.0.0.1:$port/";$state=[Convert]::ToHexString([Security.Cryptography.RandomNumberGenerator]::GetBytes(24))
$scopes=@('https://www.googleapis.com/auth/gmail.readonly','https://www.googleapis.com/auth/gmail.send','https://www.googleapis.com/auth/webmasters.readonly') -join ' '
$auth='https://accounts.google.com/o/oauth2/v2/auth?'+(@("client_id=$(Encode $clientId)","redirect_uri=$(Encode $redirect)",'response_type=code',"scope=$(Encode $scopes)",'access_type=offline','prompt=consent','include_granted_scopes=true',"state=$(Encode $state)")-join '&')
$listener=[Net.HttpListener]::new();$listener.Prefixes.Add($redirect);$listener.Start()
try{
    Write-Host 'Opening Google authorization in your browser...' -ForegroundColor Cyan
    Start-Process $auth
    $wait=$listener.GetContextAsync();$done=[Threading.Tasks.Task]::WhenAny($wait,[Threading.Tasks.Task]::Delay([TimeSpan]::FromMinutes(5))).GetAwaiter().GetResult()
    if($done -ne $wait){throw 'Google authorization timed out after five minutes.'}
    $context=$wait.GetAwaiter().GetResult();$q=$context.Request.QueryString
    $message=if($q['error']){"Authorization failed: $($q['error'])"}else{'Authorization received. You may close this browser tab.'}
    $bytes=[Text.Encoding]::UTF8.GetBytes("<html><body><h2>$message</h2></body></html>");$context.Response.ContentType='text/html';$context.Response.ContentLength64=$bytes.Length;$context.Response.OutputStream.Write($bytes,0,$bytes.Length);$context.Response.Close()
    if($q['error']){throw $message};if($q['state'] -ne $state){throw 'OAuth state validation failed.'};$code=$q['code'];if(-not $code){throw 'Google did not return an authorization code.'}
}
finally{$listener.Stop();$listener.Close()}
$token=Invoke-RestMethod -Method Post -Uri 'https://oauth2.googleapis.com/token' -Body @{client_id=$clientId;client_secret=$clientSecret;code=$code;redirect_uri=$redirect;grant_type='authorization_code'} -TimeoutSec 60
if([string]::IsNullOrWhiteSpace($token.refresh_token)){throw 'Google did not issue a refresh token. Revoke the app grant and run authorization again.'}
$headers=@{Authorization="Bearer $($token.access_token)"};$profile=Invoke-RestMethod 'https://gmail.googleapis.com/gmail/v1/users/me/profile' -Headers $headers -TimeoutSec 45;$sites=Invoke-RestMethod 'https://searchconsole.googleapis.com/webmasters/v3/sites' -Headers $headers -TimeoutSec 45
$dir=Join-Path $BusinessOpsRoot 'Secrets';New-Item $dir -ItemType Directory -Force|Out-Null;$path=Join-Path $dir 'BusinessOpsSecrets.json'
[ordered]@{FormatVersion=1;Scope='LocalMachine';CreatedUtc=[DateTime]::UtcNow.ToString('o');GoogleAccount=$profile.emailAddress;Values=[ordered]@{GoogleClientId=Protect-WickedOpsValue $clientId;GoogleClientSecret=Protect-WickedOpsValue $clientSecret;GoogleRefreshToken=Protect-WickedOpsValue ([string]$token.refresh_token)}}|ConvertTo-Json -Depth 5|Set-Content $path -Encoding utf8
$configPath=Join-Path $BusinessOpsRoot 'BusinessOps.config.json';$cfg=Get-Content $configPath -Raw|ConvertFrom-Json
foreach($site in $cfg.Sites){$siteHost=([uri]$site.Url).Host;$candidate=@($sites.siteEntry|Where-Object{$_.siteUrl -eq "sc-domain:$siteHost" -or $_.siteUrl -eq $site.Url}|Select-Object -First 1);if($candidate){if($site.PSObject.Properties['SearchConsoleProperty']){$site.SearchConsoleProperty=$candidate.siteUrl}else{$site|Add-Member NoteProperty SearchConsoleProperty $candidate.siteUrl}}}
$cfg|ConvertTo-Json -Depth 12|Set-Content $configPath -Encoding utf8
$svc="$env:COMPUTERNAME\WickedOpsSvc";&icacls.exe $dir /inheritance:r|Out-Null;&icacls.exe $dir /grant:r 'SYSTEM:(OI)(CI)F' 'BUILTIN\Administrators:(OI)(CI)F' "${svc}:(OI)(CI)RX" /T /C|Out-Null
if($LASTEXITCODE -ne 0){throw 'Failed to secure OAuth secrets.'}
Write-Host "Authorized $($profile.emailAddress); encrypted credentials saved." -ForegroundColor Green
Write-Host "Search Console properties discovered: $(@($sites.siteEntry).Count)"
