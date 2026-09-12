#!/usr/bin/env bash
# 단원에 필요한 파일과 설정을 실행 전에 확인합니다.
require_files() {
    for file in "$@"; do
        if [ ! -f "$file" ]; then
            echo "필요한 파일이 없습니다: $file" >&2
            echo "main에서 해당 단원의 코드와 설정을 작성한 뒤 다시 실행하세요." >&2
            exit 1
        fi
    done
}

require_setting() {
    require_files "$1"
    if ! grep -Fq -- "$2" "$1"; then
        echo "$1에 필요한 설정이 없습니다: $2" >&2
        echo "main에서 해당 단원의 설정을 작성한 뒤 다시 실행하세요." >&2
        exit 1
    fi
}

require_profile() {
    case "$1" in
        lite|full) ;;
        *) echo "프로파일은 lite 또는 full을 사용하세요." >&2; exit 2 ;;
    esac
}
