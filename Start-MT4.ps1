# MT4 Auto-Start Script
# Checks if MT4 is running and starts it if not

$mt4ProcessName = "terminal"  # MT4 process name is "terminal.exe" or "terminal64.exe"
$mt4Path = "C:\Program Files (x86)\MetaTrader 4\terminal.exe"  # Default path - UPDATE THIS

# Log file for troubleshooting
$logFile = "$PSScriptRoot\MT4_AutoStart_Log.txt"

function Write-Log {
    param($message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$timestamp - $message" | Out-File -FilePath $logFile -Append
    Write-Host "$timestamp - $message"
}

Write-Log "=== MT4 Auto-Start Script Started ==="

# Try to find MT4 installation path automatically
$possiblePaths = @(
    "C:\Program Files (x86)\FTMO Global Markets MT4 Terminal\terminal.exe",
    "C:\Program Files (x86)\MetaTrader 4\terminal.exe",
    "C:\Program Files\MetaTrader 4\terminal.exe",
    "$env:ProgramFiles(x86)\MetaTrader 4\terminal.exe",
    "$env:ProgramFiles\MetaTrader 4\terminal.exe",
    "C:\Program Files (x86)\FTMO MetaTrader 4\terminal.exe",
    "C:\Program Files\FTMO MetaTrader 4\terminal.exe"
)

# Search in MetaQuotes folder for terminal.exe
$metaQuotesPath = "$env:APPDATA\MetaQuotes\Terminal"
if(Test-Path $metaQuotesPath) {
    $foundTerminals = Get-ChildItem -Path $metaQuotesPath -Recurse -Filter "terminal.exe" -ErrorAction SilentlyContinue
    foreach($terminal in $foundTerminals) {
        $possiblePaths += $terminal.FullName
    }
}

# Find the correct MT4 path
$mt4ExePath = $null
foreach($path in $possiblePaths) {
    if(Test-Path $path) {
        $mt4ExePath = $path
        Write-Log "Found MT4 at: $mt4ExePath"
        break
    }
}

if(-not $mt4ExePath) {
    Write-Log "ERROR: Could not find MT4 installation. Please update the script with the correct path."
    Write-Host "`nPlease enter the full path to your terminal.exe file:" -ForegroundColor Yellow
    Write-Host "Example: C:\Program Files (x86)\MetaTrader 4\terminal.exe" -ForegroundColor Gray
    exit 1
}

# Check if MT4 is already running
$mt4Process = Get-Process -Name $mt4ProcessName -ErrorAction SilentlyContinue

if($mt4Process) {
    Write-Log "MT4 is already running (PID: $($mt4Process.Id))"
    Write-Host "✅ MT4 is already running" -ForegroundColor Green
} else {
    Write-Log "MT4 is not running. Starting MT4..."
    Write-Host "Starting MT4..." -ForegroundColor Yellow
    
    try {
        # Start MT4
        Start-Process -FilePath $mt4ExePath
        
        # Wait a moment and verify it started
        Start-Sleep -Seconds 5
        $mt4Process = Get-Process -Name $mt4ProcessName -ErrorAction SilentlyContinue
        
        if($mt4Process) {
            Write-Log "✅ MT4 started successfully (PID: $($mt4Process.Id))"
            Write-Host "✅ MT4 started successfully" -ForegroundColor Green
        } else {
            Write-Log "⚠️ MT4 process not detected after start attempt"
            Write-Host "⚠️ MT4 may not have started properly" -ForegroundColor Yellow
        }
    } catch {
        Write-Log "ERROR: Failed to start MT4 - $($_.Exception.Message)"
        Write-Host "❌ Failed to start MT4: $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
}

Write-Log "=== MT4 Auto-Start Script Completed ==="
