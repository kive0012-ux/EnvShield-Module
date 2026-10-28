#!/system/bin/sh
# ============================================================
# EnvShield - 痕迹清理与扫描
# ============================================================

ES_QUAR_COUNT=0

# ---------- /data/local/tmp 清理 ----------
# 策略：不删除，只「隔离」到 /data/adb/envshield/quarantine，可随时还原。
# 默认只搬走 ELF 可执行文件与已知工具名，不碰普通文本 / apk / 刚推入的文件，
# 避免打断 adb push 工作流。
es_clean_tmp() {
    [ "$ES_TMP_GUARD" = 1 ] || return 0

    _tmp=/data/local/tmp
    [ -d "$_tmp" ] || return 0

    mkdir -p "$ES_QUAR" 2>/dev/null
    chmod 0700 "$ES_QUAR" 2>/dev/null

    ES_QUAR_COUNT=0
    _now=$(date +%s 2>/dev/null)
    case "$_now" in ''|*[!0-9]*) _now=0 ;; esac

    for _f in "$_tmp"/* "$_tmp"/.[!.]* "$_tmp"/..?*; do
        [ -f "$_f" ] || continue
        [ -L "$_f" ] && continue

        _base=${_f##*/}

        # 新文件（可能正在 push / 拷贝）先放过，下一轮再看
        if [ "$ES_TMP_MIN_AGE" -gt 0 ] && [ "$_now" -gt 0 ]; then
            _mt=$(stat -c %Y "$_f" 2>/dev/null)
            case "$_mt" in ''|*[!0-9]*) _mt=0 ;; esac
            if [ "$_mt" -gt 0 ] && [ $((_now - _mt)) -lt "$ES_TMP_MIN_AGE" ]; then
                continue
            fi
        fi

        if [ "$ES_TMP_ALL" = 1 ] || es_is_suspect_name "$_base" || es_is_elf "$_f"; then
            _dst="$ES_QUAR/${_base}.$(date +%s)"
            if mv -f "$_f" "$_dst" 2>/dev/null; then
                ES_QUAR_COUNT=$((ES_QUAR_COUNT + 1))
                es_log "隔离 $_f -> $_dst"
            fi
        fi
    done

    # 目录权限本身也可能被当成疑点
    chmod 0771 "$_tmp" 2>/dev/null
    chown 2000:2000 "$_tmp" 2>/dev/null

    [ "$ES_QUAR_COUNT" -gt 0 ] && es_log "临时目录已隔离 $ES_QUAR_COUNT 个文件"
    return 0
}

# ---------- 风险路径扫描 ----------
es_scan_risk_paths() {
    for _p in \
        /data/adb/magisk /data/adb/ksu /data/adb/ksud /data/adb/ap \
        /data/adb/lspd /data/adb/modules /data/adb/modules_update \
        /debug_ramdisk /sbin/.magisk /dev/.magisk \
        /system/bin/su /system/xbin/su /vendor/bin/su /sbin/su /su
    do
        [ -e "$_p" ] && echo "$_p"
    done
}

# ---------- 挂载痕迹扫描 ----------
# 注意：本脚本自身在 root / 全局命名空间运行，Magisk / KSU 的挂载点本就是可见的，
# 只有普通应用进程的命名空间里看不到才算隐藏成功。这里仅作参考。
es_scan_mounts() {
    [ -r /proc/self/mountinfo ] || return 0
    grep -iE 'magisk|kernelsu|apatch|/data/adb/modules|/data/adb/ksu' \
        /proc/self/mountinfo 2>/dev/null | head -n 20
}

# ---------- 内核特征 ----------
es_kernel_flags() {
    _k=$(uname -r 2>/dev/null)
    echo "kernel: $_k"

    if echo "$_k" | grep -qi 'susfs'; then
        echo "susfs: yes"
    else
        echo "susfs: no"
    fi

    if [ -e /sys/module/kernelsu ] || [ -e /sys/module/ksu ]; then
        echo "ksu_module: yes"
    else
        echo "ksu_module: no"
    fi

    if [ -r /proc/modules ] && grep -qiE 'kernelsu|ksu' /proc/modules 2>/dev/null; then
        echo "lkm_loaded: yes"
    else
        echo "lkm_loaded: no"
    fi
}
