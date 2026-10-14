@echo off
chcp 65001 >nul
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup-mssql-mcp.ps1"
if errorlevel 1 (
    echo.
    echo 오류가 발생했습니다. 위 메시지를 확인하세요.
    pause
)
