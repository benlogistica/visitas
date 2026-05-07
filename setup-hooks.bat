@echo off
REM ===================================================================
REM setup-hooks.bat
REM Configura git pra usar os hooks da pasta .githooks/ (versionados no repo).
REM Rode UMA vez apos clonar o repositorio.
REM ===================================================================

setlocal
title Setup hooks - B^&N Logistica

cd /d "%~dp0"

echo.
echo ======================================================================
echo   Configurando git hooks (.githooks)
echo ======================================================================
echo.

REM Checa Git
git --version >nul 2>&1
if errorlevel 1 (
  echo [ERRO] Git nao encontrado no PATH!
  pause
  exit /b 1
)

REM Checa repositorio
if not exist ".git" (
  echo [ERRO] Esta pasta nao e um repositorio Git!
  pause
  exit /b 1
)

REM Checa que a pasta de hooks existe
if not exist ".githooks\pre-commit" (
  echo [ERRO] .githooks\pre-commit nao encontrado!
  pause
  exit /b 1
)

REM Aponta git pra usar a pasta versionada
git config core.hooksPath .githooks
if errorlevel 1 (
  echo [ERRO] Falha ao configurar core.hooksPath
  pause
  exit /b 1
)

echo [OK] Hook configurado.
echo.
echo Agora, todo "git commit" vai validar o index.html antes.
echo Se o arquivo estiver truncado/corrompido, o commit eh bloqueado.
echo.
echo Para testar manualmente:
echo   powershell -ExecutionPolicy Bypass -File scripts\validate-index.ps1
echo.
echo Para desativar (nao recomendado):
echo   git config --unset core.hooksPath
echo.
pause
exit /b 0
