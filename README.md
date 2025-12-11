# Git Auto-Backup Sentinel

Git Auto-Backup Sentinel 會監控指定資料夾的檔案變更，並在變更靜置一段時間後自動執行 Git 的暫存、提交與可選擇的自動推送。所有事件與錯誤資訊都會以 Git Log/Notes 的方式保存，方便追蹤。

## 功能概述

- 監控檔案的新增、修改、刪除與重新命名（遞迴目錄）。
- 依可調整的緩衝秒數進行 Debounce，避免過於頻繁的提交。
- 自動執行 `git add -A` 與提交，提交訊息包含事件摘要。
- 選擇性自動 `git push`，並將 Push 成功或失敗訊息記錄到 Git Notes。
- 啟動時會驗證目標目錄與 `.git` 目錄有效性。
- 所有事件與錯誤都寫入 Git Notes（`autobackup-log`）。

## 安裝與使用

在 PowerShell 中於專案根目錄執行：

```powershell
.\git-autobackup.ps1
```

### 參數

| 參數 | 預設值 | 說明 |
| ---- | ------ | ---- |
| `-TargetPath` | 目前工作目錄 | 欲監控的專案根目錄。 |
| `-BufferSeconds` | `5` | 檔案變更後等待的秒數，期間若有新事件會重置計時。 |
| `-AutoPush` | `False` | 啟用後，每次成功提交會立即嘗試 `git push`。 |
| `-GitDir` | `$TargetPath\.git` | 指定 Git 目錄路徑。 |
| `-Init` | `False` | 若指定則會執行 `git init -b main` 初始化儲存庫；可搭配 `-GitDir` 使用。 |

### 使用範例

```powershell
# 預設 5 秒緩衝，不自動推送
.\git-autobackup.ps1

# 自訂 10 秒緩衝
.\git-autobackup.ps1 -BufferSeconds 10

# 啟用自動 Push 並指定路徑
.\git-autobackup.ps1 -TargetPath "C:\Dev\MyProject" -AutoPush

# 指定工作目錄與 Git 目錄
.\git-autobackup.ps1 -TargetPath "C:\Dev\MyProject" -GitDir "D:\Repos\MyProject\.git" -AutoPush

# 初始化新儲存庫並啟用自動 Push
.\git-autobackup.ps1 -TargetPath "C:\Dev\MyNewProject" -Init -AutoPush
```

## 日誌與追蹤

- 事件摘要與錯誤會寫入 Git Notes：`git notes --ref=autobackup-log show`.
- Push 失敗時會以紅色訊息顯示，並寫入 Notes，但不會中斷監控。

## 終止方式

按下 `Ctrl+C` 即可停止監控並釋放所有資源。

## 測試

使用 [Pester](https://pester.dev/)：

```powershell
pwsh -NoLogo -Command "Invoke-Pester -Path tests"
```

## 授權

本專案採用 MIT 授權，詳見 [LICENSE](LICENSE)。
