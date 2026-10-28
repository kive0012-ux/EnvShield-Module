#!/system/bin/sh
# ============================================================
# EnvShield - 卸载清理
# 1) 属性按备份还原（无需重启）
# 2) 把隔离的文件还原回 /data/local/tmp
# 3) 删除数据目录
# ============================================================

ES_DIR=/data/adb/envshield
ES_QUAR="$ES_DIR/quarantine"
ES_BAK="$ES_DIR/props.backup"

# ---------- 还原属性 ----------
_RP=""
if command -v resetprop >/dev/null 2>&1; then
    _RP=resetprop
else
    for _p in /data/adb/ksu/bin/resetprop /data/adb/ap/bin/resetprop /data/adb/magisk/resetprop; do
        [ -x "$_p" ] && { _RP="$_p"; break; }
    done
fi

if [ -n "$_RP" ] && [ -f "$ES_BAK" ]; then
    while IFS='=' read -r _k _v; do
        [ -n "$_k" ] || continue
        if [ -n "$_v" ]; then
            "$_RP" -n "$_k" "$_v" >/dev/null 2>&1
        else
            "$_RP" --delete "$_k" >/dev/null 2>&1
        fi
    done < "$ES_BAK"
fi

# ---------- 还原隔离文件 ----------
if [ -d "$ES_QUAR" ]; then
    mkdir -p /data/local/tmp 2>/dev/null
    for _f in "$ES_QUAR"/*; do
        [ -e "$_f" ] || continue
        _base=${_f##*/}
        _name=${_base%.*}          # 去掉 .<时间戳>
        [ -n "$_name" ] || _name=$_base
        _dst="/data/local/tmp/$_name"
        [ -e "$_dst" ] && _dst="$_dst.restored.$(date +%s)"
        mv -f "$_f" "$_dst" 2>/dev/null
    done
fi

rm -rf "$ES_DIR" 2>/dev/null

exit 0
