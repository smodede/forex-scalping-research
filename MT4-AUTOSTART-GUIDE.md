# MT4 Auto-Start Setup Guide

This solution automatically starts MetaTrader 4 when your computer boots, if it's not already running.

## Quick Setup (Recommended)

1. **Run the setup script** (requires Administrator):
   ```powershell
   .\Setup-MT4-AutoStart.ps1
   ```

2. **Test the setup**:
   ```powershell
   .\Start-MT4.ps1
   ```

3. **Reboot your computer** to verify it works automatically

## What Gets Installed

- **Scheduled Task**: "MT4-AutoStart" 
  - Runs at Windows startup
  - 2-minute delay to ensure system is ready
  - Runs under your user account
  - Hidden PowerShell window

- **Scripts**:
  - `Start-MT4.ps1` - Checks if MT4 is running and starts it if needed
  - `MT4_AutoStart_Log.txt` - Log file for troubleshooting

## Manual Testing

Test the auto-start script without rebooting:
```powershell
.\Start-MT4.ps1
```

Test the scheduled task:
```powershell
Start-ScheduledTask -TaskName "MT4-AutoStart"
```

## View Logs

Check if the script ran successfully:
```powershell
Get-Content .\MT4_AutoStart_Log.txt -Tail 20
```

## Troubleshooting

### MT4 Not Starting Automatically

1. **Check the log file**:
   ```powershell
   Get-Content .\MT4_AutoStart_Log.txt
   ```

2. **Verify MT4 path** in `Start-MT4.ps1`:
   - Open `Start-MT4.ps1` in a text editor
   - Check the `$possiblePaths` array
   - Add your MT4 installation path if it's not listed

3. **Check Task Scheduler**:
   - Press `Win + R`, type `taskschd.msc`, press Enter
   - Look for "MT4-AutoStart" task
   - Right-click → Run to test manually
   - Check "History" tab for errors

4. **Verify task permissions**:
   - The task must run as your Windows user account
   - "Run with highest privileges" should be enabled

### MT4 Path Not Found

If the script can't find MT4, manually update `Start-MT4.ps1`:

1. Find your MT4 installation:
   - Common locations:
     - `C:\Program Files (x86)\MetaTrader 4\terminal.exe`
     - `C:\Program Files\MetaTrader 4\terminal.exe`
     - `C:\Program Files (x86)\FTMO MetaTrader 4\terminal.exe`

2. Add your path to the `$possiblePaths` array in `Start-MT4.ps1`

### Multiple MT4 Instances

If you have multiple MT4 installations:
- The script will start the first one it finds
- Modify `Start-MT4.ps1` to specify the exact path you want

## Removing Auto-Start

To disable auto-start:
```powershell
.\Remove-MT4-AutoStart.ps1
```

Or manually:
1. Open Task Scheduler (`taskschd.msc`)
2. Find "MT4-AutoStart"
3. Right-click → Delete

## Advanced Configuration

### Change Startup Delay

Edit the delay in `Setup-MT4-AutoStart.ps1`:
```powershell
$trigger.Delay = "PT2M"  # PT2M = 2 minutes
# Change to:
$trigger.Delay = "PT1M"  # 1 minute
$trigger.Delay = "PT5M"  # 5 minutes
```

### Run on Login Instead of Startup

Modify the trigger in `Setup-MT4-AutoStart.ps1`:
```powershell
# Change from:
$trigger = New-ScheduledTaskTrigger -AtStartup

# To:
$trigger = New-ScheduledTaskTrigger -AtLogOn
```

### Show PowerShell Window

To see the script output instead of hidden:

In `Setup-MT4-AutoStart.ps1`, change:
```powershell
-Argument "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"$scriptPath`""
# To:
-Argument "-ExecutionPolicy Bypass -NoExit -File `"$scriptPath`""
```

## Files Created

| File | Purpose |
|------|---------|
| `Start-MT4.ps1` | Main script that starts MT4 |
| `Setup-MT4-AutoStart.ps1` | Creates the scheduled task |
| `Remove-MT4-AutoStart.ps1` | Removes the scheduled task |
| `MT4_AutoStart_Log.txt` | Log file (auto-created) |
| `MT4-AUTOSTART-GUIDE.md` | This guide |

## Compatibility

- **OS**: Windows 10/11
- **MT4**: All versions
- **Requirements**: PowerShell 5.0 or later (built into Windows 10/11)

## Security Notes

- Script runs with your user privileges (not as SYSTEM)
- Requires Administrator permission to create scheduled task
- Hidden window mode prevents accidental closure
- Logs all activity for audit trail

## Support

If you encounter issues:
1. Check `MT4_AutoStart_Log.txt` for error messages
2. Run `.\Start-MT4.ps1` manually to test
3. Verify MT4 starts normally when double-clicked
4. Check Windows Event Viewer for Task Scheduler errors

---

**Created**: March 10, 2026  
**Version**: 1.0
