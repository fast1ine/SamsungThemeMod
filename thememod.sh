#!/usr/bin/env bash
set -euo pipefail

APP_BASENAME="OneUI7.0_ZFlip4_Maison_Margiela_Edition_v1.0.apk"
OUTPUT_BASENAME="MODed_OneUI7.0_ZFlip4_Maison_Margiela_Edition_v1.0.apk"

SRC_PREFIX="mm.theme01"
DST_PREFIX="com.samsung.High_contrast_theme_II"
APP_LABEL="MM.Theme"
OUTER_VERSION_CODE="80347"
OUTER_VERSION_NAME="8.0.34"
INNER_VERSION_CODE="1"
INNER_VERSION_NAME="1.0"
MIN_SDK="21"
TARGET_SDK="26"
PLATFORM_BUILD_CODE="23"
PLATFORM_BUILD_NAME="6.0-2438415"

SCRIPT_DIR="${BASH_SOURCE[0]%/*}"
if [ "$SCRIPT_DIR" = "${BASH_SOURCE[0]}" ]; then
    SCRIPT_DIR="."
fi

PROJECT_ROOT="$(cd "$SCRIPT_DIR" && pwd)"
INPUT_APK="$PROJECT_ROOT/proprietary/$APP_BASENAME"
OUTPUT_APK="$PROJECT_ROOT/output/$OUTPUT_BASENAME"
KEY_CERT="$PROJECT_ROOT/keys/key.x509.pem"
KEY_PK8="$PROJECT_ROOT/keys/key.pk8"

package_for_tool() {
    case "$1" in
        aapt) printf 'aapt' ;;
        apktool) printf 'apktool' ;;
        apksigner) printf 'apksigner' ;;
        cat | chmod | cp | mkdir | mv | readlink | rm | sha256sum | sort | tail) printf 'coreutils' ;;
        find) printf 'findutils' ;;
        grep) printf 'grep' ;;
        perl) printf 'perl' ;;
        sed) printf 'sed' ;;
        signapk) printf 'signapk' ;;
        unzip) printf 'unzip' ;;
        zip) printf 'zip' ;;
        zipalign) printf 'zipalign' ;;
    esac
}

require_tools() {
    local missing=()
    local packages=()
    local tool
    local package

    # Check only the commands this script calls directly.
    for tool in apktool zipalign signapk apksigner unzip zip perl sha256sum aapt find sort tail sed grep readlink cat chmod mkdir rm mv cp; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            missing+=("$tool")
            package="$(package_for_tool "$tool")"
            if [ -n "$package" ] && [[ " ${packages[*]} " != *" $package "* ]]; then
                packages+=("$package")
            fi
        fi
    done

    if [ "${#missing[@]}" -gt 0 ]; then
        printf 'Missing commands required by thememod.sh:\n' >&2
        printf '  %s\n' "${missing[@]}" >&2
        printf '\nInstall the missing packages, then run this script again:\n' >&2
        printf '  sudo apt install -y' >&2
        printf ' %s' "${packages[@]}" >&2
        printf '\n' >&2
        exit 1
    fi

    if [ ! -f "$INPUT_APK" ]; then
        printf 'Missing input APK: %s\n' "$INPUT_APK" >&2
        printf 'Run ./extract-files.sh first, or place %s in proprietary/.\n' "$APP_BASENAME" >&2
        exit 1
    fi

    if [ ! -f "$KEY_CERT" ] || [ ! -f "$KEY_PK8" ]; then
        printf 'Missing signing keys:\n' >&2
        printf '  %s\n' "$KEY_CERT" "$KEY_PK8" >&2
        exit 1
    fi
}

resolve_framework_res() {
    local candidate

    # Prefer an explicit framework path, then common apktool/framework locations.
    for candidate in \
        "${FRAMEWORK_RES:-}" \
        /usr/share/android-framework-res/framework-res.apk \
        "$HOME/.local/share/apktool/framework/1.apk" \
        "$HOME/.apktool/framework/1.apk"; do
        if [ -n "$candidate" ] && [ -f "$candidate" ]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done

    printf 'Unable to find Android framework-res.apk. Set FRAMEWORK_RES=/path/to/framework-res.apk\n' >&2
    exit 1
}

resolve_apktool_jar() {
    local apktool_bin apktool_dir candidate latest

    # apktool package layouts differ, so look next to the executable first.
    apktool_bin="$(command -v apktool)"
    apktool_dir="${apktool_bin%/*}"
    if [ "$apktool_dir" = "$apktool_bin" ]; then
        apktool_dir="."
    fi
    apktool_dir="$(cd "$apktool_dir" && pwd)"

    candidate="$apktool_dir/apktool.jar"
    if [ -f "$candidate" ]; then
        printf '%s\n' "$candidate"
        return 0
    fi

    latest="$(find "$apktool_dir" -maxdepth 1 -type f -name 'apktool_*.jar' | sort -V | tail -n 1)"
    if [ -n "$latest" ] && [ -f "$latest" ]; then
        printf '%s\n' "$latest"
        return 0
    fi

    printf 'Unable to find apktool.jar next to %s\n' "$apktool_bin" >&2
    exit 1
}

prepare_aapt2_wrapper() {
    local apktool_jar framework_res aapt2_bin wrapper
    apktool_jar="$(resolve_apktool_jar)"
    framework_res="$(resolve_framework_res)"

    # Use apktool's embedded aapt2 while injecting framework-res.apk at link time.
    mkdir -p "$WORK_DIR/aapt2"
    aapt2_bin="$WORK_DIR/aapt2/aapt2_64"
    unzip -p "$apktool_jar" prebuilt/linux/aapt2_64 > "$aapt2_bin"
    chmod +x "$aapt2_bin"

    wrapper="$WORK_DIR/aapt2/aapt2-framework-no-compile-sdk"
    cat > "$wrapper" <<EOF
#!/usr/bin/env bash
set -e
cmd="\${1:-}"
if [ "\$cmd" = "link" ]; then
    exec "$aapt2_bin" "\$1" -I "$framework_res" "\${@:2}"
fi
exec "$aapt2_bin" "\$@"
EOF
    chmod +x "$wrapper"
    printf '%s\n' "$wrapper"
}

set_sdk_info() {
    local yml="$1"

    # Keep min/target SDK metadata aligned with the final signed package.
    perl -0pi -e '
        if (/sdkInfo:\n(?:  [^\n]+\n)+/) {
            s/sdkInfo:\n(?:  [^\n]+\n)+/sdkInfo:\n  minSdkVersion: '"$MIN_SDK"'\n  targetSdkVersion: '"$TARGET_SDK"'\n/;
        } else {
            s/(apkFileName: [^\n]+\n)/$1sdkInfo:\n  minSdkVersion: '"$MIN_SDK"'\n  targetSdkVersion: '"$TARGET_SDK"'\n/;
        }
    ' "$yml"
}

remove_compile_sdk_attrs() {
    # Samsung theme compatibility requires omitting compileSdk metadata.
    perl -0pi -e 's/ d1p1:compileSdkVersion="[^"]+"//g; s/ d1p1:compileSdkVersionCodename="[^"]+"//g' "$1"
}

make_features_optional() {
    # Avoid device-feature gating that hides the theme on compatible devices.
    perl -0pi -e '
        s/(<uses-feature\b[^>]*?)\s+d1p1:required="[^"]*"([^>]*\/>)/$1$2/g;
        s/(<uses-feature\b[^>]*?)\s*\/>/$1 d1p1:required="false" \/>/g;
    ' "$1"
}

normalize_outer() {
    local outer="$1"
    local manifest="$outer/AndroidManifest.xml"
    local yml="$outer/apktool.yml"
    local themes="$outer/assets/themes.json"

    # Rewrite the outer package identity while preserving the source theme assets.
    remove_compile_sdk_attrs "$manifest"
    perl -0pi -e '
        s/package="'"$SRC_PREFIX"'"/package="'"$DST_PREFIX"'"/g;
        s/d1p1:versionCode="[^"]+"/d1p1:versionCode="'"$OUTER_VERSION_CODE"'"/;
        s/d1p1:versionName="[^"]+"/d1p1:versionName="'"$OUTER_VERSION_NAME"'"/;
        s/platformBuildVersionCode="[^"]+"/platformBuildVersionCode="'"$PLATFORM_BUILD_CODE"'"/;
        s/platformBuildVersionName="[^"]+"/platformBuildVersionName="'"$PLATFORM_BUILD_NAME"'"/;
        s/d1p1:label="[^"]+"/d1p1:label="'"$APP_LABEL"'"/;
    ' "$manifest"
    make_features_optional "$manifest"

    set_sdk_info "$yml"
    perl -0pi -e '
        s/apkFileName: .*/apkFileName: '"$OUTPUT_BASENAME"'/;
        s/versionCode: \d+/versionCode: '"$OUTER_VERSION_CODE"'/;
        s/versionName: [^\n]+/versionName: '"$OUTER_VERSION_NAME"'/;
    ' "$yml"

    perl -0pi -e '
        s/'"$SRC_PREFIX"'/'"$DST_PREFIX"'/g;
        s/\n\s*"visibilityResult"\s*:\s*"[^"]+"\s*,//g;
        s/,\n\s*"visibilityTimeStamp"\s*:\s*"[^"]+"//g;
    ' "$themes"
}

normalize_inner() {
    local decoded="$1"
    local suffix="$2"
    local manifest="$decoded/AndroidManifest.xml"
    local yml="$decoded/apktool.yml"

    # Embedded theme APKs must share the same package namespace rewrite.
    remove_compile_sdk_attrs "$manifest"
    perl -0pi -e '
        s/'"$SRC_PREFIX"'/'"$DST_PREFIX"'/g;
        s/d1p1:versionCode="[^"]+"/d1p1:versionCode="'"$INNER_VERSION_CODE"'"/;
        s/d1p1:versionName="[^"]+"/d1p1:versionName="'"$INNER_VERSION_NAME"'"/;
        s/platformBuildVersionCode="[^"]+"/platformBuildVersionCode="'"$PLATFORM_BUILD_CODE"'"/;
        s/platformBuildVersionName="[^"]+"/platformBuildVersionName="'"$PLATFORM_BUILD_NAME"'"/;
    ' "$manifest"

    set_sdk_info "$yml"
    perl -0pi -e '
        s/apkFileName: .*/apkFileName: '"$DST_PREFIX"'.'"$suffix"'.apk/;
        s/versionCode: \d+/versionCode: '"$INNER_VERSION_CODE"'/;
        s/versionName: [^\n]+/versionName: '"$INNER_VERSION_NAME"'/;
    ' "$yml"
}

replace_manifest_without_compile_sdk() {
    local apk="$1"
    local manifest="$2"
    local version_code="$3"
    local version_name="$4"
    local aapt2_wrapper="$5"
    local name manifest_apk manifest_dir abs_apk

    # Rebuild only AndroidManifest.xml with aapt2 --no-compile-sdk-metadata.
    name="${apk##*/}"
    name="${name%.apk}"
    manifest_apk="$WORK_DIR/manifest-only/$name.apk"
    manifest_dir="$WORK_DIR/manifest-only/$name"
    mkdir -p "$WORK_DIR/manifest-only"

    "$aapt2_wrapper" link \
        -o "$manifest_apk" \
        --min-sdk-version "$MIN_SDK" \
        --target-sdk-version "$TARGET_SDK" \
        --version-code "$version_code" \
        --version-name "$version_name" \
        --no-auto-version \
        --no-version-vectors \
        --no-version-transitions \
        --no-resource-deduping \
        --no-compile-sdk-metadata \
        --warn-manifest-validation \
        --manifest "$manifest" >/dev/null

    rm -rf "$manifest_dir"
    mkdir -p "$manifest_dir"
    unzip -qq -o "$manifest_apk" AndroidManifest.xml -d "$manifest_dir"

    abs_apk="$(readlink -f "$apk")"
    zip -q -d "$abs_apk" AndroidManifest.xml >/dev/null 2>&1 || true
    (cd "$manifest_dir" && zip -q -0 "$abs_apk" AndroidManifest.xml)
}

rewrite_do_not_compress() {
    local yml="$1"
    local assets_dir="$2"
    local tmp="$WORK_DIR/apktool.yml.tmp"

    # Keep embedded APKs stored uncompressed after their filenames change.
    sed '/^doNotCompress:/,$d' "$yml" > "$tmp"
    {
        printf 'doNotCompress:\n'
        printf -- '- jpg\n'
        find "$assets_dir" -maxdepth 1 -type f -name "${DST_PREFIX}.*.apk" -printf '%f\n' \
            | sort \
            | while IFS= read -r asset; do
                printf -- '- assets/%s\n' "$asset"
            done
    } >> "$tmp"
    mv "$tmp" "$yml"
}

build_inner_apks() {
    local outer="$1"
    local aapt2_wrapper="$2"
    local assets_dir="$outer/assets"
    local source_apk suffix decoded unsigned aligned signed

    # Decode, rewrite, rebuild, align, and sign each embedded theme APK.
    mkdir -p "$WORK_DIR/inner-decoded" "$WORK_DIR/inner-unsigned" "$WORK_DIR/inner-aligned" "$WORK_DIR/inner-signed"

    while IFS= read -r -d '' source_apk; do
        suffix="${source_apk##*/}"
        suffix="${suffix%.apk}"
        suffix="${suffix#${SRC_PREFIX}.}"
        decoded="$WORK_DIR/inner-decoded/$suffix"
        unsigned="$WORK_DIR/inner-unsigned/${DST_PREFIX}.${suffix}.apk"
        aligned="$WORK_DIR/inner-aligned/${DST_PREFIX}.${suffix}.apk"
        signed="$WORK_DIR/inner-signed/${DST_PREFIX}.${suffix}.apk"

        printf 'Modding embedded APK: %s\n' "$suffix"
        apktool d -f "$source_apk" -o "$decoded" >/dev/null
        normalize_inner "$decoded" "$suffix"
        apktool b -f -a "$aapt2_wrapper" "$decoded" -o "$unsigned" >/dev/null
        replace_manifest_without_compile_sdk "$unsigned" "$decoded/AndroidManifest.xml" "$INNER_VERSION_CODE" "$INNER_VERSION_NAME" "$aapt2_wrapper"
        zipalign -f -p 4 "$unsigned" "$aligned"
        signapk --min-sdk-version "$MIN_SDK" "$KEY_CERT" "$KEY_PK8" "$aligned" "$signed"

        rm -f "$source_apk"
        cp -f "$signed" "$assets_dir/${DST_PREFIX}.${suffix}.apk"
    done < <(find "$assets_dir" -maxdepth 1 -type f -name "${SRC_PREFIX}.*.apk" -print0 | sort -z)
}

verify_output() {
    local final="$1"
    local compile_hits

    # Verify alignment, signature validity, and absence of compileSdk metadata.
    zipalign -c -p 4 "$final"
    apksigner verify --verbose --min-sdk-version "$MIN_SDK" "$final" >/dev/null

    compile_hits="$(aapt dump xmltree "$final" AndroidManifest.xml | grep -c 'compileSdkVersion' || true)"
    if [ "$compile_hits" -ne 0 ]; then
        printf 'Final APK still contains compileSdkVersion in outer manifest\n' >&2
        exit 1
    fi

    printf 'Final APK:\n  %s\n' "$final"
    sha256sum "$final"
}

main() {
    require_tools
    mkdir -p "$PROJECT_ROOT/output"

    WORK_DIR="$(mktemp -d)"
    trap 'rm -rf "$WORK_DIR"' EXIT

    local aapt2_wrapper outer unsigned aligned
    aapt2_wrapper="$(prepare_aapt2_wrapper)"
    outer="$WORK_DIR/outer"
    unsigned="$WORK_DIR/${OUTPUT_BASENAME%.apk}-unsigned.apk"
    aligned="$WORK_DIR/${OUTPUT_BASENAME%.apk}-aligned.apk"

    apktool d -f "$INPUT_APK" -o "$outer" >/dev/null
    normalize_outer "$outer"
    build_inner_apks "$outer" "$aapt2_wrapper"
    rewrite_do_not_compress "$outer/apktool.yml" "$outer/assets"

    apktool b -f -a "$aapt2_wrapper" "$outer" -o "$unsigned" >/dev/null
    replace_manifest_without_compile_sdk "$unsigned" "$outer/AndroidManifest.xml" "$OUTER_VERSION_CODE" "$OUTER_VERSION_NAME" "$aapt2_wrapper"
    zipalign -f -p 4 "$unsigned" "$aligned"
    signapk --min-sdk-version "$MIN_SDK" "$KEY_CERT" "$KEY_PK8" "$aligned" "$OUTPUT_APK"

    verify_output "$OUTPUT_APK"
}

main "$@"
