#!/system/bin/sh
# ============================================================
# EnvShield - 安装脚本（Magisk / KernelSU / APatch 通用）
# customize.sh 会被管理器 source 执行，末尾不要写 exit，
# 否则会跳过管理器后续的权限设置与注册流程。
# ============================================================

SKIPUNZIP=0

# ---------- 管理器函数兜底（不同管理器提供的能力不完全一致） ----------
if ! command -v ui_print >/dev/null 2>&1; then
    ui_print() { echo "$*"; }
fi
if ! command -v set_perm_recursive >/dev/null 2>&1; then
    set_perm_recursive() {
        chown -R "$2:$3" "$1" 2>/dev/null
        find "$1" -type d -exec chmod "$4" {} + 2>/dev/null
        find "$1" -type f -exec chmod "$5" {} + 2>/dev/null
    }
fi

ui_print " "
ui_print "  EnvShield 环境净化  v1.1.0"
ui_print "  ----------------------------------"
ui_print "  纯用户态 · 不挂载 system 分区"
ui_print " "

ui_print "- 设备 : $(getprop ro.product.model 2>/dev/null) ($(getprop ro.product.device 2>/dev/null))"
ui_print "- 系统 : Android $(getprop ro.build.version.release 2>/dev/null) / $(getprop ro.build.version.sdk 2>/dev/null)"
ui_print "- ABI  : $(getprop ro.product.cpu.abi 2>/dev/null)"

if [ "$KSU" = "true" ] || [ -d /data/adb/ksu ] || command -v ksud >/dev/null 2>&1; then
    ui_print "- Root : KernelSU"
elif [ -d /data/adb/magisk ]; then
    ui_print "- Root : Magisk"
elif [ -d /data/adb/ap ]; then
    ui_print "- Root : APatch"
else
    ui_print "- Root : 未知"
fi

# 统一权限：模块脚本必须可执行
set_perm_recursive "$MODPATH" 0 0 0755 0755

# 数据目录与配置
mkdir -p /data/adb/envshield 2>/dev/null
chmod 0700 /data/adb/envshield 2>/dev/null

if [ ! -f /data/adb/envshield/envshield.conf ] && [ -f "$MODPATH/config/envshield.conf" ]; then
    cp -f "$MODPATH/config/envshield.conf" /data/adb/envshield/envshield.conf
    chmod 0600 /data/adb/envshield/envshield.conf 2>/dev/null
    ui_print "- 已生成配置: /data/adb/envshield/envshield.conf"
else
    ui_print "- 保留已有配置，未覆盖"
fi

# 依据当前配置生成 system.prop：
# KernelSU / APatch 下即使没有 resetprop，属性仍能在开机时由管理器应用
if sh "$MODPATH/bin/envshield" sync >/dev/null 2>&1 && [ -s "$MODPATH/system.prop" ]; then
    ui_print "- 已生成 system.prop（$(grep -c . "$MODPATH/system.prop" 2>/dev/null) 条属性）"
else
    ui_print "- system.prop 生成失败，属性归一将仅在支持 resetprop 的环境下运行时生效"
fi

ui_print " "
ui_print "- 建议接着安装：Zygisk Next + Shamiko（或 Zygisk Assistant）"
ui_print "- KernelSU 用户：请使用带 SUSFS 的内核，否则 LKM 特征无法隐藏"
ui_print " "
ui_print "- 自检命令："
ui_print "  su -c 'sh /data/adb/modules/envshield/bin/envshield check'"
ui_print " "
