# ETF 袋著走 1.7.1

- 保留 1.7.0 介面及所有財務、持有、配息、備份功能。
- 加入同網域的新入口 `/app-v171.html`，保持原有 manifest ID、scope 與資料儲存鍵。
- 圖示使用 v171 新路徑；PWA 不攔截 PNG/ICO/manifest；圖示 HTTP 回應提供完整內容與正確 HEAD 長度。
- 原圖示圖案與像素不變。
- 公開版本 1.7.1 已確認；63 項 Node 測試通過。
- iPhone 安裝預覽尚待使用者實機確認；不能斷言 Safari 圖示快取就是根因。
- Railway 原先 source code 更新卡住，redeploy 只重跑舊快照；更新 release 環境變數觸發新的部署後，公開版本已切換。
