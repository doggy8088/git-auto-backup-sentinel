param(
    [string]$TargetPath = (Get-Location).Path,
    [int]$BufferSeconds = 5,
    [switch]$AutoPush,
    [string]$GitDir
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function New-AutoBackupConfig {
    param(
        [string]$TargetPath,
        [int]$BufferSeconds,
        [switch]$AutoPush,
        [string]$GitDir
    )

    if (-not $TargetPath) {
        throw "TargetPath is required."
    }

    if (-not $GitDir) {
        $GitDir = Join-Path $TargetPath '.git'
    }

    if (-not (Test-Path $TargetPath)) {
        throw "TargetPath '$TargetPath' does not exist."
    }

    if (-not (Test-Path $GitDir)) {
        throw "GitDir '$GitDir' does not exist."
    }

    $gitArgs = @('--git-dir', $GitDir, '--work-tree', $TargetPath)
    $gitCheck = & git @gitArgs rev-parse --git-dir 2>$null
    if ($LASTEXITCODE -ne 0) {
        throw "GitDir '$GitDir' is not a valid git repository."
    }

    [pscustomobject]@{
        TargetPath    = (Resolve-Path -LiteralPath $TargetPath).Path
        BufferSeconds = $BufferSeconds
        AutoPush      = [bool]$AutoPush
        GitDir        = (Resolve-Path -LiteralPath $GitDir).Path
        GitArgs       = $gitArgs
    }
}

function Invoke-GitCommand {
    param(
        [object]$Config,
        [string[]]$Arguments,
        [switch]$CaptureOutput
    )

    $output = & git @($Config.GitArgs + $Arguments) 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw ($output | Out-String)
    }

    if ($CaptureOutput) {
        return ($output | Out-String)
    }
}

function Write-GitLogNote {
    param(
        [object]$Config,
        [string]$Message
    )

    try {
        & git @($Config.GitArgs + @('notes', '--ref=autobackup-log', 'append', '-m', $Message)) *> $null
    }
    catch {
        Write-Host "Failed to write git note: $_" -ForegroundColor Red
    }
}

function Format-EventDescription {
    param(
        [array]$Events
    )

    $lines = foreach ($ev in $Events) {
        $meta = @()
        if ($ev.Length) { $meta += "size=$($ev.Length)" }
        if ($ev.LastWriteTime) { $meta += "mtime=$($ev.LastWriteTime.ToString('u'))" }
        $metaText = if ($meta) { " [$($meta -join ', ')]" } else { '' }

        if ($ev.Type -eq 'Renamed' -and $ev.OldPath) {
            "Renamed: $($ev.OldPath) -> $($ev.Path)$metaText @ $($ev.Timestamp.ToString('u'))"
        }
        else {
            "$($ev.Type): $($ev.Path)$metaText @ $($ev.Timestamp.ToString('u'))"
        }
    }

    ($lines -join "`n")
}

function Get-GitStatus {
    param(
        [object]$Config
    )

    Invoke-GitCommand -Config $Config -Arguments @('status', '--porcelain') -CaptureOutput
}

function Invoke-BackupCommit {
    param(
        [object]$Config,
        [array]$Events
    )

    $timestamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    $eventText = Format-EventDescription -Events $Events
    $commitMessage = "Auto-backup: Changes detected at $timestamp"
    if ($eventText) {
        $commitMessage += "`n`n$eventText"
    }

    Invoke-GitCommand -Config $Config -Arguments @('add', '-A')
    Invoke-GitCommand -Config $Config -Arguments @('commit', '-m', $commitMessage)
    Write-Host " -> Commit Success! ($timestamp)"
    Write-GitLogNote -Config $Config -Message ("Commit at $timestamp`n$eventText")

    if ($Config.AutoPush) {
        Write-Host " -> Pushing to remote..."
        try {
            Invoke-GitCommand -Config $Config -Arguments @('push')
            Write-Host " -> Push Success!"
        }
        catch {
            Write-Host " -> Push Failed: $_" -ForegroundColor Red
            Write-GitLogNote -Config $Config -Message ("Push failed at $timestamp`n$_")
        }
    }
}

function Start-GitAutoBackup {
    param(
        [string]$TargetPath = $TargetPath,
        [int]$BufferSeconds = $BufferSeconds,
        [switch]$AutoPush = $AutoPush,
        [string]$GitDir = $GitDir
    )

    $config = New-AutoBackupConfig -TargetPath $TargetPath -BufferSeconds $BufferSeconds -AutoPush:$AutoPush -GitDir $GitDir
    $eventQueue = New-Object System.Collections.Concurrent.ConcurrentQueue[object]

    Write-Host '------------------------------------------------'
    Write-Host '  GIT AUTO-BACKUP SENTINEL'
    Write-Host "  Monitoring: $($config.TargetPath)"
    Write-Host "  Git Dir:    $($config.GitDir)"
    Write-Host "  Buffer:     $($config.BufferSeconds) seconds"
    Write-Host "  Auto-Push:  $([bool]$config.AutoPush)"
    Write-Host '  Press Ctrl+C to stop.'
    Write-Host '------------------------------------------------'

    $timer = New-Object System.Timers.Timer
    $timer.Interval = $config.BufferSeconds * 1000
    $timer.AutoReset = $false

    $timerEvent = Register-ObjectEvent -InputObject $timer -EventName Elapsed -Action {
        $localEvents = @()
        $ev = $null
        while ($eventQueue.TryDequeue([ref]$ev)) {
            $localEvents += $ev
        }

        if (-not $localEvents) {
            return
        }

        Write-Host "`nChanges stabilized. Checking git status..."

        try {
            $status = Get-GitStatus -Config $config
            if (-not $status.Trim()) {
                Write-Host "No changes detected. Waiting for next event."
                return
            }

            Write-Host " -> Committing changes..."
            Invoke-BackupCommit -Config $config -Events $localEvents
        }
        catch {
            Write-Host "Error during commit/push: $_" -ForegroundColor Red
            Write-GitLogNote -Config $config -Message ("Error during commit/push at $(Get-Date): $_")
        }
    }

    $watcher = New-Object System.IO.FileSystemWatcher $config.TargetPath, '*'
    $watcher.IncludeSubdirectories = $true
    $watcher.EnableRaisingEvents = $true
    $watcher.NotifyFilter = [IO.NotifyFilters]'FileName, DirectoryName, LastWrite, Size'

    $subscriptions = @()
    $resetTimer = {
        $timer.Stop()
        $timer.Interval = $config.BufferSeconds * 1000
        $timer.Start()
    }

    $recordEvent = {
        param($type, $path, $oldPath)
        Write-Host -NoNewline '.'
        $item = $null
        if ($type -ne 'Deleted') {
            $item = Get-Item -LiteralPath $path -ErrorAction SilentlyContinue
        }
        $length = $null
        $lastWrite = $null
        if ($null -ne $item) {
            if (-not $item.PSIsContainer) {
                $length = $item.Length
            }
            $lastWrite = $item.LastWriteTime
        }
        $eventData = [pscustomobject]@{
            Type          = $type
            Path          = $path
            OldPath       = $oldPath
            Timestamp     = Get-Date
            Length        = $length
            LastWriteTime = $lastWrite
        }
        $eventQueue.Enqueue($eventData) | Out-Null
        & $resetTimer
    }

    $subscriptions += Register-ObjectEvent -InputObject $watcher -EventName Created -Action {
        & $recordEvent 'Created' $Event.SourceEventArgs.FullPath $null
    }
    $subscriptions += Register-ObjectEvent -InputObject $watcher -EventName Changed -Action {
        & $recordEvent 'Changed' $Event.SourceEventArgs.FullPath $null
    }
    $subscriptions += Register-ObjectEvent -InputObject $watcher -EventName Deleted -Action {
        & $recordEvent 'Deleted' $Event.SourceEventArgs.FullPath $null
    }
    $subscriptions += Register-ObjectEvent -InputObject $watcher -EventName Renamed -Action {
        & $recordEvent 'Renamed' $Event.SourceEventArgs.FullPath $Event.SourceEventArgs.OldFullPath
    }

    $stopEvent = New-Object System.Threading.ManualResetEvent($false)

    Register-ObjectEvent -InputObject ([System.Console]) -EventName CancelKeyPress -SourceIdentifier Console_CancelKeyPress -Action {
        Write-Host "`nStopping Git Auto-Backup Sentinel..."
        $stopEvent.Set() | Out-Null
    } | Out-Null

    & $resetTimer
    while (-not $stopEvent.WaitOne(0)) {
        $event = Wait-Event -Timeout 1
        if (-not $event) { continue }
        if ($event.SourceIdentifier -eq 'Console_CancelKeyPress') {
            Remove-Event -EventIdentifier $event.EventIdentifier -ErrorAction SilentlyContinue
            break
        }
        Remove-Event -EventIdentifier $event.EventIdentifier -ErrorAction SilentlyContinue
    }

    $watcher.EnableRaisingEvents = $false
    foreach ($sub in $subscriptions) { Unregister-Event -SubscriptionId $sub.Id -ErrorAction SilentlyContinue }
    Unregister-Event -SourceIdentifier $timerEvent.Name -ErrorAction SilentlyContinue
    Unregister-Event -SourceIdentifier Console_CancelKeyPress -ErrorAction SilentlyContinue
    $timer.Stop()
    $timer.Dispose()
    $watcher.Dispose()
}

if ($MyInvocation.InvocationName -ne '.') {
    Start-GitAutoBackup @PSBoundParameters
}
