# ETF 袋著走 · Native UI Review

2026-10-15 新建立的 SwiftUI 介面實作。不是從無法下載的 ETFToGo_Native_UI_V2 原始工程恢復，也不是完成的 TestFlight 發佈版。

五個原生分頁：首頁、找 ETF、我的持有、配息、工具。支援持有編輯、本機 JSON 原子儲存、配息紀錄、收藏、兩檔比較、成本配置、複利情境試算、原生備份分享與合併匯入。個人富果金鑰以 Keychain 保存，僅傳給官方 API。

## 建置

安裝官方 Homebrew 套件 `xcodegen`。先將 Pocket.imageset/pocket.png 用 macOS sips 等比輸出為 AppIcon.appiconset/AppIcon.png 的 1024 × 1024 PNG，再於本目錄執行 `xcodegen generate`，以 Xcode 開啟 ETFToGo.xcodeproj。GitHub 的手動 native-ui workflow 會執行這些步驟、編譯、跑測試與擷取五張 iPhone 模擬器畫面。最終以 CI 實際結果為準。

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

驗收 UI、補接正式資料與原版功能、確認 Apple Developer Team 和正式 Bundle ID、建立 ETF 專用 provisioning profile 與 App Store Connect App、簽署 archive、上傳並確認 TestFlight 處理與測試者可用狀態。現在的 workflow 只做模擬器，沒有上傳功能，也不會修改其他 App。

富果來源：https://developer.fugle.tw/docs/data/http-api/intraday/quote/
