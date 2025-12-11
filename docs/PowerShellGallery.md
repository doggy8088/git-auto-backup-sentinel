# 上架 PowerShell Gallery 指引

本文說明如何將 Git Auto-Backup Sentinel 發佈到 PowerShell Gallery。

## 先決條件

- 安裝 PowerShellGet：`Install-Module PowerShellGet -Scope CurrentUser`.
- 申請並設定 NuGet API Key（`$env:NuGetApiKey`）。
- 確保 `git-autobackup.ps1` 放在模組資料夾並包含必要中繼資料（Version、Author、LicenseUri）。

## 打包模組

1. 建立模組結構：
   ```
   .\GitAutoBackupSentinel\
     GitAutoBackupSentinel.psd1
     git-autobackup.ps1
   ```
2. 編寫 `GitAutoBackupSentinel.psd1`，設定 `RootModule = 'git-autobackup.ps1'`、`Author = 'Will 保哥'`、`LicenseUri` 指向 MIT 授權。
3. 版本號遵循語意化版本。

## 發佈

```powershell
Publish-Module -Path .\GitAutoBackupSentinel -NuGetApiKey $env:NuGetApiKey -Repository PSGallery
```

## 驗證

- 安裝測試：`Install-Module GitAutoBackupSentinel -Scope CurrentUser`.
- 執行：`git-autobackup.ps1 -BufferSeconds 5 -AutoPush`.

## 常見問題

- 如遇認證問題，確認 API Key 正確與網路可連線。
- 若模組包含依賴，請於 `.psd1` 中標註 `RequiredModules`。
