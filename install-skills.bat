@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion

set "REPO_DIR=%~dp0"
set "REPO_DIR=%REPO_DIR:~0,-1%"
set "SKILLS_SRC=%REPO_DIR%\skills"
set "CLAUDE_SKILLS_DIR=%USERPROFILE%\.claude\skills"

if not exist "%CLAUDE_SKILLS_DIR%" (
    mkdir "%CLAUDE_SKILLS_DIR%"
)

echo.
echo === Claude Code 스킬 설치/연결 ===
echo 저장소 위치: %SKILLS_SRC%
echo 연결 위치:   %CLAUDE_SKILLS_DIR%
echo.

for /d %%S in ("%SKILLS_SRC%\*") do (
    set "NAME=%%~nxS"
    set "TARGET=%CLAUDE_SKILLS_DIR%\!NAME!"
    set "SKIP=0"
    set "IS_JUNCTION=0"

    if exist "!TARGET!" (
        dir "!TARGET!" 2>nul | findstr /C:"<JUNCTION>" >nul 2>&1
        if !errorlevel! == 0 (
            set "IS_JUNCTION=1"
        ) else (
            set "SKIP=1"
        )
    )

    if "!SKIP!"=="1" (
        echo [건너뜀] !NAME! - 이미 일반 폴더/파일로 존재함. 수동 확인 필요: !TARGET!
    ) else (
        if "!IS_JUNCTION!"=="1" (
            rmdir "!TARGET!"
        )
        mklink /J "!TARGET!" "%%~fS" >nul
        if !errorlevel! == 0 (
            echo [연결완료] !NAME!
        ) else (
            echo [실패] !NAME! 연결 중 오류 발생
        )
    )
)

echo.
echo 완료되었습니다. 이후 이 폴더에서 "git pull"만 실행하면 스킬이 최신 버전으로 자동 반영됩니다.
echo.
pause
