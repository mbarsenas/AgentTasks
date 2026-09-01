#requires -Version 7.2
param([Parameter(Mandatory)][string]$ConfigPath,[Parameter(Mandatory)][string]$LogPath)
Import-Module (Join-Path $PSScriptRoot 'WickedOps.Common.psm1') -Force
$repos=@('TenantIQ-Assessment-Engine','TenantIQ-Web','YouTube-Comment-Toolkit','Comment-Toolkit-Web','AgentTasks');$owner='mbarsenas';$since=(Get-Date).ToUniversalTime().AddDays(-7).ToString('o');$headers=@{'User-Agent'='WickedOps/1.0';Accept='application/vnd.github+json'};$out=@()
foreach($repo in $repos){try{$commits=@(Invoke-RestMethod "https://api.github.com/repos/$owner/$repo/commits?since=$([uri]::EscapeDataString($since))&per_page=100" -Headers $headers);$issues=@(Invoke-RestMethod "https://api.github.com/repos/$owner/$repo/issues?state=all&since=$([uri]::EscapeDataString($since))&per_page=100" -Headers $headers);$out+=@{Repository=$repo;Commits=$commits.Count;IssuesAndPRs=$issues.Count};Write-WickedOpsLog $LogPath "${repo}: commits=$($commits.Count); issues/PRs=$($issues.Count)."}catch{Write-WickedOpsLog $LogPath "${repo} unavailable: $($_.Exception.Message)" WARN}}
$path=Join-Path (Get-WickedOpsRoot $ConfigPath) "Reports\ProductActivity-$((Get-Date).ToString('yyyyMMdd')).json";New-Item (Split-Path $path) -ItemType Directory -Force|Out-Null;$out|ConvertTo-Json -Depth 5|Set-Content $path -Encoding utf8
$lines=($out|ForEach-Object{"- $($_.Repository): $($_.Commits) commits, $($_.IssuesAndPRs) issues/PRs"}) -join "`n"
$message=@"
GitHub product activity for the last seven days

$lines

Report: $path
"@
& (Join-Path $PSScriptRoot 'Send-WickedOpsGmailAlert.ps1') -ConfigPath $ConfigPath -Title "WickedOps weekly product activity - $((Get-Date).ToString('yyyy-MM-dd'))" -Message $message -TaskName 'WeeklyProductActivityReport'
Write-WickedOpsLog $LogPath 'Weekly product activity report emailed to the configured owner.'
