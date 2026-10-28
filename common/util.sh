#!/system/bin/sh
# ============================================================
# EnvShield - 公共函数库
# 纯 POSIX sh，Magisk (busybox ash) / KernelSU / APatch 通用
# ============================================================

ES_DIR=/data/adb/envshield
ES_CONF="$ES_DIR/envshield.conf"
ES_LOG="$ES_DIR/envshield.log"
ES_BAK="$ES_DIR/props.backup"
ES_QUAR="$ES_DIR/quarantine"
ES_LOG_MAX=262144

# 调用阶段：post-fs-data / service / cli
# post-fs-data 阶段禁止 setprop 兜底（KernelSU 文档明确会导致启动死锁）
ES_STAGE=${ES_STAGE:-service}

# ---------- 日志 ----------

es_log() {
    [ -d "$ES_DIR" ] || return 0
    printf '[%s] %s\n' "$(date '+%m-%d %H:%M:%S')" "$*" >> "$ES_LOG" 2>/dev/null
}

es_log_rotate() {
    [ -f "$ES_LOG" ] || return 0
    _size=$(wc -c < "$ES_LOG" 2>/dev/null | tr -d ' ')
    case "$_size" in ''|*[!0-9]*) return 0 ;; esac
    [ "$_size" -gt "$ES_LOG_MAX" ] || return 0
    tail -n 200 "$ES_LOG" > "$ES_LOG.tmp" 2>/dev/null &&
        mv -f "$ES_LOG.tmp" "$ES_LOG" 2>/dev/null
}

# ---------- 配置 ----------

es_load_conf() {
    # 默认值
    ES_PROP_STRICT=1
    ES_PROP_AGGRESSIVE=0
    ES_PROP_SPOOF_BOOT=0
    ES_PROP_CONSISTENT=1
    ES_SELINUX_ENFORCE=1
    ES_TMP_GUARD=1
    ES_TMP_ALL=0
    ES_TMP_MIN_AGE=30
    ES_WATCHDOG=1
    ES_WATCH_INTERVAL=30
    ES_TARGETS=""
    ES_RISK_PKGS=""

    if [ -f "$ES_CONF" ]; then
        # shellcheck disable=SC1090
        . "$ES_CONF" 2>/dev/null
    fi

    case "$ES_WATCH_INTERVAL" in
        ''|*[!0-9]*) ES_WATCH_INTERVAL=30 ;;
    esac
    case "$ES_TMP_MIN_AGE" in
        ''|*[!0-9]*) ES_TMP_MIN_AGE=30 ;;
    esac

    [ "$ES_WATCH_INTERVAL" -lt 10 ] && ES_WATCH_INTERVAL=10
    [ "$ES_WATCH_INTERVAL" -gt 600 ] && ES_WATCH_INTERVAL=600
    [ "$ES_TMP_MIN_AGE" -gt 600 ] && ES_TMP_MIN_AGE=600
    return 0
}

# ---------- 环境探测 ----------

ES_ROOT_IMPL=none
ES_RP=""

# 解析可用的 resetprop：PATH / KSU / APatch / Magisk 内部路径
es_rp_resolve() {
    ES_RP=""
    if command -v resetprop >/dev/null 2>&1; then
        ES_RP=resetprop
        return 0
    fi
    for _p in /data/adb/ksu/bin/resetprop /data/adb/ap/bin/resetprop /data/adb/magisk/resetprop; do
        if [ -x "$_p" ]; then
            ES_RP="$_p"
            return 0
        fi
    done
    return 1
}

es_detect_impl() {
    if [ "$KSU" = "true" ] || [ -d /data/adb/ksu ] || command -v ksud >/dev/null 2>&1; then
        ES_ROOT_IMPL=kernelsu
    elif [ -d /data/adb/magisk ] && { [ -x /data/adb/magisk/magisk ] || command -v magisk >/dev/null 2>&1; }; then
        ES_ROOT_IMPL=magisk
    elif [ -d /data/adb/ap ] || command -v apd >/dev/null 2>&1; then
        ES_ROOT_IMPL=apatch
    else
        ES_ROOT_IMPL=none
    fi

    es_rp_resolve
}

es_has_resetprop() {
    [ -n "$ES_RP" ]
}

# 写属性：resetprop 优先；setprop 仅在非 post-fs-data 阶段兜底
es_prop_put() {
    _k=$1
    _v=$2

    if [ -n "$ES_RP" ]; then
        "$ES_RP" -n "$_k" "$_v" >/dev/null 2>&1 && return 0
        "$ES_RP" "$_k" "$_v" >/dev/null 2>&1 && return 0
    fi

    [ "$ES_STAGE" = "post-fs-data" ] && return 1
    setprop "$_k" "$_v" >/dev/null 2>&1
}

# 删除属性：resetprop 优先；无 resetprop 时置空（对外表现等价）
es_prop_rm() {
    _k=$1

    if [ -n "$ES_RP" ]; then
        "$ES_RP" --delete "$_k" >/dev/null 2>&1 && return 0
    fi

    [ "$ES_STAGE" = "post-fs-data" ] && return 1
    setprop "$_k" "" >/dev/null 2>&1
}

# ---------- 通用判断 ----------

# 判断文件是否为 ELF（Android 上所谓「Root 二进制」基本都是 ELF）
es_is_elf() {
    if command -v od >/dev/null 2>&1; then
        _magic=$(head -c 4 "$1" 2>/dev/null | od -An -tx1 2>/dev/null | tr -d ' \n')
        [ "$_magic" = "7f454c46" ] && return 0
        return 1
    fi
    # 极简环境无 od 时按扩展名退化判断
    case "$1" in
        *.so|*.bin|*-server) return 0 ;;
    esac
    return 1
}

# 常见 Root / 注入 / 抓包 / 修改器 二进制特征名
es_is_suspect_name() {
    case "$1" in
        su|su.*|magisk*|ksu*|apd|apatch*|\
        busybox|busybox-*|frida-server*|frida-*|libgadget*.so|gadget*.so|\
        gdbserver*|tcpdump*|nmap|sqlmap*|stryker*|gameguardian*|GameGuardian*|gg|\
        xmrig*|minerd*|cpuminer*|libinject*|inject*|ldpreload*|libldpreload*)
            return 0 ;;
    esac
    return 1
}
