#!/bin/sh
# ============================================================
# EnvShield - 打包脚本
# 输出管理器可直接刷入的 zip（Magisk / KernelSU / APatch 通用）
# 用法: sh build.sh
# ============================================================
set -e
cd "$(dirname "$0")"

VER=$(sed -n 's/^version=//p' module.prop | head -n 1)
[ -n "$VER" ] || { echo "读取 module.prop version 失败"; exit 1; }

OUT="../EnvShield-${VER}.zip"
rm -f "$OUT"

chmod 0755 customize.sh post-fs-data.sh service.sh uninstall.sh bin/envshield

FILES="module.prop customize.sh post-fs-data.sh service.sh uninstall.sh update.json common bin config META-INF"
[ -f system.prop ] && FILES="$FILES system.prop"

# shellcheck disable=SC2086
zip -r -X -9 "$OUT" $FILES -x '*.DS_Store' >/dev/null

echo "已生成: $OUT"
unzip -l "$OUT"
