@echo off
setlocal EnableExtensions DisableDelayedExpansion
for /f "tokens=2 delims=:." %%C in ('chcp') do set "ORIGINAL_CODE_PAGE=%%C"
chcp 65001 >nul

rem ============================================================================
rem  AI 에이전트 개발 환경 초기 세팅 - Windows. macOS, Linux 는 install.sh 를 쓴다.
rem
rem  설치된 AI CLI(claude, codex)를 감지해서 필요한 것만 다룬다. 몇 번을 실행해도 결과가 같다.
rem  없는 것은 설치하고, 이미 있는 것은 최신으로 갱신한다.
rem  사용법은 install.bat --help 를 본다. 설치 원칙과 병렬 실행 규칙은 install.sh 머리말과 같다.
rem  레인마다 cmd 프로세스를 하나씩 띄우고, 레인이 끝나면 레인이름.done 파일을 남겨
rem  다른 레인과 메인이 그 파일로 종료를 확인한다.
rem
rem  install.sh 와 다른 점
rem   - 스킬 원본  : .agents\skills 를 심링크 대신 junction 으로 .claude\skills 에 연결한다.
rem                  이미 실제 폴더로 있으면 자동으로 옮기지 않고 건너뛴다.
rem   - 전역 CLI   : npm 이 Windows 에서는 실행 파일을 prefix 폴더에 바로 만든다.
rem                  그래서 링크 대신 그 폴더를 사용자 PATH 에 한 번만 등록한다.
rem   - im-not-ai  : upstream 설치 스크립트가 bash 와 심링크 전용이라 Claude 플러그인 마켓플레이스로 설치한다.
rem                  Codex 용은 upstream 이 WSL 을 권장하므로 건너뛴다. 그래서 im-not-ai 레인이 없다.
rem   - ouroboros  : 공식 PowerShell 설치기 install.ps1 을 쓴다.
rem                  Windows 에서 Codex 런타임은 WSL 2 전용이라 claude 가 있을 때만 설치한다.
rem   - LibreOffice: winget 으로 설치한다. Nanum, Noto CJK 폰트는 winget 패키지가 없어 건너뛴다.
rem ============================================================================

set "SCRIPT_PATH=%~f0"

rem -- 설치 목록 ---------------------------------------------------------------
rem  섹션: claude - claude 가 있을 때, codex - codex 가 있을 때, common - 둘 중 하나라도 있을 때, test
rem  npx skills add 대상은 스킬 이름을 함께 넘기는 항목이 있어서 :lane_skills 에 직접 적었다.

rem [claude] 플러그인. 마켓플레이스까지 적어야 같은 이름의 플러그인이 여러 곳에 있어도 의도한 것이 설치된다
set "CLAUDE_MARKETPLACES=freshtechbro/claudedesignskills https://github.com/Yeachan-Heo/oh-my-claudecode DietrichGebert/ponytail ayghri/i-have-adhd"
set "CLAUDE_PLUGINS=oh-my-claudecode@omc ponytail@ponytail i-have-adhd@i-have-adhd"

rem [codex] 플러그인. owner/repo@ref 는 codex plugin marketplace add --ref 로 넘긴다
set "CODEX_MARKETPLACES=ayghri/i-have-adhd@main DietrichGebert/ponytail"
set "CODEX_PLUGINS=i-have-adhd@i-have-adhd ponytail@ponytail"

rem [common]
set "IM_NOT_AI_MARKETPLACE=epoko77-ai/im-not-ai"
set "IM_NOT_AI_PLUGIN=humanize-korean@im-not-ai"
set "ECC_PACKAGE=ecc-universal@2.2.1"
set "ECC_PLUGIN=ecc@ecc"
set "OUROBOROS_INSTALLER_URL=https://raw.githubusercontent.com/Q00/ouroboros/main/scripts/install.ps1"

rem [test]
set "LIBREOFFICE_WINGET_ID=TheDocumentFoundation.LibreOffice"

rem 전역 CLI 설치 위치. nvm 의 node 버전별 폴더가 아니라 여기에 한 번만 설치한다.
set "CLI_PREFIX=%USERPROFILE%\.skills"

rem 작업 함수가 할 일이 없어 건너뛴다는 것을 알릴 때 쓰는 종료 코드. 이유는 SKIP_REASON 에 담는다.
set "SKIPPED=10"

rem 레인 프로세스는 이 스크립트를 __lane 인자로 다시 실행한다
if /i "%~1"=="__lane" goto :lane_entry

call :main %*
set "EXIT_CODE=%ERRORLEVEL%"
chcp %ORIGINAL_CODE_PAGE% >nul
exit /b %EXIT_CODE%


rem ============================================================================
rem  메인
rem ============================================================================

:main
set "IS_DRY_RUN=0"
set "SKIPPED_SECTIONS= "
set "CURRENT_LANE=main"
set "TASK_NUMBER=0"

call :parse_arguments %*
if errorlevel 3 exit /b 0
if errorlevel 2 exit /b 2
call :detect_ai_clis || exit /b 1

set "LOG_DIRECTORY=%TEMP%\ai-setup-%RANDOM%%RANDOM%"
mkdir "%LOG_DIRECTORY%" || exit /b 1
call :print_environment
call :run_lanes

if "%IS_DRY_RUN%"=="1" (
  rmdir /s /q "%LOG_DIRECTORY%"
  echo.
  echo dry-run 이라 설치하지 않았습니다.
  exit /b 0
)
call :print_summary
exit /b

:run_lanes
call :prepare_agent_homes
rem skills 레인보다 먼저 끝나야 npx skills 가 원본을 claude 스킬 폴더에 쓴다
if "%HAS_CLAUDE%"=="1" call :run_task common "skills origin .claude\skills" link_agents_skills_to_claude
if "%HAS_CLAUDE%"=="1" call :start_lane claude
if "%HAS_CODEX%"=="1" call :start_lane codex
call :start_lane npm
call :start_lane skills
call :is_section_skipped test || call :start_lane system
call :is_section_skipped common || call :start_lane shared
call :wait_for_lanes claude codex npm skills system shared
call :run_ecc_setup
exit /b 0


rem ============================================================================
rem  인자, 환경 감지
rem ============================================================================

:print_usage
echo 사용법: install.bat [--dry-run] [--skip ^<섹션^>]...
echo.
echo   (인자 없음)      없는 것은 설치하고 있는 것은 최신으로 갱신, 다시 실행해도 안전
echo   --dry-run       실행할 명령만 출력하고 설치하지 않는다
echo   --skip ^<섹션^>   섹션 제외: claude ^| codex ^| common ^| test, 여러 번 줄 수 있다
echo   -h, --help      도움말
exit /b 0

rem 종료 코드: 0 계속 진행, 2 인자 오류, 3 도움말 출력
:parse_arguments
if "%~1"=="" exit /b 0
if /i "%~1"=="--dry-run" (
  set "IS_DRY_RUN=1"
  shift
  goto :parse_arguments
)
if /i "%~1"=="--skip" (
  call :validate_section "%~2" || exit /b 2
  set "SKIPPED_SECTIONS=%SKIPPED_SECTIONS%%~2 "
  shift
  shift
  goto :parse_arguments
)
if /i "%~1"=="-h" goto :show_usage
if /i "%~1"=="--help" goto :show_usage
echo 오류: 알 수 없는 인자: %~1 1>&2
call :print_usage
exit /b 2

:show_usage
call :print_usage
exit /b 3

:validate_section
if "%~1"=="" (
  echo 오류: --skip 뒤에 섹션 이름이 필요합니다. 1>&2
  exit /b 1
)
for %%S in (claude codex common test) do if /i "%~1"=="%%S" exit /b 0
echo 오류: 알 수 없는 섹션: %~1 - claude ^| codex ^| common ^| test 1>&2
exit /b 1

rem 종료 코드 0 이면 제외한 섹션이다
:is_section_skipped
set "REMAINING_SECTIONS=%SKIPPED_SECTIONS%"
call set "REMAINING_SECTIONS=%%REMAINING_SECTIONS: %~1 =%%"
if "%REMAINING_SECTIONS%"=="%SKIPPED_SECTIONS%" exit /b 1
exit /b 0

:detect_ai_clis
set "HAS_CLAUDE=0"
set "HAS_CODEX=0"
where claude >nul 2>&1 && set "HAS_CLAUDE=1"
where codex >nul 2>&1 && set "HAS_CODEX=1"
if "%HAS_CLAUDE%%HAS_CODEX%"=="00" (
  echo 오류: claude, codex 를 둘 다 찾지 못했습니다. AI CLI 를 먼저 설치하세요. 1>&2
  exit /b 1
)
exit /b 0

:print_environment
echo == AI 개발 환경 세팅 ==
echo OS     : windows
if "%HAS_CLAUDE%"=="1" echo claude : 있음
if "%HAS_CLAUDE%"=="0" echo claude : 없음 - 관련 항목 건너뜀
if "%HAS_CODEX%"=="1" echo codex  : 있음
if "%HAS_CODEX%"=="0" echo codex  : 없음 - 관련 항목 건너뜀
if not "%SKIPPED_SECTIONS%"==" " echo 제외   :%SKIPPED_SECTIONS%
if "%IS_DRY_RUN%"=="1" echo 모드   : dry-run, 설치하지 않음
if "%IS_DRY_RUN%"=="0" echo 로그   : %LOG_DIRECTORY%
echo.
exit /b 0

rem npx skills 는 에이전트를 홈 폴더로 감지한다. CLI 만 설치하고 한 번도 실행하지 않은
rem 새 머신에서도 링크가 걸리도록 미리 만든다.
:prepare_agent_homes
set "CLAUDE_HOME_DIRECTORY=%USERPROFILE%\.claude"
if defined CLAUDE_CONFIG_DIR set "CLAUDE_HOME_DIRECTORY=%CLAUDE_CONFIG_DIR%"
set "CODEX_HOME_DIRECTORY=%USERPROFILE%\.codex"
if defined CODEX_HOME set "CODEX_HOME_DIRECTORY=%CODEX_HOME%"
if "%HAS_CLAUDE%"=="1" if not exist "%CLAUDE_HOME_DIRECTORY%" call :run_command mkdir "%CLAUDE_HOME_DIRECTORY%"
if "%HAS_CODEX%"=="1" if not exist "%CODEX_HOME_DIRECTORY%" call :run_command mkdir "%CODEX_HOME_DIRECTORY%"
exit /b 0

rem Claude 를 스킬 원본으로 둔다. 사용자 홈의 .agents\skills 를 .claude\skills 로 가는 junction 으로 만든다.
rem npx skills 는 원본을 .agents\skills 에 쓰므로 실제 파일은 .claude\skills 에 생기고 Codex 는 junction 을 따라 읽는다.
rem 이미 실제 폴더로 있으면 옮기지 않고 건너뛴다. 이전은 install.sh 에서만 자동으로 한다.
:link_agents_skills_to_claude
set "CLAUDE_SKILLS=%CLAUDE_HOME_DIRECTORY%\skills"
set "AGENTS_SKILLS=%USERPROFILE%\.agents\skills"
if not exist "%CLAUDE_SKILLS%" call :run_command mkdir "%CLAUDE_SKILLS%"
if not exist "%USERPROFILE%\.agents" call :run_command mkdir "%USERPROFILE%\.agents"
if not exist "%AGENTS_SKILLS%" goto :create_agents_skills_junction
dir /AL /B "%USERPROFILE%\.agents" 2>nul | findstr /x /i "skills" >nul && (
  set "SKIP_REASON=이미 연결됨"
  exit /b %SKIPPED%
)
set "SKIP_REASON=.agents\skills 가 실제 폴더라 연결하지 않음. 내용을 .claude\skills 로 옮긴 뒤 다시 실행"
exit /b %SKIPPED%

:create_agents_skills_junction
call :run_command mklink /J "%AGENTS_SKILLS%" "%CLAUDE_SKILLS%"
exit /b


rem ============================================================================
rem  작업 실행, 결과 기록
rem ============================================================================

rem run_command 명령... : 명령을 출력하고 실행한다. dry-run 이면 출력만 한다.
:run_command
echo + %*
if "%IS_DRY_RUN%"=="1" exit /b 0
call %*
exit /b

rem print_status_line 상태 제목 [상세]
:print_status_line
set "STATUS_LABEL=%~1    "
set "STATUS_LABEL=%STATUS_LABEL:~0,4%"
if "%~3"=="" echo   %STATUS_LABEL% [%CURRENT_LANE%] %~2
if not "%~3"=="" echo   %STATUS_LABEL% [%CURRENT_LANE%] %~2 - %~3
exit /b 0

rem record_result OK 또는 SKIP 또는 FAIL, 제목, [상세]
rem 레인마다 결과 파일을 따로 써서 여러 프로세스가 한 파일에 동시에 쓰지 않게 한다.
:record_result
call :print_status_line %1 %2 %3
if "%IS_DRY_RUN%"=="1" exit /b 0
>>"%LOG_DIRECTORY%\%CURRENT_LANE%.results" echo %~1^|%~2^|%~3
exit /b 0

rem run_task 섹션 제목 함수 [인자...]
rem 작업 출력은 작업별 로그 파일로 보내고, 터미널에는 결과 한 줄만 찍는다.
:run_task
call :is_section_skipped %~1 && exit /b 0
set "TASK_TITLE=%~2"
set "TASK_FUNCTION=%~3"
set "SKIP_REASON="
set /a TASK_NUMBER+=1
set "TASK_LOG=%LOG_DIRECTORY%\%CURRENT_LANE%-%TASK_NUMBER%.log"
if "%IS_DRY_RUN%"=="1" goto :run_task_dry_run

call :print_status_line ".." "%TASK_TITLE%"
call :%TASK_FUNCTION% %4 %5 %6 %7 %8 %9 >"%TASK_LOG%" 2>&1 <nul
set "TASK_EXIT_CODE=%ERRORLEVEL%"
if "%TASK_EXIT_CODE%"=="0" (
  call :record_result OK "%TASK_TITLE%" ""
) else if "%TASK_EXIT_CODE%"=="%SKIPPED%" (
  call :record_result SKIP "%TASK_TITLE%" "%SKIP_REASON%"
) else (
  call :record_result FAIL "%TASK_TITLE%" "%TASK_LOG%"
)
exit /b 0

:run_task_dry_run
echo   # %TASK_TITLE%
call :%TASK_FUNCTION% %4 %5 %6 %7 %8 %9
if "%ERRORLEVEL%"=="%SKIPPED%" echo     -^> 건너뜀: %SKIP_REASON%
exit /b 0

rem https://github.com/owner/repo 또는 owner/repo@ref 에서 owner/repo 만 REPOSITORY 에 남긴다
:to_repository
set "REPOSITORY=%~1"
set "REPOSITORY=%REPOSITORY:https://github.com/=%"
for /f "tokens=1 delims=@" %%R in ("%REPOSITORY%") do set "REPOSITORY=%%R"
exit /b 0


rem ============================================================================
rem  레인 공통
rem ============================================================================

rem start_lane 레인 : 레인을 새 cmd 프로세스로 띄운다.
rem 레인이 어떻게 끝나든 레인이름.done 파일이 남도록 cmd 명령줄 끝에서 만든다.
:start_lane
if "%IS_DRY_RUN%"=="1" goto :start_lane_dry_run
type nul >"%LOG_DIRECTORY%\%~1.started"
start "" /b cmd /d /c "call "%SCRIPT_PATH%" __lane %~1 & type nul >"%LOG_DIRECTORY%\%~1.done""
exit /b 0

:start_lane_dry_run
echo.
echo [%~1]
set "CURRENT_LANE=%~1"
call :lane_%~1
set "CURRENT_LANE=main"
exit /b 0

:lane_entry
set "CURRENT_LANE=%~2"
set "TASK_NUMBER=0"
call :lane_%CURRENT_LANE%
exit /b 0

rem wait_for_lanes 레인... : 시작한 레인 중 지정한 레인이 끝날 때까지 기다린다
:wait_for_lanes
for %%L in (%*) do call :wait_for_lane %%L
exit /b 0

:wait_for_lane
if not exist "%LOG_DIRECTORY%\%~1.started" exit /b 0
:wait_for_lane_loop
if exist "%LOG_DIRECTORY%\%~1.done" exit /b 0
rem timeout 명령은 입력이 리다이렉트되면 실패하므로 ping 으로 2초 기다린다
ping -n 3 127.0.0.1 >nul
goto :wait_for_lane_loop


rem ============================================================================
rem  claude 레인
rem ============================================================================

:lane_claude
set "REGISTERED_MARKETPLACES_FILE=%LOG_DIRECTORY%\claude-marketplaces.json"
set "INSTALLED_PLUGINS_FILE=%LOG_DIRECTORY%\claude-plugins.json"
call claude plugin marketplace list --json >"%REGISTERED_MARKETPLACES_FILE%" 2>nul <nul
for %%S in (%CLAUDE_MARKETPLACES%) do call :run_task claude "marketplace %%S" add_claude_marketplace %%S
call :run_task common "marketplace %IM_NOT_AI_MARKETPLACE%" add_claude_marketplace %IM_NOT_AI_MARKETPLACE%
rem 이미 등록돼 있던 마켓플레이스도 최신 목록으로 받아 와야 플러그인 업데이트가 새 버전을 찾는다
call :run_task claude "marketplaces refresh" run_command claude plugin marketplace update
call claude plugin list --json >"%INSTALLED_PLUGINS_FILE%" 2>nul <nul
for %%P in (%CLAUDE_PLUGINS%) do call :run_task claude "plugin %%P" install_or_update_claude_plugin %%P
call :run_task common "plugin %IM_NOT_AI_PLUGIN%" install_or_update_claude_plugin %IM_NOT_AI_PLUGIN%
rem ecc 는 처음에 ecc setup 대화형 설치기로 설치하므로 여기서는 설치돼 있을 때만 갱신한다
call :run_task common "plugin %ECC_PLUGIN%" update_installed_claude_plugin %ECC_PLUGIN%
exit /b 0

:add_claude_marketplace
call :to_repository %1
findstr /i /c:"%REPOSITORY%" "%REGISTERED_MARKETPLACES_FILE%" >nul 2>&1 && (
  set "SKIP_REASON=이미 등록됨"
  exit /b %SKIPPED%
)
call :run_command claude plugin marketplace add %1
exit /b

:install_or_update_claude_plugin
findstr /i /c:"%~1" "%INSTALLED_PLUGINS_FILE%" >nul 2>&1 && (
  call :run_command claude plugin update %1
  exit /b
)
call :run_command claude plugin install %1
exit /b

:update_installed_claude_plugin
findstr /i /c:"%~1" "%INSTALLED_PLUGINS_FILE%" >nul 2>&1 || (
  set "SKIP_REASON=아직 설치 전"
  exit /b %SKIPPED%
)
call :run_command claude plugin update %1
exit /b


rem ============================================================================
rem  codex 레인
rem ============================================================================

:lane_codex
set "REGISTERED_MARKETPLACES_FILE=%LOG_DIRECTORY%\codex-marketplaces.json"
call codex plugin marketplace list --json >"%REGISTERED_MARKETPLACES_FILE%" 2>nul <nul
for %%S in (%CODEX_MARKETPLACES%) do call :run_task codex "marketplace %%S" add_codex_marketplace %%S
call :run_task codex "marketplaces refresh" run_command codex plugin marketplace upgrade
rem codex 에는 plugin update 가 없다. 갱신한 마켓플레이스에서 다시 add 하면 설치든 갱신이든 같은 결과가 된다.
for %%P in (%CODEX_PLUGINS%) do call :run_task codex "plugin %%P" run_command codex plugin add %%P
call :is_section_skipped common || call :record_result SKIP "im-not-ai" "Windows 에서는 Codex 용 설치를 지원하지 않음, upstream 은 WSL 권장"
exit /b 0

:add_codex_marketplace
call :to_repository %1
findstr /i /c:"%REPOSITORY%" "%REGISTERED_MARKETPLACES_FILE%" >nul 2>&1 && (
  set "SKIP_REASON=이미 등록됨"
  exit /b %SKIPPED%
)
set "MARKETPLACE_REF="
for /f "tokens=2 delims=@" %%R in ("%~1") do set "MARKETPLACE_REF=%%R"
if defined MARKETPLACE_REF (
  call :run_command codex plugin marketplace add %REPOSITORY% --ref %MARKETPLACE_REF%
) else (
  call :run_command codex plugin marketplace add %1
)
exit /b


rem ============================================================================
rem  npm 레인: 전역 CLI
rem ============================================================================

:lane_npm
call :run_task test "cli @playwright/cli" install_global_cli @playwright/cli@latest
call :run_task test "playwright browser" prepare_playwright_browser
if "%HAS_CODEX%"=="1" call :run_task codex "cli oh-my-codex" install_global_cli oh-my-codex@latest
exit /b 0

rem 전역 CLI 를 CLI_PREFIX 에 설치한다. @latest 로 설치하므로 이미 있으면 최신으로 갱신된다.
:install_global_cli
call :run_command npm install -g --prefix "%CLI_PREFIX%" %1 || exit /b 1
call :register_cli_prefix_path
exit /b

rem npm 은 Windows 에서 실행 파일을 prefix 폴더에 바로 만든다.
rem node 버전과 상관없이 잡히도록 그 폴더를 사용자 PATH 에 한 번만 추가한다.
rem [Environment]::SetEnvironmentVariable 로 쓰면 PATH 가 REG_SZ 로 바뀌어 기존 항목의 환경 변수가
rem 풀린 경로로 고정된다. 그래서 레지스트리 값을 풀지 않고 읽어 ExpandString 으로 쓰고,
rem 임시 변수를 넣었다 지워서 새로 여는 터미널이 바뀐 PATH 를 받도록 변경 알림만 보낸다.
:register_cli_prefix_path
call :run_command powershell -NoProfile -NonInteractive -Command "$key = 'HKCU:\Environment'; $current = (Get-Item $key).GetValue('Path', '', 'DoNotExpandEnvironmentNames'); if (($current -split ';') -notcontains $env:CLI_PREFIX) { $updated = ($current.TrimEnd(';') + ';' + $env:CLI_PREFIX).TrimStart(';'); Set-ItemProperty -Path $key -Name Path -Value $updated -Type ExpandString; [Environment]::SetEnvironmentVariable('AI_SETUP_REFRESH', '1', 'User'); [Environment]::SetEnvironmentVariable('AI_SETUP_REFRESH', $null, 'User'); 'Added to user PATH: ' + $env:CLI_PREFIX }"
exit /b

rem playwright-cli 스킬은 skills 레인에서 설치하고, 여기서는 브라우저와 기본 설정만 준비한다.
rem playwright-cli install 은 현재 디렉터리를 작업 공간으로 초기화하므로 홈에서 실행한다.
:prepare_playwright_browser
pushd "%USERPROFILE%" || exit /b 1
call :run_command "%CLI_PREFIX%\playwright-cli.cmd" install
set "PLAYWRIGHT_EXIT_CODE=%ERRORLEVEL%"
popd
exit /b %PLAYWRIGHT_EXIT_CODE%


rem ============================================================================
rem  skills 레인
rem ============================================================================

rem npx skills add 는 매번 원본 저장소의 최신 내용을 받아 오므로 설치와 갱신이 같은 명령이다
:lane_skills
call :run_task common "skill anthropics/skills" add_skill_package anthropics/skills docx pdf pptx xlsx
call :run_task common "skill Leonxlnx/unlazy" add_skill_package Leonxlnx/unlazy
call :run_task common "skill tt-a1i/archify" add_skill_package tt-a1i/archify
call :run_task common "skill muthuishere/hand-drawn-diagrams" add_skill_package muthuishere/hand-drawn-diagrams
call :run_task common "skill stablyai/orca" add_skill_package stablyai/orca orca-cli orchestration computer-use
rem 같은 저장소에 있는 개발용 dev 스킬은 받지 않는다
call :run_task test "skill microsoft/playwright-cli" add_skill_package microsoft/playwright-cli playwright-cli
call :run_task test "skill heygen-com/hyperframes" add_skill_package heygen-com/hyperframes
exit /b 0

rem add_skill_package 저장소 [스킬...] : 스킬을 적지 않으면 저장소의 스킬 전부
rem -a 를 주지 않으면 skills CLI 가 감지된 에이전트 전부에 링크한다.
:add_skill_package
set "SKILL_SOURCE=%~1"
set "SKILL_NAMES="
:collect_skill_names
shift
if "%~1"=="" goto :skill_names_collected
set "SKILL_NAMES=%SKILL_NAMES% %~1"
goto :collect_skill_names
:skill_names_collected
if defined SKILL_NAMES (
  call :run_command npx --yes skills add %SKILL_SOURCE% -g -y -s%SKILL_NAMES%
) else (
  call :run_command npx --yes skills add %SKILL_SOURCE% -g -y
)
exit /b


rem ============================================================================
rem  system 레인
rem ============================================================================

:lane_system
where winget >nul 2>&1
if errorlevel 1 (
  call :record_result SKIP "LibreOffice" "winget 이 없습니다. Microsoft Store 의 App Installer 가 필요합니다"
  exit /b 0
)
call :run_task test "LibreOffice (winget)" install_libreoffice
call :record_result SKIP "Korean fonts" "Nanum, Noto CJK 는 winget 패키지가 없음. 맑은 고딕은 Windows 기본 제공"
exit /b 0

:install_libreoffice
winget list -e --id %LIBREOFFICE_WINGET_ID% --accept-source-agreements >nul 2>&1 || goto :install_libreoffice_new
call :run_command winget upgrade -e --id %LIBREOFFICE_WINGET_ID% --silent --accept-package-agreements --accept-source-agreements
rem winget upgrade 는 이미 최신이면 0x8A15002B 로 끝난다. 실패가 아니라 할 일이 없는 것이다.
if "%ERRORLEVEL%"=="-1978335189" (
  set "SKIP_REASON=이미 최신"
  exit /b %SKIPPED%
)
exit /b

:install_libreoffice_new
call :run_command winget install -e --id %LIBREOFFICE_WINGET_ID% --silent --accept-package-agreements --accept-source-agreements
exit /b


rem ============================================================================
rem  shared 레인
rem ============================================================================

rem context-mode 는 설치 후처리에서 Claude 플러그인 목록을 고치고, ouroboros 는 설치 중에
rem claude plugin install 을 실행하므로 claude, codex, npm 레인이 끝난 뒤에 돌린다.
:lane_shared
call :wait_for_lanes claude codex npm
call :run_task common "cli context-mode" install_global_cli context-mode@latest
if "%HAS_CLAUDE%"=="1" (
  call :run_task common "ouroboros" install_ouroboros
) else (
  call :record_result SKIP "ouroboros" "Windows 에서 Codex 런타임은 WSL 2 에서만 지원"
)
exit /b 0

rem 설치기가 이미 설치된 경우 최신으로 올린다.
rem 처음 설치할 때만 런타임을 정해 준다. 다시 설치할 때는 설치기가 config.yaml 의 선택을 유지한다.
rem run_task 가 표준 입력을 nul 로 연결하므로 설치기는 대화형 질문 없이 진행한다.
:install_ouroboros
set "OUROBOROS_INSTALL_RUNTIME="
if not exist "%USERPROFILE%\.ouroboros\config.yaml" set "OUROBOROS_INSTALL_RUNTIME=claude"
call :run_command powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command "irm %OUROBOROS_INSTALLER_URL% | iex"
exit /b


rem ============================================================================
rem  대화형 설치, 결과 요약
rem ============================================================================

rem ecc setup 은 설치 범위와 hook 수준을 묻는 대화형 설치기라 모든 레인이 끝난 뒤 실행한다
:run_ecc_setup
if not "%HAS_CLAUDE%"=="1" exit /b 0
call :is_section_skipped common && exit /b 0
set "CURRENT_LANE=ecc"
rem 이미 설치돼 있으면 claude 레인에서 플러그인 업데이트로 갱신했으므로 대화형 설치를 다시 띄우지 않는다
call claude plugin list --json 2>nul <nul | findstr /i /c:"%ECC_PLUGIN%" >nul && exit /b 0
echo.
echo [ecc] 대화형 설치 - 설치 범위, hook 수준을 묻는다
if "%IS_DRY_RUN%"=="1" (
  call :run_command npx --yes %ECC_PACKAGE% setup
  exit /b 0
)
call npx --yes %ECC_PACKAGE% setup
if errorlevel 1 (
  call :record_result FAIL "%ECC_PACKAGE% setup" "위 출력 참고"
) else (
  call :record_result OK "%ECC_PACKAGE% setup" ""
)
exit /b 0

:print_summary
set "OK_COUNT=0"
set "SKIP_COUNT=0"
set "FAIL_COUNT=0"
for %%F in ("%LOG_DIRECTORY%\*.results") do (
  for /f "usebackq tokens=1 delims=|" %%S in ("%%~F") do (
    if "%%S"=="OK" set /a OK_COUNT+=1
    if "%%S"=="SKIP" set /a SKIP_COUNT+=1
    if "%%S"=="FAIL" set /a FAIL_COUNT+=1
  )
)
echo.
echo == 결과: 성공 %OK_COUNT%, 건너뜀 %SKIP_COUNT%, 실패 %FAIL_COUNT% ==
if "%FAIL_COUNT%"=="0" goto :print_summary_footer
echo.
echo 실패한 작업:
for %%F in ("%LOG_DIRECTORY%\*.results") do (
  for /f "usebackq tokens=1-3 delims=|" %%A in ("%%~F") do (
    if "%%A"=="FAIL" (
      echo   [%%~nF] %%B
      echo     %%C
      if exist "%%C" powershell -NoProfile -Command "Get-Content -LiteralPath '%%C' -Tail 5 -Encoding UTF8 | ForEach-Object { '      ' + $_ }"
    )
  )
)
:print_summary_footer
echo.
echo 전체 로그: %LOG_DIRECTORY%
if not "%OK_COUNT%"=="0" echo 새 플러그인과 스킬은 Claude Code, Codex 를 다시 시작해야 적용됩니다.
if not "%FAIL_COUNT%"=="0" exit /b 1
exit /b 0
