# Remove MT4 Auto-Start Task
# Uninstalls the scheduled task for MT4 auto-start

Write-Host "`n╔═══════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║   REMOVE MT4 AUTO-START                                          ║" -ForegroundColor Cyan
Write-Host "╚═══════════════════════════════════════════════════════════════════╝`n" -ForegroundColor Cyan

# Check if running as administrator
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if(-not $isAdmin) {
    Write-Host "⚠️  This script requires Administrator privileges." -ForegroundColor Yellow
    Write-Host "`nRestarting with Administrator privileges..." -ForegroundColor Yellow
    
    Start-Process powershell.exe -ArgumentList "-ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

$taskName = "MT4-AutoStart"

# Check if task exists
$existingTask = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue

if($existingTask) {
    Write-Host "Found task: $taskName" -ForegroundColor Yellow
    Write-Host "`nAre you sure you want to remove the MT4 auto-start task? (Y/N): " -ForegroundColor Yellow -NoNewline
    $response = Read-Host
    
    if($response -eq 'Y' -or $response -eq 'y') {
        try {
            Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
            Write-Host "`n✅ Task removed successfully!" -ForegroundColor Green
            Write-Host "   MT4 will no longer start automatically on boot." -ForegroundColor Gray
        } catch {
            Write-Host "`n❌ ERROR: Failed to remove task" -ForegroundColor Red
            Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
        }
    } else {
        Write-Host "`nCancelled. Task not removed." -ForegroundColor Yellow
    }
} else {
    Write-Host "ℹ️  Task '$taskName' not found. Nothing to remove." -ForegroundColor Cyan
}

Write-Host "`n"
