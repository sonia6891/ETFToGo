# ETF 袋著走 · Native UI Review

2026-10-15 新建立的 SwiftUI 介面實作。不是從無法下載的 ETFToGo_Native_UI_V2 原始工程恢復，也不是完成的 TestFlight 發佈版。

五個原生分頁：首頁、找 ETF、我的持有、配息、工具。支援持有編輯、本機 JSON 原子儲存、配息紀錄、收藏、兩檔比較、成本配置、複利情境試算、原生備份分享與合併匯入。個人富果金鑰以 Keychain 保存，僅傳給官方 API。

## 建置

使用 Xcode 26.6，安裝官方 Homebrew 套件 `xcodegen`。先將 App/Assets.xcassets/Pocket.imageset/pocket.png 用 macOS sips 等比輸出為 App/Assets.xcassets/AppIcon.appiconset/AppIcon.png 的 1024 × 1024 PNG，再於本目錄執行 `xcodegen generate`，以 Xcode 開啟 ETFToGo.xcodeproj。GitHub 的手動 native-ui workflow 會執行這些步驟、編譯、跑測試與擷取五張 iPhone 模擬器畫面。最終以 CI 實際結果為準。

開發用 Bundle ID 為 `tw.sonia.etftogo.uireview`，尚未在 Apple 註冊，不能當作已核准的正式 Bundle ID。iOS 17 起，SwiftUI，無 WebView。

## 資料與限制

- 正常啟動為空資料；`--demo` 僅供介面測試，金額與價格是固定範例，不是真實行情，且不寫入正式資料檔。
- 目前內建 6 檔 UI 起始清單；不宣稱涵蓋全部台灣 ETF。可手動新增其他代碼的持有。完整名單需從原工程／交易所正式資料再接回。
- 富果 HTTP API 依官方文件實作，沒有真實金鑰，因此未完成線上帳戶實測。
- 配息為使用者記錄，尚未串接公告；成分股穿透、完整費用率與歷史績效未完成。
- 只支援本工程 schema 1 備份；沒有聲稱與舊 PWA 備份相容。匯入前先驗證，損壞的現有儲存檔不覆寫。
- 分類是整理策略，不是投資建議、保本或獲利保證。
- 沿用既有網站口袋圖示：`https://etf-independent-app-production.up.railway.app/icon-512-v171.png`。原圖 512 × 512，SHA-256 `b1ad9792e4c3b90e683b13a1eb68a18239171cdbc4c0bf67a77aaf0a0a558f6a`。App Icon 的 1024 版本是放大，不是新增細節。

## 尚待發佈工作

驗收 UI、補接正式資料與原版功能、確認 Apple Developer Team 和正式 Bundle ID、建立 ETF 專用 provisioning profile 與 App Store Connect App、簽署 archive、上傳並確認 TestFlight 處理與測試者可用狀態。

`native-ui.yml` 只做模擬器。`testflight.yml` 已準備手動簽署、archive 與 App Store Connect 上傳步驟；缺任何必要設定時會在前置檢查中停止。簽署與上傳尚未成功執行，不能把設定檔視為發佈證據。也尚未建立可安裝的 TestFlight build。

請在私人倉庫的 Settings → Secrets and variables → Actions 設定，勿在對話貼出密鑰：

- Variable `ETF_BUNDLE_ID`：在 Apple 註冊、且 App Store Connect App 使用的正式識別碼。
- Secrets `APPLE_TEAM_ID`、`APPLE_ASC_KEY_ID`、`APPLE_ASC_ISSUER_ID`、`APPLE_ASC_KEY_P8`。
- Secrets `APPLE_DISTRIBUTION_P12_BASE64`、`APPLE_DISTRIBUTION_P12_PASSWORD`。
- Secret `APPLE_PROFILE_ETF_BASE64`：對應正式 ETF Bundle ID 的 App Store distribution profile，不能沿用其他 App 的 profile。

上傳成功後仍需查驗 Apple 處理結果、出口合規問題、測試群組與邀請；外部測試可能需要 Beta App Review。

## 已找回的較早原始碼

倉庫另外收到 `releases/v1.7.2/` 歷史來源，其中 `ios/` 是較早的原生 0.1.0 工程，含較完整的 ETF 名單、舊備份相容與成分股等功能。目前尚未移植到本 UI 審閱版，不能宣稱功能已完整保留。歷史來源原樣保留；它不是本次編譯的 App，也不是先前缺失的 Native UI V2。

富果來源：https://developer.fugle.tw/docs/data/http-api/intraday/quote/
