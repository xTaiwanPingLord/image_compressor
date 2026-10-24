#!/bin/zsh -l
# 建置 macOS 版；記錄寫到 build_macos.log，成功後自動開啟 App
cd "$(dirname "$0")"
ROOT=$PWD; LOG=$ROOT/build_macos.log
: > $LOG
start=$SECONDS
cd app
{ flutter pub get && flutter build macos --release --no-tree-shake-icons; } 2>&1 | tee -a $LOG
code=${pipestatus[1]}
echo "build exit=$code ($((SECONDS-start))s)" | tee -a $LOG
APP=$ROOT/app/build/macos/Build/Products/Release/image_compressor.app
if [[ $code -eq 0 && -d $APP ]]; then echo "APP=$APP" | tee -a $LOG; open "$APP"; fi
