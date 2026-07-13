#!/usr/bin/env bash
set +e

# ============================================================
# export-for-platform.sh
# Export kiro-skills to other AI agent platforms
#
# Skills (SKILL.md) → symlinked (agentskills.io is cross-platform)
# Steering → converted to platform-specific format
#
# Cross-platform: Linux, macOS, Windows (Git Bash/MSYS2)
# ============================================================

VERSION="1.1.0"

# Portable realpath (works on macOS without coreutils)
_realpath() {
  if command -v realpath &>/dev/null; then
    realpath "$1"
  elif command -v greadlink &>/dev/null; then
    greadlink -f "$1"
  else
    # Pure bash fallback (POSIX compatible)
    local path="$1"
    if [[ -d "$path" ]]; then
      (cd "$path" && pwd)
    else
      (cd "$(dirname "$path")" && echo "$(pwd)/$(basename "$path")")
    fi
  fi
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SKILLS_DIR="$SOURCE_DIR/skills"
STEERING_DIR="$SOURCE_DIR/steering"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Defaults
TARGET_PLATFORM=""
OUTPUT_DIR=""
FORCE=false
SKILLS_ONLY=false
STEERING_ONLY=false

usage() {
  cat << EOF
${CYAN}kiro-skills platform exporter v${VERSION}${NC}

Export skills and steering to other AI coding agent platforms.
Skills (SKILL.md) are cross-platform via agentskills.io spec.
Steering is converted to each platform's native format.

${BLUE}Usage:${NC}
  bash scripts/export-for-platform.sh --target=<platform> [OPTIONS]

${BLUE}Platforms:${NC}
  claude-code     → ~/.claude/skills/ + CLAUDE.md
  cursor          → .cursor/skills/ + .cursor/rules/*.mdc
  copilot         → .github/skills/ + .github/copilot-instructions.md
  windsurf        → .windsurf/skills/ + .windsurfrules
  gemini          → ~/.gemini/skills/ + GEMINI.md
  agents-md       → AGENTS.md (Linux Foundation open standard, 20+ tools)
  all             → Export for all platforms

${BLUE}Options:${NC}
  --target=PLATFORM   Target platform (required)
  --output=DIR        Output base directory (default: platform-specific)
  --force             Overwrite existing files
  --skills-only       Export only skills (no steering conversion)
  --steering-only     Export only steering (no skills)
  --help              Show this help

${BLUE}Examples:${NC}
  bash scripts/export-for-platform.sh --target=claude-code
  bash scripts/export-for-platform.sh --target=cursor --output=./my-project
  bash scripts/export-for-platform.sh --target=all --force
EOF
  exit 0
}

log_info()  { echo -e "${BLUE}[INFO]${NC} $*"; }
log_ok()    { echo -e "${GREEN}[OK]${NC} $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }
log_skip()  { echo -e "${YELLOW}[SKIP]${NC} $*"; }

# Parse arguments
for arg in "$@"; do
  case $arg in
    --target=*)       TARGET_PLATFORM="${arg#*=}" ;;
    --output=*)       OUTPUT_DIR="${arg#*=}" ;;
    --force)          FORCE=true ;;
    --skills-only)    SKILLS_ONLY=true ;;
    --steering-only)  STEERING_ONLY=true ;;
    --help)           usage ;;
    *)                log_error "Unknown option: $arg"; exit 1 ;;
  esac
done

[[ -z "$TARGET_PLATFORM" ]] && { log_error "Missing --target. Use --help for options."; exit 1; }

# ============================================================
# Helper: Extract steering content (strip YAML frontmatter)
# ============================================================
strip_frontmatter() {
  local file="$1"
  if head -1 "$file" | grep -q '^---$'; then
    awk 'BEGIN{skip=0} /^---$/{skip++; next} skip>=2{print}' "$file"
  else
    cat "$file"
  fi
}

# Get fileMatchPattern from steering frontmatter
get_file_pattern() {
  local file="$1"
  sed -n '/^---$/,/^---$/p' "$file" | grep 'fileMatchPattern:' | sed 's/fileMatchPattern: *//; s/["\x27]//g'
}

# Get inclusion type
get_inclusion() {
  local file="$1"
  sed -n '/^---$/,/^---$/p' "$file" | grep 'inclusion:' | sed 's/inclusion: *//'
}

# Convert comma-separated patterns to array format
patterns_to_array() {
  local patterns="$1"
  echo "$patterns" | tr ',' '\n' | sed 's/^ *//;s/ *$//' | while read -r p; do
    echo "  - \"$p\""
  done
}

# ============================================================
# Export Skills (same for all platforms)
# Uses symlink by default (SKILL.md is cross-platform, no conversion needed)
# Falls back to copy if symlink fails (cross-filesystem, Windows, etc.)
# ============================================================
export_skills() {
  local dest_skills_dir="$1"
  local count=0

  mkdir -p "$dest_skills_dir"

  for skill_dir in "$SKILLS_DIR"/*/; do
    [[ -d "$skill_dir" ]] || continue
    local skill_name=$(basename "$skill_dir")
    # Skip private skills
    [[ "$skill_name" == _* ]] && continue
    [[ ! -f "$skill_dir/SKILL.md" ]] && continue

    local dest="$dest_skills_dir/$skill_name"

    if [[ -e "$dest" && "$FORCE" == false ]]; then
      log_skip "$skill_name (exists, use --force to overwrite)"
      continue
    fi

    # Remove existing (could be old copy or broken symlink)
    [[ -e "$dest" || -L "$dest" ]] && rm -rf "$dest"

    # Symlink (preferred: single source of truth, instant sync)
    # Fallback to copy if symlink fails
    if ln -sf "$(_realpath "$skill_dir")" "$dest" 2>/dev/null; then
      ((count++))
    else
      cp -r "$skill_dir" "$dest"
      ((count++))
    fi
  done

  log_ok "$count skills synced → $dest_skills_dir (symlink)"
}

# ============================================================
# Platform: Claude Code
# Location: ~/.claude/skills/ + project CLAUDE.md
# Steering → single CLAUDE.md (concatenated)
# ============================================================
export_claude_code() {
  local base="${OUTPUT_DIR:-$HOME/.claude}"
  local skills_dest="$base/skills"
  local claude_md="${OUTPUT_DIR:-.}/CLAUDE.md"

  echo ""
  log_info "Exporting for Claude Code..."
  log_info "Skills → $skills_dest"
  log_info "Steering → $claude_md"
  echo ""

  # Skills
  if [[ "$STEERING_ONLY" == false ]]; then
    export_skills "$skills_dest"
  fi

  # Steering → CLAUDE.md
  if [[ "$SKILLS_ONLY" == false ]]; then
    if [[ -f "$claude_md" && "$FORCE" == false ]]; then
      log_skip "CLAUDE.md exists (use --force to overwrite)"
    else
      {
        echo "# Project Rules"
        echo ""
        echo "<!-- Auto-generated from kiro-skills steering files -->"
        echo "<!-- Source: https://github.com/shyswy/kiro-skills -->"
        echo ""

        for steering_file in "$STEERING_DIR/"*.md; do
          [[ -f "$steering_file" ]] || continue
          local fname=$(basename "$steering_file")
          [[ "$fname" == _* ]] && continue

          local inclusion=$(get_inclusion "$steering_file")
          local content=$(strip_frontmatter "$steering_file")

          # Only include always + fileMatch rules
          if [[ "$inclusion" == "manual" ]]; then
            continue
          fi

          echo "---"
          echo ""
          echo "$content"
          echo ""
        done
      } > "$claude_md"
      log_ok "CLAUDE.md generated"
    fi
  fi
}

# ============================================================
# Platform: Cursor
# Location: .cursor/skills/ + .cursor/rules/*.mdc
# Steering → individual .mdc files with frontmatter
# ============================================================
export_cursor() {
  local base="${OUTPUT_DIR:-.}"
  local skills_dest="$base/.cursor/skills"
  local rules_dest="$base/.cursor/rules"

  echo ""
  log_info "Exporting for Cursor..."
  log_info "Skills → $skills_dest"
  log_info "Steering → $rules_dest"
  echo ""

  # Skills
  if [[ "$STEERING_ONLY" == false ]]; then
    export_skills "$skills_dest"
  fi

  # Steering → .mdc files
  if [[ "$SKILLS_ONLY" == false ]]; then
    mkdir -p "$rules_dest"

    for steering_file in "$STEERING_DIR/"*.md; do
      [[ -f "$steering_file" ]] || continue
      local fname=$(basename "$steering_file" .md)
      [[ "$fname" == _* ]] && continue

      local dest_file="$rules_dest/${fname}.mdc"

      if [[ -f "$dest_file" && "$FORCE" == false ]]; then
        log_skip "$fname.mdc (exists)"
        continue
      fi

      local inclusion=$(get_inclusion "$steering_file")
      local pattern=$(get_file_pattern "$steering_file")
      local content=$(strip_frontmatter "$steering_file")

      # Build Cursor .mdc frontmatter
      {
        echo "---"
        # Get first heading as description
        local desc=$(echo "$content" | grep -m1 '^#' | sed 's/^#* *//')
        
        # Cursor uses: description, globs, alwaysApply
        if [[ "$inclusion" == "always" || -z "$inclusion" ]]; then
          echo "description: \"${desc:-$fname}\""
          echo "alwaysApply: true"
        elif [[ "$inclusion" == "fileMatch" && -n "$pattern" ]]; then
          echo "description: \"${desc:-$fname}\""
          echo "globs:"
          # Convert comma-separated to YAML array
          echo "$pattern" | tr ',' '\n' | sed 's/^ *//;s/ *$//' | while read -r p; do
            echo "  - \"$p\""
          done
          echo "alwaysApply: false"
        else
          echo "description: \"${desc:-$fname}\""
          echo "alwaysApply: false"
        fi
        echo "---"
        echo ""
        echo "$content"
      } > "$dest_file"
    done

    local rule_count=$(find "$rules_dest" -name "*.mdc" | wc -l)
    log_ok "$rule_count rules exported → $rules_dest"
  fi
}

# ============================================================
# Platform: GitHub Copilot
# Location: .github/skills/ + .github/copilot-instructions.md
# Steering → single copilot-instructions.md + path-specific .instructions.md
# ============================================================
export_copilot() {
  local base="${OUTPUT_DIR:-.}"
  local skills_dest="$base/.github/skills"
  local instructions_md="$base/.github/copilot-instructions.md"
  local instructions_dir="$base/.github/instructions"

  echo ""
  log_info "Exporting for GitHub Copilot..."
  log_info "Skills → $skills_dest"
  log_info "Steering → $instructions_md + $instructions_dir/"
  echo ""

  # Skills
  if [[ "$STEERING_ONLY" == false ]]; then
    export_skills "$skills_dest"
  fi

  # Steering → copilot-instructions.md (always rules) + path-specific .instructions.md
  if [[ "$SKILLS_ONLY" == false ]]; then
    mkdir -p "$instructions_dir"

    # Main instructions (always-applied rules)
    if [[ -f "$instructions_md" && "$FORCE" == false ]]; then
      log_skip "copilot-instructions.md exists"
    else
      {
        echo "<!-- Auto-generated from kiro-skills steering files -->"
        echo "<!-- Source: https://github.com/shyswy/kiro-skills -->"
        echo ""

        for steering_file in "$STEERING_DIR/"*.md; do
          [[ -f "$steering_file" ]] || continue
          local fname=$(basename "$steering_file")
          [[ "$fname" == _* ]] && continue

          local inclusion=$(get_inclusion "$steering_file")
          [[ "$inclusion" == "fileMatch" ]] && continue  # These go to path-specific
          [[ "$inclusion" == "manual" ]] && continue

          local content=$(strip_frontmatter "$steering_file")
          echo "$content"
          echo ""
        done
      } > "$instructions_md"
      log_ok "copilot-instructions.md generated"
    fi

    # Path-specific instructions (fileMatch rules)
    for steering_file in "$STEERING_DIR/"*.md; do
      [[ -f "$steering_file" ]] || continue
      local fname=$(basename "$steering_file" .md)
      [[ "$fname" == _* ]] && continue

      local inclusion=$(get_inclusion "$steering_file")
      [[ "$inclusion" != "fileMatch" ]] && continue

      local pattern=$(get_file_pattern "$steering_file")
      local content=$(strip_frontmatter "$steering_file")
      local dest_file="$instructions_dir/${fname}.instructions.md"

      if [[ -f "$dest_file" && "$FORCE" == false ]]; then
        log_skip "$fname.instructions.md (exists)"
        continue
      fi

      {
        echo "---"
        echo "applyTo: \"$pattern\""
        echo "---"
        echo ""
        echo "$content"
      } > "$dest_file"
    done

    local instr_count=$(find "$instructions_dir" -name "*.instructions.md" 2>/dev/null | wc -l)
    log_ok "$instr_count path-specific instructions exported"
  fi
}

# ============================================================
# Platform: Windsurf
# Location: .windsurf/skills/ + .windsurfrules
# Steering → single .windsurfrules (concatenated, global)
# ============================================================
export_windsurf() {
  local base="${OUTPUT_DIR:-.}"
  local skills_dest="$base/.windsurf/skills"
  local rules_file="$base/.windsurfrules"

  echo ""
  log_info "Exporting for Windsurf..."
  log_info "Skills → $skills_dest"
  log_info "Steering → $rules_file"
  echo ""

  # Skills
  if [[ "$STEERING_ONLY" == false ]]; then
    export_skills "$skills_dest"
  fi

  # Steering → .windsurfrules
  if [[ "$SKILLS_ONLY" == false ]]; then
    if [[ -f "$rules_file" && "$FORCE" == false ]]; then
      log_skip ".windsurfrules exists (use --force to overwrite)"
    else
      {
        echo "# Windsurf Rules"
        echo "# Auto-generated from kiro-skills steering files"
        echo "# Source: https://github.com/shyswy/kiro-skills"
        echo ""

        for steering_file in "$STEERING_DIR/"*.md; do
          [[ -f "$steering_file" ]] || continue
          local fname=$(basename "$steering_file")
          [[ "$fname" == _* ]] && continue
          [[ "$(get_inclusion "$steering_file")" == "manual" ]] && continue

          local content=$(strip_frontmatter "$steering_file")
          echo "$content"
          echo ""
        done
      } > "$rules_file"
      log_ok ".windsurfrules generated"
    fi
  fi
}

# ============================================================
# Platform: Gemini CLI
# Location: skills in project + GEMINI.md
# Steering → single GEMINI.md (concatenated)
# ============================================================
export_gemini() {
  local base="${OUTPUT_DIR:-.}"
  local skills_dest="$base/skills"
  local gemini_md="$base/GEMINI.md"

  echo ""
  log_info "Exporting for Gemini CLI..."
  log_info "Skills → $skills_dest"
  log_info "Steering → $gemini_md"
  echo ""

  # Skills
  if [[ "$STEERING_ONLY" == false ]]; then
    export_skills "$skills_dest"
  fi

  # Steering → GEMINI.md
  if [[ "$SKILLS_ONLY" == false ]]; then
    if [[ -f "$gemini_md" && "$FORCE" == false ]]; then
      log_skip "GEMINI.md exists (use --force to overwrite)"
    else
      {
        echo "# Project Rules"
        echo ""
        echo "<!-- Auto-generated from kiro-skills steering files -->"
        echo "<!-- Source: https://github.com/shyswy/kiro-skills -->"
        echo ""

        for steering_file in "$STEERING_DIR/"*.md; do
          [[ -f "$steering_file" ]] || continue
          local fname=$(basename "$steering_file")
          [[ "$fname" == _* ]] && continue
          [[ "$(get_inclusion "$steering_file")" == "manual" ]] && continue

          local content=$(strip_frontmatter "$steering_file")
          echo "$content"
          echo ""
        done
      } > "$gemini_md"
      log_ok "GEMINI.md generated"
    fi
  fi
}

# ============================================================
# Platform: AGENTS.md (Linux Foundation Open Standard)
# Location: AGENTS.md at project root
# The universal standard read by 20+ tools natively:
# Codex, Cursor, Copilot, Gemini CLI, Windsurf, Aider, Zed, etc.
# Steering → single AGENTS.md with structured sections
# ============================================================
export_agents_md() {
  local base="${OUTPUT_DIR:-.}"
  local agents_md="$base/AGENTS.md"
  local skills_dest="$base/skills"

  echo ""
  log_info "Exporting as AGENTS.md (open standard)..."
  log_info "Rules → $agents_md"
  log_info "Skills → $skills_dest"
  echo ""

  # Skills
  if [[ "$STEERING_ONLY" == false ]]; then
    export_skills "$skills_dest"
  fi

  # Steering → AGENTS.md
  if [[ "$SKILLS_ONLY" == false ]]; then
    if [[ -f "$agents_md" && "$FORCE" == false ]]; then
      log_skip "AGENTS.md exists (use --force to overwrite)"
    else
      {
        echo "# AGENTS.md"
        echo ""
        echo "<!-- Auto-generated from kiro-skills (https://github.com/shyswy/kiro-skills) -->"
        echo "<!-- This file follows the AGENTS.md open standard (Linux Foundation / Agentic AI Foundation) -->"
        echo "<!-- Supported by: Codex, Cursor, Copilot, Gemini CLI, Claude Code, Windsurf, Aider, Zed, and more -->"
        echo ""

        # Always-applied rules first
        local has_always=false
        for steering_file in "$STEERING_DIR/"*.md; do
          [[ -f "$steering_file" ]] || continue
          local fname=$(basename "$steering_file")
          [[ "$fname" == _* ]] && continue
          local inclusion=$(get_inclusion "$steering_file")
          [[ "$inclusion" == "fileMatch" ]] && continue
          [[ "$inclusion" == "manual" ]] && continue

          if [[ "$has_always" == false ]]; then
            echo "## General Rules"
            echo ""
            has_always=true
          fi

          local content=$(strip_frontmatter "$steering_file")
          echo "$content"
          echo ""
        done

        # File-specific rules
        local has_filematch=false
        for steering_file in "$STEERING_DIR/"*.md; do
          [[ -f "$steering_file" ]] || continue
          local fname=$(basename "$steering_file")
          [[ "$fname" == _* ]] && continue
          local inclusion=$(get_inclusion "$steering_file")
          [[ "$inclusion" != "fileMatch" ]] && continue

          if [[ "$has_filematch" == false ]]; then
            echo "## File-Specific Rules"
            echo ""
            has_filematch=true
          fi

          local pattern=$(get_file_pattern "$steering_file")
          local content=$(strip_frontmatter "$steering_file")

          echo "### Files: \`$pattern\`"
          echo ""
          echo "$content"
          echo ""
        done
      } > "$agents_md"
      log_ok "AGENTS.md generated (open standard)"
    fi
  fi
}

# ============================================================
# Main Dispatch
# ============================================================

echo ""
echo "============================================"
echo "  kiro-skills platform exporter v${VERSION}"
echo "============================================"

case "$TARGET_PLATFORM" in
  claude-code|claude)  export_claude_code ;;
  cursor)              export_cursor ;;
  copilot)             export_copilot ;;
  windsurf)            export_windsurf ;;
  gemini)              export_gemini ;;
  agents-md|agents)    export_agents_md ;;
  all)
    export_agents_md
    export_claude_code
    export_cursor
    export_copilot
    export_windsurf
    export_gemini
    ;;
  *)
    log_error "Unknown platform: $TARGET_PLATFORM"
    echo "Supported: claude-code, cursor, copilot, windsurf, gemini, agents-md, all"
    exit 1
    ;;
esac

echo ""
echo "============================================"
echo -e "${GREEN}Export complete!${NC}"
echo "============================================"
echo ""
echo "Notes:"
echo "  - Skills synced via symlink (single source of truth, instant updates)"
echo "  - Steering converted to platform-native format"
echo "  - Private files (_prefix) excluded from export"
echo ""
