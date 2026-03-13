# Daily P&L and Group Performance Analysis
$logPath = "C:\Users\m_ode\AppData\Roaming\MetaQuotes\Terminal\56EE5B2C68594C11EBC44B2E705CB8B7\MQL4\Files\shra_provider_audit_410038624.csv"

Write-Host "`n╔═══════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║   DAILY P&L & GROUP PERFORMANCE ANALYSIS                        ║" -ForegroundColor Cyan
Write-Host "║   Account: 410038624 (FTMO $200K)                               ║" -ForegroundColor Cyan
Write-Host "╚═══════════════════════════════════════════════════════════════════╝`n" -ForegroundColor Cyan

# Import and parse data
Write-Host "[1/3] Loading audit log..." -ForegroundColor Yellow
$data = Import-Csv $logPath -Header 'Timestamp','Account','Provider','EventType','Peak','Current','DDPercent','TradesCount','Details'

$data | ForEach-Object { 
    $_.Timestamp = [DateTime]::ParseExact($_.Timestamp, 'yyyy.MM.dd HH:mm:ss', $null)
    $_.Peak = [double]$_.Peak
    $_.Current = [double]$_.Current
    $_.DDPercent = [double]$_.DDPercent
    $_.TradesCount = [int]$_.TradesCount
}

Write-Host "  ✓ Loaded $($data.Count) entries`n" -ForegroundColor Green

# ============================================================================
# DAILY ACCOUNT CLOSED P&L
# ============================================================================
Write-Host "[2/3] Analyzing Daily Account Closed P&L..." -ForegroundColor Yellow

# Get ACCOUNT_STATUS and DAILY_INIT events which contain account-level metrics
$accountEvents = $data | Where-Object { $_.Provider -eq 'ACCOUNT_WIDE' -and ($_.EventType -eq 'ACCOUNT_STATUS' -or $_.EventType -eq 'DAILY_INIT') }

Write-Host "`n  📊 ACCOUNT-LEVEL EVENTS (Last 30):" -ForegroundColor Cyan
$recentAccountEvents = $accountEvents | Sort-Object Timestamp -Descending | Select-Object -First 30
$recentAccountEvents | ForEach-Object {
    $dateStr = $_.Timestamp.ToString('yyyy-MM-dd HH:mm:ss')
    Write-Host "    [$dateStr] $($_.EventType): $($_.Details)" -ForegroundColor Gray
}

# Extract daily P&L by analyzing ACCOUNT_STATUS details
Write-Host "`n  💰 DAILY CLOSED P&L SUMMARY:" -ForegroundColor Green

# Group by date and analyze
$dailySummary = $accountEvents | Group-Object { $_.Timestamp.Date } | Sort-Object Name -Descending | Select-Object -First 10

foreach($day in $dailySummary) {
    $dateStr = ([DateTime]$day.Name).ToString('yyyy-MM-dd')
    $dayEvents = $day.Group | Sort-Object Timestamp
    
    Write-Host "`n    Date: $dateStr" -ForegroundColor Yellow
    Write-Host "    Events: $($dayEvents.Count)" -ForegroundColor Gray
    
    # Parse details for P&L information
    foreach($event in $dayEvents) {
        if($event.Details -match 'TotalPL:[\$\s]*(-?\d+\.?\d*)') {
            $totalPL = [double]$matches[1]
            Write-Host "      Total P&L: `$$($totalPL.ToString('N2'))" -ForegroundColor $(if($totalPL -gt 0){'Green'}else{'Red'})
        }
        if($event.Details -match 'ClosedPL:[\$\s]*(-?\d+\.?\d*)') {
            $closedPL = [double]$matches[1]
            Write-Host "      Closed P&L: `$$($closedPL.ToString('N2'))" -ForegroundColor $(if($closedPL -gt 0){'Green'}else{'Red'})
        }
        if($event.Details -match 'FloatingPL:[\$\s]*(-?\d+\.?\d*)') {
            $floatingPL = [double]$matches[1]
            Write-Host "      Floating P&L: `$$($floatingPL.ToString('N2'))" -ForegroundColor $(if($floatingPL -gt 0){'Green'}else{'Red'})
        }
    }
}

# ============================================================================
# GROUP PERFORMANCE ANALYSIS
# ============================================================================
Write-Host "`n`n[3/3] Analyzing Group Performance..." -ForegroundColor Yellow

# Get latest STATUS for all providers to calculate group performance
$latestStatus = $data | Where-Object { $_.EventType -eq 'STATUS' } | 
                Group-Object Provider | 
                ForEach-Object { $_.Group | Sort-Object Timestamp -Descending | Select-Object -First 1 }

# Extract group IDs from provider names
$groupData = $latestStatus | ForEach-Object {
    if($_.Provider -match '_(\d+)$') {
        [PSCustomObject]@{
            Group = $matches[1]
            Provider = $_.Provider
            Peak = $_.Peak
            Current = $_.Current
            DDPercent = $_.DDPercent
            TradesCount = $_.TradesCount
            Timestamp = $_.Timestamp
        }
    }
}

# Group performance summary
$groupSummary = $groupData | Group-Object Group | ForEach-Object {
    $groupProviders = $_.Group
    $totalCurrent = ($groupProviders | Measure-Object -Property Current -Sum).Sum
    $totalPeak = ($groupProviders | Measure-Object -Property Peak -Sum).Sum
    $activeCount = ($groupProviders | Where-Object { $_.TradesCount -gt 0 }).Count
    $profitableCount = ($groupProviders | Where-Object { $_.Current -gt 0 }).Count
    $losingCount = ($groupProviders | Where-Object { $_.Current -lt 0 }).Count
    
    # Calculate group DD
    $groupDD = 0
    if($totalPeak -gt 0) {
        $groupDD = (($totalPeak - $totalCurrent) / $totalPeak) * 100
    }
    
    [PSCustomObject]@{
        Group = $_.Name
        ProviderCount = $_.Count
        ActiveProviders = $activeCount
        ProfitableProviders = $profitableCount
        LosingProviders = $losingCount
        TotalPeak = $totalPeak
        TotalCurrent = $totalCurrent
        GroupDD = $groupDD
        NetPL = $totalCurrent
    }
} | Sort-Object TotalCurrent -Descending

Write-Host "`n  📊 GROUP PERFORMANCE SUMMARY:" -ForegroundColor Cyan
Write-Host "  Total Groups: $($groupSummary.Count)`n" -ForegroundColor Gray

# Display top performing groups
Write-Host "  🏆 TOP 15 GROUPS BY NET P&L:" -ForegroundColor Green
$groupSummary | Select-Object -First 15 | ForEach-Object {
    $color = if($_.NetPL -gt 0){'Green'}else{'Red'}
    $ddColor = if($_.GroupDD -gt 50){'Red'}elseif($_.GroupDD -gt 25){'Yellow'}else{'Green'}
    
    Write-Host "`n    Group $($_.Group):" -ForegroundColor Cyan
    Write-Host "      Providers: $($_.ProviderCount) (Active: $($_.ActiveProviders), Profitable: $($_.ProfitableProviders), Losing: $($_.LosingProviders))"
    Write-Host "      Net P&L: `$$($_.NetPL.ToString('N2'))" -ForegroundColor $color
    Write-Host "      Peak: `$$($_.TotalPeak.ToString('N2')) | Current: `$$($_.TotalCurrent.ToString('N2'))"
    Write-Host "      Group DD: $($_.GroupDD.ToString('N2'))%" -ForegroundColor $ddColor
}

# Display worst performing groups
Write-Host "`n`n  ⚠️  BOTTOM 10 GROUPS BY NET P&L:" -ForegroundColor Red
$groupSummary | Sort-Object TotalCurrent | Select-Object -First 10 | ForEach-Object {
    $ddColor = if($_.GroupDD -gt 50){'Red'}elseif($_.GroupDD -gt 25){'Yellow'}else{'Green'}
    
    Write-Host "`n    Group $($_.Group):" -ForegroundColor Yellow
    Write-Host "      Providers: $($_.ProviderCount) (Active: $($_.ActiveProviders), Profitable: $($_.ProfitableProviders), Losing: $($_.LosingProviders))"
    Write-Host "      Net P&L: `$$($_.NetPL.ToString('N2'))" -ForegroundColor Red
    Write-Host "      Peak: `$$($_.TotalPeak.ToString('N2')) | Current: `$$($_.TotalCurrent.ToString('N2'))"
    Write-Host "      Group DD: $($_.GroupDD.ToString('N2'))%" -ForegroundColor $ddColor
}

# Group statistics
Write-Host "`n`n  📈 GROUP STATISTICS:" -ForegroundColor Cyan
$profitableGroups = ($groupSummary | Where-Object { $_.NetPL -gt 0 }).Count
$losingGroups = ($groupSummary | Where-Object { $_.NetPL -lt 0 }).Count
$totalGroupPL = ($groupSummary | Measure-Object -Property NetPL -Sum).Sum
$avgGroupPL = ($groupSummary | Measure-Object -Property NetPL -Average).Average
$totalProviders = ($groupSummary | Measure-Object -Property ProviderCount -Sum).Sum

Write-Host "    Profitable Groups: $profitableGroups" -ForegroundColor Green
Write-Host "    Losing Groups: $losingGroups" -ForegroundColor Red
Write-Host "    Total Providers Across Groups: $totalProviders"
Write-Host "    Total Group P&L: `$$($totalGroupPL.ToString('N2'))" -ForegroundColor $(if($totalGroupPL -gt 0){'Green'}else{'Red'})
Write-Host "    Average Group P&L: `$$($avgGroupPL.ToString('N2'))"

# Export to CSV for further analysis
$groupSummary | Export-Csv -Path "c:\Users\m_ode\OneDrive\Documents\GitHub\MQL4\Group_Performance_$(Get-Date -Format 'yyyy-MM-dd_HHmmss').csv" -NoTypeInformation
Write-Host "`n✅ Group performance exported to: Group_Performance_$(Get-Date -Format 'yyyy-MM-dd_HHmmss').csv" -ForegroundColor Green

Write-Host "`n╔═══════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║   ANALYSIS COMPLETE                                              ║" -ForegroundColor Cyan
Write-Host "╚═══════════════════════════════════════════════════════════════════╝`n" -ForegroundColor Cyan
