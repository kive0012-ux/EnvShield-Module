#!/system/bin/sh
# ============================================================
# EnvShield - 目标应用加白
#
# 说明：本模块只负责「把目标包名登记进 Magisk DenyList」，
# 真正做 mount/namespace 隐藏的是 Shamiko / Zygisk Assistant / SUSFS。
# 不自动打开 Magisk 的 "Enforce DenyList" ——
# 它与 Shamiko 的工作模式冲突（Shamiko 要求该开关保持关闭）。
# KernelSU / APatch 的 per-app「卸载模块」配置保存在管理器数据库里，
# 没有稳定的 CLI，因此不做伪造写入，只提示用户去管理器里开启。
# ============================================================

es_valid_pkg() {
    case "$1" in
        ''|*[!A-Za-z0-9._]*) return 1 ;;
        *.*) return 0 ;;
        *) return 1 ;;
    esac
}

es_apply_targets() {
    [ -n "$ES_TARGETS" ] || return 0

    _ok=0
    _fail=0

    for _p in $ES_TARGETS; do
        es_valid_pkg "$_p" || continue

        case "$ES_ROOT_IMPL" in
            magisk)
                if magisk --denylist add "$_p" >/dev/null 2>&1; then
                    _ok=$((_ok + 1))
                else
                    _fail=$((_fail + 1))
                    es_log "DenyList 写入失败: $_p"
                fi
                ;;
            kernelsu|apatch)
                # 只能提示，管理器里需要手动开启「卸载模块」
                _ok=$((_ok + 1))
                ;;
            *)
                _fail=$((_fail + 1))
                es_log "未知 Root 环境，跳过目标登记: $_p"
                ;;
        esac
    done

    if [ "$ES_ROOT_IMPL" = "kernelsu" ] || [ "$ES_ROOT_IMPL" = "apatch" ]; then
        es_log "KernelSU/APatch：请在管理器中为这些应用开启『卸载模块』：$ES_TARGETS"
    fi

    [ "$_fail" -gt 0 ] && es_log "目标登记: 成功 $_ok 失败 $_fail"
    return 0
}

# ---------- 隐藏组件状态 ----------
es_component_status() {
    _m=/data/adb/modules

    for _d in "$_m"/*; do
        [ -d "$_d" ] || continue
        _id=${_d##*/}
        case "$_id" in
            zygisk*|*zygisk*)          echo "zygisk: $_id" ;;
            shamiko*|*shamiko*)        echo "shamiko: $_id" ;;
            *tricky*|*Tricky*)         echo "trickystore: $_id" ;;
            *playintegrityfix*|*pif*)  echo "pif: $_id" ;;
            *susfs*)                   echo "susfs_module: $_id" ;;
            lsposed*|*LSPosed*)        echo "lsposed: $_id" ;;
            *hidemyapplist*|*HMA*)     echo "hma: $_id" ;;
        esac
    done
}

# ---------- Zygisk 开关（Magisk 专用，读取失败返回 unknown） ----------
es_zygisk_state() {
    [ "$ES_ROOT_IMPL" = "magisk" ] || { echo "unknown"; return; }
    command -v magisk >/dev/null 2>&1 || { echo "unknown"; return; }

    _v=$(magisk --sqlite "SELECT value FROM settings WHERE key='zygisk'" 2>/dev/null | tail -n 1 | sed 's/.*=//')
    case "$_v" in
        1) echo "enabled" ;;
        0) echo "disabled" ;;
        *) echo "unknown" ;;
    esac
}
