# image_compressor

跨平台圖片壓縮工具。規格見 Claude 專案中的 `plan.md`。

| 目錄 | 內容 |
|---|---|
| `crates/imgcore` | Rust 影像核心：電商模式（Shopee / momo）、普通模式（對照 Caesium） |
| `crates/cli` | 命令列工具 `imgc` |
| `app/` | Flutter 桌面 / 行動 App；`app/rust` 以 flutter_rust_bridge 包裝 imgcore |

## 桌面 App（Windows）

雙擊 `build_windows.bat`：檢查開發人員模式 → `flutter build windows --release` → 成功後自動開啟 App。
執行檔在 `app\build\windows\x64\runner\Release\image_compressor.exe`（整個 Release 資料夾一起複製才能在別台電腦執行）。記錄寫在 `build_windows.log`。

### 多語系、主題與字體

- 設定頁：語言（繁體中文 / 简体中文 / English）、主題（自動 / 淺色 / 深色）、色彩（10 色或跟隨系統：Android 12+ 桌布色、Windows / macOS 強調色）、字體（系統預設 / 內建 MiSans，依語言以 MiSans TC 或 MiSans 為主、另一套補字）
- 介面文字在 `app/lib/l10n/app_zh.arb`（繁中，範本）、`app_zh_CN.arb`、`app_en.arb`；修改後執行 `flutter gen-l10n`
- Rust 端的警告與錯誤以代碼傳到 UI 再翻譯（`imgcore::warn::Warn`、`ErrorInfo`）
- MiSans TC 與 MiSans（小米 MiSans 字體，免費商用，需在軟體中註明）：`app/assets/fonts/`，各 Regular / Medium / Semibold / Bold，合計約 39 MB
- Windows 已停用無障礙（UIA / MSAA）橋接：Flutter 引擎的 AccessibilityBridge 有空指標崩潰（flutter/flutter#182444），runner 攔截 `WM_GETOBJECT` 避免啟用，代價是螢幕閱讀器無法讀取本程式

修改 `app/rust/src/api` 後需重新產生 binding：`cd app && flutter_rust_bridge_codegen generate`（需先 `cargo install flutter_rust_bridge_codegen --version 2.13.0`）。

## 建置（Windows）

需要：rustup（stable，≥1.88）、Visual Studio 2022 Build Tools（Desktop C++）、NASM（mozjpeg SIMD 用，需在 PATH）。

```
cargo test            # 規格測試
cargo build --release # 產生 target\release\imgc.exe
```

## 用法

### 普通模式

```
imgc compress 圖片或資料夾… [-q 80] [--lossless] [--max-kb 500] [--format same|jpeg|png|webp]
              [--long-edge 1920] [--out 資料夾] [--suffix _compressed] [--strip]
```

資料夾會含子資料夾；指定 `--out` 時保留資料夾結構。App 內有完整設定（壓縮 / 縮放 / 輸出）與即時預覽。

### 電商模式

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
| `--shopee-max-width 2000` | Shopee 輸出最大寬度，0 = 不限制 |
| `--momo-min-last 300` | momo 詳情圖尾段低於此高度時從前一段挪高度，0 = 保持實際高度 |
| `--smart-cut` | 切段處往上 150px 找最接近純色的橫列下刀 |
| `--out 路徑` | 輸出根目錄（預設：三區合計圖片最多的來源資料夾） |
| `--dry-run` | 只預檢與壓縮，不寫檔 |
| `--no-trash` | 舊檔移到 `_old/`，不用系統垃圾桶 |
| `--json` | 以 JSON 輸出結果 |

也可用 `imgc job 工作檔.json` 執行（欄位同 `imgcore::ecommerce::Job`，可個別設定每張圖的 `fit`）。

詳情圖段數超過上限時會顯示警告、整批不輸出（exit code 2）。輸出到 `<來源>/shopee/`、`<來源>/momo/`，檔名 `name_main_01.jpg`、`name_variant_01.jpg`、`name_desc_01.jpg`；重新執行時只清理本次有處理的類別舊檔。
