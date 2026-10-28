#!/system/bin/sh
# ============================================================
# EnvShield - late_start service
# 开机完成后补齐：属性复核、目标加白、痕迹清理，并进入低频看护循环
# ============================================================

ES_STAGE=service

# 模块目录：优先用管理器注入的 MODDIR，其次按脚本路径推导，最后兜底
[ -n "$MODDIR" ] || MODDIR=$(cd "${0%/*}" 2>/dev/null && pwd)
[ -d "$MODDIR/common" ] || MODDIR=/data/adb/modules/envshield

[ -f "$MODDIR/disable" ] && exit 0
[ -f "$MODDIR/remove" ] && exit 0

. "$MODDIR/common/util.sh"
. "$MODDIR/common/props.sh"
. "$MODDIR/common/traces.sh"
. "$MODDIR/common/denylist.sh"

mkdir -p "$ES_DIR" 2>/dev/null
chmod 0700 "$ES_DIR" 2>/dev/null

es_load_conf
es_detect_impl

# 等待开机完成，最多约 4 分钟
_i=0
while [ "$(getprop sys.boot_completed 2>/dev/null)" != "1" ] && [ "$_i" -lt 120 ]; do
    sleep 2
    _i=$((_i + 1))
done

es_apply_props
es_apply_consistency
es_selinux_enforce
es_apply_targets
es_clean_tmp
es_log_rotate

es_log "service: 开机初始化完成 (changes=$ES_CHANGED, quarantined=$ES_QUAR_COUNT)"

[ "$ES_WATCHDOG" = "1" ] || exit 0

# 低频看护：只做幂等操作，无变化时不写日志，功耗可忽略
# 每轮重新读取配置，改完配置文件无需重启即可生效
_n=0
while true; do
    sleep "$ES_WATCH_INTERVAL"

    [ -d "$MODDIR" ] || break
    [ -f "$MODDIR/disable" ] && break
    [ -f "$MODDIR/remove" ] && break

    es_load_conf
    [ "$ES_WATCHDOG" = "1" ] || break

    es_apply_props
    es_apply_consistency
    es_selinux_enforce
    es_clean_tmp

    _n=$((_n + 1))
    if [ "$_n" -ge 10 ]; then
        _n=0
        es_log_rotate
    fi
done
