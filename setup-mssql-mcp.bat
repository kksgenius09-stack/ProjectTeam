@echo off
chcp 65001 >nul
setlocal

set "REPO_DIR=%~dp0"
set "REPO_DIR=%REPO_DIR:~0,-1%"
set "MSSQL_DIR=%USERPROFILE%\.mssql-mcp-server"

echo.
echo === mssql MCP (읽기전용 DB 연결) 설정 ===
echo.

if not exist "%MSSQL_DIR%" (
    mkdir "%MSSQL_DIR%"
)

if exist "%MSSQL_DIR%\environments.json" (
    echo [건너뜀] environments.json 이미 존재함: %MSSQL_DIR%\environments.json
) else (
    set "ENV_PATH=%MSSQL_DIR%\.env"
    set "ENV_PATH=%ENV_PATH:\=/%"
    powershell -NoProfile -Command "(Get-Content -Raw '%REPO_DIR%\mssql-setup\environments.json') -replace 'REPLACED_AT_INSTALL_TIME', '%ENV_PATH%' | Set-Content -Encoding UTF8 '%MSSQL_DIR%\environments.json'"
    echo [생성] %MSSQL_DIR%\environments.json
)

if exist "%MSSQL_DIR%\.env" (
    echo [건너뜀] .env 이미 존재함: %MSSQL_DIR%\.env ^(비밀번호 변경이 필요하면 이 파일을 직접 수정하세요^)
) else (
    echo DB 읽기전용 계정(aceexsis) 비밀번호를 입력하세요.
    echo ^(비밀번호는 담당자에게 별도로 전달받으세요 - 이 저장소에는 포함되어 있지 않습니다^)
    set /p MSSQL_PWD=비밀번호:
    echo MSSQL_PASSWORD=%MSSQL_PWD%> "%MSSQL_DIR%\.env"
    echo [생성] %MSSQL_DIR%\.env
)

echo.
echo Claude Code에 mssql MCP 서버를 등록합니다...
claude mcp add -s user mssql -e "ENVIRONMENTS_CONFIG_PATH=%MSSQL_DIR%\environments.json" -e "AUDIT_LOG_PATH=%MSSQL_DIR%\logs" -- npx -y @connorbritain/mssql-mcp-reader@latest

echo.
echo 완료되었습니다. Claude Code를 재시작하면 mssql MCP 연결이 적용됩니다.
echo.
pause
