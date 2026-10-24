#!/bin/zsh -l
# iOS 模擬器：建置 → 開模擬器 → 安裝 → 啟動；記錄寫到 build_ios.log
cd "$(dirname "$0")"
ROOT=$PWD; LOG=$ROOT/build_ios.log
: > $LOG
start=$SECONDS
cd app
{ flutter pub get && flutter build ios --simulator --debug --no-tree-shake-icons; } 2>&1 | tee -a $LOG
code=${pipestatus[1]}
echo "build exit=$code ($((SECONDS-start))s)" | tee -a $LOG
APP=$ROOT/app/build/ios/iphonesimulator/Runner.app
[[ $code -eq 0 && -d $APP ]] || exit 1
UDID=$(xcrun simctl list devices booted | grep -m1 -oE '[0-9A-F-]{36}')
if [[ -z $UDID ]]; then
  UDID=$(xcrun simctl list devices available | grep -m1 'iPhone' | grep -oE '[0-9A-F-]{36}')
  xcrun simctl boot $UDID 2>&1 | tee -a $LOG
fi
echo "simulator=$(xcrun simctl list devices | grep $UDID)" | tee -a $LOG
open -a Simulator
xcrun simctl install $UDID "$APP" 2>&1 | tee -a $LOG
xcrun simctl launch $UDID tw.toast.imageCompressor 2>&1 | tee -a $LOG
