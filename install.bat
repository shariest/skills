@echo off
setlocal EnableExtensions DisableDelayedExpansion

rem ============================================================================
rem  AI agent dev environment setup for Windows. macOS and Linux use install.sh.
rem
rem  Detects the installed AI CLIs (claude, codex) and handles only what they need. Idempotent:
rem  missing items are installed and existing ones are updated to the latest version.
rem  See install.bat --help for usage. Install principles and lane rules match the install.sh header.
rem  Each lane runs in its own cmd process and leaves LANE.done when it finishes so that
rem  other lanes and the main process can wait on that file.
rem
rem  This file must stay ASCII only. cmd misreads line boundaries of batch files that contain
rem  multi-byte characters, which can execute fragments of lines as commands.
rem
rem  Differences from install.sh
rem   - skills origin: .agents\skills is a junction (not a symlink) to .claude\skills.
rem                    An existing real .agents\skills folder is left alone and reported.
rem   - global CLIs  : npm on Windows puts executables directly in the prefix folder,
rem                    so that folder is added to the user PATH once instead of linking.
rem   - im-not-ai    : the upstream installer needs bash and symlinks, so it is installed as a Claude plugin.
rem                    The Codex variant is skipped because upstream recommends WSL. No im-not-ai lane.
rem   - ouroboros    : uses the official PowerShell installer install.ps1. The Codex runtime needs WSL 2
rem                    on Windows, so it is installed only when claude exists.
rem   - LibreOffice  : installed with winget. Nanum and Noto CJK fonts have no winget package.
rem ============================================================================

set "SCRIPT_PATH=%~f0"

rem -- install list ------------------------------------------------------------
rem  sections: claude - needs claude, codex - needs codex, common - needs either, test
rem  npx skills add targets live in :lane_skills because some entries pass skill names.

rem [claude] plugins. Naming the marketplace picks the intended plugin when names collide.
set "CLAUDE_MARKETPLACES=freshtechbro/claudedesignskills https://github.com/Yeachan-Heo/oh-my-claudecode DietrichGebert/ponytail ayghri/i-have-adhd"
set "CLAUDE_PLUGINS=oh-my-claudecode@omc ponytail@ponytail i-have-adhd@i-have-adhd"

rem [codex] plugins. owner/repo@ref is passed as codex plugin marketplace add --ref
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

rem Global CLI prefix. Installed once here instead of under each nvm node version.
set "CLI_PREFIX=%USERPROFILE%\.skills"

rem Exit code a task returns when there is nothing to do. The reason goes to SKIP_REASON.
set "SKIPPED=10"

rem Lane processes run this script again with the __lane argument
if /i "%~1"=="__lane" goto :lane_entry

call :main %*
set "EXIT_CODE=%ERRORLEVEL%"
exit /b %EXIT_CODE%


rem ============================================================================
rem  main
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
  echo Dry run: nothing was installed.
  exit /b 0
)
call :print_summary
exit /b

:run_lanes
call :prepare_agent_homes
rem Must finish before the skills lane so that npx skills writes into the claude skills folder
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
rem  arguments and environment
rem ============================================================================

:print_usage
echo Usage: install.bat [--dry-run] [--skip ^<section^>]...
echo.
echo   (no arguments)     install what is missing and update what exists, safe to rerun
echo   --dry-run          print the commands without installing anything
echo   --skip ^<section^>   skip a section: claude ^| codex ^| common ^| test, repeatable
echo   -h, --help         show this help
exit /b 0

rem Exit codes: 0 continue, 2 argument error, 3 help printed
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
echo Error: unknown argument: %~1 1>&2
call :print_usage
exit /b 2

:show_usage
call :print_usage
exit /b 3

:validate_section
if "%~1"=="" (
  echo Error: --skip needs a section name. 1>&2
  exit /b 1
)
for %%S in (claude codex common test) do if /i "%~1"=="%%S" exit /b 0
echo Error: unknown section: %~1 - claude ^| codex ^| common ^| test 1>&2
exit /b 1

rem Exit code 0 means the section is skipped
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
  echo Error: neither claude nor codex was found. Install an AI CLI first. 1>&2
  exit /b 1
)
exit /b 0

:print_environment
echo == AI dev environment setup ==
echo OS     : windows
if "%HAS_CLAUDE%"=="1" echo claude : found
if "%HAS_CLAUDE%"=="0" echo claude : not found - related items skipped
if "%HAS_CODEX%"=="1" echo codex  : found
if "%HAS_CODEX%"=="0" echo codex  : not found - related items skipped
if not "%SKIPPED_SECTIONS%"==" " echo skip   :%SKIPPED_SECTIONS%
if "%IS_DRY_RUN%"=="1" echo mode   : dry run, nothing is installed
if "%IS_DRY_RUN%"=="0" echo logs   : %LOG_DIRECTORY%
echo.
exit /b 0

rem npx skills detects agents by their home folders. Create them so that links are made even
rem on a new machine where the CLI was installed but never started.
:prepare_agent_homes
set "CLAUDE_HOME_DIRECTORY=%USERPROFILE%\.claude"
if defined CLAUDE_CONFIG_DIR set "CLAUDE_HOME_DIRECTORY=%CLAUDE_CONFIG_DIR%"
set "CODEX_HOME_DIRECTORY=%USERPROFILE%\.codex"
if defined CODEX_HOME set "CODEX_HOME_DIRECTORY=%CODEX_HOME%"
if "%HAS_CLAUDE%"=="1" if not exist "%CLAUDE_HOME_DIRECTORY%" call :run_command mkdir "%CLAUDE_HOME_DIRECTORY%"
if "%HAS_CODEX%"=="1" if not exist "%CODEX_HOME_DIRECTORY%" call :run_command mkdir "%CODEX_HOME_DIRECTORY%"
exit /b 0

rem Make Claude the skills origin: user .agents\skills becomes a junction to .claude\skills.
rem npx skills writes into .agents\skills, so files land in .claude\skills and Codex reads them through the junction.
rem An existing real folder is not moved. Only install.sh migrates automatically.
:link_agents_skills_to_claude
set "CLAUDE_SKILLS=%CLAUDE_HOME_DIRECTORY%\skills"
set "AGENTS_SKILLS=%USERPROFILE%\.agents\skills"
if not exist "%CLAUDE_SKILLS%" call :run_command mkdir "%CLAUDE_SKILLS%"
if not exist "%USERPROFILE%\.agents" call :run_command mkdir "%USERPROFILE%\.agents"
if not exist "%AGENTS_SKILLS%" goto :create_agents_skills_junction
dir /AL /B "%USERPROFILE%\.agents" 2>nul | findstr /x /i "skills" >nul && (
  set "SKIP_REASON=already linked"
  exit /b %SKIPPED%
)
set "SKIP_REASON=.agents\skills is a real folder, not linked. Move its contents to .claude\skills and rerun"
exit /b %SKIPPED%

:create_agents_skills_junction
call :run_command mklink /J "%AGENTS_SKILLS%" "%CLAUDE_SKILLS%"
exit /b


rem ============================================================================
rem  task execution and results
rem ============================================================================

rem run_command CMD... : print and run a command. Only print it in dry run.
:run_command
echo + %*
if "%IS_DRY_RUN%"=="1" exit /b 0
call %*
exit /b

rem print_status_line STATUS TITLE [DETAIL]
:print_status_line
set "STATUS_LABEL=%~1    "
set "STATUS_LABEL=%STATUS_LABEL:~0,4%"
if "%~3"=="" echo   %STATUS_LABEL% [%CURRENT_LANE%] %~2
if not "%~3"=="" echo   %STATUS_LABEL% [%CURRENT_LANE%] %~2 - %~3
exit /b 0

rem record_result OK or SKIP or FAIL, TITLE, [DETAIL]
rem Each lane writes its own result file so that processes never write one file at once.
:record_result
call :print_status_line %1 %2 %3
if "%IS_DRY_RUN%"=="1" exit /b 0
>>"%LOG_DIRECTORY%\%CURRENT_LANE%.results" echo %~1^|%~2^|%~3
exit /b 0

rem run_task SECTION TITLE FUNCTION [ARGS...]
rem Task output goes to a per-task log file. The terminal gets one result line.
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
if "%ERRORLEVEL%"=="%SKIPPED%" echo     -^> skipped: %SKIP_REASON%
exit /b 0

rem Keep only owner/repo from https://github.com/owner/repo or owner/repo@ref in REPOSITORY
:to_repository
set "REPOSITORY=%~1"
set "REPOSITORY=%REPOSITORY:https://github.com/=%"
for /f "tokens=1 delims=@" %%R in ("%REPOSITORY%") do set "REPOSITORY=%%R"
exit /b 0


rem ============================================================================
rem  lane helpers
rem ============================================================================

rem start_lane LANE : run a lane in a new cmd process.
rem LANE.done is created at the end of the cmd command line so it exists however the lane ends.
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

rem wait_for_lanes LANE... : wait until the given lanes that were started have finished
:wait_for_lanes
for %%L in (%*) do call :wait_for_lane %%L
exit /b 0

:wait_for_lane
if not exist "%LOG_DIRECTORY%\%~1.started" exit /b 0
:wait_for_lane_loop
if exist "%LOG_DIRECTORY%\%~1.done" exit /b 0
rem timeout fails when input is redirected, so ping waits 2 seconds instead
ping -n 3 127.0.0.1 >nul
goto :wait_for_lane_loop


rem ============================================================================
rem  claude lane
rem ============================================================================

:lane_claude
set "REGISTERED_MARKETPLACES_FILE=%LOG_DIRECTORY%\claude-marketplaces.json"
set "INSTALLED_PLUGINS_FILE=%LOG_DIRECTORY%\claude-plugins.json"
call claude plugin marketplace list --json >"%REGISTERED_MARKETPLACES_FILE%" 2>nul <nul
for %%S in (%CLAUDE_MARKETPLACES%) do call :run_task claude "marketplace %%S" add_claude_marketplace %%S
call :run_task common "marketplace %IM_NOT_AI_MARKETPLACE%" add_claude_marketplace %IM_NOT_AI_MARKETPLACE%
rem Refresh registered marketplaces too, otherwise plugin update cannot see new versions
call :run_task claude "marketplaces refresh" run_command claude plugin marketplace update
call claude plugin list --json >"%INSTALLED_PLUGINS_FILE%" 2>nul <nul
for %%P in (%CLAUDE_PLUGINS%) do call :run_task claude "plugin %%P" install_or_update_claude_plugin %%P
call :run_task common "plugin %IM_NOT_AI_PLUGIN%" install_or_update_claude_plugin %IM_NOT_AI_PLUGIN%
rem ecc is first installed by the interactive ecc setup, so here it is only updated when present
call :run_task common "plugin %ECC_PLUGIN%" update_installed_claude_plugin %ECC_PLUGIN%
exit /b 0

:add_claude_marketplace
call :to_repository %1
findstr /i /c:"%REPOSITORY%" "%REGISTERED_MARKETPLACES_FILE%" >nul 2>&1 && (
  set "SKIP_REASON=already registered"
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
  set "SKIP_REASON=not installed yet"
  exit /b %SKIPPED%
)
call :run_command claude plugin update %1
exit /b


rem ============================================================================
rem  codex lane
rem ============================================================================

:lane_codex
set "REGISTERED_MARKETPLACES_FILE=%LOG_DIRECTORY%\codex-marketplaces.json"
call codex plugin marketplace list --json >"%REGISTERED_MARKETPLACES_FILE%" 2>nul <nul
for %%S in (%CODEX_MARKETPLACES%) do call :run_task codex "marketplace %%S" add_codex_marketplace %%S
call :run_task codex "marketplaces refresh" run_command codex plugin marketplace upgrade
rem codex has no plugin update. Adding again from the refreshed marketplace installs or updates.
for %%P in (%CODEX_PLUGINS%) do call :run_task codex "plugin %%P" run_command codex plugin add %%P
call :is_section_skipped common || call :record_result SKIP "im-not-ai" "not supported for Codex on Windows, upstream recommends WSL"
exit /b 0

:add_codex_marketplace
call :to_repository %1
findstr /i /c:"%REPOSITORY%" "%REGISTERED_MARKETPLACES_FILE%" >nul 2>&1 && (
  set "SKIP_REASON=already registered"
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
rem  npm lane: global CLIs
rem ============================================================================

:lane_npm
call :run_task test "cli @playwright/cli" install_global_cli @playwright/cli@latest
call :run_task test "playwright browser" prepare_playwright_browser
if "%HAS_CODEX%"=="1" call :run_task codex "cli oh-my-codex" install_global_cli oh-my-codex@latest
exit /b 0

rem Install a global CLI into CLI_PREFIX. @latest updates it when it already exists.
:install_global_cli
call :run_command npm install -g --prefix "%CLI_PREFIX%" %1 || exit /b 1
call :register_cli_prefix_path
exit /b

rem npm on Windows puts executables directly in the prefix folder.
rem Add that folder to the user PATH once so the CLIs work with any node version.
rem [Environment]::SetEnvironmentVariable writes PATH as REG_SZ and freezes variables in existing
rem entries. So the raw value is read unexpanded and written back as ExpandString, and a
rem temporary variable is set and removed only to broadcast the change to new terminals.
:register_cli_prefix_path
call :run_command powershell -NoProfile -NonInteractive -Command "$key = 'HKCU:\Environment'; $current = (Get-Item $key).GetValue('Path', '', 'DoNotExpandEnvironmentNames'); if (($current -split ';') -notcontains $env:CLI_PREFIX) { $updated = ($current.TrimEnd(';') + ';' + $env:CLI_PREFIX).TrimStart(';'); Set-ItemProperty -Path $key -Name Path -Value $updated -Type ExpandString; [Environment]::SetEnvironmentVariable('AI_SETUP_REFRESH', '1', 'User'); [Environment]::SetEnvironmentVariable('AI_SETUP_REFRESH', $null, 'User'); 'Added to user PATH: ' + $env:CLI_PREFIX }"
exit /b

rem The playwright-cli skill is installed in the skills lane. This only prepares the browser and config.
rem playwright-cli install initializes the current folder as a workspace, so it runs from home.
:prepare_playwright_browser
pushd "%USERPROFILE%" || exit /b 1
call :run_command "%CLI_PREFIX%\playwright-cli.cmd" install
set "PLAYWRIGHT_EXIT_CODE=%ERRORLEVEL%"
popd
exit /b %PLAYWRIGHT_EXIT_CODE%


rem ============================================================================
rem  skills lane
rem ============================================================================

rem npx skills add fetches the latest source every time, so install and update are the same command
:lane_skills
call :run_task common "skill anthropics/skills" add_skill_package anthropics/skills docx pdf pptx xlsx
call :run_task common "skill Leonxlnx/unlazy" add_skill_package Leonxlnx/unlazy
call :run_task common "skill tt-a1i/archify" add_skill_package tt-a1i/archify
call :run_task common "skill muthuishere/hand-drawn-diagrams" add_skill_package muthuishere/hand-drawn-diagrams
call :run_task common "skill stablyai/orca" add_skill_package stablyai/orca orca-cli orchestration computer-use
rem Skip the dev skill that lives in the same repository
call :run_task test "skill microsoft/playwright-cli" add_skill_package microsoft/playwright-cli playwright-cli
call :run_task test "skill heygen-com/hyperframes" add_skill_package heygen-com/hyperframes
exit /b 0

rem add_skill_package REPOSITORY [SKILLS...] : without skill names every skill in the repository
rem Without -a the skills CLI links to every detected agent.
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
rem  system lane
rem ============================================================================

:lane_system
where winget >nul 2>&1
if errorlevel 1 (
  call :record_result SKIP "LibreOffice" "winget not found. App Installer from the Microsoft Store is required"
  exit /b 0
)
call :run_task test "LibreOffice (winget)" install_libreoffice
call :record_result SKIP "Korean fonts" "Nanum and Noto CJK have no winget package. Malgun Gothic ships with Windows"
exit /b 0

:install_libreoffice
winget list -e --id %LIBREOFFICE_WINGET_ID% --accept-source-agreements >nul 2>&1 || goto :install_libreoffice_new
call :run_command winget upgrade -e --id %LIBREOFFICE_WINGET_ID% --silent --accept-package-agreements --accept-source-agreements
rem winget upgrade ends with 0x8A15002B when already up to date. That is not a failure.
if "%ERRORLEVEL%"=="-1978335189" (
  set "SKIP_REASON=already up to date"
  exit /b %SKIPPED%
)
exit /b

:install_libreoffice_new
call :run_command winget install -e --id %LIBREOFFICE_WINGET_ID% --silent --accept-package-agreements --accept-source-agreements
exit /b


rem ============================================================================
rem  shared lane
rem ============================================================================

rem context-mode edits the Claude plugin list in its postinstall and ouroboros runs
rem claude plugin install, so they run after the claude, codex and npm lanes.
:lane_shared
call :wait_for_lanes claude codex npm
call :run_task common "cli context-mode" install_global_cli context-mode@latest
if "%HAS_CLAUDE%"=="1" (
  call :run_task common "ouroboros" install_ouroboros
) else (
  call :record_result SKIP "ouroboros" "the Codex runtime needs WSL 2 on Windows"
)
exit /b 0

rem The installer upgrades an existing installation.
rem The runtime is chosen only on first install. Later runs keep the choice in config.yaml.
rem run_task connects stdin to nul, so the installer runs without questions.
:install_ouroboros
set "OUROBOROS_INSTALL_RUNTIME="
if not exist "%USERPROFILE%\.ouroboros\config.yaml" set "OUROBOROS_INSTALL_RUNTIME=claude"
call :run_command powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command "irm %OUROBOROS_INSTALLER_URL% | iex"
exit /b


rem ============================================================================
rem  interactive install and summary
rem ============================================================================

rem ecc setup asks for install scope and hook level, so it runs after all lanes
:run_ecc_setup
if not "%HAS_CLAUDE%"=="1" exit /b 0
call :is_section_skipped common && exit /b 0
set "CURRENT_LANE=ecc"
rem Already installed means the claude lane updated it, so the interactive setup is not shown again
call claude plugin list --json 2>nul <nul | findstr /i /c:"%ECC_PLUGIN%" >nul && exit /b 0
echo.
echo [ecc] interactive install - asks for install scope and hook level
if "%IS_DRY_RUN%"=="1" (
  call :run_command npx --yes %ECC_PACKAGE% setup
  exit /b 0
)
call npx --yes %ECC_PACKAGE% setup
if errorlevel 1 (
  call :record_result FAIL "%ECC_PACKAGE% setup" "see the output above"
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
echo == Result: ok %OK_COUNT%, skipped %SKIP_COUNT%, failed %FAIL_COUNT% ==
if "%FAIL_COUNT%"=="0" goto :print_summary_footer
echo.
echo Failed tasks:
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
echo Logs: %LOG_DIRECTORY%
if not "%OK_COUNT%"=="0" echo Restart Claude Code and Codex to load new plugins and skills.
if not "%FAIL_COUNT%"=="0" exit /b 1
exit /b 0
