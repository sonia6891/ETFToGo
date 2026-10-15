# 1.7.3 桌面捷徑安裝

完整應用程式基底見 ../v1.7.2/。本版本只新增 /install-icon.html 與 /ETFToGo-Pocket.mobileconfig，既有 App HTML 與功能保持不變。部署使用 deploy/railway-v173.ts（完整 Railway Function）。

描述檔只含一個可移除 Web Clip，內嵌原有口袋 PNG，指向既有 production App；不含 MDM、VPN、憑證、帳號設定。未簽署，安裝需使用者自行於 iOS 設定確認。保留舊入口與本機資料備份。iPhone 實機結果尚待確認；不宣稱原 Safari 圖示辨識問題已修復。
