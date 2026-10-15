# 1.7.2 圖示相容性修正

部署來源：`deploy/railway-v172.ts`。保留 1.7.1 的功能與介面，僅修改安裝圖示 metadata 與公開圖片 HTTP 回應；iPhone 主畫面是否採用仍需實機確認。

> 2026-10-15 最新 PWA 版本：1.7.1，已部署並核對公開檔案與本機一致。新入口：https://etf-independent-app-production.up.railway.app/app-v171.html 。iPhone 加入主畫面的口袋圖示仍待實機確認，不宣稱已完成實機驗收。詳見 `docs/release-v171.json`。iOS 原生工程維持原版本。

# ETF 袋著走 1.7.0

目前主畫面 App：https://etf-independent-app-production.up.railway.app/

## 1.7.0 操作介面整理
- 底部分頁改為首頁／找 ETF／持有／配息／更多；配息提醒仍保留在頂部鈴鐺、配息頁與更多。
- 首頁直接新增持有與記錄股息；ETF 詳情的記錄持有、比較按鈕移到內容前方。
- 三種投資角色以文字卡片呈現；基金策略仍可展開篩選，新增清除搜尋與篩選。
- 更多依試算與研究、我的紀錄、備份與設定分組；所有原有功能入口保留。
- 工具頁使用明確名稱與返回位置；表單分區、按鈕文字、觸控區域和文字大小調整。
- 財務公式、ETF 分類規則、行情服務、資料驗證、儲存鍵與備份格式不變。原生 iOS 工程未作介面修改。
- 部署來源：`deploy/railway-v170.ts`；產生指令：`node scripts/package-ui-release.mjs`。需要既有公開素材環境變數與本版 `ETF_ASSETS_V170_*`。
- iPhone 主畫面 E 圖示問題仍未確認解決，這次不宣稱已修好。

## 1.6.x 功能範圍
- 保留 1.5.0 介面、口袋 Icon、持有／配息／收藏的原有儲存鍵。
- 證交所上市 ETF 全類型名單，含海外標的與外幣級別，不含上櫃。2026-10-14 快照為 272 個證券代碼。
- 存錢筒／印鈔機／老虎機：規則初判、收益候選及待核驗；無任何已驗證穩定獲利標的。
- 篩選、逐檔判斷依據與風險說明，與原本基金策略分類分開。
- 1.6.0 Service Worker 快取；使用原網址即可更新，不必刪除主畫面 App。
- 外幣 ETF 的自填估值須換算台幣，不提供自動匯率轉換。

## 開發
Node 22+：`npm run build`、`npm test`。
Bun：公開參考服務 `PORT=3001 bun server/reference-service.js`；主服務 `APP_ORIGIN=https://your-domain.example REFERENCE_ENDPOINT=http://127.0.0.1:3001/catalog bun server/index.js`。
不得提交 `.env` 或行情金鑰。
`deploy/railway-v161.ts` 與 `reference-v160.ts` 是本次既有 Railway Functions 的完整部署來源；主 Function 沿用既有公開資產環境變數。全新部署請使用 server/index.js，無需舊資產變數。

## 原生 iOS
`ios/` 保留 SwiftUI 0.1.0-native-source 工程；尚未經 Xcode 完整編譯、簽章或真機驗證。根目錄 GitHub Actions 已設定 ios 工作目錄；遠端尚未執行。原生版本與 PWA 各自保存資料，可透過備份匯出／匯入。

## 驗證
62 項 JavaScript 測試通過、60 項模擬資料介面流程檢查通過（含 320px 各頁面）。另檢查四種角色篩選、272 代碼載入、候選說明與無水平溢出。原生核心25項測試已通過。

## 尚未完成
完整歷史含息報酬與分類驗證、官方配息自動同步、跨券商同步、iOS 簽章與安裝包。GitHub 專用儲存庫尚未取得，沒有宣稱已推送。

## 1.6.1 圖示修正
沿用口袋原圖，像素相同，轉為 RGB PNG；全新 v161 圖示網址、真實 favicon.ico、根目錄 apple-touch-icon-precomposed.png、更新 manifest 啟動版本。新增 /install-v161.html 安裝入口。62 項程式測試通過；尚待使用者 iPhone 加入主畫面預覽確認，不宣稱已在真機解決。

## 1.6.2 安裝流程修訂
撤回描述檔安裝引導與下載端點，回到 Safari「分享 → 加入主畫面」。`/install-pocket.html` 只提供一般入口與簡短說明，不再提供描述檔下載。

手機日誌顯示新版圖示請求成功，但使用者實機的安裝預覽仍顯示 E；原因尚未確認，不能視為已修復。此修訂沒有清除本機資料，也沒有變更 App 功能、圖示或主網址。

部署檔：`node scripts/package-simple-install.mjs` 產生 `deploy/railway-simple-install.ts`；延用既有公開素材變數，僅覆寫安裝頁與 HTTP host。
