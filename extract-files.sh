#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="${BASH_SOURCE[0]%/*}"
if [ "$SCRIPT_DIR" = "${BASH_SOURCE[0]}" ]; then
    SCRIPT_DIR="."
fi

PROJECT_ROOT="$(cd "$SCRIPT_DIR" && pwd)"
FIRMWARE_DIR="$PROJECT_ROOT/firmware"
PROPRIETARY_DIR="$PROJECT_ROOT/proprietary"
LIST_FILE="$PROJECT_ROOT/proprietary-files.txt"

package_for_tool() {
    case "$1" in
        7z) printf 'p7zip-full' ;;
        cp | head | mkdir | mktemp | rm | sha256sum | sort) printf 'coreutils' ;;
        file) printf 'file' ;;
        find) printf 'findutils' ;;
        lz4) printf 'lz4' ;;
        tar) printf 'tar' ;;
    esac
}

require_tools() {
    local missing=()
    local packages=()
    local tool
    local package

    # Check only the commands this script calls directly.
    for tool in tar lz4 7z sha256sum file find sort head mktemp mkdir rm cp; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            missing+=("$tool")
            package="$(package_for_tool "$tool")"
            if [ -n "$package" ] && [[ " ${packages[*]} " != *" $package "* ]]; then
                packages+=("$package")
            fi
        fi
    done

    if [ "${#missing[@]}" -gt 0 ]; then
        printf 'Missing commands required by extract-files.sh:\n' >&2
        printf '  %s\n' "${missing[@]}" >&2
        printf '\nInstall the missing packages, then run this script again:\n' >&2
        printf '  sudo apt install -y' >&2
        printf ' %s' "${packages[@]}" >&2
        printf '\n' >&2
        exit 1
    fi
}

first_firmware() {
    find "$FIRMWARE_DIR" -maxdepth 1 -type f \( \
        -name '*.tar' -o \
        -name '*.tar.md5' -o \
        -name '*.md5' \
    \) | sort | head -n 1
}

extract_one() {
    local entry="$1"
    local image_name inner_path image_lz4 image_raw out_dir extracted dest

    entry="${entry#/}"
    image_name="${entry%%/*}"
    inner_path="${entry#*/}"

    if [ "$entry" = "$inner_path" ] || [ -z "$image_name" ] || [ -z "$inner_path" ]; then
        printf 'Invalid proprietary entry: %s\n' "$entry" >&2
        return 1
    fi

    image_lz4="$WORK_DIR/tar/${image_name}.img.lz4"
    image_raw="$WORK_DIR/tar/${image_name}.img"

    if [ ! -f "$image_raw" ]; then
        if [ ! -f "$image_lz4" ]; then
            printf 'Missing image for entry %s: expected %s or %s\n' "$entry" "$image_raw" "$image_lz4" >&2
            return 1
        fi
        lz4 -d -f "$image_lz4" "$image_raw" >/dev/null
    fi

    out_dir="$WORK_DIR/out/$image_name"
    rm -rf "$out_dir"
    mkdir -p "$out_dir"

    7z x -y "$image_raw" -o"$out_dir" "$inner_path" >/dev/null

    extracted="$out_dir/$inner_path"
    if [ ! -f "$extracted" ]; then
        printf 'Failed to extract %s from %s\n' "$inner_path" "$image_raw" >&2
        return 1
    fi

    dest="$PROPRIETARY_DIR/${entry##*/}"
    cp -f "$extracted" "$dest"

    printf 'Extracted %s\n' "$dest"
    file "$dest"
    sha256sum "$dest"
}

trim_line() {
    local value="$1"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    printf '%s\n' "$value"
}

main() {
    require_tools

    mkdir -p "$PROPRIETARY_DIR"

    if [ ! -f "$LIST_FILE" ]; then
        printf 'Missing %s\n' "$LIST_FILE" >&2
        exit 1
    fi

    local firmware
    firmware="$(first_firmware)"
    if [ -z "$firmware" ]; then
        printf 'No .tar, .tar.md5, or .md5 firmware file found in %s\n' "$FIRMWARE_DIR" >&2
        exit 1
    fi

    WORK_DIR="$(mktemp -d)"
    trap 'rm -rf "$WORK_DIR"' EXIT
    mkdir -p "$WORK_DIR/tar" "$WORK_DIR/out"

    printf 'Using firmware: %s\n' "$firmware"
    tar xf "$firmware" -C "$WORK_DIR/tar"

    local line entry extracted_count=0
    while IFS= read -r line || [ -n "$line" ]; do
        entry="$(trim_line "$line")"

        if [ -z "$entry" ]; then
            continue
        fi

        # Category comments are allowed; extraction targets must be plain paths.
        if [[ "$entry" == \#* ]]; then
            continue
        fi

        if [[ "$entry" == *"#"* ]]; then
            printf 'Invalid inline comment in %s: %s\n' "$LIST_FILE" "$line" >&2
            exit 1
        fi

        extract_one "$entry"
        extracted_count=$((extracted_count + 1))
    done < "$LIST_FILE"

    if [ "$extracted_count" -eq 0 ]; then
        printf 'No proprietary file entries found in %s\n' "$LIST_FILE" >&2
        exit 1
    fi
}

main "$@"
