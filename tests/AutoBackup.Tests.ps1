Import-Module Pester -ErrorAction Stop

BeforeAll {
    $root = Split-Path -Path $PSScriptRoot -Parent
    $scriptPath = Join-Path -Path $root -ChildPath 'git-autobackup.ps1'
    . $scriptPath
}

Describe 'New-AutoBackupConfig' {
    It 'defaults GitDir to .git inside target' {
        $repoRoot = Join-Path $TestDrive 'repo'
        $null = New-Item -ItemType Directory -Path $repoRoot
        Push-Location $repoRoot
        git init 2>&1 | Out-Null
        Pop-Location

        $config = New-AutoBackupConfig -TargetPath $repoRoot -BufferSeconds 5

        $config.GitDir | Should -Be (Join-Path $repoRoot '.git')
        $config.BufferSeconds | Should -Be 5
    }
}

Describe 'Format-EventDescription' {
    It 'formats renamed events with metadata' {
        $now = Get-Date
        $events = @(
            [pscustomobject]@{
                Type          = 'Renamed'
                Path          = 'B.txt'
                OldPath       = 'A.txt'
                Timestamp     = $now
                Length        = 10
                LastWriteTime = $now
            }
        )

        $text = Format-EventDescription -Events $events
        $text | Should -Match 'A.txt -> B.txt'
        $text | Should -Match 'size=10'
    }
}

Describe 'Invoke-BackupCommit' {
    BeforeEach {
        Mock -CommandName Invoke-GitCommand
        Mock -CommandName Write-GitLogNote
    }

    It 'pushes when AutoPush is enabled' {
        $config = [pscustomobject]@{
            GitArgs       = @()
            AutoPush      = $true
            BufferSeconds = 5
        }

        Invoke-BackupCommit -Config $config -Events @()

        Assert-MockCalled -CommandName Invoke-GitCommand -ParameterFilter { $Arguments -contains 'push' } -Times 1
    }

    It 'does not push when AutoPush is disabled' {
        $config = [pscustomobject]@{
            GitArgs       = @()
            AutoPush      = $false
            BufferSeconds = 5
        }

        Invoke-BackupCommit -Config $config -Events @()

        Assert-MockCalled -CommandName Invoke-GitCommand -ParameterFilter { $Arguments -contains 'push' } -Times 0
    }

    It 'writes git note on push failure' {
        Mock -CommandName Invoke-GitCommand -MockWith {
            param($Config, $Arguments, $CaptureOutput)
            if ($Arguments -contains 'push') { throw 'push error' }
        }
        Mock -CommandName Write-GitLogNote

        $config = [pscustomobject]@{
            GitArgs       = @()
            AutoPush      = $true
            BufferSeconds = 5
        }

        { Invoke-BackupCommit -Config $config -Events @() } | Should -Not -Throw

        Assert-MockCalled -CommandName Write-GitLogNote -ParameterFilter { $Message -like '*Push failed*' } -Times 1
    }
}
