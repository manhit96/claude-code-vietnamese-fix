#!/bin/bash
#
# Claude Code Vietnamese IME Fix - Updated for v2.1.9+
# Fixes Vietnamese input bug in Claude Code CLI
#
# Bug: Claude Code processes DEL (0x7F) characters from Vietnamese IME
#      but returns without inserting the replacement text
#
# Updated to work with Claude Code 2.1.9+ where variable names changed:
#   - Offset setter: j (was _)
#   - Cursor var: _A (was EA/FA/A)
#   - Cleanup funcs: Oe1(),Me1() (was BB0(),GB0())
#   - Input var: n (was s)
#
# Repository: https://github.com/manhit96/claude-code-vietnamese-fix
# License: MIT
#

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Patch marker
PATCH_MARKER="PHTV Vietnamese IME fix"

echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║     Claude Code Vietnamese IME Fix - Patch Script          ║${NC}"
echo -e "${BLUE}║     Fix lỗi gõ tiếng Việt trong Claude Code CLI            ║${NC}"
echo -e "${BLUE}║     Updated for Claude Code 2.1.9+                         ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Function to find Claude Code cli.js
find_cli_js() {
    local cli_path=""

    # Method 1: Use 'which claude' and resolve symlinks
    if command -v claude &> /dev/null; then
        local claude_bin=$(which claude)
        # Use realpath first (more reliable), fallback to readlink
        local resolved_path=$(realpath "$claude_bin" 2>/dev/null || readlink -f "$claude_bin" 2>/dev/null || echo "$claude_bin")

        # Check if it's a binary (Homebrew/native) or script (npm)
        # Check the original symlink target, not the resolved path
        if file "$claude_bin" | grep -q "text"; then
            # It's a script, find cli.js in same directory or parent
            local dir=$(dirname "$resolved_path")

            # Try lib path for npm global installs
            local lib_path=$(echo "$dir" | sed 's|/bin$|/lib/node_modules/@anthropic-ai/claude-code|')
            if [[ -f "$lib_path/cli.js" ]]; then
                cli_path="$lib_path/cli.js"
            elif [[ -f "$dir/cli.js" ]]; then
                cli_path="$dir/cli.js"
            elif [[ -f "$dir/../cli.js" ]]; then
                cli_path=$(cd "$dir/.." && pwd)/cli.js
            fi
        else
            echo -e "${RED}✗ Claude Code được cài bằng binary (Homebrew/native).${NC}" >&2
            echo -e "${YELLOW}  Không thể patch bản binary. Vui lòng cài lại bằng npm:${NC}" >&2
            echo "" >&2
            echo -e "  ${GREEN}# Gỡ bản cũ${NC}" >&2
            echo -e "  brew uninstall --cask claude-code  # nếu dùng Homebrew" >&2
            echo "" >&2
            echo -e "  ${GREEN}# Cài bản npm${NC}" >&2
            echo -e "  npm install -g @anthropic-ai/claude-code" >&2
            echo "" >&2
            exit 1
        fi
    fi

    # Method 2: Check common npm paths
    if [[ -z "$cli_path" ]]; then
        local npm_paths=(
            "$HOME/.nvm/versions/node/"*"/lib/node_modules/@anthropic-ai/claude-code/cli.js"
            "$HOME/.fnm/node-versions/"*"/installation/lib/node_modules/@anthropic-ai/claude-code/cli.js"
            "/usr/local/lib/node_modules/@anthropic-ai/claude-code/cli.js"
            "/opt/homebrew/lib/node_modules/@anthropic-ai/claude-code/cli.js"
        )

        for pattern in "${npm_paths[@]}"; do
            for path in $pattern; do
                if [[ -f "$path" ]]; then
                    cli_path="$path"
                    break 2
                fi
            done
        done
    fi

    echo "$cli_path"
}

# Function to check if already patched
is_patched() {
    local cli_path="$1"
    grep -q "$PATCH_MARKER" "$cli_path" 2>/dev/null
}

# Function to check Claude Code version
get_version() {
    claude --version 2>/dev/null | head -1 || echo "unknown"
}

# Function to apply patch using Python
apply_patch() {
    local cli_path="$1"
    local backup_path="${cli_path}.backup-$(date +%Y%m%d-%H%M%S)"

    # Check if we can write to the file
    if [[ ! -w "$cli_path" ]]; then
        echo -e "${YELLOW}→ File cần quyền elevated permissions...${NC}"
        USE_SUDO="sudo"
    else
        USE_SUDO=""
    fi

    echo -e "${YELLOW}→ Đang tạo backup...${NC}"
    $USE_SUDO cp "$cli_path" "$backup_path"
    echo -e "  Backup: $backup_path"

    echo -e "${YELLOW}→ Đang phân tích và áp dụng patch...${NC}"

    # Use Python for reliable patching - updated for v2.1.9+
    $USE_SUDO python3 - "$cli_path" "$backup_path" << 'PYTHON_EOF'
import sys
import re

cli_path = sys.argv[1]
backup_path = sys.argv[2]

# Read file
with open(cli_path, 'r', encoding='utf-8') as f:
    content = f.read()

# Patch marker
PATCH_MARKER = "/* PHTV Vietnamese IME fix */"

# Already patched?
if PATCH_MARKER in content:
    print("ALREADY_PATCHED")
    sys.exit(0)

patched = False

# Strategy: Find the Vietnamese IME handling block by its characteristic pattern:
# - Contains .includes("\x7f") or .includes with DEL char
# - Has .match(/\x7f/g) pattern
# - Has backspace() loop
# - Ends with: OFFSET_FUNC(VAR.offset)}CLEANUP1(),CLEANUP2();return}

# More flexible pattern matching for different minified versions
# Pattern: (\w+)\((\w+)\.offset\)\}(\w+)\(\),(\w+)\(\);return\}
# Group 1: offset setter function (j, _, etc)
# Group 2: cursor variable (_A, EA, FA, A, etc)
# Group 3: cleanup func 1
# Group 4: cleanup func 2

# Find the block containing "\x7f" handling
del_char = '\x7f'
search_start = 0

while True:
    # Find includes with DEL char
    idx = content.find('.includes("', search_start)
    if idx == -1:
        idx = content.find(".includes('", search_start)
    if idx == -1:
        break

    # Check if this includes has DEL char nearby
    check_range = content[idx:idx+30]
    has_del = del_char in check_range or '\\x7f' in check_range

    if has_del:
        # Found potential block, look at broader context
        block_start = max(0, idx - 200)
        block_end = min(len(content), idx + 500)
        block = content[block_start:block_end]

        # Verify this is the Vietnamese IME block
        if 'backspace()' in block and '.match(/' in block:
            # Find the return pattern
            # Pattern: VAR.offset)}FUNC(),FUNC();return}
            pattern = r'(\w+)\((\w+)\.offset\)\}(\w+)\(\),(\w+)\(\);return\}'

            match = re.search(pattern, block)
            if match:
                offset_func = match.group(1)
                cursor_var = match.group(2)
                cleanup1 = match.group(3)
                cleanup2 = match.group(4)

                print(f"FOUND offset_func={offset_func}, cursor_var={cursor_var}, cleanup1={cleanup1}, cleanup2={cleanup2}")

                # Find the exact position in original content
                # Search for: offset_func(cursor_var.offset)}
                search_pattern = f'{offset_func}({cursor_var}.offset)}}'
                insert_pos = content.find(search_pattern, idx - 200)

                if insert_pos != -1:
                    insert_pos += len(search_pattern)

                    # Determine input variable name - look for .includes pattern
                    # Usually the variable before .includes
                    includes_match = re.search(r'(\w+)\.includes\(', block)
                    input_var = includes_match.group(1) if includes_match else 'n'

                    # Build fix code
                    fix_code = (
                        f'{PATCH_MARKER}'
                        f'let _phtv_clean={input_var}.replace(/\\x7f/g,"");'
                        f'if(_phtv_clean.length>0){{'
                        f'for(const _c of _phtv_clean){{{cursor_var}={cursor_var}.insert(_c)}}'
                        f'if(!P.equals({cursor_var})){{'
                        f'if(P.text!=={cursor_var}.text)Q({cursor_var}.text);'
                        f'{offset_func}({cursor_var}.offset)'
                        f'}}'
                        f'}}'
                    )

                    # Insert fix code
                    content = content[:insert_pos] + fix_code + content[insert_pos:]
                    patched = True
                    break

    search_start = idx + 1

# Fallback: Try the old fixed patterns for backward compatibility
if not patched:
    # Old pattern matching for older versions
    search_patterns = [
        ('_(FA.offset)}', 'FA', 's'),  # v2.1.7 Windows/newer versions
        ('_(EA.offset)}', 'EA', 's'),  # Older versions
        ('_(A.offset)}', 'A', 's'),    # Some versions
    ]

    for search_pat, var_name, input_var in search_patterns:
        idx = 0
        while True:
            idx = content.find(search_pat, idx)
            if idx == -1:
                break

            # Check context before this point (should have backspace loop)
            start_ctx = max(0, idx - 500)
            context = content[start_ctx:idx]

            # Verify this is the Vietnamese IME block
            if 'backspace()' in context and ('.match(/\\x7f/g)' in context or '.match(/\x7f/g)' in context):
                # Find the return statement after this
                end_idx = idx + len(search_pat)

                # Look for pattern: FUNC(),FUNC();return}
                remaining = content[end_idx:end_idx+100]

                # Match: XX0(),YY0();return} or similar cleanup pattern
                match = re.match(r'(\s*\w+\(\)\s*,\s*\w+\(\)\s*;\s*return\s*\})', remaining)
                if match:
                    # Build fix code with correct variable name
                    fix_code = PATCH_MARKER + f'let _phtv_clean={input_var}.replace(/\\x7f/g,"");if(_phtv_clean.length>0){{for(const _c of _phtv_clean){{{var_name}={var_name}.insert(_c)}}if(!j.equals({var_name})){{if(j.text!=={var_name}.text)Q({var_name}.text);_({var_name}.offset)}}}}'
                    # Insert fix code right after _(<VAR>.offset)}
                    insert_point = end_idx
                    content = content[:insert_point] + fix_code + content[insert_point:]
                    patched = True
                    print(f"FOUND_VAR:{var_name} (fallback)")
                    break

            idx += 1

        if patched:
            break

if patched:
    with open(cli_path, 'w', encoding='utf-8') as f:
        f.write(content)
    print("SUCCESS")
else:
    print("PATTERN_NOT_FOUND")
    sys.exit(1)
PYTHON_EOF

    local result=$?

    # Verify patch was applied
    if grep -q "$PATCH_MARKER" "$cli_path" 2>/dev/null; then
        return 0
    else
        # Restore backup
        echo -e "${YELLOW}→ Đang khôi phục từ backup...${NC}"
        $USE_SUDO cp "$backup_path" "$cli_path"
        return 1
    fi
}

# Function to remove patch
remove_patch() {
    local cli_path="$1"

    # Find latest backup
    local latest_backup=$(ls -t "${cli_path}.backup-"* 2>/dev/null | head -1)

    if [[ -z "$latest_backup" ]]; then
        echo -e "${RED}✗ Không tìm thấy file backup.${NC}"
        echo -e "  Bạn có thể cài lại Claude Code để khôi phục:"
        echo -e "  ${GREEN}npm install -g @anthropic-ai/claude-code${NC}"
        return 1
    fi

    # Check if we need sudo
    if [[ ! -w "$cli_path" ]]; then
        USE_SUDO="sudo"
    else
        USE_SUDO=""
    fi

    echo -e "${YELLOW}→ Đang khôi phục từ backup...${NC}"
    $USE_SUDO cp "$latest_backup" "$cli_path"
    $USE_SUDO rm -f "$latest_backup"
    echo -e "${GREEN}✓ Đã khôi phục Claude Code về bản gốc.${NC}"
}

# Main script
main() {
    local action="${1:-patch}"

    echo -e "${YELLOW}→ Đang tìm Claude Code...${NC}"

    CLI_PATH=$(find_cli_js)

    if [[ -z "$CLI_PATH" ]] || [[ ! -f "$CLI_PATH" ]]; then
        echo -e "${RED}✗ Không tìm thấy Claude Code.${NC}"
        echo -e "  Vui lòng cài đặt Claude Code trước:"
        echo -e "  ${GREEN}npm install -g @anthropic-ai/claude-code${NC}"
        exit 1
    fi

    echo -e "  Đường dẫn: ${BLUE}$CLI_PATH${NC}"
    echo -e "  Phiên bản: ${BLUE}$(get_version)${NC}"
    echo ""

    case "$action" in
        patch|fix|apply)
            if is_patched "$CLI_PATH"; then
                echo -e "${GREEN}✓ Claude Code đã được patch trước đó.${NC}"
                exit 0
            fi

            echo -e "${YELLOW}→ Đang áp dụng patch...${NC}"

            if apply_patch "$CLI_PATH"; then
                echo ""
                echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
                echo -e "${GREEN}║  ✓ Patch thành công! Vietnamese IME fix đã được áp dụng.  ║${NC}"
                echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
                echo ""
                echo -e "Vui lòng ${YELLOW}khởi động lại Claude Code${NC} để áp dụng thay đổi."
                echo ""
            else
                echo ""
                echo -e "${RED}✗ Không thể áp dụng patch.${NC}"
                echo -e "  Code structure có thể đã thay đổi trong phiên bản mới."
                echo -e "  Vui lòng báo lỗi tại: ${BLUE}https://github.com/manhit96/claude-code-vietnamese-fix/issues${NC}"
                exit 1
            fi
            ;;

        unpatch|remove|restore)
            if ! is_patched "$CLI_PATH"; then
                echo -e "${YELLOW}Claude Code chưa được patch.${NC}"
                exit 0
            fi

            if remove_patch "$CLI_PATH"; then
                echo -e "${GREEN}✓ Đã gỡ patch thành công.${NC}"
            else
                exit 1
            fi
            ;;

        status|check)
            echo -e "${YELLOW}→ Kiểm tra trạng thái patch...${NC}"
            echo ""

            if is_patched "$CLI_PATH"; then
                echo -e "  Trạng thái: ${GREEN}✓ Đã patch${NC}"
            else
                echo -e "  Trạng thái: ${RED}✗ Chưa patch${NC}"

                # Check if buggy code exists
                if grep -q 'backspace()' "$CLI_PATH" 2>/dev/null && grep -q $'\x7f' "$CLI_PATH" 2>/dev/null; then
                    echo -e "  Bug code:   ${YELLOW}Có tồn tại${NC} - Cần patch!"
                else
                    echo -e "  Bug code:   ${BLUE}Không tìm thấy${NC} - Có thể đã được fix bởi Anthropic"
                fi
            fi
            ;;

        *)
            echo "Usage: $0 [patch|unpatch|status]"
            echo ""
            echo "Commands:"
            echo "  patch    - Áp dụng Vietnamese IME fix (default)"
            echo "  unpatch  - Gỡ bỏ patch, khôi phục bản gốc"
            echo "  status   - Kiểm tra trạng thái patch"
            exit 1
            ;;
    esac
}

main "$@"
