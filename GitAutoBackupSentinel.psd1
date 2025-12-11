@{
    RootModule        = 'git-autobackup.ps1'
    ModuleVersion     = '1.0.0'
    GUID              = '00000000-0000-0000-0000-000000000001'
    Author            = 'Will 保哥'
    CompanyName       = 'Community'
    LicenseUri        = 'https://opensource.org/licenses/MIT'
    ProjectUri        = 'https://github.com/doggy8088/git-auto-backup-sentinel'
    Description       = 'Automatically stage, commit, and optionally push git changes with debounced filesystem monitoring.'
    PowerShellVersion = '5.1'
    FunctionsToExport = @()
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
    PrivateData       = @{
        PSData = @{
            Tags         = @('git', 'backup', 'automation')
            LicenseUri   = 'https://opensource.org/licenses/MIT'
            ProjectUri   = 'https://github.com/doggy8088/git-auto-backup-sentinel'
            ReleaseNotes = 'Initial release with auto-backup sentinel script.'
        }
    }
}
