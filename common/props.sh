#!/system/bin/sh
# ============================================================
# EnvShield - 属性归一与一致性
#
# 设计原则：
#   1. 只改能确定推导、且不与 TEE / Keymaster 交叉校验冲突的属性。
#   2. 属性之间必须互相自洽：改了 ro.build.tags 却不改 fingerprint，
#      等于主动制造「指纹里还写着 test-keys」这种低级破绽。
#   3. 涉及 bootloader / verified boot 的属性放在 tier 3，默认关闭，
#      真机解锁状态下强行改成 green 反而会被一致性校验抓住。
#
# KernelSU / APatch 可能没有 resetprop（或仅在特定路径下提供）：
# 此时属性由模块目录下的 system.prop 在开机时生效，
# 运行时修改会在下次开机后落地。
# ============================================================

ES_CHANGED=0

# ---------- 属性表（唯一数据源） ----------
# 格式：key|value|tier|mode
es_prop_table() {
    cat <<'PROPS'
# --- tier 1：安全区，与内核/引导器无交叉校验冲突 ---
ro.secure|1|1|set
ro.build.selinux||1|del
ro.boot.selinux|enforcing|1|set
# --- tier 2：会关闭 adb root / 调试能力，需要用户明确开启 ---
ro.debuggable|0|2|set
ro.adb.secure|1|2|set
ro.kernel.qemu|0|2|set
# --- tier 3：引导态伪装，默认关闭 ---
ro.boot.verifiedbootstate|green|3|set
ro.boot.flash.locked|1|3|set
ro.boot.veritymode|enforcing|3|set
ro.boot.vbmeta.device_state|locked|3|set
ro.boot.warranty_bit|0|3|set
ro.warranty_bit|0|3|set
ro.oem_unlock_supported|0|3|set
sys.oem_unlock_allowed|0|3|set
PROPS
}

# ---------- 基础读写（带原始值备份） ----------

es_prop_backup() {
    _k=$1
    [ -f "$ES_BAK" ] || : > "$ES_BAK" 2>/dev/null

    # 字面比较 key，避免 . 被当成正则通配、也避免重复记录
    while IFS='=' read -r _bk _bv; do
        [ "$_bk" = "$_k" ] && return 0
    done < "$ES_BAK" 2>/dev/null

    printf '%s=%s\n' "$_k" "$(getprop "$_k" 2>/dev/null)" >> "$ES_BAK" 2>/dev/null
}

es_prop_set() {
    _k=$1
    _v=$2
    _cur=$(getprop "$_k" 2>/dev/null)
    [ "$_cur" = "$_v" ] && return 0

    es_prop_backup "$_k"

    if es_prop_put "$_k" "$_v"; then
        ES_CHANGED=$((ES_CHANGED + 1))
        es_log "属性 $_k: '$_cur' -> '$_v'"
        return 0
    fi
    es_log "属性写入失败: $_k=$_v"
    return 1
}

es_prop_del() {
    _k=$1
    _cur=$(getprop "$_k" 2>/dev/null)
    [ -z "$_cur" ] && return 0

    es_prop_backup "$_k"

    if es_prop_rm "$_k"; then
        ES_CHANGED=$((ES_CHANGED + 1))
        es_log "属性删除: $_k (原值 '$_cur')"
        return 0
    fi
    es_log "属性删除失败: $_k"
    return 1
}

# ---------- 一致性归一（build.type / build.tags / fingerprint / description） ----------
# 输出 key|value；$1=diff 只输出需要改的，$1=all 输出全部（用于生成 system.prop，保证幂等）
es_props_normalized() {
    _mode=${1:-diff}

    getprop 2>/dev/null |
        sed -n 's/^\[\([^]]*\)\]: \[\(.*\)\]$/\1|\2/p' |
        while IFS='|' read -r _k _v; do
            [ -n "$_k" ] || continue
            case "$_k" in
                *.build.type)
                    _nv=$(printf '%s' "$_v" | sed 's/^userdebug$/user/; s/^eng$/user/')
                    ;;
                *.build.tags)
                    _nv=$(printf '%s' "$_v" | sed 's/^test-keys$/release-keys/; s/^dev-keys$/release-keys/')
                    ;;
                *.build.fingerprint|*.build.description)
                    # fingerprint 格式：brand/product/device:ver/id/incremental:type/tags
                    # description 格式：brand-product-device-type ver id incremental tags
                    _nv=$(printf '%s' "$_v" | sed \
                        -e 's/userdebug/user/g' \
                        -e 's/test-keys/release-keys/g' \
                        -e 's/dev-keys/release-keys/g' \
                        -e 's#/eng/#/user/#g' \
                        -e 's#:eng/#:user/#g' \
                        -e 's#-eng #-user #g')
                    ;;
                *)
                    continue
                    ;;
            esac

            if [ "$_mode" != "all" ] && [ "$_nv" = "$_v" ]; then
                continue
            fi
            printf '%s|%s\n' "$_k" "$_nv"
        done
}

# ---------- 应用：基础属性 ----------

es_apply_props() {
    ES_CHANGED=0
    [ "$ES_PROP_STRICT" = 1 ] || return 0

    if ! es_has_resetprop; then
        es_log "跳过运行时属性写入：未找到 resetprop（属性由 system.prop 在开机时生效）"
        return 1
    fi

    _tbl=$(es_prop_table)
    while IFS='|' read -r _key _val _tier _mode; do
        case "$_key" in
            ''|'#'*) continue ;;
        esac
        case "$_tier" in
            1) ;;
            2) [ "$ES_PROP_AGGRESSIVE" = 1 ] || continue ;;
            3) [ "$ES_PROP_SPOOF_BOOT" = 1 ] || continue ;;
            *) continue ;;
        esac

        # 只有真的处于 Enforcing 才宣称 enforcing，避免自相矛盾
        if [ "$_key" = "ro.boot.selinux" ]; then
            [ "$(getenforce 2>/dev/null)" = "Enforcing" ] || continue
        fi

        if [ "$_mode" = "del" ]; then
            es_prop_del "$_key"
        else
            es_prop_set "$_key" "$_val"
        fi
    done <<EOF
$_tbl
EOF

    return 0
}

# ---------- 应用：一致性归一 ----------

es_apply_consistency() {
    [ "$ES_PROP_STRICT" = 1 ] || return 0
    [ "$ES_PROP_CONSISTENT" = 1 ] || return 0
    es_has_resetprop || return 0

    _lst=$(es_props_normalized diff)
    [ -n "$_lst" ] || return 0

    while IFS='|' read -r _k _v; do
        [ -n "$_k" ] && es_prop_set "$_k" "$_v"
    done <<EOF
$_lst
EOF

    return 0
}

# ---------- 生成 system.prop（KernelSU / APatch 无 resetprop 时的落地方案） ----------

es_sync_system_prop() {
    [ -n "$MODDIR" ] || return 1
    [ -d "$MODDIR" ] || return 1

    _f="$MODDIR/system.prop"
    _tmp="$_f.tmp"
    : > "$_tmp" 2>/dev/null || return 1

    if [ "$ES_PROP_STRICT" = 1 ]; then
        _tbl=$(es_prop_table)
        while IFS='|' read -r _k _v _t _m; do
            case "$_k" in
                ''|'#'*) continue ;;
            esac
            case "$_t" in
                1) ;;
                2) [ "$ES_PROP_AGGRESSIVE" = 1 ] || continue ;;
                3) [ "$ES_PROP_SPOOF_BOOT" = 1 ] || continue ;;
                *) continue ;;
            esac
            if [ "$_k" = "ro.boot.selinux" ]; then
                [ "$(getenforce 2>/dev/null)" = "Enforcing" ] || continue
            fi

            # system.prop 无法表达「删除属性」，这类 key 只在 resetprop 可用时处理
            [ "$_m" = "del" ] && continue
            printf '%s=%s\n' "$_k" "$_v" >> "$_tmp"
        done <<EOF
$_tbl
EOF

        if [ "$ES_PROP_CONSISTENT" = 1 ]; then
            _lst=$(es_props_normalized all)
            while IFS='|' read -r _k _v; do
                [ -n "$_k" ] && printf '%s=%s\n' "$_k" "$_v" >> "$_tmp"
            done <<EOF
$_lst
EOF
        fi
    fi

    mv -f "$_tmp" "$_f" 2>/dev/null
}

# ---------- SELinux ----------

es_selinux_enforce() {
    [ "$ES_SELINUX_ENFORCE" = 1 ] || return 0
    command -v getenforce >/dev/null 2>&1 || return 0

    _st=$(getenforce 2>/dev/null)

    if [ "$_st" = "Enforcing" ]; then
        es_prop_set ro.boot.selinux enforcing >/dev/null 2>&1
        return 0
    fi
    [ "$_st" = "Permissive" ] || return 0

    if setenforce 1 >/dev/null 2>&1; then
        es_log "SELinux: Permissive -> Enforcing"
        es_prop_set ro.boot.selinux enforcing >/dev/null 2>&1
        return 0
    fi

    es_log "SELinux 切换 Enforcing 失败（内核可能不支持 setenforce）"
    return 1
}
