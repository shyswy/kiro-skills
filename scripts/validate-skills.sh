#!/usr/bin/env bash
set +e  # Don't exit on error (we track errors manually)

# ============================================================
# validate-skills.sh
# Validates SKILL.md files against agentskills.io spec
# Exit code 0 = all pass, 1 = errors found
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_DIR="${SCRIPT_DIR}/../skills"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

errors=0
warnings=0
checked=0

log_error() { echo -e "${RED}[ERROR]${NC} $*"; ((errors++)); }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; ((warnings++)); }
log_ok()    { echo -e "${GREEN}[OK]${NC} $*"; }

# Extract YAML frontmatter field value (single-line only)
get_frontmatter_field() {
  local file="$1"
  local field="$2"
  local value=""
  value=$(sed -n '/^---$/,/^---$/p' "$file" | grep -E "^${field}:" | head -1 | sed "s/^${field}: *//" | sed 's/^["|'"'"']//' | sed 's/["|'"'"']*$//' | sed 's/|//g' | sed 's/>//g' | tr -s ' ') || true
  echo "$value"
}

# Check if file has YAML frontmatter
has_frontmatter() {
  local file="$1"
  head -1 "$file" | grep -q '^---$'
}

# Validate a single SKILL.md
validate_skill() {
  local skill_dir="$1"
  local skill_name=$(basename "$skill_dir")
  local skill_md="$skill_dir/SKILL.md"
  
  # Skip private skills
  [[ "$skill_name" == _* ]] && return 0
  
  ((checked++))
  
  # Check SKILL.md exists
  if [[ ! -f "$skill_md" ]]; then
    log_error "$skill_name: SKILL.md not found"
    return
  fi
  
  # Check frontmatter exists
  if ! has_frontmatter "$skill_md"; then
    log_error "$skill_name: Missing YAML frontmatter (must start with ---)"
    return
  fi
  
  # Check required fields
  local name=$(get_frontmatter_field "$skill_md" "name")
  local description=$(get_frontmatter_field "$skill_md" "description")
  
  # name field
  if [[ -z "$name" ]]; then
    log_error "$skill_name: Missing 'name' field in frontmatter"
  else
    # Validate name format: lowercase, hyphens, numbers only
    if ! echo "$name" | grep -qE '^[a-z][a-z0-9-]*[a-z0-9]$'; then
      # Allow single-char names too
      if ! echo "$name" | grep -qE '^[a-z]([a-z0-9-]*[a-z0-9])?$'; then
        log_error "$skill_name: Invalid name format '$name' (must be lowercase, hyphens, no start/end hyphen)"
      fi
    fi
    # Check max length
    if [[ ${#name} -gt 64 ]]; then
      log_error "$skill_name: Name exceeds 64 chars (${#name})"
    fi
  fi
  
  # description field (handles multiline with | or >)
  if [[ -z "$description" ]]; then
    local has_desc=$(sed -n '/^---$/,/^---$/p' "$skill_md" | grep -c "^description:" || true)
    if [[ "$has_desc" -eq 0 ]]; then
      log_error "$skill_name: Missing 'description' field in frontmatter"
    fi
    # If description: | or description: > exists, it's valid multiline
  fi
  
  # Body length check (warning only)
  local body_lines=$(sed '1,/^---$/{ /^---$/!d; }' "$skill_md" | sed '1,/^---$/d' | wc -l)
  if [[ $body_lines -gt 500 ]]; then
    log_warn "$skill_name: SKILL.md body is ${body_lines} lines (recommend < 500)"
  fi
  
  # Check directory name matches skill name
  if [[ -n "$name" && "$name" != "$skill_name" ]]; then
    log_warn "$skill_name: Directory name doesn't match frontmatter name '$name'"
  fi
}

# Main
echo "============================================"
echo "  Validating skills..."
echo "============================================"
echo ""

for skill_dir in "$SKILLS_DIR"/*/; do
  [[ -d "$skill_dir" ]] || continue
  validate_skill "$skill_dir"
done

echo ""
echo "============================================"
echo "  Results: $checked checked, $errors errors, $warnings warnings"
echo "============================================"

if [[ $errors -gt 0 ]]; then
  echo -e "${RED}FAILED${NC} — fix errors above"
  exit 1
else
  if [[ $warnings -gt 0 ]]; then
    echo -e "${YELLOW}PASSED with warnings${NC}"
  else
    echo -e "${GREEN}ALL PASSED${NC}"
  fi
  exit 0
fi
