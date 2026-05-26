#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/sliceai-public-skill-smoke.XXXXXX")"
MANIFEST_PATH="$WORK_DIR/public-skill-smoke-manifest.json"

cleanup() {
  if [[ "${SLICEAI_KEEP_PUBLIC_SKILL_SMOKE:-0}" != "1" ]]; then
    rm -rf "$WORK_DIR"
  else
    printf '[phase2-public-skill-smoke] kept work dir: %s\n' "$WORK_DIR"
  fi
}
trap cleanup EXIT

fetch_repo() {
  local id="$1"
  local url="$2"
  local commit="$3"
  local dest="$4"
  shift 4
  local paths=("$@")

  printf '[phase2-public-skill-smoke] fetching %s @ %s\n' "$id" "$commit"
  mkdir -p "$dest"
  git -C "$dest" init -q
  git -C "$dest" remote add origin "$url"
  git -C "$dest" fetch --depth=1 --filter=blob:none origin "$commit"
  git -C "$dest" sparse-checkout init --cone
  git -C "$dest" sparse-checkout set "${paths[@]}"
  git -C "$dest" checkout --quiet --detach FETCH_HEAD

  local actual
  actual="$(git -C "$dest" rev-parse HEAD)"
  if [[ "$actual" != "$commit" ]]; then
    printf '[phase2-public-skill-smoke] commit mismatch for %s: expected=%s actual=%s\n' \
      "$id" "$commit" "$actual" >&2
    return 1
  fi
}

ANTHROPICS_ROOT="$WORK_DIR/anthropics-skills"
OPENAI_ROOT="$WORK_DIR/openai-skills"
JMERTA_ROOT="$WORK_DIR/jmerta-codex-skills"

fetch_repo \
  "anthropics-skills" \
  "https://github.com/anthropics/skills.git" \
  "690f15cac7f7b4c055c5ab109c79ed9259934081" \
  "$ANTHROPICS_ROOT" \
  "skills/docx" \
  "skills/frontend-design" \
  "skills/mcp-builder"

fetch_repo \
  "openai-skills" \
  "https://github.com/openai/skills.git" \
  "b0401f07213a66414d84a65cb50c1d226f99485a" \
  "$OPENAI_ROOT" \
  "skills/.curated/openai-docs" \
  "skills/.curated/pdf" \
  "skills/.curated/security-threat-model"

fetch_repo \
  "jmerta-codex-skills" \
  "https://github.com/jMerta/codex-skills.git" \
  "1be063de2a730d61133e957dfc01a670cce7abd4" \
  "$JMERTA_ROOT" \
  "agents-md" \
  "bug-triage" \
  "plan-work"

cat > "$MANIFEST_PATH" <<JSON
{
  "repositories": [
    {
      "id": "anthropics-skills",
      "url": "https://github.com/anthropics/skills.git",
      "commit": "690f15cac7f7b4c055c5ab109c79ed9259934081",
      "rootPath": "$ANTHROPICS_ROOT",
      "expectedNames": ["docx", "frontend-design", "mcp-builder"]
    },
    {
      "id": "openai-skills",
      "url": "https://github.com/openai/skills.git",
      "commit": "b0401f07213a66414d84a65cb50c1d226f99485a",
      "rootPath": "$OPENAI_ROOT",
      "expectedNames": ["openai-docs", "pdf", "security-threat-model"]
    },
    {
      "id": "jmerta-codex-skills",
      "url": "https://github.com/jMerta/codex-skills.git",
      "commit": "1be063de2a730d61133e957dfc01a670cce7abd4",
      "rootPath": "$JMERTA_ROOT",
      "expectedNames": ["agents-md", "bug-triage", "plan-work"]
    }
  ]
}
JSON

printf '[phase2-public-skill-smoke] manifest: %s\n' "$MANIFEST_PATH"
SLICEAI_PUBLIC_SKILL_SMOKE_MANIFEST="$MANIFEST_PATH" \
  swift test --package-path "$ROOT_DIR/SliceAIKit" --filter CapabilitiesTests.PublicSkillRepositorySmokeTests

printf '[phase2-public-skill-smoke] passed: 3 repositories, 9 public skills\n'
