#!/bin/bash
set -euo pipefail

# ============================================================
# kiro-skills installer
# Hybrid: supports both "clone = install" and "merge into existing ~/.kiro"
# ============================================================

VERSION="2.0.0"
REPO_URL="https://github.com/shyswy/kiro-skills.git"
DEFAULT_TARGET="$HOME/.kiro"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Defaults
PROFILE="full"
TARGET="$DEFAULT_TARGET"
BACKUP=false
USE_SYMLINK=false
INSTALL_HOOKS=true
SOURCE_DIR=""

usage() {
  cat << EOF
kiro-skills installer v${VERSION}

Usage:
  # Scenario A: Fresh install (clone = install)
  git clone ${REPO_URL} ~/.kiro

  # Scenario B: Merge into existing ~/.kiro
  git clone ${REPO_URL} /tmp/kiro-skills
  bash /tmp/kiro-skills/scripts/install.sh [OPTIONS]

Options:
  --profile=PROFILE   Installation profile (default: full)
                      full     - All skills + steering
                      minimal  - Steering only
                      aws      - AWS-related skills only
                      infra    - Platform & infra skills only
  --target=PATH       Target directory (default: ~/.kiro)
  --backup            Backup existing target before install
  --symlink           Use symlinks instead of copy (for development)
  --no-hooks          Skip hooks installation
  --help              Show this help

Examples:
  bash scripts/install.sh --profile=full --backup
  bash scripts/install.sh --profile=aws --target=~/.kiro --symlink
EOF
  exit 0
}

log_info()  { echo -e "${BLUE}[INFO]${NC} $*"; }
log_ok()    { echo -e "${GREEN}[OK]${NC} $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

# Parse arguments
for arg in "$@"; do
  case $arg in
    --profile=*)  PROFILE="${arg#*=}" ;;
    --target=*)   TARGET="${arg#*=}" ;;
    --backup)     BACKUP=true ;;
    --symlink)    USE_SYMLINK=true ;;
    --no-hooks)   INSTALL_HOOKS=false ;;
    --help)       usage ;;
    *)            log_error "Unknown option: $arg" ;;
  esac
done

# Expand ~ in target
TARGET="${TARGET/#\~/$HOME}"

# Determine source directory (where this script lives)
SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Validate profile
case $PROFILE in
  full|minimal|aws|infra) ;;
  *) log_error "Invalid profile: $PROFILE. Use: full, minimal, aws, infra" ;;
esac

echo ""
echo "============================================"
echo "  kiro-skills installer v${VERSION}"
echo "============================================"
echo ""
log_info "Profile: $PROFILE"
log_info "Target:  $TARGET"
log_info "Source:  $SOURCE_DIR"
log_info "Symlink: $USE_SYMLINK"
echo ""

# Backup if requested
if [[ "$BACKUP" == true && -d "$TARGET" ]]; then
  BACKUP_DIR="${TARGET}.bak.$(date +%Y%m%d%H%M%S)"
  log_info "Backing up $TARGET → $BACKUP_DIR"
  cp -r "$TARGET" "$BACKUP_DIR"
  log_ok "Backup created: $BACKUP_DIR"
fi

# Create target directories
mkdir -p "$TARGET/steering"
mkdir -p "$TARGET/skills"
mkdir -p "$TARGET/scripts"

# Determine which skills to install based on profile
get_skill_list() {
  local profile="$1"
  local skills_dir="$SOURCE_DIR/skills"
  
  case $profile in
    full)
      # All public skills (exclude _ prefix)
      find "$skills_dir" -maxdepth 1 -mindepth 1 -type d ! -name '_*' -printf '%f\n' | sort
      ;;
    minimal)
      # No skills for minimal profile
      ;;
    aws)
      # AWS-related skills
      find "$skills_dir" -maxdepth 1 -mindepth 1 -type d \
        \( -name 'aws-*' -o -name 'api-gateway' -o -name 'dynamodb' -o -name 'supabase-postgres' \) \
        -printf '%f\n' | sort
      ;;
    infra)
      # Platform & infra skills
      find "$skills_dir" -maxdepth 1 -mindepth 1 -type d \
        \( -name 'k8s-*' -o -name 'docker-*' -o -name 'helm-*' -o -name 'gitops-*' -o -name 'observability' -o -name 'terraform-*' \) \
        -printf '%f\n' | sort
      ;;
  esac
}

# Install function (symlink or copy)
install_item() {
  local src="$1"
  local dest="$2"
  
  if [[ "$USE_SYMLINK" == true ]]; then
    ln -sf "$src" "$dest"
  else
    cp -r "$src" "$dest"
  fi
}

# Install steering (always installed regardless of profile)
log_info "Installing steering files..."
for f in "$SOURCE_DIR/steering/"*.md; do
  [[ -f "$f" ]] || continue
  fname=$(basename "$f")
  # Skip private steering
  [[ "$fname" == _* ]] && continue
  install_item "$f" "$TARGET/steering/$fname"
done
log_ok "Steering files installed"

# Install skills
if [[ "$PROFILE" != "minimal" ]]; then
  log_info "Installing skills (profile: $PROFILE)..."
  skill_count=0
  while IFS= read -r skill_name; do
    [[ -z "$skill_name" ]] && continue
    src="$SOURCE_DIR/skills/$skill_name"
    dest="$TARGET/skills/$skill_name"
    
    # Remove existing if not using symlink
    [[ -d "$dest" && "$USE_SYMLINK" == false ]] && rm -rf "$dest"
    
    install_item "$src" "$dest"
    ((skill_count++))
  done < <(get_skill_list "$PROFILE")
  log_ok "$skill_count skills installed"
fi

# Install scripts
log_info "Installing scripts..."
for f in "$SOURCE_DIR/scripts/"*.sh; do
  [[ -f "$f" ]] || continue
  install_item "$f" "$TARGET/scripts/$(basename "$f")"
done
chmod +x "$TARGET/scripts/"*.sh 2>/dev/null || true
log_ok "Scripts installed"

# Install hooks
if [[ "$INSTALL_HOOKS" == true && -d "$SOURCE_DIR/.kiro/hooks" ]]; then
  log_info "Installing hooks..."
  mkdir -p "$TARGET/.kiro/hooks"
  for f in "$SOURCE_DIR/.kiro/hooks/"*; do
    [[ -f "$f" ]] || continue
    install_item "$f" "$TARGET/.kiro/hooks/$(basename "$f")"
  done
  log_ok "Hooks installed"
fi

# Copy config template (only if target doesn't have one)
if [[ ! -f "$TARGET/steering/_user-scope-config.md" ]]; then
  if [[ -f "$SOURCE_DIR/steering/user-scope-config.example.md" ]]; then
    log_warn "No _user-scope-config.md found. Copy the example and customize:"
    log_warn "  cp $TARGET/steering/user-scope-config.example.md $TARGET/steering/_user-scope-config.md"
  fi
fi

# Summary
echo ""
echo "============================================"
log_ok "Installation complete!"
echo "============================================"
echo ""
echo "Next steps:"
echo "  1. Customize: cp steering/user-scope-config.example.md steering/_user-scope-config.md"
echo "  2. Edit _user-scope-config.md with your environment details"
echo "  3. Configure MCP: edit settings/mcp.json (see README)"
echo ""
