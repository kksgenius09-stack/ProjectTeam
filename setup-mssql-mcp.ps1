$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

$repoDir = $PSScriptRoot
$mssqlDir = Join-Path $env:USERPROFILE ".mssql-mcp-server"

Write-Host ""
Write-Host "=== mssql MCP (읽기전용 DB 연결) 설정 ==="
Write-Host ""

if (-not (Test-Path $mssqlDir)) {
    New-Item -ItemType Directory -Path $mssqlDir | Out-Null
}

$envJsonPath = Join-Path $mssqlDir "environments.json"

if (Test-Path $envJsonPath) {
    Write-Host "[건너뜀] environments.json 이미 존재함: $envJsonPath"
} else {
    $envFilePath = (Join-Path $mssqlDir ".env").Replace('\', '/')
    $templatePath = Join-Path $repoDir "mssql-setup\environments.json"
    if (-not (Test-Path $templatePath)) {
        Write-Host "[오류] 템플릿 파일을 찾을 수 없습니다: $templatePath"
        Write-Host "이 스크립트는 ProjectTeam 저장소 폴더 안에서 실행해야 합니다."
        Read-Host "계속하려면 Enter를 누르세요"
        exit 1
    }
    $content = Get-Content -Raw $templatePath
    $content = $content.Replace('REPLACED_AT_INSTALL_TIME', $envFilePath)
    Set-Content -Path $envJsonPath -Value $content -Encoding UTF8
    Write-Host "[생성] $envJsonPath"
}

$envFile = Join-Path $mssqlDir ".env"

if (Test-Path $envFile) {
    Write-Host "[건너뜀] .env 이미 존재함: $envFile (비밀번호 변경이 필요하면 이 파일을 직접 수정하세요)"
} else {
    Write-Host "DB 읽기전용 계정(aceexsis) 비밀번호를 입력하세요."
    Write-Host "(비밀번호는 담당자에게 별도로 전달받으세요 - 이 저장소에는 포함되어 있지 않습니다)"
    $securePwd = Read-Host -Prompt "비밀번호" -AsSecureString
    $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePwd)
    $plainPwd = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
    [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    Set-Content -Path $envFile -Value "MSSQL_PASSWORD=$plainPwd" -Encoding UTF8
    Write-Host "[생성] $envFile"
}

$logsDir = Join-Path $mssqlDir "logs"

Write-Host ""
Write-Host "Claude Code에 mssql MCP 서버를 등록합니다..."
claude mcp add -s user mssql -e "ENVIRONMENTS_CONFIG_PATH=$envJsonPath" -e "AUDIT_LOG_PATH=$logsDir" -- npx -y "@connorbritain/mssql-mcp-reader@latest"

Write-Host ""
Write-Host "완료되었습니다. Claude Code를 재시작하면 mssql MCP 연결이 적용됩니다."
Write-Host ""
Read-Host "계속하려면 Enter를 누르세요"
