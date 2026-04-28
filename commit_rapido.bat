@echo off
REM commit_rapido.bat
REM Atalho pra commit + push de mudancas que NAO mexem no JSON (so HTML/CSS/JS).
REM Pra atualizacao de DADOS (XLSX novos), use atualizar_dashboard.bat.

setlocal EnableDelayedExpansion
title Commit rapido - B^&N Logistica

cd /d "%~dp0"

echo.
echo ======================================================================
echo   COMMIT RAPIDO - so HTML/CSS/JS (sem regenerar JSON)
echo ======================================================================
echo.

REM ---- Checa Git -----------------------------------------------------
git --version >nul 2>&1
if errorlevel 1 (
    echo [ERRO] Git nao encontrado no PATH!
    pause
    exit /b 1
)

REM ---- Checa repositorio --------------------------------------------
if not exist ".git" (
    echo [ERRO] Esta pasta nao e um repositorio Git!
    pause
    exit /b 1
)

REM ---- Limpa index.lock orfao (Sprint 9.32.110) ---------------------
REM Erro classico: "Unable to create '.git/index.lock': File exists"
REM Acontece quando uma operacao git anterior travou/morreu sem limpar.
if exist ".git\index.lock" (
    echo [AVISO] Encontrei um .git\index.lock orfao - vou tentar remover.
    REM Verifica se ha algum processo git.exe rodando
    tasklist /FI "IMAGENAME eq git.exe" 2>nul | find /I "git.exe" >nul
    if not errorlevel 1 (
        echo [ERRO] Tem um processo git.exe rodando ainda! Feche-o antes de continuar.
        echo        Veja com: tasklist ^| findstr git
        pause
        exit /b 1
    )
    del ".git\index.lock" >nul 2>&1
    if exist ".git\index.lock" (
        echo [ERRO] Nao consegui apagar .git\index.lock - permissao?
        pause
        exit /b 1
    )
    echo [OK] Lock removido. Continuando...
    echo.
)

REM ---- Sprint 9.32.110: garante que index.html sempre entra ----------
REM Mesmo que git status diga "nada mudou" no index.html, forcamos o add.
REM (git add num arquivo sem mudanca e' no-op silencioso, sem erro.)
if exist "index.html" (
    git add index.html >nul 2>&1
)

REM ---- Mostra o que mudou -------------------------------------------
echo Mudancas pendentes:
echo ----------------------------------------------------------------------
git status --short
echo ----------------------------------------------------------------------
echo.

REM ---- Verifica se ha algo pra commitar -----------------------------
for /f %%i in ('git status --short ^| find /c /v ""') do set MUDANCAS=%%i
if %MUDANCAS%==0 (
    echo [OK] Nada mudou. Nenhum commit necessario.
    echo.
    pause
    exit /b 0
)

REM ---- Confirma antes ------------------------------------------------
echo.
set /p CONF="Confirma o commit desses arquivos? (S/N): "
if /i not "!CONF!"=="S" (
    echo.
    echo Cancelado.
    pause
    exit /b 0
)

REM ---- Pega mensagem do commit --------------------------------------
echo.
set /p MSG="Mensagem do commit (Enter pra usar 'Ajuste rapido'): "
if "!MSG!"=="" set MSG=Ajuste rapido

echo.
echo ======================================================================
echo   git add . ^&^& git commit -m "!MSG!" ^&^& git push
echo ======================================================================
echo.

git add .
if errorlevel 1 (
    echo [AVISO] git add . falhou - tentando commitar so o index.html que ja foi adicionado.
)

git commit -m "!MSG!"
if errorlevel 1 (
    echo.
    echo [AVISO] Falha ao commitar. Pode ser que nao ha nada pra commitar.
    pause
    exit /b 1
)

echo.
echo Enviando pro GitHub...
git push
if errorlevel 1 (
    echo.
    echo [ERRO] Push falhou! Verifique sua conexao e autenticacao.
    pause
    exit /b 1
)

echo.
echo ======================================================================
echo   SUCESSO! Mudancas no ar.
echo ======================================================================
echo.
echo   https://benlogistica.github.io/visitas
echo   (aguarde 1-2 min pro GitHub Pages publicar)
echo.
pause
exit /b 0
