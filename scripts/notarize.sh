#!/bin/bash
#
# 公证 FreeSwitch —— 用你自己的 Apple 开发者账号跑。
# 需要：付费 Apple Developer 账号 + 一张「Developer ID Application」证书（在钥匙串里）。
#
# 用法（二选一）：
#   1) 先存一次凭据（推荐，一次即可）：
#        xcrun notarytool store-credentials freeswitch-notary \
#          --apple-id "you@example.com" --team-id MXHBUQH27V \
#          --password "app-专用密码"        # 在 appleid.apple.com 生成
#      然后：
#        NOTARY_PROFILE=freeswitch-notary ./scripts/notarize.sh
#
#   2) 或直接传账号（不存凭据）：
#        APPLE_ID="you@example.com" TEAM_ID=MXHBUQH27V APP_PASSWORD="app-专用密码" \
#          ./scripts/notarize.sh
#
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="FreeSwitch"
SCHEME="FreeSwitch"
PROJECT="FreeSwitch.xcodeproj"
TEAM_ID="${TEAM_ID:-MXHBUQH27V}"
SIGN_ID="${SIGN_ID:-Developer ID Application}"       # 也可写全名 "Developer ID Application: 你的名字 (TEAMID)"
BUILD_DIR="$(pwd)/build-notarize"
APP_PATH="$BUILD_DIR/Build/Products/Release/$APP_NAME.app"
ZIP_PATH="$BUILD_DIR/$APP_NAME.zip"

echo "==> 1/5 检查 Developer ID 证书…"
if ! security find-identity -v -p codesigning | grep -q "Developer ID Application"; then
  echo "❌ 钥匙串里没有「Developer ID Application」证书。"
  echo "   打开 Xcode ▸ 设置 ▸ Accounts ▸ 选中团队 ▸ Manage Certificates ▸ + ▸ Developer ID Application。"
  exit 1
fi

echo "==> 2/5 构建 Release（Developer ID + 加固运行时 + 时间戳）…"
xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Release \
  -derivedDataPath "$BUILD_DIR" \
  -destination 'generic/platform=macOS' \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="$SIGN_ID" \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  ENABLE_HARDENED_RUNTIME=YES \
  OTHER_CODE_SIGN_FLAGS="--timestamp --options runtime" \
  clean build

echo "==> 3/5 打包 zip…"
rm -f "$ZIP_PATH"
/usr/bin/ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"

echo "==> 4/5 提交公证（会等待结果，通常 1–5 分钟）…"
if [ -n "${NOTARY_PROFILE:-}" ]; then
  xcrun notarytool submit "$ZIP_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
else
  : "${APPLE_ID:?需要 APPLE_ID 或 NOTARY_PROFILE}"
  : "${APP_PASSWORD:?需要 APP_PASSWORD（app 专用密码）或 NOTARY_PROFILE}"
  xcrun notarytool submit "$ZIP_PATH" \
    --apple-id "$APPLE_ID" --team-id "$TEAM_ID" --password "$APP_PASSWORD" --wait
fi

echo "==> 5/5 装订票据并校验…"
xcrun stapler staple "$APP_PATH"
xcrun stapler validate "$APP_PATH"
echo "--- Gatekeeper 评估 ---"
spctl -a -vvv --type execute "$APP_PATH" || true

echo
echo "✅ 完成。已公证的 App：$APP_PATH"
echo "   现在双击/分发它，弹出的管理员框不会再出现「Apple 无法验证…恶意软件」那句。"
