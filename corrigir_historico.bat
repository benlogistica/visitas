@echo off
REM corrigir_historico.bat
REM Remove o commit que continha a Groq API Key vazada do historico local,
REM mantendo o conteudo atual dos arquivos (ja sem a chave).
REM
REM ESTRATEGIA:
REM   1. Backup do estado atual em uma branch
REM   2. git reset --soft origin/main  -> volta o HEAD pro ultimo commit pushado,
REM      mas mantem as mudancas no staging
REM   3. git commit novo -> reune tudo num commit limpo (sem o b6a63a2 no meio)
REM   4. git push --force-with-lease -> envia o historico limpo
REM
REM PRE-REQUISITO: voce JA REVOGOU a chave antiga em https://console.groq.com/keys

setlocal EnableDelayedExpansion
title Corrigir historico - remover chave vazada

cd /d "%~dp0"

echo.
echo ======================================================================
echo   CORRIGIR HISTORICO - remover commit com Groq API Key vazada
echo ======================================================================
echo.

REM ---- Checa Git -----------------------------------------------------
git --version >nul 2>&1
if errorlevel 1 (
    echo [ERRO] Git nao encontrado no PATH!
    pause
    exit /b 1
)

if not exist ".git" (
    echo [ERRO] Esta pasta nao e um repositorio Git!
    pause
    exit /b 1
)

REM ---- Mostra estado atual ------------------------------------------
echo Estado atual:
echo ----------------------------------------------------------------------
git log --oneline origin/main..HEAD
echo ----------------------------------------------------------------------
echo.
echo HEAD atual:
git rev-parse HEAD
echo.
echo origin/main:
git rev-parse origin/main
echo.
echo ======================================================================
echo   O que vai acontecer:
echo ======================================================================
echo   1. Backup do estado atual em branch 'backup-pre-corrigir-DATA'
echo   2. Reset --soft pra origin/main (volta o ponteiro, mantem arquivos)
echo   3. Commit novo de tudo sem o commit poluido no meio
echo   4. Force-push (with-lease, mais seguro)
echo.
echo   Os ARQUIVOS atuais nao serao alterados. So o historico local muda.
echo ======================================================================
echo.

set /p CONF="Confirma? (digite SIM em maiusculo pra continuar): "
if /i not "!CONF!"=="SIM" (
    echo.
    echo Cancelado. Nada foi alterado.
    pause
    exit /b 0
)

REM ---- 1) Backup --------------------------------------------------------
REM Pega data/hora via PowerShell (wmic foi removido do Win11)
for /f %%a in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd-HHmmss"') do set DT=%%a
if "%DT%"=="" set DT=manual
set BACKUP_BRANCH=backup-pre-corrigir-%DT%
echo.
echo [1/4] Criando backup em branch: %BACKUP_BRANCH%
git branch %BACKUP_BRANCH%
if errorlevel 1 (
    echo [ERRO] Nao consegui criar backup. Abortando.
    pause
    exit /b 1
)
echo [OK] Backup criado.

REM ---- 2) Reset --soft pra origin/main ----------------------------------
echo.
echo [2/4] Reset --soft pra origin/main (mantendo arquivos)...
git reset --soft origin/main
if errorlevel 1 (
    echo [ERRO] Reset falhou. Voce pode restaurar com: git reset --hard %BACKUP_BRANCH%
    pause
    exit /b 1
)
echo [OK] Ponteiro voltou pra origin/main, arquivos preservados no staging.

REM ---- 3) Garantir que index.html limpo esta no staging -----------------
echo.
echo [3/4] Adicionando arquivos ao staging...
git add -A
if errorlevel 1 (
    echo [AVISO] git add -A falhou.
)

echo.
echo Mudancas que vao no commit novo:
echo ----------------------------------------------------------------------
git status --short
echo ----------------------------------------------------------------------
echo.

REM ---- Verifica que index.html nao tem mais a chave ---------------------
findstr /C:"gsk_5pSEF" index.html >nul 2>&1
if not errorlevel 1 (
    echo [ERRO CRITICO] index.html AINDA contem a chave! Nao vou commitar.
    echo Restaure com: git reset --hard %BACKUP_BRANCH%
    pause
    exit /b 1
)
echo [OK] index.html esta limpo (sem a chave).

REM ---- Commit ----------------------------------------------------------
echo.
echo Mensagem do commit:
set MSG=Sprint 9.32.199 - mic Groq Whisper (chave configuravel via Configuracoes)
echo "%MSG%"
echo.

git commit -m "%MSG%"
if errorlevel 1 (
    echo [ERRO] Commit falhou. Voce pode restaurar com: git reset --hard %BACKUP_BRANCH%
    pause
    exit /b 1
)
echo [OK] Commit limpo criado.

REM ---- 4) Force-push with-lease ----------------------------------------
echo.
echo [4/4] Enviando pro GitHub (force-push with-lease)...
echo.
echo IMPORTANTE: --force-with-lease so vai dar push se NINGUEM tiver feito
echo commit no GitHub depois do seu ultimo pull. Se alguem fez, ele recusa
echo (te protege de sobrescrever o trabalho do outro).
echo.

git push --force-with-lease origin main
if errorlevel 1 (
    echo.
    echo [ERRO] Push falhou.
    echo.
    echo Possiveis causas:
    echo   - Alguem fez commit no GitHub depois do seu ultimo pull
    echo   - Conexao
    echo   - Autenticacao
    echo.
    echo Pra restaurar o estado anterior:
    echo   git reset --hard %BACKUP_BRANCH%
    echo.
    pause
    exit /b 1
)

echo.
echo ======================================================================
echo   SUCESSO! Historico limpo, chave removida, push feito.
echo ======================================================================
echo.
echo   Backup do estado anterior: %BACKUP_BRANCH%
echo   (pode apagar com: git branch -D %BACKUP_BRANCH% quando tiver certeza)
echo.
echo   Site no ar em ~1-2 min:
echo   https://benlogistica.github.io/visitas
echo.
pause
exit /b 0
