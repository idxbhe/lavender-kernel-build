#!/bin/sh
# get-kernel-info.sh — Gather kernel SOURCE/BUILD info for an AnyKernel3 zip
#
# Usage:
#   sh get-kernel-info.sh [kernel_source_dir]
#
# Env (optional):
#   DEVICE_CODENAME  highlight/filter DTB variants matching this codename
#   OUT_DIR          override the build-output dir (default: <src>/out)
#   OUTPUT_DIR       where to write JSON+log (default: script dir)
#
# READ-ONLY: this script never writes into the kernel source tree or its out/
# folder. Everything is read with grep/find/cat/od/strings. The only files
# created are the JSON + log in OUTPUT_DIR.
#
# POSIX compliant — runs on the host (linux/zsh/bash/dash/busybox sh), not on
# the device. No set -e: missing build artifacts should produce empty fields,
# not abort the whole collector. Guard reads individually.

set +e

# ============================================
# ARGUMENTS & PATHS
# ============================================
SCRIPT_PATH="$0"
SCRIPT_DIR=$(CDPATH= cd "$(dirname "$SCRIPT_PATH")" && pwd)

if [ -n "$1" ]; then
    KSRC=$(CDPATH= cd "$1" && pwd)
else
    # default: sibling san-kernel-4.19 if present, else current dir
    if [ -d "$SCRIPT_DIR/san-kernel-4.19" ]; then
        KSRC="$SCRIPT_DIR/san-kernel-4.19"
    else
        KSRC="$PWD"
    fi
fi

if [ ! -d "$KSRC" ]; then
    echo "ERROR: kernel source dir not found: $KSRC" >&2
    exit 1
fi

# Build output dir: honour OUT_DIR, else <src>/out
if [ -n "$OUT_DIR" ]; then
    KOUT=$(CDPATH= cd "$OUT_DIR" 2>/dev/null && pwd) || KOUT="$OUT_DIR"
else
    KOUT="$KSRC/out"
fi

OUTPUT_DIR="${OUTPUT_DIR:-$SCRIPT_DIR}"
[ -d "$OUTPUT_DIR" ] || OUTPUT_DIR="$PWD"

# Output filenames: stem = the kernel source directory's base name
# (e.g. /home/bhe/lavender/san-kernel-4.19 -> san-kernel-4.19.json / .log).
# This lets multiple kernel trees collect info side-by-side without colliding,
# and ties the file unambiguously to the source it describes.
KDIR_NAME=$(basename "$KSRC")
[ -n "$KDIR_NAME" ] || KDIR_NAME="kernel_info"
JSON_FILE="$OUTPUT_DIR/${KDIR_NAME}.json"
LOG_FILE="$OUTPUT_DIR/${KDIR_NAME}.log"

# ============================================
# LOGGING
# ============================================
log_header() { printf '=== %s ===\n' "$1" >> "$LOG_FILE"; printf '=== %s ===\n' "$1" >&2; }
log_info()   { printf '[INFO] %s\n' "$1" >> "$LOG_FILE"; printf '[INFO] %s\n' "$1" >&2; }
log_warn()   { printf '[WARN] %s\n' "$1" >> "$LOG_FILE"; printf '[WARN] %s\n' "$1" >&2; }
log_step()   { printf '[STEP] %s\n' "$1" >> "$LOG_FILE"; printf '[STEP] %s\n' "$1" >&2; }
log_raw()    { printf '%s\n' "$1" >> "$LOG_FILE"; printf '%s\n' "$1" >&2; }

# JSON helpers (same style as lavender.json / get.sh)
json_init()     { printf '{\n' > "$JSON_FILE"; }
json_add_str()  { printf '  "%s": "%s",\n' "$1" "$2" >> "$JSON_FILE"; }
json_add()      { printf '  "%s": %s,\n' "$1" "$2" >> "$JSON_FILE"; }
json_finalize() { sed -i '$ s/,$//' "$JSON_FILE" 2>/dev/null || true; printf '}\n' >> "$JSON_FILE"; }

# Escape for JSON (read-only: input via stdin to be portable across sed variants)
jesc() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr '\n' ' '; }

# ============================================
# INIT LOG
# ============================================
{
    echo "Kernel Info Collector for AnyKernel3"
    echo "Source: $KSRC"
    echo "Out:    $KOUT"
    echo "Started: $(date 2>/dev/null)"
    echo "JSON:   $JSON_FILE"
    echo ""
} > "$LOG_FILE"

printf '==========================================\n'
printf '  Kernel Info Collector for AnyKernel3\n'
printf '  Source: %s\n' "$KSRC"
printf '  Out:    %s\n' "$KOUT"
printf '==========================================\n\n'

json_init

# ============================================
# 1. KERNEL VERSION (from Makefile + build release)
# ============================================
log_header "1. KERNEL VERSION"

# Makefile is the source of truth for the version being built.
KV_VERSION=$(sed -n 's/^VERSION = //p' "$KSRC/Makefile" 2>/dev/null | head -1)
KV_PATCHLEVEL=$(sed -n 's/^PATCHLEVEL = //p' "$KSRC/Makefile" 2>/dev/null | head -1)
KV_SUBLEVEL=$(sed -n 's/^SUBLEVEL = //p' "$KSRC/Makefile" 2>/dev/null | head -1)
KV_EXTRA=$(sed -n 's/^EXTRAVERSION = //p' "$KSRC/Makefile" 2>/dev/null | head -1)
KV_NAME=$(sed -n 's/^NAME = //p' "$KSRC/Makefile" 2>/dev/null | head -1 | sed 's/^"//; s/"$//')
KV_BASE="${KV_VERSION}.${KV_PATCHLEVEL}.${KV_SUBLEVEL}"

# Real built release string from out/include/config/kernel.release (includes
# CONFIG_LOCALVERSION appended). Falls back to $KV_BASE $KV_EXTRA.
KREL=""
if [ -f "$KOUT/include/config/kernel.release" ]; then
    KREL=$(cat "$KOUT/include/config/kernel.release" 2>/dev/null | tr -d '\r\n')
fi
[ -z "$KREL" ] && KREL="${KV_BASE}${KV_EXTRA}"

# CONFIG_LOCALVERSION from built .config (e.g. "-San-Kernel-...-EOL")
LOCALVER=$(grep '^CONFIG_LOCALVERSION=' "$KOUT/.config" 2>/dev/null | head -1 | sed 's/^CONFIG_LOCALVERSION=//; s/^"//; s/"$//')
LOCALVER_AUTO=$(grep '^CONFIG_LOCALVERSION_AUTO=' "$KOUT/.config" 2>/dev/null | head -1)

log_info "Makefile version : ${KV_VERSION}.${KV_PATCHLEVEL}.${KV_SUBLEVEL}${KV_EXTRA}"
log_info "kernel.release   : $KREL"
log_info "CONFIG_LOCALVER  : $LOCALVER"
log_info "LOCALVERSION_AUTO: $LOCALVER_AUTO"

json_add_str "kernel_version_makefile" "$KV_BASE"
json_add_str "kernel_extra_version"    "$KV_EXTRA"
json_add_str "kernel_codename"         "$(jesc "$KV_NAME")"
json_add_str "kernel_release"         "$(jesc "$KREL")"
json_add_str "config_localversion"    "$LOCALVER"
json_add_str "config_localversion_auto" "$LOCALVER_AUTO"

# ============================================
# 2. ARCHITECTURE (from build.config, ARCH in out Makefile, boot dir)
# ============================================
log_header "2. ARCHITECTURE"

# Prefer $ARCH from build.config.* found in source root; else infer from out/arch subdir
KARCH=""
for bc in "$KSRC"/build.config.*; do
    [ -f "$bc" ] || continue
    a=$(grep '^ARCH=' "$bc" 2>/dev/null | head -1 | cut -d= -f2)
    [ -n "$a" ] && KARCH="$a" && break
done
# Infer from built out dir if still empty
if [ -z "$KARCH" ]; then
    if [ -d "$KOUT/arch/arm64" ]; then KARCH="arm64"; fi
fi
# Cross compile toolchain prefix
CROSS_PREFIX=$(grep '^CROSS_COMPILE=' "$KSRC"/build.config.* 2>/dev/null | head -1 | cut -d= -f2-)
CROSS_COMPAT=$(grep '^CROSS_COMPILE_COMPAT=' "$KSRC"/build.config.* 2>/dev/null | head -1 | cut -d= -f2-)

log_info "ARCH            : $KARCH"
log_info "CROSS_COMPILE   : $CROSS_PREFIX"
log_info "CROSS_COMPILE_C : $CROSS_COMPAT"

json_add_str "arch" "$KARCH"
json_add_str "cross_compile" "$CROSS_PREFIX"
json_add_str "cross_compile_compat" "$CROSS_COMPAT"

# ============================================
# 3. BUILT KERNEL VERSION STRING (from vmlinux "Linux version ...")
#    + toolchain identification
# ============================================
log_header "3. BUILT KERNEL VERSION STRING & TOOLCHAIN"

LINUX_VER=""
COMPILER=""
LINKER=""
if [ -f "$KOUT/vmlinux" ]; then
    LINUX_VER=$(strings "$KOUT/vmlinux" 2>/dev/null | grep -E -m1 '^Linux version ')
    log_info "Linux version line: $LINUX_VER"
    # The version line is:
#   Linux version <rel> (<builduser>) (<compiler...>, GNU ld (...)) #N SMP ...
# There are TWO parenthesised groups: build host (1) and toolchain (2).
# Strip the first " (...)" then take everything between the next "(" and the
# matching ")" before " #". This tolerates nested parens inside the compiler.
    rest=$(printf '%s' "$LINUX_VER")
    # drop build-host parens "(bhe@localhost)"
    rest=${rest#*(*) }
    # الآن rest starts at "(<compiler...>) #N..."
    if [ "${rest#"("}" != "$rest" ]; then
        # strip leading "( "
        rest=${rest#(}
        # cut at ") #" boundary — toolchain block is up to the last ")" before " #"
        tchain=${rest%" #"*}
        # tchain may keep a trailing ")"; drop it
        tchain=${tchain%)}
        # split on ", GNU ld"
        COMPILER=$(printf '%s' "$tchain" | sed 's/, GNU ld.*//; s/[[:space:]]*$//')
        LINKER=$(printf '%s' "$tchain" | sed -n 's/.*\(GNU ld.*\)/\1/p')
    fi
else
    log_warn "No out/vmlinux — cannot read built version string"
fi

log_info "Compiler : $COMPILER"
log_info "Linker   : $LINKER"

# Build host / SMP / preempt from the same line (e.g. "#3 SMP PREEMPT Sat ...")
BUILD_NR=$(printf '%s' "$LINUX_VER" | sed -n 's/.*#\(.*\) SMP.*/\1/p' | tr -d ' ')
SMP=$(printf '%s' "$LINUX_VER" | grep -q ' SMP ' && echo 1 || echo 0)
PREEMPT_BUILT=$(printf '%s' "$LINUX_VER" | grep -q 'PREEMPT' && echo 1 || echo 0)
BUILD_DATE=$(printf '%s' "$LINUX_VER" | sed -n \
    -e 's/.*SMP PREEMPT[[:space:]]*//p' \
    -e 's/.*SMP[[:space:]]*//p' \
    | head -1)

json_add_str "linux_version_string"  "$(jesc "$LINUX_VER")"
json_add_str "compiler"              "$(jesc "$COMPILER")"
json_add_str "linker"                 "$(jesc "$LINKER")"
json_add_str "build_number"          "$BUILD_NR"
json_add_str "smp"                   "$SMP"
json_add_str "preempt_built"          "$PREEMPT_BUILT"
json_add_str "build_date"            "$BUILD_DATE"

# ============================================
# 4. KERNEL IMAGE ARTIFACTS (what AK3 will actually package)
#    scan out/arch/<arch>/boot/ for AK3-recognized kernel filenames,
#    detect compression by magic bytes, pick the recommended one.
# ============================================
log_header "4. KERNEL IMAGE ARTIFACTS"

# The filenames AK3's flash_boot recognises (ak3-core.sh:264). We only probe
# the ones that exist on disk and report size + compression each.
# order mirrors AK3's scan order (first present wins when picking).
AK3_KERNEL_NAMES="zImage zImage-dtb Image Image-dtb Image.gz Image.gz-dtb Image.bz2 Image.bz2-dtb Image.lzo Image.lzo-dtb Image.lzma Image.lzma-dtb Image.xz Image.xz-dtb Image.lz4 Image.lz4-dtb Image.fit"

# Detect compression by sniffing first 6 bytes (magic)
sniff_comp() {
    # $1 = file path
    [ -f "$1" ] || { echo ""; return; }
    local m
    m=$(od -An -tx1 -N6 "$1" 2>/dev/null | tr -d ' \n')
    case "$m" in
        1f8b08*)           echo "gzip";;
        425a68*)           echo "bzip2";;
        fd*377a585a00)     echo "xz";;
        28b52ffd*|04224d18*|02214c18*) echo "lz4";;
        894c5a4f)          echo "lzop";;
        5d000080*)         echo "lzma";;
        # arm64 Image raw starts with branch stxlr (smallval). Treat as raw.
        *)                 echo "raw";;
    esac
}

BOOTDIR="$KOUT/arch/$KARCH/boot"
log_info "Boot dir: $BOOTDIR"

KERNEL_IMGS_JSON=""
RECOMMENDED_KERNEL=""
RECOMMENDED_KERNEL_COMP=""
RECOMMENDED_KERNEL_SIZE=0

# Build a comma-free ranking of which present kernel to pick.
# Priority (so lavender ships the appended-DTB form):
#   3 = compressed + appended-dtb  (Image.gz-dtb / Image.lz4-dtb / ...)
#   2 = compressed, no dtb         (Image.gz / Image.lz4 / ...)
#   1 = raw + appended-dtb         (Image-dtb)
#   0 = raw, no dtb                (Image, zImage)
BEST_RANK=-1
for kn in $AK3_KERNEL_NAMES; do
    f="$BOOTDIR/$kn"
    [ -f "$f" ] || continue
    sz=$(wc -c < "$f" 2>/dev/null | tr -d ' ')
    comp=$(sniff_comp "$f")
    log_info "  found: $kn (${sz} bytes, ${comp})"
    KERNEL_IMGS_JSON="${KERNEL_IMGS_JSON}{\"name\":\"$kn\",\"size\":${sz:-0},\"compression\":\"$comp\"},"
    rank=0
    case "$kn" in
        *-dtb)
            case "$comp" in
                gzip|bzip2|lz4|lzma|xz|lzop) rank=3 ;;
                *)                            rank=1 ;;
            esac
            ;;
        *)
            case "$comp" in
                gzip|bzip2|lz4|lzma|xz|lzop) rank=2 ;;
                *)                            rank=0 ;;
            esac
            ;;
    esac
    if [ "$rank" -gt "$BEST_RANK" ]; then
        BEST_RANK=$rank
        RECOMMENDED_KERNEL="$kn"
        RECOMMENDED_KERNEL_COMP="$comp"
        RECOMMENDED_KERNEL_SIZE="$sz"
    fi
done

if [ -n "$RECOMMENDED_KERNEL" ]; then
    log_info "Recommended kernel file for AK3 zip root: $RECOMMENDED_KERNEL ($RECOMMENDED_KERNEL_COMP, ${RECOMMENDED_KERNEL_SIZE} bytes)"
else
    log_warn "No AK3-recognised kernel image found in $BOOTDIR"
fi

KERNEL_IMGS_JSON="[${KERNEL_IMGS_JSON%,}]"
json_add "kernel_images" "$KERNEL_IMGS_JSON"
json_add_str "ak3_recommended_kernel_file" "$RECOMMENDED_KERNEL"
json_add_str "ak3_recommended_kernel_compression" "$RECOMMENDED_KERNEL_COMP"
json_add_str "ak3_recommended_kernel_size" "$RECOMMENDED_KERNEL_SIZE"

# ============================================
# 5. APPENDED-DTB DECOMPOSITION (what Image.gz-dtb actually concatenated)
#    read out/arch/<arch>/boot/.Image.gz-dtb.cmd (or *.cmd) — read-only.
# ============================================
log_header "5. APPENDED-DTB FILES"

APPENDED_DTBS_JSON=""
APPENDED_DTBS_LIST=""
# Try .cmd for the found kernel with '-dtb' suffix family
for f in "$BOOTDIR"/.*-dtb.cmd "$BOOTDIR"/.*-dtb\*.cmd; do
    [ -f "$f" ] || continue
    log_step "Reading $(basename "$f")"
    # The .cmd body is: cmd_<target> := (<files cat'd>) || (...)
    # Extract every path under arch/.../dts/ from inside the parentheses.
    dtbs=$(sed -n 's/.*(\(.*\)) .*/\1/p' "$f" 2>/dev/null \
           | tr ' ' '\n' \
           | grep -E '/dts/.*\.(dtb|dtbo)$')
    for d in $dtbs; do
        # .cmd files store build paths relative to KSRC (e.g. arch/arm64/boot/dts/...).
        # Make absolute: if not starting with /, prefix KSRC. KOUT is usually KSRC/out
        # and the dts files live under KOUT, so prefix KOUT first then KSRC fallback.
        case "$d" in
            /*) abs="$d" ;;
            *)  if [ -f "$KOUT/$d" ]; then abs="$KOUT/$d"; else abs="$KSRC/$d"; fi ;;
        esac
        rel=$(printf '%s' "$abs" | sed "s#^$KOUT/##; s#^$KSRC/##")
        sz=$(wc -c < "$abs" 2>/dev/null | tr -d ' ')
        log_info "  appended: $rel (${sz} bytes)"
        APPENDED_DTBS_JSON="${APPENDED_DTBS_JSON}{\"path\":\"$(jesc "$rel")\",\"size\":${sz:-0}},"
        APPENDED_DTBS_LIST="$APPENDED_DTBS_LIST $rel"
    done
done
APPENDED_DTBS_JSON="[${APPENDED_DTBS_JSON%,}]"
json_add "appended_dtb_files" "$APPENDED_DTBS_JSON"

# ============================================
# 6. STANDALONE DTB / DTBO ARTIFACTS in out/arch/<arch>/boot/dts/
# ============================================
log_header "6. DTB / DTBO ARTIFACTS"

DTB_JSON=""
DTBO_JSON=""
DTB_ALL_COUNT=0
DTBO_ALL_COUNT=0
DTSROOT="$KOUT/arch/$KARCH/boot/dts"
log_info "DTS out root: $DTSROOT"

if [ -d "$DTSROOT" ]; then
    DTB_ALL=$(find "$DTSROOT" -type f -name '*.dtb' 2>/dev/null)
    DTBO_ALL=$(find "$DTSROOT" -type f -name '*.dtbo' 2>/dev/null)
    DTB_ALL_COUNT=$(printf '%s\n' "$DTB_ALL" | grep -c '\.dtb$' 2>/dev/null)
    DTBO_ALL_COUNT=$(printf '%s\n' "$DTBO_ALL" | grep -c '\.dtbo$' 2>/dev/null)
    log_info "Total .dtb  files built: $DTB_ALL_COUNT"
    log_info "Total .dtbo files built: $DTBO_ALL_COUNT"

    # Build per-file entries, flagging files matching DEVICE_CODENAME
    if [ -n "$DTB_ALL" ]; then
        printf '%s\n' "$DTB_ALL" | while IFS= read -r d; do
            [ -f "$d" ] || continue
            rel=$(printf '%s' "$d" | sed "s#^$DTSROOT/##")
            sz=$(wc -c < "$d" 2>/dev/null | tr -d ' ')
            base=$(basename "$rel")
            matches=0
            if [ -n "$DEVICE_CODENAME" ]; then
                case "$base" in
                    *"$DEVICE_CODENAME"*) matches=1 ;;
                esac
            fi
            log_info "  dtb : $rel (${sz} bytes)$([ "$matches" -eq 1 ] && echo "  <-- matches $DEVICE_CODENAME")"
            printf '%s\n' "{\"path\":\"$(jesc "$rel")\",\"size\":${sz:-0},\"matches_codename\":$matches}"
        done > "$OUTPUT_DIR/.tmp_dtb_entries.json" 2>/dev/null
        DTB_JSON=$(paste -sd, "$OUTPUT_DIR/.tmp_dtb_entries.json" 2>/dev/null | sed 's/^/[/;s/$/]/' | head -c 1000000)
        rm -f "$OUTPUT_DIR/.tmp_dtb_entries.json"
    fi
    if [ -n "$DTBO_ALL" ]; then
        printf '%s\n' "$DTBO_ALL" | while IFS= read -r d; do
            [ -f "$d" ] || continue
            rel=$(printf '%s' "$d" | sed "s#^$DTSROOT/##")
            sz=$(wc -c < "$d" 2>/dev/null | tr -d ' ')
            base=$(basename "$rel")
            matches=0
            if [ -n "$DEVICE_CODENAME" ]; then
                case "$base" in
                    *"$DEVICE_CODENAME"*) matches=1 ;;
                esac
            fi
            log_info "  dtbo: $rel (${sz} bytes)$([ "$matches" -eq 1 ] && echo "  <-- matches $DEVICE_CODENAME")"
            printf '%s\n' "{\"path\":\"$(jesc "$rel")\",\"size\":${sz:-0},\"matches_codename\":$matches}"
        done > "$OUTPUT_DIR/.tmp_dtbo_entries.json" 2>/dev/null
        DTBO_JSON=$(paste -sd, "$OUTPUT_DIR/.tmp_dtbo_entries.json" 2>/dev/null | sed 's/^/[/;s/$/]/' | head -c 1000000)
        rm -f "$OUTPUT_DIR/.tmp_dtbo_entries.json"
    fi
fi
[ -z "$DTB_JSON" ]  && DTB_JSON="[]"
[ -z "$DTBO_JSON" ] && DTBO_JSON="[]"

json_add "dtb_files"  "$DTB_JSON"
json_add "dtbo_files" "$DTBO_JSON"
json_add_str "dtb_file_count"  "$DTB_ALL_COUNT"
json_add_str "dtbo_file_count" "$DTBO_ALL_COUNT"

# ============================================
# 7. KERNEL .config KEY FLAGS (read out/.config — read-only)
# ============================================
log_header "7. KERNEL .config KEY FLAGS"

KCONFIG="$KOUT/.config"
HAS_CONFIG=0
[ -f "$KCONFIG" ] && HAS_CONFIG=1
log_info ".config present: $HAS_CONFIG ($KCONFIG)"

# Helper: read a CONFIG_ value. Returns "" if not set, "n" if "# ... is not set"
cfg() {
    [ "$HAS_CONFIG" -eq 1 ] || { echo ""; return; }
    local v
    v=$(grep -E "^$1=|^# $1 is not set" "$KCONFIG" 2>/dev/null | head -1)
    case "$v" in
        "$1="*)        printf '%s' "$v" | sed "s/^$1=//; s/^\"//; s/\"$//";;
        "# $1 is not set") echo "n";;
        *)             echo "";;
    esac
}
# boolean helper -> 1/0/n
cfgb() {
    local v; v=$(cfg "$1")
    case "$v" in
        y) echo 1;;
        n) echo 0;;
        m) echo m;;
        "") echo "";;
        *) echo "$v";;
    esac
}

# Compose key-flag JSON object — only flags that matter for AK3 packaging
# decisions (modules, KSU, kprobes, ikconfig, preempt, hz, kallsyms, etc.)
KV_FLAGS=",CONFIG_KSU,CONFIG_KSU_DEBUG,CONFIG_KSU_MANUAL_HOOK,CONFIG_KSU_DISABLE_MANAGER,CONFIG_KPROBES,CONFIG_HAVE_KPROBES,CONFIG_KALLSYMS,CONFIG_IKCONFIG,CONFIG_IKCONFIG_PROC,CONFIG_IKHEADERS,CONFIG_MODULES,CONFIG_MODVERSIONS,CONFIG_LOCALVERSION,CONFIG_LOCALVERSION_AUTO,CONFIG_RANDOMIZE_BASE,CONFIG_PREEMPT,CONFIG_PREEMPT_NONE,CONFIG_PREEMPT_VOLUNTARY,CONFIG_HZ,CONFIG_CPU_IDLE,CONFIG_INIT_STACK_ALL_ZERO,CONFIG_INIT_STACK_ALL_PATTERN,CONFIG_INIT_STACK_NONE,CONFIG_INIT_ON_ALLOC_DEFAULT_ON,CONFIG_INIT_ON_FREE_DEFAULT_ON,CONFIG_OVERLAY_FS,CONFIG_TUN,CONFIG_WIREGUARD,"

CFG_JSON=""
FIRST=1
printf '%s' "$KV_FLAGS" | tr ',' '\n' | while IFS= read -r opt; do
    [ -n "$opt" ] || continue
    val=$(cfg "$opt")
    [ -n "$val" ] || val="unset"
    printf '%s\n' "\"$opt\":\"$(jesc "$val")\""
done > "$OUTPUT_DIR/.tmp_cfg_pairs.txt" 2>/dev/null
CFG_JSON=$(paste -sd, "$OUTPUT_DIR/.tmp_cfg_pairs.txt" 2>/dev/null | sed 's/^/ {/;s/$/ }/' | head -c 2000000)
rm -f "$OUTPUT_DIR/.tmp_cfg_pairs.txt"
[ -z "$CFG_JSON" ] && CFG_JSON="{}"

json_add "config_flags" "$CFG_JSON"

# Quick high-level booleans (for builder convenience)
KSU=$(cfgb CONFIG_KSU)
KPROBES=$(cfgb CONFIG_KPROBES)
IKCONFIG_PROC=$(cfgb CONFIG_IKCONFIG_PROC)
MODULES=$(cfgb CONFIG_MODULES)
PREEMPT=$(cfgb CONFIG_PREEMPT)
KALLSYMS=$(cfgb CONFIG_KALLSYMS)
HZ=$(cfg CONFIG_HZ)
log_info "KSU=$KSU KPROBES=$KPROBES IKCONFIG_PROC=$IKCONFIG_PROC MODULES=$MODULES PREEMPT=$PREEMPT KALLSYMS=$KALLSYMS HZ=$HZ"

json_add_str "ksu"            "$KSU"
json_add_str "kprobes"        "$KPROBES"
json_add_str "ikconfig_proc"  "$IKCONFIG_PROC"
json_add_str "modules_built"  "$MODULES"
json_add_str "preempt"        "$PREEMPT"
json_add_str "kallsyms"       "$KALLSYMS"
json_add_str "hz"             "$HZ"

# ============================================
# 8. OUT-OF-TREE / BUILT MODULES (.ko)
# ============================================
log_header "8. BUILT MODULES (.ko)"

KO_LIST=$(find "$KOUT" -type f -name '*.ko' 2>/dev/null)
KO_COUNT=$(printf '%s\n' "$KO_LIST" | grep -c '\.ko$' 2>/dev/null)
[ -z "$KO_COUNT" ] && KO_COUNT=0
log_info "Built .ko modules: $KO_COUNT"

KO_JSON=""
if [ "$KO_COUNT" -gt 0 ] && [ -n "$KO_LIST" ]; then
    printf '%s\n' "$KO_LIST" | while IFS= read -r ko; do
        [ -f "$ko" ] || continue
        rel=$(printf '%s' "$ko" | sed "s#^$KOUT/##")
        sz=$(wc -c < "$ko" 2>/dev/null | tr -d ' ')
        printf '%s\n' "{\"path\":\"$(jesc "$rel")\",\"size\":${sz:-0}}"
    done > "$OUTPUT_DIR/.tmp_ko_entries.json" 2>/dev/null
    KO_JSON=$(paste -sd, "$OUTPUT_DIR/.tmp_ko_entries.json" 2>/dev/null | sed 's/^/[/;s/$/]/' | head -c 5000000)
    rm -f "$OUTPUT_DIR/.tmp_ko_entries.json"
    # print up to 30 sample
    printf '%s\n' "$KO_LIST" | head -30 | while IFS= read -r ko; do
        log_info "  $(printf '%s' "$ko" | sed "s#^$KOUT/##")"
    done
fi
[ -z "$KO_JSON" ] && KO_JSON="[]"

json_add "built_ko_modules" "$KO_JSON"
json_add_str "built_ko_count" "$KO_COUNT"

# ============================================
# 9. KSU SOURCE TREE + selected defconfig
# ============================================
log_header "9. KSU SOURCE TREE & DEFCONFIG"

KSU_TREE=""
[ -d "$KSRC/KernelSU-Next" ] && KSU_TREE="KernelSU-Next"
[ -z "$KSU_TREE" ] && [ -d "$KSRC/KernelSU" ] && KSU_TREE="KernelSU"
[ -z "$KSU_TREE" ] && { [ -d "$KSRC/drivers/kernelsu" ] && KSU_TREE="drivers/kernelsu"; }
log_info "KSU source tree: ${KSU_TREE:-none}"

# Defconfigs available for the arch (highest-relevance ones)
DEFCONFIGS_JSON=""
DEFDIR="$KSRC/arch/$KARCH/configs"
if [ -d "$DEFDIR" ]; then
    log_info "Top-level defconfigs in $DEFDIR:"
    for dc in "$DEFDIR"/*defconfig; do
        [ -f "$dc" ] || continue
        base=$(basename "$dc")
        log_info "  $base"
        DEFCONFIGS_JSON="${DEFCONFIGS_JSON}\"$(jesc "$base")\","
    done
    # also vendor subdir (qcom→lavender-perf_defconfig etc.)
    if [ -d "$DEFDIR/vendor" ]; then
        for dc in "$DEFDIR"/vendor/*defconfig; do
            [ -f "$dc" ] || continue
            base=$(basename "$dc")
            log_info "  vendor/$base"
            DEFCONFIGS_JSON="${DEFCONFIGS_JSON}\"vendor/$(jesc "$base")\","
        done
    fi
fi
DEFCONFIGS_JSON="[${DEFCONFIGS_JSON%,}]"
json_add "defconfigs" "$DEFCONFIGS_JSON"
json_add_str "ksu_source_tree" "$KSU_TREE"

# Heuristic: which defconfig built this .config? Try grep for the localversion
# marker against each defconfig; report the best-match matches_codename.
BEST_DEFCFG=""
if [ -n "$DEVICE_CODENAME" ] && [ -d "$DEFDIR" ]; then
    case "$DEVICE_CODENAME" in
        *) best_grep="$DEVICE_CODENAME" ;;
    esac
    for dc in "$DEFDIR"/vendor/*"$DEVICE_CODENAME"*defconfig; do
        [ -f "$dc" ] || continue
        BEST_DEFCFG="vendor/$(basename "$dc")"
        break
    done
fi
log_info "Best-guess defconfig for $DEVICE_CODENAME: ${BEST_DEFCFG:-N/A}"
json_add_str "best_guess_defconfig" "$BEST_DEFCFG"

# ============================================
# 10. BUILD.PIPELINE HINTS (build.config.*, BRANCH)
# ============================================
log_header "10. BUILD PIPELINE HINTS"

BRANCH=$(grep '^BRANCH=' "$KSRC"/build.config.* 2>/dev/null | head -1 | cut -d= -f2)
LLVM=$(grep -l '^LLVM=1' "$KSRC"/build.config.* 2>/dev/null | head -1)
[ -n "$LLVM" ] && LLVM_USED=1 || LLVM_USED=0
log_info "BRANCH (build.config): $BRANCH"
log_info "LLVM=1 set in any build.config: $LLVM_USED"
json_add_str "build_branch"  "$BRANCH"
json_add_str "llvm_enabled" "$LLVM_USED"

# ============================================
# 11. AK3 ZIP-PACKAGING CHEATSHEET (derived)
# ============================================
log_header "11. AK3 ZIP-PACKAGING SUMMARY"

# Pick the kernel file the zip should ship. If a -dtb variant exists, prefer it
# (keeps DTB appended — lavender ships Image.gz-dtb). Otherwise prefer the
# compressed form (Image.gz) over raw Image to save space.
ZIP_KERNEL_FILE="$RECOMMENDED_KERNEL"
if [ -n "$ZIP_KERNEL_FILE" ]; then
    case "$ZIP_KERNEL_FILE" in
        *-dtb) ZIP_KERNEL_HAS_DTB=1 ;;
        *)     ZIP_KERNEL_HAS_DTB=0 ;;
    esac
else
    ZIP_KERNEL_HAS_DTB=0
fi

# do.modules: 1 only if .ko modules were actually built
if [ "$KO_COUNT" -gt 0 ]; then
    ZIP_DO_MODULES=1
else
    ZIP_DO_MODULES=0
fi

log_info "zip kernel file : $ZIP_KERNEL_FILE"
log_info "zip has appended DTB : $ZIP_KERNEL_HAS_DTB"
log_info "zip do.modules  : $ZIP_DO_MODULES (built .ko count=$KO_COUNT)"
log_info "zip kernel.string suggestion: $KREL"

json_add_str "zip_kernel_file"       "$ZIP_KERNEL_FILE"
json_add_str "zip_kernel_has_dtb"    "$ZIP_KERNEL_HAS_DTB"
json_add_str "zip_do_modules"        "$ZIP_DO_MODULES"
json_add_str "zip_kernel_string_suggest" "$KREL"

# ============================================
# 12. FINALIZE JSON + emit anykernel.sh snippet to log
# ============================================
log_header "12. FINALIZING"

json_add_str "source_path"  "$KSRC"
json_add_str "out_path"     "$KOUT"
json_add_str "collected_at" "$(date -u 2>/dev/null | tr -d '\n')"
json_add_str "script_version" "1.0"

json_finalize

echo "" >> "$LOG_FILE"
echo "# =========================================" >> "$LOG_FILE"
echo "# Derived anykernel.sh hints (review & edit)" >> "$LOG_FILE"
echo "# =========================================" >> "$LOG_FILE"
{
    echo "kernel.string=${KREL:-YourKernelName by YourName}"
    echo "do.modules=$ZIP_DO_MODULES"
    echo "do.systemless=1"
    echo "do.cleanup=1"
    echo "do.cleanuponabort=0"
    [ -n "$DEVICE_CODENAME" ] && echo "device.name1=$DEVICE_CODENAME"
    echo ""
    echo "# Kernel file to drop at zip root: $ZIP_KERNEL_FILE"
    if [ "$ZIP_KERNEL_HAS_DTB" -eq 0 ]; then
        echo "# NOTE: kernel has NO appended DTB — if device needs dtbo, also"
        echo "#       ship dtbo partition image and call flash_dtbo;"
        echo "#       also ensure a dtb file is present if device boot needs one."
    else
        echo "# NOTE: $ZIP_KERNEL_FILE has DTB appended — no separate dtb needed."
    fi
    echo ""
    echo "BLOCK=auto   # see <device>_codename.json ak3_recommended_block"
    echo "RAMDISK_COMPRESSION=auto"
    echo ". tools/ak3-core.sh"
    if [ "$ZIP_KERNEL_HAS_DTB" -eq 1 ]; then
        echo "split_boot   # kernel-only (DTB already appended)"
        echo "flash_boot"
    else
        echo "split_boot"
        echo "flash_boot"
    fi
} >> "$LOG_FILE"

# Also print the cheatsheet to stdout for convenience
log_raw ""
log_raw "# AK3 zip-packaging cheatsheet (saved to log):"
log_raw "  kernel.string=$KREL"
log_raw "  zip kernel file = $ZIP_KERNEL_FILE (appended dtb=$ZIP_KERNEL_HAS_DTB)"
log_raw "  do.modules=$ZIP_DO_MODULES"
log_raw ""

log_info "JSON output: $JSON_FILE"
log_info "Log output : $LOG_FILE"

exit 0
