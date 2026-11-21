@echo off
setlocal
cd /d "%~dp0"
where node >nul 2>&1
if errorlevel 1 (
    echo Instale o Node.js 24 LTS antes de iniciar o RODX Menu.
    pause
    exit /b 1
)
node -e "const [major,minor]=process.versions.node.split('.').map(Number);process.exit(major>22||(major===22&&minor>=12)?0:1)"
if errorlevel 1 (
    echo Versao de Node.js incompativel. Use Node.js 24 LTS.
    pause
    exit /b 1
)
if not exist node_modules\.bin\next.cmd (
    echo Instalando dependencias locais do RODX Menu...
    call npm.cmd ci --no-audit --no-fund --prefer-offline
    if errorlevel 1 (
        echo A instalacao nao foi concluida. Veja as mensagens acima.
        pause
        exit /b 1
    )
)
echo Acesse http://localhost:3000 quando aparecer Ready.
call npm.cmd run dev
pause
