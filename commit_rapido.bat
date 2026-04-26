@echo off
REM commit_rapido.bat
REM Atalho pra commit + push de mudancas que NAO mexem no JSON (so HTML/CSS/JS).
REM Pra atualizacao de DADOS (XLSX novos), use atualizar_dashboard.bat.

setlocal EnableDelayedExpansion
title Commit rapido - Nutricionais

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
echo   git add . && git commit -m "!MSG!" && git push
echo ======================================================================
echo.

git add .
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
echo   https://nutricionais.github.io/nutricionais-visitas
echo   (aguarde 1-2 min pro GitHub Pages publicar)
echo.
pause
exit /b 0
