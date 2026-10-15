# ETF 袋著走 · Native UI Review

目前唯一使用的原始碼為本工程的 SwiftUI 0.2.0。依 2026-10-15 的決定，後續開發以此版本為準，舊版來源已從現行工程移除。本版尚未完成 TestFlight 發佈。

五個原生分頁：首頁、找 ETF、我的持有、配息、工具。支援持有編輯、本機 JSON 原子儲存、配息紀錄、收藏、兩檔比較、成本配置、複利情境試算、原生備份分享與合併匯入。個人富果金鑰以 Keychain 保存，僅傳給官方 API。

本次已通過 Xcode 26.6 的原生建置及 8 項測試，並完成正式簽署、archive 與 IPA 匯出。**尚未上傳 TestFlight**，目前卡在 Apple 網站的新 App 記錄。完整證據與限制見 `RELEASE_STATUS.md`。

## 建置

使用 Xcode 26.6，安裝官方 Homebrew 套件 `xcodegen`。先將 App/Assets.xcassets/Pocket.imageset/pocket.png 用 macOS sips 等比輸出為 App/Assets.xcassets/AppIcon.appiconset/AppIcon.png 的 1024 × 1024 PNG，再於本目錄執行 `xcodegen generate`，以 Xcode 開啟 ETFToGo.xcodeproj。GitHub 的手動 native-ui workflow 會執行這些步驟、編譯、跑測試與擷取五張 iPhone 模擬器畫面。最終以 CI 實際結果為準。

本機預覽用 Bundle ID 為 `tw.sonia.etftogo.uireview`。正式 Bundle ID `com.sonia.etftogo` 已向 Apple 註冊；封存時以建置設定覆蓋為正式 ID。iOS 17 起，SwiftUI，無 WebView。交付資料夾已包含產生的 Xcode 專案與 App Icon，可直接開啟 ETFToGo.xcodeproj。

## 資料與限制

- 正常啟動為空資料；`--demo` 僅供介面測試，金額與價格是固定範例，不是真實行情，且不寫入正式資料檔。
- 目前內建 6 檔 UI 起始清單；不宣稱涵蓋全部台灣 ETF。可手動新增其他代碼的持有。完整名單待使用交易所正式資料擴充。
- 富果 HTTP API 依官方文件實作，沒有真實金鑰，因此未完成線上帳戶實測。
- 配息為使用者記錄，尚未串接公告；成分股穿透、完整費用率與歷史績效未完成。
- 只支援本工程 schema 1 備份；沒有聲稱與舊 PWA 備份相容。匯入前先驗證，損壞的現有儲存檔不覆寫。
- 分類是整理策略，不是投資建議、保本或獲利保證。
- 沿用既有網站口袋圖示：`https://etf-independent-app-production.up.railway.app/icon-512-v171.png`。原圖 512 × 512，SHA-256 `b1ad9792e4c3b90e683b13a1eb68a18239171cdbc4c0bf67a77aaf0a0a558f6a`。App Icon 的 1024 版本是放大，不是新增細節。

## 尚待發佈工作

Apple Team、正式 Bundle ID、ETF 專用 provisioning profile 與已簽署 archive 均已備妥。接下來需要建立 App Store Connect App 記錄、上傳並確認 TestFlight 處理與測試者可用狀態。

`native-ui.yml` 做模擬器驗證。`testflight.yml` 提供此倉庫專用的手動發佈流程，缺設定會在前置檢查停止。

已使用既有 Apple 簽署環境的獨立分支完成正式簽署、archive 和 IPA 匯出：版本 **0.2.0 (2.2)**、**Xcode 26.6 / iOS 26.5 SDK**、正式 Bundle ID **com.sonia.etftogo**。成功紀錄：[signed archive run 38665723372](https://github.com/sonia6891/meow-work-app/actions/runs/38665723372)。來源固定為 ETFToGo commit `b4d340a506324318969c8c550ee8e95ef259e0fd`；既有 App 的主分支未變更，秘密仍留在原本的 GitHub 簽署環境。

**尚未上傳，也沒有可安裝的 TestFlight build。** Apple API 已確認 ETF App 記錄不存在，上傳步驟因此跳過；必須先在 App Store Connect 網站登入並建立記錄。參見 `RELEASE_STATUS.md`。IPA 是 App Store distribution 檔，不能當成一般 iPhone 點開即可安裝的檔案。

若日後要把簽署流程獨立搬到此私人倉庫，在 Settings → Secrets and variables → Actions 設定以下項目；現有獨立簽署分支已可使用，毋須為本次重建憑證或在對話貼出密鑰：

- Variable `ETF_BUNDLE_ID`：在 Apple 註冊、且 App Store Connect App 使用的正式識別碼。
- Secrets `APPLE_TEAM_ID`、`APPLE_ASC_KEY_ID`、`APPLE_ASC_ISSUER_ID`、`APPLE_ASC_KEY_P8`。
- Secrets `APPLE_DISTRIBUTION_P12_BASE64`、`APPLE_DISTRIBUTION_P12_PASSWORD`。
- Secret `APPLE_PROFILE_ETF_BASE64`：對應正式 ETF Bundle ID 的 App Store distribution profile，不能沿用其他 App 的 profile。

上傳成功後仍需查驗 Apple 處理結果、出口合規問題、測試群組與邀請；外部測試可能需要 Beta App Review。

富果來源：https://developer.fugle.tw/docs/data/http-api/intraday/quote/
