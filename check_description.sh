#!/bin/bash

# Check that Lean module docs follow a consistent structure.
# We require a '/-! ... -/' block with a title, and conditional non-empty sections:
# - require a Definitions section if the file defines defs/abbrevs/classes/structures/instances
# - require a Theorems section if the file contains theorem/lemma declarations
# - require that every theorem/lemma in the file is listed in the Theorems section,
#   and that every listed name actually exists in the file (bidirectional check).

MATCHES=()

section_has_content() {
    local module_doc="$1"
    local section_kind="$2"

    awk -v section_kind="$section_kind" '
        BEGIN { in_section = 0; has_content = 0 }
        {
          line = tolower($0)
        }
        section_kind == "definitions" && line ~ /^[[:space:]]*##[[:space:]]+.*definitions?([^a-z0-9_]|$)/ { in_section = 1; next }
        section_kind == "theorems" && line ~ /^[[:space:]]*##[[:space:]]+.*theorems?([^a-z0-9_]|$)/ { in_section = 1; next }
        in_section && $0 ~ /^[[:space:]]*##[[:space:]]+/ { exit(has_content ? 0 : 1) }
        in_section && $0 ~ /[^[:space:]]/ { has_content = 1 }
        END { if (in_section == 0) exit 2; exit(has_content ? 0 : 1) }
    ' <<< "$module_doc"
}

# Extract backticked declaration names from a given module-doc section.
section_names() {
    local module_doc="$1"
    local section_kind="$2"

    awk -v section_kind="$section_kind" '
        BEGIN { in_section = 0 }
        {
          line = tolower($0)
        }
        section_kind == "definitions" && line ~ /^[[:space:]]*##[[:space:]]+.*definitions?([^a-z0-9_]|$)/ { in_section = 1; next }
        section_kind == "theorems" && line ~ /^[[:space:]]*##[[:space:]]+.*theorems?([^a-z0-9_]|$)/ { in_section = 1; next }
        in_section && $0 ~ /^[[:space:]]*##[[:space:]]+/ { exit }
        in_section && match($0, /`[A-Za-z0-9_'\'']+`/) {
            name = substr($0, RSTART + 1, RLENGTH - 2)
            print name
        }
    ' <<< "$module_doc" | sort -u
}

# Extract theorem/lemma declaration names from a Lean file.
# Matches public declarations at the start of a line, optionally preceded by an
# attribute on the same line (`@[simp] theorem foo`) or on the previous line.
# `private` declarations are internal helpers and are not required to be listed.
# Namespace-qualified names (`Layer.foo`) are reduced to their bare name.
file_theorem_names() {
    local file_path="$1"
    awk '
        /^[[:space:]]*@\[[^]]*\]$/ { pending = 1; next }
        {
            line = $0
            sub(/^[[:space:]]*@\[[^]]*\][[:space:]]*/, "", line)
            sub(/^protected[[:space:]]+/, "", line)
            if (line ~ /^(theorem|lemma)[[:space:]]+/) {
                sub(/^(theorem|lemma)[[:space:]]+/, "", line)
                split(line, parts, /[^A-Za-z0-9_.'\'']/)
                name = parts[1]
                sub(/^.*\./, "", name)
                if (name != "") print name
                pending = 0
                next
            }
            if (pending == 1 && line ~ /^(theorem|lemma)[[:space:]]+/) {
                sub(/^(theorem|lemma)[[:space:]]+/, "", line)
                split(line, parts, /[^A-Za-z0-9_.'\'']/)
                name = parts[1]
                sub(/^.*\./, "", name)
                if (name != "") print name
            }
            pending = 0
        }
    ' "$file_path" | sort -u
}

while IFS= read -r file_path; do
    [ -z "$file_path" ] && continue

    module_doc="$(awk '
        BEGIN { in_doc = 0; found = 0 }
        /^[[:space:]]*\/-!/ && found == 0 { in_doc = 1; found = 1 }
        in_doc { print }
        in_doc && /-\/[[:space:]]*$/ { exit }
    ' "$file_path")"

    if [ -z "$module_doc" ]; then
        MATCHES+=("$file_path: missing module doc block (/-! ... -/)")
        continue
    fi

    if ! printf "%s\n" "$module_doc" | grep -qE '^[[:space:]]*#[[:space:]]+\S'; then
        MATCHES+=("$file_path: missing module title heading (# ...)")
    fi

    has_defs=0
    if grep -qE '^[[:space:]]*(noncomputable[[:space:]]+)?(def|abbrev|class|structure|instance)\b' "$file_path"; then
        has_defs=1
    fi

    has_theorems=0
    if grep -qE '^[[:space:]]*(protected[[:space:]]+)?(theorem|lemma)\b' "$file_path"; then
        has_theorems=1
    fi

    if [ "$has_defs" -eq 1 ] && ! printf "%s\n" "$module_doc" | grep -qiE '^[[:space:]]*##[[:space:]]+.*definitions?\b'; then
        MATCHES+=("$file_path: missing Definitions section heading (## ... Definitions ...)")
    elif [ "$has_defs" -eq 1 ]; then
        if ! section_has_content "$module_doc" "definitions"; then
            MATCHES+=("$file_path: Definitions section is empty")
        fi
    fi

    if [ "$has_theorems" -eq 1 ] && ! printf "%s\n" "$module_doc" | grep -qiE '^[[:space:]]*##[[:space:]]+.*theorems?\b'; then
        MATCHES+=("$file_path: missing Theorems section heading (## ... Theorems ...)")
    elif [ "$has_theorems" -eq 1 ]; then
        if ! section_has_content "$module_doc" "theorems"; then
            MATCHES+=("$file_path: Theorems section is empty")
        fi
    fi

    # Bidirectional theorem-listing check: every declared theorem/lemma in the
    # file must be listed in the Theorems section, and every listed name must
    # actually be declared.
    if [ "$has_theorems" -eq 1 ]; then
        declared="$(file_theorem_names "$file_path")"
        listed="$(section_names "$module_doc" "theorems")"

        while IFS= read -r name; do
            [ -z "$name" ] && continue
            if ! printf "%s\n" "$listed" | grep -qx "$name"; then
                MATCHES+=("$file_path: theorem/lemma '${name}' is not listed in the Theorems section")
            fi
        done <<< "$declared"

        while IFS= read -r name; do
            [ -z "$name" ] && continue
            if ! printf "%s\n" "$declared" | grep -qx "$name"; then
                MATCHES+=("$file_path: Theorems section lists '${name}' but it is not declared in the file")
            fi
        done <<< "$listed"
    fi
done < <(git ls-files '*.lean')

if [ "${#MATCHES[@]}" -gt 0 ]; then
    echo "ERROR: Module documentation structure check failed."
    echo "Each Lean file needs a module doc title, plus required non-empty Definitions/Theorems sections."
    echo "Theorems must be listed in the Theorems section exactly when they are declared."
    printf "%s\n" "${MATCHES[@]}"
    exit 1
fi

echo "✓ All Lean files satisfy module documentation structure rules."
exit 0
