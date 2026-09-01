#!/bin/bash

set -euo pipefail

# Format Lean files by:
# 1) collapsing repeated blank lines
# 2) ensuring a blank line before declaration docstrings (/--)
# 3) sorting the first contiguous import block alphabetically
# 4) removing trailing whitespace
# By default, this targets all tracked .lean files.
# Use --check (or --dry-run) to report files that would change.

collect_targets() {
    if [ "$#" -gt 0 ]; then
        printf '%s\n' "$@"
        return
    fi

    git ls-files '*.lean'
}

format_file() {
    local file_path="$1"
    local check_mode="$2"
    local temp_file
    local sorted_file

    if [ ! -f "$file_path" ]; then
        echo "Skipping missing file: $file_path"
        return
    fi

    temp_file="$(mktemp)"
    sorted_file="$(mktemp)"
    awk '
        function is_blank(line) {
            return line ~ /^[[:space:]]*$/
        }
        function is_top_level_docstring(line) {
            return line ~ /^\/--/
        }
        function is_indented_comment(line) {
            return line ~ /^[[:space:]]+\/--/ || line ~ /^[[:space:]]+\/-/ || line ~ /^[[:space:]]+--/
        }
        function ends_with_in(line) {
            return line ~ /[[:space:]]in[[:space:]]*$/
        }
        {
            sub(/[[:space:]]+$/, "", $0)

            if (is_blank($0)) {
                pending_blank = 1
                next
            }

            if (pending_blank == 1) {
                if (prev_nonblank_ends_in == 0 && is_top_level_docstring($0)) {
                    print ""
                    emitted_any = 1
                } else if (prev_nonblank_ends_in == 0 && is_indented_comment($0)) {
                    # Never keep blank lines before indented comments/docstrings.
                } else if (prev_nonblank_ends_in == 0) {
                    print ""
                    emitted_any = 1
                }
                pending_blank = 0
            } else if (is_top_level_docstring($0) && emitted_any == 1 && prev_nonblank_ends_in == 0) {
                # Keep top-level declaration docstrings visually separated from
                # prior code, except immediately after command headers like
                # `omit ... in`.
                print ""
                emitted_any = 1
            }

            print
            prev_was_blank = 0
            emitted_any = 1
            prev_nonblank_ends_in = ends_with_in($0)
        }
    ' "$file_path" > "$temp_file"

    awk '
        BEGIN {
            import_start = 0
            import_end = 0
        }
        {
            lines[NR] = $0
            if (import_start == 0 && $0 ~ /^import[[:space:]]+/) {
                import_start = NR
            } else if (import_start > 0 && import_end == 0 && $0 !~ /^import[[:space:]]+/) {
                import_end = NR - 1
            }
        }
        END {
            if (NR == 0) {
                exit
            }

            if (import_start == 0) {
                for (i = 1; i <= NR; i++) {
                    print lines[i]
                }
                exit
            }

            if (import_end == 0) {
                import_end = NR
            }

            for (i = 1; i < import_start; i++) {
                print lines[i]
            }

            for (i = import_start; i <= import_end; i++) {
                print lines[i] | "LC_ALL=C sort"
            }
            close("LC_ALL=C sort")

            for (i = import_end + 1; i <= NR; i++) {
                print lines[i]
            }
        }
    ' "$temp_file" > "$sorted_file"

    if cmp -s "$file_path" "$sorted_file"; then
        rm -f "$temp_file" "$sorted_file"
        return 1
    fi

    if [ "$check_mode" -eq 1 ]; then
        echo "$file_path"
        rm -f "$temp_file" "$sorted_file"
        return 0
    fi

    mv "$sorted_file" "$file_path"
    rm -f "$temp_file"
    return 0
}

print_usage() {
    cat <<'EOF'
Usage:
  ./scripts/format_lean.sh [--check|--dry-run] [PATH ...]

Options:
  --check, --dry-run  Report files that would change without rewriting.
  --help              Show this help message.
EOF
}

main() {
    local check_mode=0
    local input_paths=()
    local targets=()
    local line
    local changed_count=0

    for arg in "$@"; do
        case "$arg" in
            --check|--dry-run)
                check_mode=1
                ;;
            --help|-h)
                print_usage
                exit 0
                ;;
            --*)
                echo "ERROR: Unknown option: $arg"
                print_usage
                exit 1
                ;;
            *)
                input_paths+=("$arg")
                ;;
        esac
    done

    if [ "${#input_paths[@]}" -gt 0 ]; then
        while IFS= read -r line; do
            targets+=("$line")
        done < <(collect_targets "${input_paths[@]}")
    else
        while IFS= read -r line; do
            targets+=("$line")
        done < <(collect_targets)
    fi

    if [ "${#targets[@]}" -eq 0 ]; then
        echo "No .lean files found."
        exit 0
    fi

    for file_path in "${targets[@]}"; do
        if format_file "$file_path" "$check_mode"; then
            changed_count=$((changed_count + 1))
        fi
    done

    if [ "$check_mode" -eq 1 ]; then
        if [ "$changed_count" -gt 0 ]; then
            echo "ERROR: ${changed_count} Lean file(s) require formatting."
            exit 1
        fi
        echo "✓ All Lean files are properly formatted."
        exit 0
    fi

    echo "Formatted ${#targets[@]} Lean file(s); updated ${changed_count}."
}

main "$@"
