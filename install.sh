#!/usr/bin/env bash
#
# AI 에이전트 개발 환경 초기 세팅 (macOS / Linux). Windows 는 install.bat 을 쓴다.
#
# 설치된 AI CLI(claude, codex)와 OS 를 감지해서 필요한 것만 다룬다. 몇 번을 실행해도 결과가 같다(멱등).
# 없는 것은 설치하고, 이미 있는 것은 최신으로 갱신한다. 사용법은 ./install.sh --help 를 본다.
#
# 설치 원칙
#   - 스킬 원본은 Claude 의 ~/.claude/skills 에 둔다. ~/.agents/skills 는 그 폴더를 가리키는 링크로 만든다.
#     npx skills 는 원본을 ~/.agents/skills 에 쓰므로 실제 파일은 ~/.claude/skills 에 생기고,
#     Codex 는 ~/.agents/skills(링크)를 따라가 같은 폴더를 읽는다. Claude 에서 직접 만든 스킬도 Codex 에 보인다.
#     npx skills add 는 매번 원본 저장소의 최신 내용을 받아 오므로 다시 실행하면 그대로 갱신이 된다.
#   - 전역 CLI 는 nvm 의 node 버전별 폴더가 아니라 ~/.skills 에 한 번만 설치하고 ~/.local/bin 에 링크한다.
#     node 버전을 바꿔도 사라지지 않는다. 실행은 그때 활성화된 node 로 한다.
#   - hooks, MCP 까지 담은 플러그인은 에이전트마다 형식이 달라 각 에이전트의 플러그인 매니저로 설치한다.
#
# 병렬 실행 규칙
#   같은 설정 파일을 고치는 작업이 동시에 돌면 서로의 변경을 덮어쓴다.
#   그래서 겹치면 안 되는 대상 단위로 레인을 나눠, 레인 안에서는 순서대로, 레인끼리는 병렬로 돌린다.
#
#   레인        겹치면 안 되는 대상                            작업
#   claude     ~/.claude/plugins, ~/.claude/settings.json     Claude 플러그인
#   codex      ~/.codex/config.toml                           Codex 플러그인
#   npm        ~/.skills (전역 CLI 설치 위치)                  playwright-cli, oh-my-codex
#   skills     ~/.agents/.skill-lock.json                     npx skills add
#   system     brew / apt                                     LibreOffice, 한글 폰트
#   im-not-ai  -                                              im-not-ai (git clone 또는 pull + install.sh)
#   shared     claude, codex, npm 레인의 대상 전부              context-mode, ouroboros
#
#   shared 는 claude, codex, npm 레인이 끝난 뒤 시작한다. context-mode 는 설치 후처리(postinstall)에서
#   Claude 플러그인 목록을 고치고, ouroboros 는 설치 중에 claude plugin install 과 Codex 설정을 실행한다.
#
#   ecc setup 은 설치 범위와 hook 수준을 묻는 대화형 설치기라 처음 한 번만 모든 레인이 끝난 뒤 터미널에서
#   실행한다. 이미 설치돼 있으면 claude 레인에서 플러그인 업데이트로 갱신한다.
#
# macOS 기본 bash(3.2)에서도 돌도록 연관 배열과 wait -n 을 쓰지 않는다.

set -uo pipefail

# ── 설치 목록 ────────────────────────────────────────────────────────────────
# 섹션: claude(claude 가 있을 때) · codex(codex 가 있을 때) · common(둘 중 하나라도 있을 때) · test

# [claude] 플러그인
CLAUDE_MARKETPLACES=(
  "freshtechbro/claudedesignskills"
  "https://github.com/Yeachan-Heo/oh-my-claudecode"
  "DietrichGebert/ponytail"
  "ayghri/i-have-adhd"
)
# 마켓플레이스까지 적어야 같은 이름의 플러그인이 여러 마켓플레이스에 있어도 의도한 것이 설치된다
CLAUDE_PLUGINS=(
  "oh-my-claudecode@omc"
  "ponytail@ponytail"
  "i-have-adhd@i-have-adhd"
)

# [codex] 플러그인. owner/repo@ref 는 codex plugin marketplace add --ref <ref> 로 넘긴다
CODEX_MARKETPLACES=(
  "ayghri/i-have-adhd@main"
  "DietrichGebert/ponytail"
)
CODEX_PLUGINS=(
  "i-have-adhd@i-have-adhd"
  "ponytail@ponytail"
)

# [common] 스킬: npx skills add <저장소> [스킬...]  스킬을 적지 않으면 저장소의 스킬 전부
COMMON_SKILL_PACKAGES=(
  "anthropics/skills docx pdf pptx xlsx"
  "Leonxlnx/unlazy"
  "tt-a1i/archify"
  "muthuishere/hand-drawn-diagrams"
  "stablyai/orca orca-cli orchestration computer-use"
)
# [common] 자체 설치기가 있는 것
ECC_PACKAGE="ecc-universal@2.2.1"
ECC_PLUGIN="ecc@ecc"
OUROBOROS_INSTALLER_URL="https://raw.githubusercontent.com/Q00/ouroboros/main/scripts/install.sh"
IM_NOT_AI_REPOSITORY_URL="https://github.com/epoko77-ai/im-not-ai.git"
# im-not-ai 의 install.sh 는 이 디렉터리를 가리키는 심링크를 만든다. 지우면 스킬이 깨진다.
IM_NOT_AI_DIRECTORY="${XDG_DATA_HOME:-$HOME/.local/share}/im-not-ai"

# [test]
TEST_SKILL_PACKAGES=(
  # 같은 저장소에 있는 개발용 dev 스킬은 받지 않는다
  "microsoft/playwright-cli playwright-cli"
  "heygen-com/hyperframes"
)
MACOS_CASKS=(
  libreoffice
  font-nanum-gothic
  font-nanum-myeongjo
  font-nanum-gothic-coding
  font-noto-sans-cjk-kr
  font-noto-serif-cjk-kr
)
LINUX_APT_PACKAGES=(
  libreoffice-writer libreoffice-calc libreoffice-impress libreoffice-draw
  libreoffice-base libreoffice-math libreoffice-core libreoffice-common
  libreoffice-base-core libreoffice-base-drivers libreoffice-report-builder
  libreoffice-report-builder-bin libreoffice-java-common
  libreoffice-script-provider-python libreoffice-sdbc-hsqldb
  libreoffice-sdbc-postgresql libreoffice-sdbc-mysql libreoffice-nlpsolver
  libreoffice-librelogo libreoffice-numbertext libreoffice-pdfimport
  libreoffice-style-colibre libreoffice-l10n-ko python3-uno default-jre
  fonts-nanum fonts-nanum-coding fonts-noto-cjk
)

# 전역 CLI 설치 위치와 실행 파일 링크 위치
CLI_PREFIX="$HOME/.skills"
CLI_LINK_DIRECTORY="$HOME/.local/bin"

# ── 실행 상태 ────────────────────────────────────────────────────────────────

# 작업 함수가 "할 일이 없어 건너뛴다"를 알릴 때 쓰는 종료 코드. 이유는 SKIP_REASON 에 담는다.
readonly SKIPPED=10
SKIP_REASON=""

IS_DRY_RUN=false
SKIPPED_SECTIONS=" "
OS_NAME=""
HAS_CLAUDE=false
HAS_CODEX=false
SYSTEM_PACKAGES_SKIP_REASON=""
LOG_DIRECTORY=""
RESULTS_FILE=""
STARTED_LANES=" "
CURRENT_LANE="main"

# ── 인자 / 환경 감지 ─────────────────────────────────────────────────────────

print_usage() {
  cat <<'USAGE'
사용법: ./install.sh [--dry-run] [--skip <섹션>]...

  (인자 없음)      없는 것은 설치하고 있는 것은 최신으로 갱신 (다시 실행해도 안전)
  --dry-run       실행할 명령만 출력하고 설치하지 않는다
  --skip <섹션>   섹션 제외: claude | codex | common | test (여러 번 줄 수 있다)
  -h, --help      도움말
USAGE
}

print_error() {
  echo "오류: $*" >&2
}

parse_arguments() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --dry-run)
        IS_DRY_RUN=true
        ;;
      --skip)
        if [ "$#" -lt 2 ]; then
          print_error "--skip 뒤에 섹션 이름이 필요합니다."
          exit 2
        fi
        validate_section "$2"
        SKIPPED_SECTIONS="$SKIPPED_SECTIONS$2 "
        shift
        ;;
      -h | --help)
        print_usage
        exit 0
        ;;
      *)
        print_error "알 수 없는 인자: $1"
        print_usage
        exit 2
        ;;
    esac
    shift
  done
}

validate_section() {
  case "$1" in
    claude | codex | common | test) ;;
    *)
      print_error "알 수 없는 섹션: $1 (claude | codex | common | test)"
      exit 2
      ;;
  esac
}

is_section_skipped() {
  case "$SKIPPED_SECTIONS" in
    *" $1 "*) return 0 ;;
    *) return 1 ;;
  esac
}

detect_environment() {
  case "$(uname -s)" in
    Darwin) OS_NAME="macos" ;;
    Linux) OS_NAME="linux" ;;
    *)
      print_error "지원하지 않는 OS 입니다: $(uname -s). Windows 에서는 install.bat 을 실행하세요."
      exit 1
      ;;
  esac

  if command -v claude >/dev/null 2>&1; then
    HAS_CLAUDE=true
  fi
  if command -v codex >/dev/null 2>&1; then
    HAS_CODEX=true
  fi
  if [ "$HAS_CLAUDE" = false ] && [ "$HAS_CODEX" = false ]; then
    print_error "claude, codex 를 둘 다 찾지 못했습니다. AI CLI 를 먼저 설치하세요."
    exit 1
  fi
}

describe_presence() {
  if [ "$1" = true ]; then
    echo "있음"
  else
    echo "없음 (관련 항목 건너뜀)"
  fi
}

print_environment() {
  echo "== AI 개발 환경 세팅 =="
  echo "OS     : $OS_NAME"
  echo "claude : $(describe_presence "$HAS_CLAUDE")"
  echo "codex  : $(describe_presence "$HAS_CODEX")"
  if [ "$SKIPPED_SECTIONS" != " " ]; then
    echo "제외   :$SKIPPED_SECTIONS"
  fi
  if [ "$IS_DRY_RUN" = true ]; then
    echo "모드   : dry-run (설치하지 않음)"
  else
    echo "로그   : $LOG_DIRECTORY"
  fi
  case ":$PATH:" in
    *":$CLI_LINK_DIRECTORY:"*) ;;
    *) echo "주의   : $CLI_LINK_DIRECTORY 가 PATH 에 없습니다. 전역 CLI(playwright-cli 등)를 쓰려면 PATH 에 추가하세요." ;;
  esac
  echo
}

# npx skills 는 에이전트를 홈 폴더(~/.claude, ~/.codex)로 감지한다.
# CLI 만 설치하고 한 번도 실행하지 않은 새 머신에서도 링크가 걸리도록 미리 만든다.
prepare_agent_homes() {
  if [ "$HAS_CLAUDE" = true ]; then
    run_command mkdir -p "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
  fi
  if [ "$HAS_CODEX" = true ]; then
    run_command mkdir -p "${CODEX_HOME:-$HOME/.codex}"
  fi
}

# Claude 를 스킬 원본으로 둔다: ~/.agents/skills 를 ~/.claude/skills 로 가는 링크로 만든다.
link_agents_skills_to_claude() {
  local claude_skills="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/skills"
  local agents_skills="$HOME/.agents/skills"
  if [ -L "$agents_skills" ]; then
    if [ "$(readlink "$agents_skills")" = "$claude_skills" ]; then
      SKIP_REASON="이미 연결됨"
      return "$SKIPPED"
    fi
    echo "중단: $agents_skills 가 다른 곳($(readlink "$agents_skills"))을 가리킨다"
    return 1
  fi
  run_command mkdir -p "$claude_skills" "$HOME/.agents" || return 1
  if [ -d "$agents_skills" ]; then
    move_agents_skills_into_claude "$agents_skills" "$claude_skills" || return 1
    run_command rmdir "$agents_skills" || return 1
  fi
  run_command ln -s "$claude_skills" "$agents_skills"
}

# 이전 방식(원본 ~/.agents/skills + ~/.claude/skills 링크)으로 설치된 머신을 옮긴다.
# ~/.claude/skills 쪽 링크는 원본으로 바꾸고, 같은 이름의 실제 폴더가 있으면 덮어쓰지 않고 중단한다.
move_agents_skills_into_claude() {
  local agents_skills="$1" claude_skills="$2" entry target
  for entry in "$agents_skills"/* "$agents_skills"/.[!.]*; do
    if [ ! -e "$entry" ] && [ ! -L "$entry" ]; then
      continue
    fi
    target="$claude_skills/$(basename "$entry")"
    if [ -L "$target" ]; then
      run_command rm "$target" || return 1
    elif [ -e "$target" ]; then
      echo "중단: $target 가 실제 폴더로 있어 $entry 를 옮기지 않는다"
      return 1
    fi
    run_command mv "$entry" "$target" || return 1
  done
}

# LibreOffice·폰트를 설치할 수 있는지 확인한다.
# Linux 는 sudo 인증을 여기서 미리 받는다. 백그라운드 레인에서는 비밀번호를 물을 수 없다.
prepare_system_packages() {
  if is_section_skipped test; then
    return
  fi
  case "$OS_NAME" in
    macos)
      if ! command -v brew >/dev/null 2>&1; then
        SYSTEM_PACKAGES_SKIP_REASON="Homebrew 가 없습니다 (https://brew.sh)"
      fi
      ;;
    linux)
      if ! command -v apt-get >/dev/null 2>&1; then
        SYSTEM_PACKAGES_SKIP_REASON="apt-get 이 없습니다 (Debian/Ubuntu 계열만 지원)"
      elif [ "$(id -u)" -ne 0 ]; then
        authenticate_sudo
      fi
      ;;
  esac
}

authenticate_sudo() {
  if ! command -v sudo >/dev/null 2>&1; then
    SYSTEM_PACKAGES_SKIP_REASON="root 가 아니고 sudo 도 없습니다"
    return
  fi
  if [ "$IS_DRY_RUN" = true ]; then
    return
  fi
  echo "LibreOffice 설치(apt-get)에 sudo 권한이 필요합니다."
  if ! sudo -v; then
    SYSTEM_PACKAGES_SKIP_REASON="sudo 인증에 실패했습니다"
    return
  fi
  # 설치가 끝날 때까지 sudo 인증을 유지한다. 이 스크립트가 끝나면 같이 끝난다.
  (
    while kill -0 "$$" 2>/dev/null; do
      sudo -n true
      sleep 50
    done
  ) </dev/null >/dev/null 2>&1 &
}

as_root() {
  if [ "$(id -u)" -eq 0 ]; then
    "$@"
  else
    sudo -n "$@"
  fi
}

# ── 작업 실행 / 결과 기록 ────────────────────────────────────────────────────

# 명령을 출력하고 실행한다. --dry-run 이면 출력만 한다.
run_command() {
  echo "+ $*"
  if [ "$IS_DRY_RUN" = true ]; then
    return 0
  fi
  "$@"
}

print_status_line() {
  local status="$1" title="$2" detail="${3:-}"
  if [ -n "$detail" ]; then
    printf '  %-4s %-9s %s  (%s)\n' "$status" "$CURRENT_LANE" "$title" "$detail"
  else
    printf '  %-4s %-9s %s\n' "$status" "$CURRENT_LANE" "$title"
  fi
}

# record_result <OK|SKIP|FAIL> <제목> [상세]
record_result() {
  local status="$1" title="$2" detail="${3:-}"
  print_status_line "$status" "$title" "$detail"
  if [ "$IS_DRY_RUN" = false ]; then
    printf '%s|%s|%s|%s\n' "$status" "$CURRENT_LANE" "$title" "$detail" >>"$RESULTS_FILE"
  fi
}

to_file_name() {
  printf '%s' "$1" | tr -cs 'A-Za-z0-9._-' '-'
}

# run_task <섹션> <제목> <함수> [인자...]
# 작업 출력은 작업별 로그 파일로 보내고, 터미널에는 결과 한 줄만 찍는다.
run_task() {
  local section="$1" title="$2"
  shift 2
  if is_section_skipped "$section"; then
    return 0
  fi

  local exit_code
  SKIP_REASON=""
  if [ "$IS_DRY_RUN" = true ]; then
    echo "  # $title"
    "$@"
    exit_code=$?
    if [ "$exit_code" -eq "$SKIPPED" ]; then
      echo "    → 건너뜀: $SKIP_REASON"
    fi
    return 0
  fi

  local task_log started_at
  task_log="$LOG_DIRECTORY/$CURRENT_LANE-$(to_file_name "$title").log"
  started_at="$SECONDS"
  print_status_line ".." "$title"
  "$@" >"$task_log" 2>&1 </dev/null
  exit_code=$?
  if [ "$exit_code" -eq 0 ]; then
    record_result OK "$title" "$((SECONDS - started_at))s"
  elif [ "$exit_code" -eq "$SKIPPED" ]; then
    record_result SKIP "$title" "$SKIP_REASON"
  else
    record_result FAIL "$title" "$task_log"
  fi
}

# ── 레인 공통 ────────────────────────────────────────────────────────────────

# start_lane <레인> <함수> : 레인을 백그라운드로 띄운다. 어떻게 끝나든 <레인>.done 파일을 남긴다.
start_lane() {
  local lane="$1" lane_function="$2"
  if [ "$IS_DRY_RUN" = true ]; then
    echo
    echo "[$lane]"
    CURRENT_LANE="$lane"
    "$lane_function"
    CURRENT_LANE="main"
    return
  fi

  STARTED_LANES="$STARTED_LANES$lane "
  (
    trap 'touch "$LOG_DIRECTORY/$lane.done"' EXIT
    CURRENT_LANE="$lane"
    "$lane_function"
  ) </dev/null &
}

# wait_for_lanes <레인...> : 시작한 레인 중 지정한 레인이 끝날 때까지 기다린다.
# 백그라운드 레인끼리는 서로를 wait 할 수 없어서 .done 파일로 확인한다.
wait_for_lanes() {
  local lane
  for lane in "$@"; do
    case "$STARTED_LANES" in
      *" $lane "*) ;;
      *) continue ;;
    esac
    while [ ! -e "$LOG_DIRECTORY/$lane.done" ]; do
      sleep 1
    done
  done
}

contains_ignoring_case() {
  grep -Fqi -- "$2" <<<"$1"
}

# https://github.com/owner/repo(.git), owner/repo@ref → owner/repo
to_repository() {
  local repository="${1#https://github.com/}"
  repository="${repository%.git}"
  printf '%s' "${repository%@*}"
}

# ── claude 레인 ──────────────────────────────────────────────────────────────

lane_claude() {
  local registered_marketplaces installed_plugins source plugin
  registered_marketplaces="$(claude plugin marketplace list --json 2>/dev/null)"
  for source in "${CLAUDE_MARKETPLACES[@]}"; do
    run_task claude "marketplace $(to_repository "$source")" \
      add_claude_marketplace "$source" "$registered_marketplaces"
  done
  # 이미 등록돼 있던 마켓플레이스도 최신 목록으로 받아 와야 플러그인 업데이트가 새 버전을 찾는다
  run_task claude "marketplaces refresh" run_command claude plugin marketplace update
  installed_plugins="$(claude plugin list --json 2>/dev/null)"
  for plugin in "${CLAUDE_PLUGINS[@]}"; do
    run_task claude "plugin $plugin" install_or_update_claude_plugin "$plugin" "$installed_plugins"
  done
  # ecc 는 처음에 ecc setup(대화형)으로 설치하므로 여기서는 설치돼 있을 때만 갱신한다
  run_task common "plugin $ECC_PLUGIN" update_installed_claude_plugin "$ECC_PLUGIN" "$installed_plugins"
}

add_claude_marketplace() {
  local source="$1" registered_marketplaces="$2"
  if contains_ignoring_case "$registered_marketplaces" "$(to_repository "$source")"; then
    SKIP_REASON="이미 등록됨"
    return "$SKIPPED"
  fi
  run_command claude plugin marketplace add "$source"
}

install_or_update_claude_plugin() {
  local plugin="$1" installed_plugins="$2"
  if contains_ignoring_case "$installed_plugins" "\"$plugin\""; then
    run_command claude plugin update "$plugin"
  else
    run_command claude plugin install "$plugin"
  fi
}

update_installed_claude_plugin() {
  local plugin="$1" installed_plugins="$2"
  if ! contains_ignoring_case "$installed_plugins" "\"$plugin\""; then
    SKIP_REASON="아직 설치 전"
    return "$SKIPPED"
  fi
  run_command claude plugin update "$plugin"
}

# ── codex 레인 ───────────────────────────────────────────────────────────────

lane_codex() {
  local registered_marketplaces source plugin
  registered_marketplaces="$(codex plugin marketplace list --json 2>/dev/null)"
  for source in "${CODEX_MARKETPLACES[@]}"; do
    run_task codex "marketplace $(to_repository "$source")" \
      add_codex_marketplace "$source" "$registered_marketplaces"
  done
  run_task codex "marketplaces refresh" run_command codex plugin marketplace upgrade
  # codex 에는 plugin update 가 없다. 갱신한 마켓플레이스에서 다시 add 하면 설치든 갱신이든 같은 결과가 된다.
  for plugin in "${CODEX_PLUGINS[@]}"; do
    run_task codex "plugin $plugin" run_command codex plugin add "$plugin"
  done
}

add_codex_marketplace() {
  local source="$1" registered_marketplaces="$2"
  if contains_ignoring_case "$registered_marketplaces" "$(to_repository "$source")"; then
    SKIP_REASON="이미 등록됨"
    return "$SKIPPED"
  fi
  case "$source" in
    *@*) run_command codex plugin marketplace add "${source%@*}" --ref "${source##*@}" ;;
    *) run_command codex plugin marketplace add "$source" ;;
  esac
}

# ── npm 레인: 전역 CLI ───────────────────────────────────────────────────────

lane_npm() {
  run_task test "cli @playwright/cli" install_global_cli "@playwright/cli@latest"
  run_task test "playwright browser" prepare_playwright_browser
  if [ "$HAS_CODEX" = true ]; then
    run_task codex "cli oh-my-codex" install_global_cli "oh-my-codex@latest"
  fi
}

# 전역 CLI 를 CLI_PREFIX 에 설치하고 실행 파일을 CLI_LINK_DIRECTORY 에 링크한다.
# @latest 로 설치하므로 이미 있으면 최신으로 갱신된다.
install_global_cli() {
  run_command npm install -g --prefix "$CLI_PREFIX" "$1" || return 1
  link_cli_binaries
}

link_cli_binaries() {
  local binary link existing_target
  run_command mkdir -p "$CLI_LINK_DIRECTORY" || return 1
  for binary in "$CLI_PREFIX"/bin/*; do
    if [ ! -e "$binary" ]; then
      continue
    fi
    link="$CLI_LINK_DIRECTORY/$(basename "$binary")"
    # 같은 이름으로 사용자가 둔 파일이나 다른 곳을 가리키는 링크(예: codex 셔임)는 덮어쓰지 않는다
    if [ -e "$link" ] || [ -L "$link" ]; then
      existing_target="$(readlink "$link" 2>/dev/null || true)"
      case "$existing_target" in
        "$CLI_PREFIX"/*) ;;
        *)
          echo "건너뜀: $link 가 이미 있고 $CLI_PREFIX 를 가리키지 않는다"
          continue
          ;;
      esac
    fi
    run_command ln -sfn "$binary" "$link" || return 1
  done
}

# playwright-cli 스킬은 skills 레인에서 설치하고, 여기서는 브라우저와 기본 설정만 준비한다.
# playwright-cli install 은 현재 디렉터리를 작업 공간으로 초기화하므로 홈에서 실행한다.
prepare_playwright_browser() {
  (
    cd "$HOME" || exit 1
    run_command "$CLI_PREFIX/bin/playwright-cli" install
  )
}

# ── skills 레인 ──────────────────────────────────────────────────────────────

# npx skills add 는 매번 원본 저장소의 최신 내용을 받아 오므로 설치와 갱신이 같은 명령이다
lane_skills() {
  local package
  for package in "${COMMON_SKILL_PACKAGES[@]}"; do
    run_task common "skill ${package%% *}" add_skill_package "$package"
  done
  for package in "${TEST_SKILL_PACKAGES[@]}"; do
    run_task test "skill ${package%% *}" add_skill_package "$package"
  done
}

# add_skill_package "<저장소> [스킬...]"
# -a 를 주지 않으면 skills CLI 가 감지된 에이전트 전부에 링크한다.
add_skill_package() {
  local package_words
  read -r -a package_words <<<"$1"
  if [ "${#package_words[@]}" -gt 1 ]; then
    run_command npx --yes skills add "${package_words[0]}" -g -y -s "${package_words[@]:1}"
  else
    run_command npx --yes skills add "${package_words[0]}" -g -y
  fi
}

# ── system 레인 ──────────────────────────────────────────────────────────────

lane_system() {
  if [ -n "$SYSTEM_PACKAGES_SKIP_REASON" ]; then
    record_result SKIP "LibreOffice + fonts" "$SYSTEM_PACKAGES_SKIP_REASON"
    return
  fi
  case "$OS_NAME" in
    macos) run_task test "LibreOffice + fonts (brew)" install_macos_casks ;;
    linux) run_task test "LibreOffice + fonts (apt)" install_linux_apt_packages ;;
  esac
}

install_macos_casks() {
  local cask missing_casks=() installed_casks=()
  for cask in "${MACOS_CASKS[@]}"; do
    if brew list --cask "$cask" >/dev/null 2>&1; then
      installed_casks+=("$cask")
    elif [ "$cask" = "libreoffice" ] && [ -d "/Applications/LibreOffice.app" ]; then
      # brew 밖에서 설치한 LibreOffice 는 brew 가 덮어쓰기를 거부하므로 손대지 않는다
      continue
    else
      missing_casks+=("$cask")
    fi
  done
  if [ "${#missing_casks[@]}" -gt 0 ]; then
    run_command brew install --cask "${missing_casks[@]}" || return 1
  fi
  if [ "${#installed_casks[@]}" -gt 0 ]; then
    # 이미 최신이면 아무것도 하지 않고 성공한다
    run_command brew upgrade --cask "${installed_casks[@]}" || return 1
  fi
}

# apt-get install 은 이미 설치된 패키지도 새 버전이 있으면 올린다
install_linux_apt_packages() {
  run_command as_root apt-get update || return 1
  run_command as_root env DEBIAN_FRONTEND=noninteractive \
    apt-get install -y --no-install-recommends "${LINUX_APT_PACKAGES[@]}"
}

# ── im-not-ai 레인 ───────────────────────────────────────────────────────────

lane_im_not_ai() {
  run_task common "im-not-ai" install_im_not_ai
}

# 클론 한 벌을 두고 im-not-ai 의 install.sh 가 감지된 에이전트마다 심링크를 건다.
# 이미 클론돼 있으면 pull 로 갱신한다.
install_im_not_ai() {
  if [ -d "$IM_NOT_AI_DIRECTORY/.git" ]; then
    run_command git -C "$IM_NOT_AI_DIRECTORY" pull --ff-only || return 1
  else
    run_command mkdir -p "$(dirname "$IM_NOT_AI_DIRECTORY")" || return 1
    run_command git clone "$IM_NOT_AI_REPOSITORY_URL" "$IM_NOT_AI_DIRECTORY" || return 1
  fi
  run_command bash "$IM_NOT_AI_DIRECTORY/install.sh"
}

# ── shared 레인 ──────────────────────────────────────────────────────────────

lane_shared() {
  wait_for_lanes claude codex npm
  run_task common "cli context-mode" install_global_cli "context-mode@latest"
  run_task common "ouroboros" install_ouroboros
}

# 설치기가 이미 설치된 경우 최신으로 올린다.
install_ouroboros() {
  # 처음 설치할 때만 런타임을 정해 준다. 다시 설치할 때는 설치기가 ~/.ouroboros/config.yaml 의 선택을 유지한다.
  local runtime=""
  if [ ! -f "$HOME/.ouroboros/config.yaml" ]; then
    if [ "$HAS_CLAUDE" = true ]; then
      runtime="claude"
    else
      runtime="codex"
    fi
  fi
  echo "+ curl -fsSL $OUROBOROS_INSTALLER_URL | OUROBOROS_INSTALL_RUNTIME=$runtime bash"
  if [ "$IS_DRY_RUN" = true ]; then
    return 0
  fi
  # 표준 입력이 파이프라 설치기가 대화형 질문 없이 진행한다
  curl -fsSL "$OUROBOROS_INSTALLER_URL" | OUROBOROS_INSTALL_RUNTIME="$runtime" bash
}

# ── 대화형 / 결과 요약 ───────────────────────────────────────────────────────

run_ecc_setup() {
  if [ "$HAS_CLAUDE" = false ] || is_section_skipped common; then
    return
  fi
  CURRENT_LANE="ecc"
  local title="$ECC_PACKAGE setup"
  # 이미 설치돼 있으면 claude 레인에서 플러그인 업데이트로 갱신했으므로 대화형 설치를 다시 띄우지 않는다
  if contains_ignoring_case "$(claude plugin list --json 2>/dev/null)" "\"$ECC_PLUGIN\""; then
    return
  fi
  echo
  echo "[ecc] 대화형 설치 (설치 범위, hook 수준을 묻는다)"
  if [ "$IS_DRY_RUN" = true ]; then
    run_command npx --yes "$ECC_PACKAGE" setup
    return
  fi

  local started_at="$SECONDS" exit_code
  if [ -t 0 ]; then
    npx --yes "$ECC_PACKAGE" setup
    exit_code=$?
  elif (exec </dev/tty) 2>/dev/null; then
    # curl | bash 로 실행하면 표준 입력이 스크립트 본문이라 터미널을 직접 연결한다
    npx --yes "$ECC_PACKAGE" setup </dev/tty
    exit_code=$?
  else
    record_result SKIP "$title" "터미널이 없음. 직접 실행: npx $ECC_PACKAGE setup"
    return
  fi

  if [ "$exit_code" -eq 0 ]; then
    record_result OK "$title" "$((SECONDS - started_at))s"
  else
    record_result FAIL "$title" "종료 코드 $exit_code, 위 출력 참고"
  fi
}

run_lanes() {
  prepare_agent_homes
  # skills 레인보다 먼저 끝나야 npx skills 가 원본을 ~/.claude/skills 에 쓴다
  if [ "$HAS_CLAUDE" = true ]; then
    run_task common "skills origin ~/.claude/skills" link_agents_skills_to_claude
  fi
  prepare_system_packages

  if [ "$HAS_CLAUDE" = true ]; then
    start_lane claude lane_claude
  fi
  if [ "$HAS_CODEX" = true ]; then
    start_lane codex lane_codex
  fi
  start_lane npm lane_npm
  start_lane skills lane_skills
  if ! is_section_skipped test; then
    start_lane system lane_system
  fi
  if ! is_section_skipped common; then
    start_lane im-not-ai lane_im_not_ai
    start_lane shared lane_shared
  fi

  wait_for_lanes claude codex npm skills system im-not-ai shared
  run_ecc_setup
}

count_results() {
  grep -c "^$1|" "$RESULTS_FILE"
}

print_summary() {
  local ok_count skip_count fail_count
  ok_count="$(count_results OK)"
  skip_count="$(count_results SKIP)"
  fail_count="$(count_results FAIL)"

  echo
  echo "== 결과: 성공 $ok_count, 건너뜀 $skip_count, 실패 $fail_count =="
  if [ "$fail_count" -gt 0 ]; then
    local status lane title detail
    echo
    echo "실패한 작업:"
    while IFS='|' read -r status lane title detail; do
      if [ "$status" != "FAIL" ]; then
        continue
      fi
      echo "  [$lane] $title"
      if [ -f "$detail" ]; then
        echo "    로그: $detail"
        tail -n 5 "$detail" | sed 's/^/      /'
      else
        echo "    $detail"
      fi
    done <"$RESULTS_FILE"
  fi
  echo
  echo "전체 로그: $LOG_DIRECTORY"
  if [ "$ok_count" -gt 0 ]; then
    echo "새 플러그인과 스킬은 Claude Code / Codex 를 다시 시작해야 적용됩니다."
  fi
  [ "$fail_count" -eq 0 ]
}

handle_interrupt() {
  # 아래 kill 0 이 이 스크립트에도 SIGTERM 을 보내므로 먼저 무시해 둔다
  trap '' INT TERM
  echo
  print_error "중단했습니다. 실행 중인 설치 작업을 종료합니다."
  # 백그라운드 레인과 그 자식 프로세스는 SIGINT 를 무시하므로 프로세스 그룹 전체에 SIGTERM 을 보낸다
  kill 0
  exit 130
}

main() {
  parse_arguments "$@"
  detect_environment
  trap handle_interrupt INT TERM

  if [ "$IS_DRY_RUN" = false ]; then
    LOG_DIRECTORY="$(mktemp -d "${TMPDIR:-/tmp}/ai-setup.XXXXXX")" || exit 1
    RESULTS_FILE="$LOG_DIRECTORY/results"
    : >"$RESULTS_FILE"
  fi
  print_environment
  run_lanes

  if [ "$IS_DRY_RUN" = true ]; then
    echo
    echo "dry-run 이라 설치하지 않았습니다."
    return 0
  fi
  print_summary
}

main "$@"
