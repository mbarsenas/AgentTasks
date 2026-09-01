#requires -Version 7.2
param([Parameter(Mandatory)][string]$ConfigPath,[Parameter(Mandatory)][string]$LogPath)
Import-Module (Join-Path $PSScriptRoot 'WickedOps.Common.psm1') -Force
$root=Get-WickedOpsRoot $ConfigPath; $since=(Get-Date).AddDays(-1); $logs=Get-ChildItem (Join-Path $root 'Logs') -Filter '*.log'|Where-Object { $_.LastWriteTime -ge $since -and $_.Name -notlike 'DailySalesOutreachReport-*' }
$text=($logs|ForEach-Object{Get-Content $_.FullName -ErrorAction SilentlyContinue}) -join "`n"
$paidSessions=0
foreach($match in [regex]::Matches($text,'(?m)(\d+) completed paid checkout session\(s\)')){$paidSessions += [int]$match.Groups[1].Value}
$counts=[ordered]@{PaidSessions=$paidSessions;Errors=([regex]::Matches($text,'\[ERROR\]').Count);Warnings=([regex]::Matches($text,'\[WARN\]').Count);BounceSignals=([regex]::Matches($text,'(?i)bounce|delivery failure').Count);ReplySignals=([regex]::Matches($text,'(?i)human repl|prospect repl').Count)}
Write-WickedOpsLog $LogPath ("Daily summary: " + (($counts.GetEnumerator()|ForEach-Object{"$($_.Key)=$($_.Value)"}) -join '; '))
$report=Join-Path $root "Reports\Daily-$((Get-Date).ToString('yyyyMMdd')).json"; New-Item (Split-Path $report) -ItemType Directory -Force|Out-Null
[ordered]@{Generated=(Get-Date).ToString('o');WindowHours=24;Counts=$counts;SourceLogs=@($logs.Name)}|ConvertTo-Json -Depth 5|Set-Content $report -Encoding utf8
Write-WickedOpsLog $LogPath "Report saved: $report"
$summary=@"
Daily BusinessOps summary for the last 24 hours

Paid checkout sessions: $($counts.PaidSessions)
Errors: $($counts.Errors)
Warnings: $($counts.Warnings)
Bounce/delivery signals: $($counts.BounceSignals)
Reply signals: $($counts.ReplySignals)

Report: $report
"@
& (Join-Path $PSScriptRoot 'Send-WickedOpsGmailAlert.ps1') -ConfigPath $ConfigPath -Title "WickedOps daily report - $((Get-Date).ToString('yyyy-MM-dd'))" -Message $summary -TaskName 'DailySalesOutreachReport'
Write-WickedOpsLog $LogPath 'Daily report emailed to the configured owner.'
