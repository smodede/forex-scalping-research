# Setup MT4 Auto-Start on Windows Boot
# This script creates a Windows Task Scheduler task to start MT4 automatically

Write-Host "`n╔═══════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║   MT4 AUTO-START SETUP                                           ║" -ForegroundColor Cyan
Write-Host "╚═══════════════════════════════════════════════════════════════════╝`n" -ForegroundColor Cyan

# Check if running as administrator
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if(-not $isAdmin) {
    Write-Host "⚠️  This script requires Administrator privileges to create a scheduled task." -ForegroundColor Yellow
    Write-Host "`nRestarting with Administrator privileges..." -ForegroundColor Yellow
    
    # Restart as administrator
    Start-Process powershell.exe -ArgumentList "-ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

Write-Host "✅ Running with Administrator privileges`n" -ForegroundColor Green

# Get the path to the Start-MT4.ps1 script
$scriptPath = Join-Path $PSScriptRoot "Start-MT4.ps1"

if(-not (Test-Path $scriptPath)) {
    Write-Host "❌ ERROR: Start-MT4.ps1 not found in the same directory!" -ForegroundColor Red
    Write-Host "Expected location: $scriptPath" -ForegroundColor Yellow
    exit 1
}

Write-Host "📄 Script location: $scriptPath" -ForegroundColor Gray

# Task Scheduler settings
$taskName = "MT4-AutoStart"
$taskDescription = "Automatically starts MetaTrader 4 when Windows boots"
$currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name

Write-Host "`n[1/4] Checking for existing task..." -ForegroundColor Yellow

# Check if task already exists
$existingTask = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue

if($existingTask) {
    Write-Host "⚠️  Task '$taskName' already exists." -ForegroundColor Yellow
    $response = Read-Host "Do you want to remove it and create a new one? (Y/N)"
    
    if($response -eq 'Y' -or $response -eq 'y') {
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
        Write-Host "✅ Existing task removed" -ForegroundColor Green
    } else {
        Write-Host "Setup cancelled." -ForegroundColor Yellow
        exit 0
    }
}

Write-Host "`n[2/4] Creating scheduled task action..." -ForegroundColor Yellow

# Create the action (what to run)
$action = New-ScheduledTaskAction `
    -Execute "powershell.exe" `
    -Argument "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"$scriptPath`""

Write-Host "✅ Task action created" -ForegroundColor Green

Write-Host "`n[3/4] Creating scheduled task trigger..." -ForegroundColor Yellow

# Create the trigger (when to run)
$trigger = New-ScheduledTaskTrigger -AtStartup

# Add a delay to ensure system is ready
$trigger.Delay = "PT2M"  # 2 minute delay after startup

Write-Host "✅ Task trigger created (runs at startup with 2-minute delay)" -ForegroundColor Green

Write-Host "`n[4/4] Registering scheduled task..." -ForegroundColor Yellow

# Create task settings
$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 10)

# Create and register the task
$principal = New-ScheduledTaskPrincipal -UserId $currentUser -LogonType Interactive -RunLevel Highest

try {
    Register-ScheduledTask `
        -TaskName $taskName `
        -Description $taskDescription `
        -Action $action `
        -Trigger $trigger `
        -Settings $settings `
        -Principal $principal `
        -Force | Out-Null
    
    Write-Host "✅ Scheduled task registered successfully!" -ForegroundColor Green
    
    Write-Host "`n╔═══════════════════════════════════════════════════════════════════╗" -ForegroundColor Green
    Write-Host "║   SETUP COMPLETE                                                 ║" -ForegroundColor Green
    Write-Host "╚═══════════════════════════════════════════════════════════════════╝" -ForegroundColor Green
    
    Write-Host "`n📋 Task Details:" -ForegroundColor Cyan
    Write-Host "   Task Name: $taskName" -ForegroundColor Gray
    Write-Host "   Run User: $currentUser" -ForegroundColor Gray
    Write-Host "   Trigger: At system startup (2 minute delay)" -ForegroundColor Gray
    Write-Host "   Script: $scriptPath" -ForegroundColor Gray
    
    Write-Host "`n🎯 Next Steps:" -ForegroundColor Cyan
    Write-Host "   1. Test the setup by running:" -ForegroundColor Yellow
    Write-Host "      Start-ScheduledTask -TaskName '$taskName'" -ForegroundColor White
    Write-Host "`n   2. Or test the script directly:" -ForegroundColor Yellow
    Write-Host "      .\Start-MT4.ps1" -ForegroundColor White
    Write-Host "`n   3. To view the task in Task Scheduler:" -ForegroundColor Yellow
    Write-Host "      taskschd.msc" -ForegroundColor White
    Write-Host "`n   4. To check the log file after reboot:" -ForegroundColor Yellow
    Write-Host "      Get-Content .\MT4_AutoStart_Log.txt" -ForegroundColor White
    
    Write-Host "`n⚠️  Important Notes:" -ForegroundColor Yellow
    Write-Host "   • The script will start MT4 2 minutes after Windows boots" -ForegroundColor Gray
    Write-Host "   • If MT4 is already running, it won't start a second instance" -ForegroundColor Gray
    Write-Host "   • Check MT4_AutoStart_Log.txt for troubleshooting" -ForegroundColor Gray
    Write-Host "   • Make sure MT4 path is correct in Start-MT4.ps1" -ForegroundColor Gray
    
    # Offer to test now
    Write-Host "`n❓ Would you like to test the task now? (Y/N): " -ForegroundColor Cyan -NoNewline
    $testResponse = Read-Host
    
    if($testResponse -eq 'Y' -or $testResponse -eq 'y') {
        Write-Host "`n🧪 Testing task..." -ForegroundColor Yellow
        Start-ScheduledTask -TaskName $taskName
        Start-Sleep -Seconds 3
        
        # Check if MT4 started
        $mt4Process = Get-Process -Name "terminal" -ErrorAction SilentlyContinue
        if($mt4Process) {
            Write-Host "✅ Success! MT4 is running (PID: $($mt4Process.Id))" -ForegroundColor Green
        } else {
            Write-Host "⚠️  MT4 process not detected. Check the log file for details." -ForegroundColor Yellow
        }
    }
    
} catch {
    Write-Host "❌ ERROR: Failed to register scheduled task" -ForegroundColor Red
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

Write-Host "`n"
