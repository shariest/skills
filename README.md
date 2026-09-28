# skills

Claude Code 스킬 모음입니다.

## AI 개발 환경 세팅

설치된 AI CLI(`claude`, `codex`)와 OS를 감지해서 필요한 플러그인·스킬·도구만 다룹니다. 몇 번을 실행해도 결과가 같으니(멱등) 안심하고 다시 돌리셔도 됩니다. 없는 것은 설치하고 이미 있는 것은 최신으로 올립니다.
같은 설정 파일을 고치는 작업은 순서대로, 나머지는 병렬로 실행합니다. 레인 구성은 `install.sh` 머리말에 적어 두었습니다.

### 바로 실행 (clone 없이)

macOS / Linux

```bash
curl -fsSL https://raw.githubusercontent.com/shariest/skills/main/install.sh | bash

# 인자는 bash -s -- 뒤에 붙입니다
curl -fsSL https://raw.githubusercontent.com/shariest/skills/main/install.sh | bash -s -- --skip test
```

Windows (명령 프롬프트)

```bat
curl.exe -fsSL -o "%TEMP%\install.bat" https://raw.githubusercontent.com/shariest/skills/main/install.bat && "%TEMP%\install.bat"
```

Windows (PowerShell)

```powershell
curl.exe -fsSL -o "$env:TEMP\install.bat" https://raw.githubusercontent.com/shariest/skills/main/install.bat; & "$env:TEMP\install.bat"
```

- 주소는 `github.com/...`이 아니라 파일 원본을 내려주는 `raw.githubusercontent.com/<계정>/<저장소>/<브랜치>/<파일>`입니다.
- Windows에서는 임시 폴더에 받은 뒤 실행합니다. `cmd`는 표준 입력으로 받은 배치 파일의 `goto`와 `call`을 처리하지 못해서 파이프로 바로 실행할 수 없습니다.
- `curl.exe`는 Windows 10 1803 이상에 기본으로 들어 있습니다. PowerShell 5.1에서는 `curl`이 `Invoke-WebRequest`의 별칭이라 `.exe`까지 적어야 합니다.
- `curl | bash`로 실행해도 sudo 비밀번호와 ecc 대화형 설치는 터미널에서 직접 입력받습니다.

### clone 해서 실행

```bash
git clone https://github.com/shariest/skills.git && cd skills
./install.sh                           # 설치와 갱신 (주기적으로 다시 실행하면 됩니다)
./install.sh --dry-run                 # 실행할 명령만 확인 (선택)
./install.sh --skip test --skip codex  # 섹션 제외
```

Windows에서는 `install.bat`을 같은 인자로 실행합니다.

### 설치 원칙

| 대상 | 설치 방식 | 다시 실행할 때 |
|---|---|---|
| 스킬 | 원본은 Claude의 `~/.claude/skills`에 둡니다. `~/.agents/skills`는 그 폴더로 가는 링크(Windows는 junction)입니다. 그래서 `npx skills add`가 쓰는 파일은 `~/.claude/skills`에 생기고 Codex는 링크를 따라 같은 폴더를 읽습니다. Claude에서 직접 만든 스킬도 Codex에 보입니다. | `npx skills add`가 최신 내용을 다시 받습니다 |
| 전역 CLI (playwright-cli, omx, context-mode) | nvm의 node 버전별 폴더 대신 `~/.skills`에 한 번만 설치하고 `~/.local/bin`에 링크합니다. node 버전을 바꿔도 사라지지 않습니다. | `@latest`로 다시 설치해 최신으로 올립니다 |
| im-not-ai | `~/.local/share/im-not-ai`에 클론한 뒤 upstream `install.sh`가 에이전트마다 링크를 겁니다. | `git pull` 후 `install.sh`를 다시 실행합니다 |
| 플러그인 (omc, ponytail, i-have-adhd, ecc, ouroboros) | hooks와 MCP까지 담고 있어 에이전트마다 형식이 다릅니다. 각 에이전트의 플러그인 매니저로 설치합니다. | 마켓플레이스를 갱신한 뒤 Claude는 `plugin update`, Codex는 `plugin add`로 다시 설치합니다 |

### 섹션

| 섹션 | 조건 | 내용 |
|---|---|---|
| `claude` | `claude` 있음 | 플러그인 oh-my-claudecode, ponytail, i-have-adhd (마켓플레이스 4개) |
| `codex` | `codex` 있음 | 플러그인 i-have-adhd, ponytail, oh-my-codex |
| `common` | 둘 중 하나라도 있음 | 스킬(docx, pdf, pptx, xlsx, unlazy, archify, hand-drawn-diagrams, orca), context-mode, ouroboros, im-not-ai, ecc(Claude 전용) |
| `test` | 항상 | 스킬(playwright-cli, hyperframes), playwright-cli 브라우저, LibreOffice와 한글 폰트 |

### OS별 차이

| 항목 | macOS | Linux | Windows |
|---|---|---|---|
| 전역 CLI 노출 | `~/.local/bin` 링크 | macOS와 같음 | `%USERPROFILE%\.skills`를 사용자 PATH에 등록 |
| LibreOffice, 폰트 | brew cask (Nanum, Noto CJK KR) | apt, Debian/Ubuntu 계열만 (sudo) | winget, LibreOffice만 |
| im-not-ai | 클론 + 링크 | macOS와 같음 | Claude 플러그인 마켓플레이스, Codex용은 건너뜀 |
| ouroboros | `install.sh` | `install.sh` | `install.ps1`, claude가 있을 때만 |

### 알아두실 점

- 전역 CLI를 쓰려면 `~/.local/bin`이 PATH에 있어야 합니다. 없으면 실행할 때 경고가 나옵니다.
- 전역 CLI는 그때 활성화된 node로 실행됩니다. context-mode에는 node 22.5 이상이 필요합니다.
- `ecc setup`은 설치 범위와 hook 수준을 묻는 대화형 설치기입니다. 그래서 처음 한 번만, 다른 설치가 모두 끝난 뒤 터미널에서 띄웁니다. 그다음부터는 플러그인 업데이트로 갱신합니다.
- LibreOffice와 폰트도 이미 있으면 최신으로 올립니다(brew upgrade, apt install, winget upgrade).
- 예전 방식(원본이 `~/.agents/skills`)으로 설치한 머신이라면 `install.sh`가 원본을 `~/.claude/skills`로 옮기고 링크로 바꿉니다. 같은 이름의 실제 폴더가 양쪽에 있으면 아무것도 지우지 않고 멈춥니다. `install.bat`은 자동으로 옮기지 않고 건너뜁니다.
- 에이전트 폴더에 같은 이름의 스킬이 실제 폴더로 있으면 `npx skills`가 그 폴더를 지우고 링크로 바꿉니다. 이미 쓰던 머신에서 돌리기 전에 직접 고친 스킬이 없는지 확인해 주세요.
- 새로 설치한 플러그인과 스킬은 Claude Code / Codex를 다시 시작해야 적용됩니다.
