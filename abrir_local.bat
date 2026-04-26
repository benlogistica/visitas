@echo off
REM ============================================================
REM  abrir_local.bat
REM  Sobe servidor HTTP local e abre o app no navegador.
REM  Necessario porque o navegador bloqueia fetch em file://
REM ============================================================

setlocal EnableDelayedExpansion
title Servidor Local Nutricionais

cd /d "%~dp0"

echo.
echo ======================================================================
echo   SERVIDOR LOCAL - DASHBOARD NUTRICIONAIS
echo ======================================================================
echo.

REM ---- Verifica se index.html existe ----
if not exist "index.html" (
    echo [ERRO] index.html nao encontrado em %CD%
    echo.
    echo Coloque este .bat na mesma pasta do index.html
    echo.
    pause
    exit /b 1
)

REM ---- Verifica Python ----
python --version >nul 2>&1
if errorlevel 1 (
    echo [ERRO] Python nao encontrado no PATH
    echo Instale em: https://www.python.org/downloads/
    pause
    exit /b 1
)

REM ---- Define porta (8765 - bem unica, dificil estar em uso) ----
set PORTA=8765

REM ---- Mata processo anterior na mesma porta (se houver) ----
echo Verificando se porta %PORTA% esta livre...
for /f "tokens=5" %%p in ('netstat -ano ^| findstr :%PORTA% ^| findstr LISTENING') do (
    echo   Matando processo antigo PID %%p
    taskkill /F /PID %%p >nul 2>&1
)
echo.

REM ---- Mostra informacoes ----
echo ======================================================================
echo   Servidor rodando em: http://localhost:%PORTA%
echo ======================================================================
echo.
echo   Abrindo navegador automaticamente em 2 segundos...
echo.
echo   IMPORTANTE:
echo     - DEIXE ESTA JANELA ABERTA enquanto usar o app
echo     - Pra parar: feche esta janela ou Ctrl+C
echo     - Pra recarregar mudancas: Ctrl+Shift+R no navegador
echo.
echo ======================================================================
echo.

REM ---- Abre o navegador depois de 2s (em paralelo) ----
start "" /B cmd /C "timeout /t 2 /nobreak >nul && start http://localhost:%PORTA%/index.html"

REM ---- Sobe o servidor (bloqueia ate fechar o terminal) ----
python -m http.server %PORTA%

REM ---- Se chegou aqui, servidor fechou ----
echo.
echo Servidor encerrado.
pause
