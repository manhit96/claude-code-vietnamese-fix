#!/bin/bash
#
# Claude Code Vietnamese IME Fix - BINARY PATCH (EXPERIMENTAL)
#
# ⚠️  CẢNH BÁO: ĐÂY LÀ BẢN THỬ NGHIỆM ⚠️
# - Patch trực tiếp vào binary có thể gây lỗi không lường trước
# - Binary sẽ được re-sign với ad-hoc signature (không phải Apple signed)
# - Một số hệ thống có thể từ chối chạy binary không có signature chính thức
# - Khuyến khích dùng bản npm nếu có thể: npm install -g @anthropic-ai/claude-code
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
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# Patch marker (embedded in the fix code comment)
PATCH_MARKER="PHTV_FIX"

echo -e "${MAGENTA}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${MAGENTA}║  Claude Code Vietnamese IME Fix - BINARY PATCH (EXPERIMENTAL)  ║${NC}"
echo -e "${MAGENTA}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${YELLOW}⚠️  CẢNH BÁO: Đây là bản thử nghiệm, có thể gây lỗi!${NC}"
echo -e "${YELLOW}   Khuyến khích dùng bản npm nếu có thể.${NC}"
echo ""

# Function to find Claude Code binary
find_binary() {
    local binary_path=""

    # Method 1: Check Homebrew cask location
    local homebrew_paths=(
        "/opt/homebrew/bin/claude"
        "/usr/local/bin/claude"
        "/opt/homebrew/Caskroom/claude-code/*/claude"
        "/usr/local/Caskroom/claude-code/*/claude"
    )

    for pattern in "${homebrew_paths[@]}"; do
        for path in $pattern; do
            if [[ -f "$path" ]]; then
                # Check if it's a binary (not a script)
                if file "$path" | grep -q "Mach-O"; then
                    binary_path="$path"
                    break 2
                fi
            fi
        done
    done

    # Method 2: Use 'which claude' and check if binary
    if [[ -z "$binary_path" ]] && command -v claude &> /dev/null; then
        local claude_bin=$(which claude)
        local resolved_path=$(realpath "$claude_bin" 2>/dev/null || readlink -f "$claude_bin" 2>/dev/null || echo "$claude_bin")

        if file "$resolved_path" | grep -q "Mach-O"; then
            binary_path="$resolved_path"
        fi
    fi

    echo "$binary_path"
}

# Function to check if binary is already patched
is_patched() {
    local binary_path="$1"
    strings "$binary_path" 2>/dev/null | grep -q "$PATCH_MARKER"
}

# Function to get Claude Code version
get_version() {
    claude --version 2>/dev/null | head -1 || echo "unknown"
}

# Function to apply patch
apply_patch() {
    local binary_path="$1"
    local backup_path="${binary_path}.backup-$(date +%Y%m%d-%H%M%S)"

    echo -e "${YELLOW}→ Đang tạo backup...${NC}"
    cp "$binary_path" "$backup_path"
    echo -e "  Backup: ${BLUE}$backup_path${NC}"

    echo -e "${YELLOW}→ Đang áp dụng patch...${NC}"

    # Use Python for binary patching
    python3 - "$binary_path" "$PATCH_MARKER" << 'PYTHON_EOF'
import sys

binary_path = sys.argv[1]
patch_marker = sys.argv[2]

with open(binary_path, 'rb') as f:
    content = bytearray(f.read())

original_size = len(content)

# Original bug block (215 bytes) - Updated for Claude Code v2.1.11
# Bug: processes backspaces for DEL chars but returns without inserting replacement text
original_block = b'if(!RT.backspace&&!RT.delete&&p.includes("\\x7F")){let ZT=(p.match(/\\x7f/g)||[]).length,hT=S;for(let zT=0;zT<ZT;zT++)hT=hT.backspace();if(!S.equals(hT)){if(S.text!==hT.text)R(hT.text);w(hT.offset)}JeR(),OeR();return}'

# Fixed version (201 bytes)
# Fix: after backspace, insert the clean text (without DEL chars)
fixed_code = b'if(!RT.backspace&&!RT.delete&&p.includes("\\x7F")){let X=p.split("\\x7f").length-1,O=S;while(X--)O=O.backspace();for(let c of p.replace(/\\x7f/g,""))O=O.insert(c);R(O.text);w(O.offset);JeR(),OeR();return'

# Add padding with marker to maintain same length (215 bytes total)
padding_needed = len(original_block) - len(fixed_code) - 1  # -1 for closing }
# Use marker in comment for detection
marker_comment = f'/*{patch_marker}*/'.encode()
extra_padding = padding_needed - len(marker_comment)
if extra_padding < 0:
    print("ERROR: Marker too long")
    sys.exit(1)

fixed_padded = fixed_code + marker_comment + b' ' * extra_padding + b'}'

if len(original_block) != len(fixed_padded):
    print(f"ERROR: Length mismatch: {len(original_block)} vs {len(fixed_padded)}")
    sys.exit(1)

# Check if already patched
if patch_marker.encode() in content:
    print("ALREADY_PATCHED")
    sys.exit(0)

# Find and replace all occurrences
idx = content.find(original_block)
count = 0
while idx != -1:
    count += 1
    content[idx:idx+len(original_block)] = fixed_padded
    idx = content.find(original_block, idx + 1)

if count == 0:
    print("PATTERN_NOT_FOUND")
    sys.exit(1)

# Also patch version string to indicate this is a patched version
# Replace "(Claude Code)" with "(IME Patched)" - both are 13 bytes
version_original = b'(Claude Code)'
version_patched = b'(IME Patched)'
version_count = 0
vidx = content.find(version_original)
while vidx != -1:
    version_count += 1
    content[vidx:vidx+len(version_original)] = version_patched
    vidx = content.find(version_original, vidx + 1)

with open(binary_path, 'wb') as f:
    f.write(content)

new_size = len(content)
if original_size != new_size:
    print("SIZE_CHANGED")
    sys.exit(1)

print(f"SUCCESS:{count}:{version_count}")
PYTHON_EOF

    local result=$?
    local output=$(python3 -c "
import sys
marker = '$PATCH_MARKER'
with open('$binary_path', 'rb') as f:
    content = f.read()
if marker.encode() in content:
    print('PATCHED')
else:
    print('NOT_PATCHED')
")

    if [[ "$output" != "PATCHED" ]]; then
        echo -e "${RED}✗ Patch thất bại!${NC}"
        echo -e "${YELLOW}→ Đang khôi phục từ backup...${NC}"
        cp "$backup_path" "$binary_path"
        return 1
    fi

    # Re-sign binary with ad-hoc signature
    echo -e "${YELLOW}→ Đang re-sign binary...${NC}"
    codesign --remove-signature "$binary_path" 2>/dev/null || true
    if ! codesign -s - -f "$binary_path" 2>/dev/null; then
        echo -e "${RED}✗ Re-sign thất bại!${NC}"
        echo -e "${YELLOW}→ Đang khôi phục từ backup...${NC}"
        cp "$backup_path" "$binary_path"
        return 1
    fi

    # Verify binary still works
    echo -e "${YELLOW}→ Đang kiểm tra binary...${NC}"
    if ! "$binary_path" --version &>/dev/null; then
        echo -e "${RED}✗ Binary không chạy được sau khi patch!${NC}"
        echo -e "${YELLOW}→ Đang khôi phục từ backup...${NC}"
        cp "$backup_path" "$binary_path"
        return 1
    fi

    return 0
}

# Function to restore from backup
restore_backup() {
    local binary_path="$1"

    # Find latest backup
    local backup_dir=$(dirname "$binary_path")
    local binary_name=$(basename "$binary_path")
    local latest_backup=$(ls -t "${binary_path}.backup-"* 2>/dev/null | head -1)

    if [[ -z "$latest_backup" ]]; then
        echo -e "${RED}✗ Không tìm thấy file backup.${NC}"
        echo -e "  Bạn có thể cài lại Claude Code:"
        echo -e "  ${GREEN}brew reinstall --cask claude-code${NC}"
        return 1
    fi

    echo -e "${YELLOW}→ Tìm thấy backup: ${BLUE}$latest_backup${NC}"
    echo -e "${YELLOW}→ Đang khôi phục...${NC}"

    cp "$latest_backup" "$binary_path"

    # Re-sign with ad-hoc (backup might have original signature which won't work after copy)
    codesign --remove-signature "$binary_path" 2>/dev/null || true
    codesign -s - -f "$binary_path" 2>/dev/null || true

    # Verify
    if "$binary_path" --version &>/dev/null; then
        echo -e "${GREEN}✓ Đã khôi phục thành công!${NC}"
        rm -f "$latest_backup"
        echo -e "  Đã xóa backup: $latest_backup"
    else
        echo -e "${RED}✗ Khôi phục thất bại!${NC}"
        echo -e "  Vui lòng cài lại: ${GREEN}brew reinstall --cask claude-code${NC}"
        return 1
    fi
}

# Function to list backups
list_backups() {
    local binary_path="$1"
    local backups=$(ls -t "${binary_path}.backup-"* 2>/dev/null)

    if [[ -z "$backups" ]]; then
        echo -e "${YELLOW}Không có backup nào.${NC}"
        return
    fi

    echo -e "${BLUE}Danh sách backup:${NC}"
    echo "$backups" | while read -r backup; do
        local size=$(ls -lh "$backup" | awk '{print $5}')
        local date=$(echo "$backup" | grep -o '[0-9]\{8\}-[0-9]\{6\}')
        echo -e "  - $backup (${size})"
    done
}

# Main script
main() {
    local action="${1:-patch}"

    echo -e "${YELLOW}→ Đang tìm Claude Code binary...${NC}"

    BINARY_PATH=$(find_binary)

    if [[ -z "$BINARY_PATH" ]] || [[ ! -f "$BINARY_PATH" ]]; then
        echo -e "${RED}✗ Không tìm thấy Claude Code binary.${NC}"
        echo ""
        echo -e "  Script này chỉ hỗ trợ bản binary (Homebrew/native installer)."
        echo -e "  Nếu bạn cài qua npm, hãy dùng script khác:"
        echo -e "  ${GREEN}curl -fsSL https://raw.githubusercontent.com/manhit96/claude-code-vietnamese-fix/main/patch-claude-code-vn-npm.sh | bash${NC}"
        exit 1
    fi

    echo -e "  Đường dẫn: ${BLUE}$BINARY_PATH${NC}"
    echo -e "  Phiên bản: ${BLUE}$(get_version)${NC}"

    # Check if it's really a binary
    if ! file "$BINARY_PATH" | grep -q "Mach-O"; then
        echo -e "${RED}✗ File không phải là Mach-O binary.${NC}"
        echo -e "  Có vẻ bạn đang dùng bản npm. Hãy dùng script khác:"
        echo -e "  ${GREEN}curl -fsSL https://raw.githubusercontent.com/manhit96/claude-code-vietnamese-fix/main/patch-claude-code-vn-npm.sh | bash${NC}"
        exit 1
    fi

    echo ""

    case "$action" in
        patch|fix|apply)
            if is_patched "$BINARY_PATH"; then
                echo -e "${GREEN}✓ Binary đã được patch trước đó.${NC}"
                exit 0
            fi

            echo -e "${YELLOW}⚠️  Bạn có chắc muốn patch binary không?${NC}"
            echo -e "   Nhấn Enter để tiếp tục, Ctrl+C để hủy..."
            read -r < /dev/tty

            if apply_patch "$BINARY_PATH"; then
                echo ""
                echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
                echo -e "${GREEN}║  ✓ Patch thành công! Vietnamese IME fix đã được áp dụng.      ║${NC}"
                echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
                echo ""
                echo -e "Vui lòng ${YELLOW}khởi động lại Claude Code${NC} để áp dụng thay đổi."
                echo ""
                echo -e "${YELLOW}Lưu ý:${NC}"
                echo -e "  - Binary đã được re-sign với ad-hoc signature"
                echo -e "  - Nếu gặp lỗi, chạy: ${GREEN}$0 restore${NC}"
                echo ""
            else
                echo ""
                echo -e "${RED}✗ Patch thất bại!${NC}"
                echo -e "  Code structure có thể đã thay đổi trong phiên bản mới."
                echo -e "  Vui lòng báo lỗi tại: ${BLUE}https://github.com/manhit96/claude-code-vietnamese-fix/issues${NC}"
                exit 1
            fi
            ;;

        unpatch|remove|restore)
            echo -e "${YELLOW}→ Đang khôi phục binary gốc...${NC}"
            if restore_backup "$BINARY_PATH"; then
                echo -e "${GREEN}✓ Đã khôi phục Claude Code về bản gốc.${NC}"
            else
                exit 1
            fi
            ;;

        status|check)
            echo -e "${YELLOW}→ Kiểm tra trạng thái patch...${NC}"
            echo ""

            if is_patched "$BINARY_PATH"; then
                echo -e "  Trạng thái: ${GREEN}✓ Đã patch${NC}"
            else
                echo -e "  Trạng thái: ${RED}✗ Chưa patch${NC}"
            fi

            # Check signature
            local sig_status=$(codesign -dvv "$BINARY_PATH" 2>&1 | grep -i "signature" | head -1)
            echo -e "  Signature: ${BLUE}$sig_status${NC}"

            echo ""
            list_backups "$BINARY_PATH"
            ;;

        list-backups|backups)
            list_backups "$BINARY_PATH"
            ;;

        *)
            echo "Usage: $0 [patch|restore|status|list-backups]"
            echo ""
            echo "Commands:"
            echo "  patch        - Áp dụng Vietnamese IME fix (default)"
            echo "  restore      - Khôi phục binary gốc từ backup"
            echo "  status       - Kiểm tra trạng thái patch"
            echo "  list-backups - Liệt kê các file backup"
            echo ""
            echo -e "${YELLOW}⚠️  Đây là bản thử nghiệm cho binary. Nếu dùng npm, hãy dùng:${NC}"
            echo -e "  ${GREEN}curl -fsSL https://raw.githubusercontent.com/manhit96/claude-code-vietnamese-fix/main/patch-claude-code-vn-npm.sh | bash${NC}"
            exit 1
            ;;
    esac
}

main "$@"