#!/system/bin/sh
# ============================================================
# EnvShield - post-fs-data 阶段
# 在 system_server 起来之前完成属性归一，最早降低暴露面
# ============================================================

ES_STAGE=post-fs-data

# 模块目录：优先用管理器注入的 MODDIR，其次按脚本路径推导，最后兜底
[ -n "$MODDIR" ] || MODDIR=$(cd "${0%/*}" 2>/dev/null && pwd)
[ -d "$MODDIR/common" ] || MODDIR=/data/adb/modules/envshield

# 模块已被停用 / 移除时不做任何事
[ -f "$MODDIR/disable" ] && exit 0
[ -f "$MODDIR/remove" ] && exit 0

. "$MODDIR/common/util.sh"
. "$MODDIR/common/props.sh"
. "$MODDIR/common/traces.sh"

mkdir -p "$ES_DIR" 2>/dev/null
chmod 0700 "$ES_DIR" 2>/dev/null

# 首次启动把默认配置落到数据目录，方便用户修改
if [ ! -f "$ES_CONF" ] && [ -f "$MODDIR/config/envshield.conf" ]; then
    cp -f "$MODDIR/config/envshield.conf" "$ES_CONF" 2>/dev/null
    chmod 0600 "$ES_CONF" 2>/dev/null
fi

es_load_conf
es_detect_impl

es_log "post-fs-data: impl=$ES_ROOT_IMPL resetprop=${ES_RP:-none}"

es_apply_props
es_apply_consistency
es_selinux_enforce
# 配置改动后无需手动执行 apply，重启时自动重生成 system.prop
es_sync_system_prop
es_log_rotate

exit 0
