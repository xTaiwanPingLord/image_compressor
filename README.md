# image_compressor

跨平台圖片壓縮工具。目前為第一階段：Rust 核心（`crates/imgcore`）＋ 命令列工具 `imgc`（`crates/cli`），已完成電商模式（Shopee / momo）。規格見 Claude 專案中的 `plan.md`。

## 建置（Windows）

需要：rustup（stable，≥1.88）、Visual Studio 2022 Build Tools（Desktop C++）、NASM（mozjpeg SIMD 用，需在 PATH）。

```
cargo test            # 規格測試
cargo build --release # 產生 target\release\imgc.exe
```

## 用法

```
imgc info 商品_1.png 商品_2.jpg
imgc ecommerce --name 223_ssd --main 主圖資料夾 --variant 規格_1.jpg --desc 詳情資料夾 ^
     --crop 商品_1.png --smart-cut
```

| 參數 | 說明 |
|---|---|
| `--main / --variant / --desc` | 檔案或資料夾，可多個；預設依檔名自然排序（`--keep-order` 保持輸入順序） |
| `--platform shopee momo` | 預設兩個平台都輸出 |
| `--fit pad\|crop` | 主圖/選項圖比例不符時的預設處理（預設補白） |
| `--crop 檔名 …` / `--pad 檔名 …` | 個別圖片改用裁切或補白 |
| `--shopee-max 12` / `--momo-max 18` | 詳情圖最多張數（momo 上限 20） |
| `--smart-cut` | 切段處往上 150px 找最接近純色的橫列下刀 |
| `--out 路徑` | 輸出根目錄（預設：三區合計圖片最多的來源資料夾） |
| `--dry-run` | 只預檢與壓縮，不寫檔 |
| `--no-trash` | 舊檔移到 `_old/`，不用系統垃圾桶 |
| `--json` | 以 JSON 輸出結果 |

也可用 `imgc job 工作檔.json` 執行（欄位同 `imgcore::ecommerce::Job`，可個別設定每張圖的 `fit`）。

詳情圖段數超過上限時會顯示警告、整批不輸出（exit code 2）。輸出到 `<來源>/shopee/`、`<來源>/momo/`，檔名 `name_main_01.jpg`、`name_variant_01.jpg`、`name_desc_01.jpg`；重新執行時只清理本次有處理的類別舊檔。
