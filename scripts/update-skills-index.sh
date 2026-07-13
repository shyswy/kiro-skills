#!/usr/bin/env bash
# update-skills-index.sh
# skills/ 디렉토리를 스캔하여 README.md의 Skills 목록을 자동 갱신한다.
# Usage: bash scripts/update-skills-index.sh
# Requires: bash 4+ (macOS: brew install bash)

KIRO_DIR="$HOME/.kiro"
SKILLS_DIR="$KIRO_DIR/skills"
README="$KIRO_DIR/README.md"

# SKILL.md에서 description 첫 줄 추출
get_description() {
  local skill_md="$1/SKILL.md"
  if [[ -f "$skill_md" ]]; then
    # YAML frontmatter의 description 필드에서 첫 줄만 추출
    sed -n '/^description:/,/^[a-z]/{ /^description:/{ s/^description: *//; s/|//; p; d }; /^  /{ s/^  *//; p; q } }' "$skill_md" | head -1 | sed 's/^ *//;s/ *$//'
  fi
}

# 카테고리 분류
categorize_skill() {
  local name="$1"
  case "$name" in
    aws-*|api-gateway|supabase-postgres|terraform-skill)
      echo "AWS & Cloud";;
    k8s-*|docker-*|helm-*|gitops-*|observability)
      echo "Platform & Infra";;
    kafka-*|elasticsearch-*|dynamodb|rdb-*|iot-*)
      echo "Data & Messaging";;
    typescript-*|api-design|architecture|git-*)
      echo "Development";;
    jira-*|sprint-*|knowledge-*|scope-*|skill-*|project-*)
      echo "Workflow & Management";;
    *)
      echo "Other";;
  esac
}

# 스킬 목록 수집
declare -A CATEGORIES

for skill_dir in "$SKILLS_DIR"/*/; do
  [[ -d "$skill_dir" ]] || continue
  skill_name=$(basename "$skill_dir")
  [[ -f "$skill_dir/SKILL.md" ]] || continue
  # Skip private skills (underscore prefix)
  [[ "$skill_name" == _* ]] && continue
  
  category=$(categorize_skill "$skill_name")
  desc=$(get_description "$skill_dir")
  
  if [[ -z "${CATEGORIES[$category]}" ]]; then
    CATEGORIES[$category]="$skill_name|$desc"
  else
    CATEGORIES[$category]="${CATEGORIES[$category]}"$'\n'"$skill_name|$desc"
  fi
done

# 스킬 수 계산 (public only)
total_skills=0
for skill_dir in "$SKILLS_DIR"/*/; do
  [[ -f "$skill_dir/SKILL.md" ]] || continue
  skill_name=$(basename "$skill_dir")
  [[ "$skill_name" == _* ]] && continue
  ((total_skills++))
done

# steering 수 계산 (public only, exclude _ prefix)
total_steering=0
for f in "$KIRO_DIR/steering/"*.md; do
  [[ -f "$f" ]] || continue
  fname=$(basename "$f")
  [[ "$fname" == _* ]] && continue
  ((total_steering++))
done

# README 재생성
cat > "$README" << 'HEADER'
# kiro-skills

🛠️ Personal Kiro user-scope configuration — skills, steering, and project context for full-stack cloud development.

## What's Inside

HEADER

echo "- **${total_steering} Steering files** — coding rules auto-applied by file type" >> "$README"
echo "- **${total_skills} Skills** — domain expertise loaded on-demand via [agentskills.io](https://agentskills.io) spec" >> "$README"
echo "" >> "$README"

# Steering 섹션
cat >> "$README" << 'STEERING'
### Steering (always/fileMatch)

| File | Trigger | Scope |
|------|---------|-------|
STEERING

for steering_file in "$KIRO_DIR/steering/"*.md; do
  [[ -f "$steering_file" ]] || continue
  fname=$(basename "$steering_file")
  # Skip private steering (underscore prefix)
  [[ "$fname" == _* ]] && continue
  
  # inclusion 타입 확인
  inclusion=$(sed -n 's/^inclusion: *//p' "$steering_file" | head -1)
  pattern=$(sed -n 's/^fileMatchPattern: *//p' "$steering_file" | sed "s/['\"]//g" | head -1)
  
  if [[ "$inclusion" == "fileMatch" && -n "$pattern" ]]; then
    trigger="\`$pattern\`"
  elif [[ "$inclusion" == "manual" ]]; then
    trigger="manual (#)"
  else
    trigger="always"
  fi
  
  # 첫 번째 주석이 아닌 줄에서 scope 추출
  scope=$(grep -m1 '^#' "$steering_file" | sed 's/^# *//')
  [[ -z "$scope" ]] && scope="$fname"
  
  echo "| $fname | $trigger | $scope |" >> "$README"
done

echo "" >> "$README"

# Skills 섹션
echo "### Skills by Category" >> "$README"
echo "" >> "$README"

# 카테고리 순서 고정
for category in "AWS & Cloud" "Platform & Infra" "Data & Messaging" "Development" "Workflow & Management" "Other"; do
  [[ -z "${CATEGORIES[$category]}" ]] && continue
  
  echo "**${category}**" >> "$README"
  echo "" >> "$README"
  
  echo "${CATEGORIES[$category]}" | sort | while IFS='|' read -r name desc; do
    if [[ -n "$desc" ]]; then
      echo "- \`$name\` — $desc" >> "$README"
    else
      echo "- \`$name\`" >> "$README"
    fi
  done
  
  echo "" >> "$README"
done

# Installation 섹션
cat >> "$README" << 'INSTALL'
## Installation

```bash
git clone https://github.com/shyswy/kiro-skills.git ~/.kiro-repo

# Symlink or copy to ~/.kiro
ln -sf ~/.kiro-repo/steering/* ~/.kiro/steering/
ln -sf ~/.kiro-repo/skills/* ~/.kiro/skills/
```

Or if this IS your `~/.kiro` directory:

```bash
cd ~/.kiro
git init
git remote add origin https://github.com/shyswy/kiro-skills.git
git pull origin main
```

## Structure

```
~/.kiro/
├── steering/           # Steering files (auto-loaded by file type)
├── skills/             # Skills (loaded on-demand by trigger keywords)
├── projects/           # Project context (managed by project-context-manager)
├── scripts/            # Automation scripts
└── settings/           # MCP configs (gitignored, contains secrets)
```

## Customization

Edit `steering/user-scope-config.md` to update your environment. Use the `scope-manager` skill for guided updates.

## Auto-indexing

When a new skill is added, run:
```bash
bash scripts/update-skills-index.sh
```
Or it runs automatically via the `skill-index-updater` hook when SKILL.md files are created.

## License

MIT — see [LICENSE](LICENSE)

## Attribution

See [ATTRIBUTION.md](ATTRIBUTION.md) for all referenced sources.
INSTALL

echo ""
echo "✅ README.md updated (${total_skills} skills, ${total_steering} steering files)"
