# Signal Harvester Risk Manager - Performance Report Generator
# Analyzes EA audit log and generates comprehensive report

$logPath = "C:\Users\m_ode\AppData\Roaming\MetaQuotes\Terminal\56EE5B2C68594C11EBC44B2E705CB8B7\MQL4\Files\shra_provider_audit_410038624.csv"
$reportDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

Write-Host "`n╔═══════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║   SIGNAL HARVESTER RISK MANAGER - PERFORMANCE REPORT            ║" -ForegroundColor Cyan
Write-Host "║   Account: 410038624 (FTMO $200K)                               ║" -ForegroundColor Cyan
Write-Host "║   Report Date: $reportDate                          ║" -ForegroundColor Cyan
Write-Host "╚═══════════════════════════════════════════════════════════════════╝`n" -ForegroundColor Cyan

# Import data
Write-Host "[1/7] Loading audit log..." -ForegroundColor Yellow
$data = Import-Csv $logPath -Header 'Timestamp','Account','Provider','EventType','Peak','Current','DDPercent','TradesCount','Details'

# Parse timestamps
$data | ForEach-Object { 
    $_.Timestamp = [DateTime]::ParseExact($_.Timestamp, 'yyyy.MM.dd HH:mm:ss', $null)
    $_.Peak = [double]$_.Peak
    $_.Current = [double]$_.Current
    $_.DDPercent = [double]$_.DDPercent
    $_.TradesCount = [int]$_.TradesCount
}

Write-Host "  ✓ Loaded $($data.Count) log entries" -ForegroundColor Green
Write-Host "  ✓ Date range: $($data[0].Timestamp) to $($data[-1].Timestamp)`n" -ForegroundColor Green

# Analyze today's data
Write-Host "[2/7] Analyzing today's activity..." -ForegroundColor Yellow
$today = (Get-Date).Date
$todayData = $data | Where-Object { $_.Timestamp.Date -eq $today }
Write-Host "  ✓ Today's entries: $($todayData.Count)" -ForegroundColor Green

# Event types distribution
Write-Host "`n[3/7] Event Types Distribution (All Time)..." -ForegroundColor Yellow
$eventTypes = $data | Group-Object EventType | Sort-Object Count -Descending
$eventTypes | ForEach-Object {
    $pct = [math]::Round(($_.Count / $data.Count) * 100, 2)
    Write-Host "  $($_.Name.PadRight(25)) : $($_.Count.ToString('N0').PadLeft(10)) ($pct%)"
}

# Critical events
Write-Host "`n[4/7] Critical Events Analysis..." -ForegroundColor Yellow
$killSwitches = $data | Where-Object { $_.EventType -match 'KILL_SWITCH' }
$warnings = $data | Where-Object { $_.EventType -match 'WARNING' }
$emergencies = $data | Where-Object { $_.EventType -match 'EMERGENCY' }
$trims = $data | Where-Object { $_.EventType -match 'TRIM' }

Write-Host "  Kill Switches:        $($killSwitches.Count)" -ForegroundColor $(if($killSwitches.Count -gt 0){'Red'}else{'Green'})
Write-Host "  Emergency Events:     $($emergencies.Count)" -ForegroundColor $(if($emergencies.Count -gt 0){'Red'}else{'Yellow'})
Write-Host "  Warnings:             $($warnings.Count)" -ForegroundColor Yellow
Write-Host "  Trade Trims:          $($trims.Count)" -ForegroundColor Yellow

# Recent kill switches (last 7 days)
if($killSwitches.Count -gt 0) {
    $recentKills = $killSwitches | Where-Object { $_.Timestamp -ge (Get-Date).AddDays(-7) }
    if($recentKills.Count -gt 0) {
        Write-Host "`n  ⚠ RECENT KILL SWITCHES (Last 7 days):" -ForegroundColor Red
        $recentKills | Select-Object -Last 10 | ForEach-Object {
            Write-Host "    $($_.Timestamp.ToString('yyyy-MM-dd HH:mm')) | $($_.Provider) | $($_.Details)" -ForegroundColor Red
        }
    }
}

# Provider performance
Write-Host "`n[5/7] Provider Performance Summary..." -ForegroundColor Yellow
$latestStatus = $data | Where-Object { $_.EventType -eq 'STATUS' } | 
                Group-Object Provider | 
                ForEach-Object { $_.Group | Sort-Object Timestamp -Descending | Select-Object -First 1 }

$activeProviders = $latestStatus | Where-Object { $_.TradesCount -gt 0 }
$profitableProviders = $latestStatus | Where-Object { $_.Current -gt 0 }
$losingProviders = $latestStatus | Where-Object { $_.Current -lt 0 }

Write-Host "  Total Providers:      $($latestStatus.Count)"
Write-Host "  Active (with trades): $($activeProviders.Count)" -ForegroundColor Cyan
Write-Host "  Profitable:           $($profitableProviders.Count)" -ForegroundColor Green
Write-Host "  Losing:               $($losingProviders.Count)" -ForegroundColor Red

# Top performers
Write-Host "`n  TOP 10 PERFORMERS (Current P&L):" -ForegroundColor Green
$latestStatus | Sort-Object { [double]$_.Current } -Descending | Select-Object -First 10 | ForEach-Object {
    $color = if([double]$_.Current -gt 0){'Green'}else{'Red'}
    Write-Host "    $($_.Provider.PadRight(30)) | `$$($_.Current.ToString('N2').PadLeft(10)) | Trades: $($_.TradesCount)" -ForegroundColor $color
}

Write-Host "`n  BOTTOM 10 PERFORMERS (Current P&L):" -ForegroundColor Red
$latestStatus | Sort-Object { [double]$_.Current } | Select-Object -First 10 | ForEach-Object {
    Write-Host "    $($_.Provider.PadRight(30)) | `$$($_.Current.ToString('N2').PadLeft(10)) | Trades: $($_.TradesCount)" -ForegroundColor Red
}

# Group analysis
Write-Host "`n[6/7] Group Analysis..." -ForegroundColor Yellow
$groups = $latestStatus | ForEach-Object {
    if($_.Provider -match '_(\d+)$') {
        $matches[1]
    }
} | Group-Object | Sort-Object Count -Descending

Write-Host "  Active Groups: $($groups.Count)"
$groups | Select-Object -First 5 | ForEach-Object {
    Write-Host "    Group $($_.Name): $($_.Count) providers"
}

# Group performance
$groupPerformance = $latestStatus | ForEach-Object {
    if($_.Provider -match '_(\d+)$') {
        [PSCustomObject]@{
            Group = $matches[1]
            Provider = $_.Provider
            Current = [double]$_.Current
            Peak = [double]$_.Peak
        }
    }
} | Group-Object Group | ForEach-Object {
    $totalCurrent = ($_.Group | Measure-Object -Property Current -Sum).Sum
    $totalPeak = ($_.Group | Measure-Object -Property Peak -Sum).Sum
    [PSCustomObject]@{
        Group = $_.Name
        Providers = $_.Count
        TotalCurrent = $totalCurrent
        TotalPeak = $totalPeak
    }
} | Sort-Object TotalCurrent -Descending

Write-Host "`n  GROUP PERFORMANCE (Top 10):" -ForegroundColor Cyan
$groupPerformance | Select-Object -First 10 | ForEach-Object {
    $color = if($_.TotalCurrent -gt 0){'Green'}else{'Red'}
    Write-Host "    Group $($_.Group.PadRight(10)) | $($_.Providers) providers | `$$($_.TotalCurrent.ToString('N2').PadLeft(10))" -ForegroundColor $color
}

# Account-level metrics
Write-Host "`n[7/7] Account-Level Metrics..." -ForegroundColor Yellow
$accountEvents = $data | Where-Object { $_.Provider -eq 'ACCOUNT_WIDE' } | Sort-Object Timestamp -Descending
if($accountEvents.Count -gt 0) {
    $latestAccountStatus = $accountEvents | Where-Object { $_.EventType -eq 'ACCOUNT_STATUS' } | Select-Object -First 1
    if($latestAccountStatus) {
        Write-Host "  Latest Account Status:"
        Write-Host "    $($latestAccountStatus.Details)" -ForegroundColor Cyan
    }
}

# Calculate total current P&L across all providers
$totalPL = ($latestStatus | Measure-Object -Property Current -Sum).Sum
$totalPeak = ($latestStatus | Measure-Object -Property Peak -Sum).Sum

Write-Host "`n  OVERALL PORTFOLIO:"
Write-Host "    Total Current P&L:  `$$($totalPL.ToString('N2'))" -ForegroundColor $(if($totalPL -gt 0){'Green'}else{'Red'})
Write-Host "    Total Peak P&L:     `$$($totalPeak.ToString('N2'))" -ForegroundColor Cyan
if($totalPeak -gt 0) {
    $portfolioDD = (($totalPeak - $totalPL) / $totalPeak) * 100
    Write-Host "    Portfolio DD:       $($portfolioDD.ToString('N2'))%" -ForegroundColor $(if($portfolioDD -gt 10){'Red'}elseif($portfolioDD -gt 5){'Yellow'}else{'Green'})
}

# Summary
Write-Host "`n╔═══════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║   SUMMARY                                                         ║" -ForegroundColor Cyan
Write-Host "╚═══════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host "  Report generated successfully at $reportDate" -ForegroundColor Green
Write-Host "  Log file analyzed: $logPath" -ForegroundColor Gray
Write-Host "  Total entries: $($data.Count.ToString('N0'))" -ForegroundColor Gray
Write-Host "`n"

# Export summary to file
$reportFile = "c:\Users\m_ode\OneDrive\Documents\GitHub\MQL4\EA_Performance_Report_$(Get-Date -Format 'yyyy-MM-dd_HHmmss').txt"
$summary = @"
SIGNAL HARVESTER RISK MANAGER - PERFORMANCE REPORT
Account: 410038624 (FTMO `$200K)
Report Date: $reportDate

═══════════════════════════════════════════════════════════════════

OVERVIEW
--------
Total Log Entries: $($data.Count.ToString('N0'))
Date Range: $($data[0].Timestamp) to $($data[-1].Timestamp)
Today's Entries: $($todayData.Count)

EVENT SUMMARY
-------------
Kill Switches: $($killSwitches.Count)
Emergency Events: $($emergencies.Count)
Warnings: $($warnings.Count)
Trade Trims: $($trims.Count)

PROVIDER SUMMARY
----------------
Total Providers: $($latestStatus.Count)
Active Providers (with trades): $($activeProviders.Count)
Profitable Providers: $($profitableProviders.Count)
Losing Providers: $($losingProviders.Count)

PORTFOLIO METRICS
-----------------
Total Current P&L: `$$($totalPL.ToString('N2'))
Total Peak P&L: `$$($totalPeak.ToString('N2'))
$(if($totalPeak -gt 0){"Portfolio DD: $($portfolioDD.ToString('N2'))%"}else{"Portfolio DD: N/A"})

═══════════════════════════════════════════════════════════════════
Report generated by generate_ea_report.ps1
"@

$summary | Out-File -FilePath $reportFile -Encoding UTF8
Write-Host "📄 Full report saved to: $reportFile" -ForegroundColor Green
