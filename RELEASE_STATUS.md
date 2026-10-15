# ETF 袋著走 — 原生 UI 審閱版與發佈紀錄

更新日期：2026-10-15。這是本次新實作的 SwiftUI UI 審閱版，不是聲稱已找回的 ETFToGo_Native_UI_V2。

## 已實際完成

- 五個原生分頁：首頁、找 ETF、我的持有、配息、工具。
- 可操作的持有新增／編輯／刪除、配息記錄、收藏、比較、試算、備份與富果金鑰設定。
- 正式 Bundle ID：`com.sonia.etftogo`。Apple 資源 ID：`465MBRR9MN`。
- 專用 App Store profile：`M8Z48T98CP`，狀態 ACTIVE，有效至 2027-09-30。
- 原生 arm64 iPhone App 簽署、封存、匯出成功，版本 `0.2.0 (2.2)`。
- 封存工具：Xcode 26.6 (17F113)，iOS 26.5 SDK；最低 iOS 17。
- IPA 含正式 Bundle ID、原生執行檔、App Icon 與 embedded provisioning profile。CI 已執行嚴格簽署驗證。
- IPA SHA-256：`1bc8250e10a6b2eb7439370352ba298a4d7402ebf11ae45687d2f36a86ecf185`。

## 可重查的證據

- [iOS 18.5 模擬器驗證](https://github.com/sonia6891/ETFToGo/actions/runs/38664300600)：6 項單元測試、2 項 UI 測試通過。搜尋、五個分頁操作、持有儲存後重新啟動均有自動化驗證。
- [Xcode 26.6 模擬器驗證](https://github.com/sonia6891/ETFToGo/actions/runs/38665125561)：**成功**。iPhone 17 Pro / iOS 26.4.1 上完成原生編譯、五頁截圖、6 項單元測試及 2 項 UI 測試，全部零失敗。包含損壞資料原始位元組匯出、搜尋鍵盤收起與持有重新啟動後保留。
- [正式簽署與匯出](https://github.com/sonia6891/meow-work-app/actions/runs/38665723372)：ARCHIVE SUCCEEDED、EXPORT SUCCEEDED。Upload 步驟為 skipped。
- 本資料夾 `Evidence/` 保存封存、匯出、Apple 設定與 IPA 檢查結果。
- `Screens/` 保存五張 1206 × 2622 原尺寸截圖與總覽；全部為實際模擬器輸出，使用示範資料。
- 編譯／封存來源：ETFToGo commit `b4d340a506324318969c8c550ee8e95ef259e0fd`。

## TestFlight 尚缺的步驟

Apple API 可讀取帳號並使用現有發佈憑證；不需要再購買會員或重建憑證。目前缺少 ETF 的 App Store Connect App 記錄，網站尚未登入成功。

1. 在 [App Store Connect](https://appstoreconnect.apple.com/apps) 登入既有 Apple Developer 帳號並完成雙重驗證。
2. 在「我的 App」新增 iOS App：名稱「ETF 袋著走」、主要語言繁體中文、Bundle ID `com.sonia.etftogo`、SKU `ETFTOGO-IOS-001`。若 Apple 提示名稱不可用，需另行決定名稱，不能宣稱已建立。
3. 完成後即可續行原生上傳；再確認 Apple 處理成功、出口合規、測試群組與邀請。外部測試可能需要 Beta App Review。

既有簽署環境的獨立分支為 `sonia6891/meow-work-app` 的 `codex/etftogo-signing-check-20261015`，工作流程 `.github/workflows/etftogo-archive.yml`。其輸入是固定版本的 ETF 原生來源 ZIP；不改動原 App 主分支、不把秘密匯出到本機或 ETF 倉庫。重新執行會先查詢 ETF App 記錄；不存在時仍會跳過上傳。

**目前沒有 TestFlight 安裝連結，也沒有實機安裝成功證據。** 已簽署 IPA 只能作為發佈產物，不能冒充 TestFlight 邀請。

## 這版的範圍

- 正常啟動為空資料。截圖使用 `--demo`，數字為示範資料，且不寫入使用者正式資料。
- 本版僅內建 6 檔 UI 起始清單；原始碼檔案庫中的歷史 `releases/v1.7.2/ios/` 包含 272 筆上市代碼快照，尚未移植到本版。快照不等於即時全台 ETF 總數，也不含上櫃。
- 原生 JSON 存檔採原子寫入，壞檔不覆寫，匯出會保留損壞檔原始位元組以便救援。本版 schema 1 備份尚不相容舊 PWA 備份。
- 富果以官方 HTTP API 和 Keychain 實作；尚無可用的個人富果金鑰，因此沒有帳戶連線實測證據。報價缺失時不會用成本假裝市值。
- 配息由使用者記錄，區分已入帳、已公告、預估，沒有自動公告串接。
- 原版的完整名單、成分股、舊備份、完整配息欄位和其他進階功能尚待整合，不宣稱這是功能完整的舊版替代品。
- App Icon 沿用既有 512 × 512 圖案，1024 × 1024 版本為等比放大，已成功納入 App。

Apple 官方說明：[新增 App 必須從網站進行](https://developer.apple.com/documentation/appstoreconnectapi/apps)、[建立 App 記錄](https://developer.apple.com/help/app-store-connect/create-an-app-record/add-a-new-app/)、[現行 SDK 最低要求](https://developer.apple.com/news/upcoming-requirements/?id=04282026a)。
