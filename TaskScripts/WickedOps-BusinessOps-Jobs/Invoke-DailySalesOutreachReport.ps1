#requires -Version 7.2
param([Parameter(Mandatory)][string]$ConfigPath,[Parameter(Mandatory)][string]$LogPath)
Import-Module (Join-Path $PSScriptRoot 'WickedOps.Common.psm1') -Force
$root=Get-WickedOpsRoot $ConfigPath; $since=(Get-Date).AddDays(-1); $logs=Get-ChildItem (Join-Path $root 'Logs') -Filter '*.log'|Where-Object { $_.LastWriteTime -ge $since -and $_.Name -notlike 'DailySalesOutreachReport-*' }
$logData=@($logs|ForEach-Object{
    $lines=@(Get-Content $_.FullName -ErrorAction SilentlyContinue)
    $windowLines=@($lines|Where-Object{
        if($_ -match '^(?<Timestamp>\d{4}-\d{2}-\d{2}T\S+) '){
            try{[DateTimeOffset]::Parse($Matches.Timestamp) -ge $since}catch{$false}
        }else{$false}
    })
    [pscustomobject]@{Name=$_.Name;Lines=$windowLines}
})
$text=($logData.Lines) -join "`n"

# Stripe monitor runs overlap the same rolling window. Use the newest count for
# each product instead of summing repeated observations of the same sessions.
$paidByProduct=@{}
foreach($line in $text -split "`n"){
    if($line -match '(?<Product>AgentLedger|TenantIQ365|CommentHarbor): (?<Count>\d+) completed paid checkout session\(s\)'){
        $paidByProduct[$Matches.Product]=[int]$Matches.Count
    }
}
$paidSessions=($paidByProduct.Values|Measure-Object -Sum).Sum
if($null -eq $paidSessions){$paidSessions=0}

# Use the latest explicit numeric result. A line such as "Bounces: 0" is a
# health confirmation and must never be counted as a bounce signal.
$signalCounts=[ordered]@{Bounces=0;Complaints=0;OptOuts=0;Replies=0}
foreach($line in $text -split "`n"){
    foreach($signal in @('Bounces','Complaints','OptOuts','Replies')){
        if($line -match "(?i)\b$signal\s*:\s*(?<Count>\d+)\s+signal"){
            $signalCounts[$signal]=[int]$Matches.Count
        }
    }
}
$suppressionSignals=$signalCounts.Bounces+$signalCounts.Complaints+$signalCounts.OptOuts

# Report historical observations separately from the status of the latest run.
$currentFailures=@()
foreach($entry in $logData){
    $latestStart=-1
    for($i=0;$i -lt $entry.Lines.Count;$i++){
        if($entry.Lines[$i] -match '\[INFO\] Starting '){$latestStart=$i}
    }
    if($latestStart -ge 0){
        $latestRun=@($entry.Lines[$latestStart..($entry.Lines.Count-1)])
        if(($latestRun -match '\[ERROR\]').Count -gt 0 -and ($latestRun -match 'completed successfully').Count -eq 0){
            $currentFailures+=$entry.Name
        }
    }
}
$counts=[ordered]@{
    PaidSessions=[int]$paidSessions
    HistoricalErrors=([regex]::Matches($text,'\[ERROR\]').Count)
    HistoricalWarnings=([regex]::Matches($text,'\[WARN\]').Count)
    ActiveFailures=$currentFailures.Count
    Bounces=$signalCounts.Bounces
    Complaints=$signalCounts.Complaints
    OptOuts=$signalCounts.OptOuts
    BounceSignals=$suppressionSignals
    ReplySignals=$signalCounts.Replies
}
Write-WickedOpsLog $LogPath ("Daily summary: " + (($counts.GetEnumerator()|ForEach-Object{"$($_.Key)=$($_.Value)"}) -join '; '))
$report=Join-Path $root "Reports\Daily-$((Get-Date).ToString('yyyyMMdd')).json"; New-Item (Split-Path $report) -ItemType Directory -Force|Out-Null
[ordered]@{Generated=(Get-Date).ToString('o');WindowHours=24;Counts=$counts;ActiveFailureLogs=@($currentFailures);SourceLogs=@($logs.Name)}|ConvertTo-Json -Depth 5|Set-Content $report -Encoding utf8
Write-WickedOpsLog $LogPath "Report saved: $report"
$summary=@"
Daily BusinessOps summary for the last 24 hours

Paid checkout sessions: $($counts.PaidSessions)
Active task failures: $($counts.ActiveFailures)
Historical errors observed: $($counts.HistoricalErrors)
Historical warnings observed: $($counts.HistoricalWarnings)
Bounces: $($counts.Bounces)
Complaints: $($counts.Complaints)
Opt-outs: $($counts.OptOuts)
Reply signals: $($counts.ReplySignals)

Report: $report
"@
& (Join-Path $PSScriptRoot 'Send-WickedOpsGmailAlert.ps1') -ConfigPath $ConfigPath -Title "WickedOps daily report - $((Get-Date).ToString('yyyy-MM-dd'))" -Message $summary -TaskName 'DailySalesOutreachReport'
Write-WickedOpsLog $LogPath 'Daily report emailed to the configured owner.'
