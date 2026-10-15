/** App research labels; never an official rating or verified stable profit. */
export function classifyRole(e){
 const s=[e.name,e.fullName,e.fundType,e.index].join(' ').toLowerCase();
 const contains=words=>words.some(w=>s.includes(w.toLowerCase()));
 const result=(role,status,reason,risk)=>({role,status,reason,risk,historyVerified:false,ruleVersion:'role-1.0'});
 if(contains(["槓桿", "反向", "正2", "反1", "正向兩倍", "兩倍", "2倍"]) || e.code.endsWith("L") || e.code.endsWith("R"))return result('slotMachine',"結構判定","官方類型或名稱顯示槓桿／反向結構，通常以單日倍數為目標。","高｜每日重設與複利偏離；長期結果不是指數的固定倍數。");
 if(contains(["非投資等級", "高收益債", "新興市場債", "新興美元債", "新興債"]))return result('slotMachine',"策略初判","名稱或指數含較高信用／新興市場曝險。","偏高｜信用、匯率及流動性風險；仍須檢查實際持倉。");
 if(contains(["期貨", "期信", "石油", "原油", "vix", "波動率"]))return result('slotMachine',"結構初判","商品或期貨結構，須考慮轉倉與追蹤差異。","偏高｜不適合僅因價格低而視為存錢工具。");
 if(contains(["半導體", "科技", "生技", "機器人", "電動車", "航太", "5g", "網路", "人工智慧", "金融", "ic設計", "數位", "太空", "綠能", "nasdaq", "納斯達克", "那斯達克", "fang"]) || /\bai\b/i.test(s))return result('slotMachine',"集中度初判","名稱或指數具有產業／主題集中，優先於高息字樣判斷。","偏高｜產業景氣和集中度可能放大波動；未核驗歷史波動。");
 if(contains(["20年", "20+", "20yr", "20y", "長天期", "長期公債", "長債", "15年", "15+", "10年", "10+"]) && contains(["債", "bond", "treasury"]))return result('slotMachine',"利率敏感度初判","長天期債券對利率較敏感，不能因固定配息就視為穩定獲利。","偏高｜利率及匯率風險；分類是 App 初判。");
 if(contains(["0-1", "0至1", "0到1", "1-3", "1至3", "短期", "短天期", "短債"]) && contains(["公債", "政府債", "國庫券", "treasury"]))return result('piggyBank',"策略初判","短天期政府債策略偏向保守累積。","仍有匯率、利率與價格風險；不是保本存款。");
 if(contains(["高股息", "高息", "優息", "優利", "股利", "收益", "投資級", "投資等級", "公司債", "債券"]))return result('printer',"候選・待核驗","具有收益／配息取向；仍須以含息報酬、回撤與跨年度表現驗證獲利穩定性。","尚未證實穩定獲利；配息不等於總報酬，也可能減少。");
 if(contains(["主動式", "主動", "active"]))return result(null,"待核驗","主動管理不能直接推定穩定或高風險，需取得持倉與歷史報酬。","資料不足，暫不強制放入三類。");
 if(contains(["台灣50", "臺灣50", "中型100", "s&p 500", "s&p500", "標普500", "標準普爾500", "全市場", "全世界", "全球股票", "msci臺灣", "msci台灣", "加權", "市值", "富櫃50", "摩台", "msci world", "msci acwi"]))return result('piggyBank',"策略初判","大盤／廣泛市場指數適合作為長期累積取向的研究起點。","股票仍可能大幅回撤；單一市場或權重集中仍有風險。");
 return result(null,'待核驗','目前公開欄位不足以判斷投資角色，需檢查指數規則、持倉與含息報酬。','不以名稱猜測穩定獲利。');
}
