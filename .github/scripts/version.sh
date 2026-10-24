#!/usr/bin/env bash
# VERSION：標籤 v1.2.3 → 1.2.3（v1.2.3-beta.1 → 1.2.3-beta.1）；否則取 pubspec.yaml 的版本
# BUILD_NUMBER：GitHub 執行編號（Android versionCode 需遞增）
set -euo pipefail
if [[ "${GITHUB_REF:-}" == refs/tags/v* ]]; then
  V="${GITHUB_REF_NAME#v}"
else
  V=$(sed -n 's/^version: *\([^+]*\).*/\1/p' app/pubspec.yaml)
fi
echo "VERSION=$V" >> "$GITHUB_ENV"
echo "BUILD_NUMBER=$GITHUB_RUN_NUMBER" >> "$GITHUB_ENV"
echo "version $V build $GITHUB_RUN_NUMBER"
