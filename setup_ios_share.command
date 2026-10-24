#!/bin/zsh -l
# 在 iOS 專案加入 Share Extension target（可重複執行）；記錄寫到 setup_ios_share.log
# xcodeproj gem 與相依套件裝在 ~/.cache/imgc-gems，不動系統或 CocoaPods 的 gem
cd "$(dirname "$0")"
LOG=$PWD/setup_ios_share.log
cd app/ios
{
  export GEM_HOME=$HOME/.cache/imgc-gems GEM_PATH=$HOME/.cache/imgc-gems
  echo "ruby: $(command -v ruby) $(ruby -v)"
  ruby -rxcodeproj -e1 2>/dev/null || gem install --no-document --install-dir $GEM_HOME xcodeproj
  ruby add_share_extension.rb && echo "setup ok"
} > $LOG 2>&1
cat $LOG
