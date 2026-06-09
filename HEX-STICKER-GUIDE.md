# 六角徽章（hex sticker）說明 — yyliou 系列風格

`twhotel` 的徽章刻意做成跟你其他套件／課程徽章（`twweather`、`Statistics`、
`Data Analysis`、`Programming`…）同一套風格。這份文件記錄那套規格，方便日後重做或新增。

成品：`man/figures/logo.png`；可編輯原始檔：`man/figures/logo.svg`。

---

## 1. 共通規格（house style）

所有徽章都用同一份手繪 SVG 樣板，**不靠 hexSticker、不用漸層**，重點是乾淨、扁平、好縮小：

| 項目 | 規格 |
|---|---|
| 畫布 | `viewBox="0 0 173 200"`（尖角朝上的正六邊形） |
| 六邊形路徑 | `M86.5 2 L171 50.5 V149.5 L86.5 198 L2 149.5 V50.5 Z` |
| 填色 | 單一中明度主色，`stroke` 用更深一階、`stroke-width="4"`、`stroke-linejoin="round"` |
| 內框 | 同一條路徑，`fill="none"`、淡色 tint、`stroke-width="1.5"`、`opacity="0.55"`，並 `scale(0.92)` 內縮 |
| 主視覺 | **單色白色**為主，搭配同色系淡 tint 作次要元素（軸線、底線、網格）。置於上半部 |
| 套件名 | 置中 `x="86.5"`、`y≈140`、**Georgia 襯線粗體**、白色，字級依長度調整（約 19–26） |
| 其他 | 不放網址、不放副標、不加陰影或漸層 |

每個套件配一個專屬色相（已用：藍 `#3a82c4`、海軍藍 `#2b4c6f`、磚紅 `#a4593e`、墨綠 `#2f5d50`）。

## 2. twhotel 用色與圖案

- **色相（梅紫，未與其他徽章重複）**：主色 `#7a4a63`、深框 `#5c3149`、淡 tint `#e0c2d2`。
- **圖案**：一棟白色旅館立面，窗戶與大門用「挖空」手法（填回背景主色）露出底色；門上方一道
  tint 雨遮、底部一條 tint 地面線；上方四顆 tint 星星 = 旅館星級。整體呼應「觀光旅館」主題，
  又維持系列的極簡白色主視覺。

## 3. 怎麼改

直接編輯 `man/figures/logo.svg`：

- 換色：改三個顏色（主色 / `stroke` 深色 / tint）即可，其餘留白。
- 換字：改最後一個 `<text>`；字太長就把 `font-size` 調小（參考 weather=26、Data Analysis=19）。
- 換圖：主圖形用 `fill="#ffffff"`，次要元素用 tint。窗戶這類「挖空」用 `fill-rule="evenodd"`
  的複合 path（外框順時針、內孔同向）即可。

改完轉 PNG（README／pkgdown 用）：

```bash
rsvg-convert -w 1200 man/figures/logo.svg -o man/figures/logo.png
# 或
python3 -c "import cairosvg; cairosvg.svg2png(url='man/figures/logo.svg', \
            write_to='man/figures/logo.png', output_width=1200, output_height=1387)"
```

> 高寬比固定 173:200，所以 1200 寬對應 1387 高，縮放不會變形。

## 4. 掛到 README / pkgdown

慣例放在 `man/figures/logo.png`，README 標題列右側用一行 HTML：

```markdown
# twhotel <img src="man/figures/logo.png" align="right" height="138" alt="twhotel hex logo" />
```

`height="138"` 是 tidyverse 慣用值。若用 `usethis`：`usethis::use_logo("man/figures/logo.png")`。

## 5. （選用）hexSticker 路線

若想改用 R 的 [`hexSticker`](https://github.com/GuangchuangYu/hexSticker) 產生，本 repo 附了
`make-logo.R`。注意 hexSticker 產出的構圖（圓角小圖＋自動排版）跟上述手繪扁平風格略有差異；
本套件**實際出貨的是手繪 SVG**，hexSticker 版僅作備選。
