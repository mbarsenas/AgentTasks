#requires -Version 7.2
param([Parameter(Mandatory)][string]$ConfigPath,[Parameter(Mandatory)][string]$LogPath)
Import-Module (Join-Path $PSScriptRoot 'WickedOps.Common.psm1') -Force
$cfg=Get-Content $ConfigPath -Raw|ConvertFrom-Json;$s=Get-WickedOpsSecrets $ConfigPath;$t=Get-GoogleAccessToken $s;$end=(Get-Date).Date.AddDays(-1);$start=$end.AddDays(-6)
$out=@()
foreach($site in $cfg.Sites){$property=if($site.PSObject.Properties['SearchConsoleProperty']){$site.SearchConsoleProperty}else{$site.Url};$uri='https://searchconsole.googleapis.com/webmasters/v3/sites/'+[uri]::EscapeDataString($property)+'/searchAnalytics/query';$body=@{startDate=$start.ToString('yyyy-MM-dd');endDate=$end.ToString('yyyy-MM-dd');dimensions=@('query');rowLimit=10};$r=Invoke-GoogleApi $t $uri Post $body;$rows=if($r.PSObject.Properties['rows']){@($r.rows)}else{@()};$clicks=($rows|Measure-Object clicks -Sum).Sum;$impressions=($rows|Measure-Object impressions -Sum).Sum;Write-WickedOpsLog $LogPath "$($site.Name): clicks=$([int]$clicks); impressions=$([int]$impressions); topQueries=$($rows.Count).";$out+=@{Product=$site.Name;Clicks=[int]$clicks;Impressions=[int]$impressions;Rows=$rows}}
$path=Join-Path (Get-WickedOpsRoot $ConfigPath) "Reports\SEO-$((Get-Date).ToString('yyyyMMdd')).json";New-Item (Split-Path $path) -ItemType Directory -Force|Out-Null;$out|ConvertTo-Json -Depth 8|Set-Content $path -Encoding utf8
