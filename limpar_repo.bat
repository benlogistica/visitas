@echo off
REM limpar_repo.bat — Remove do GitHub o que foi enviado por engano.
REM Os arquivos continuam na sua pasta local, so saem do tracking do git.
REM Roda UMA vez. Depois disso, o .gitignore garante que nao acontece de novo.

setlocal EnableDelayedExpansion
title Limpar repo - Nutricionais

cd /d "%~dp0"

echo.
echo ======================================================================
echo   LIMPEZA DE ARQUIVOS PESADOS DO REPO
echo ======================================================================
echo.
echo Vai remover do GitHub (NAO da sua pasta local) os seguintes itens:
echo   - DESIGN DO PROJETO/   (zips pesados, so design)
echo   - entrada/*.xlsx       (dados sensiveis de faturamento)
echo   - bckps/               (backups)
echo   - logs/                (logs)
echo   - migrar_para_json_separado.py (script one-shot)
echo.
echo Os arquivos continuam na sua pasta intactos.
echo.
set /p CONFIRMA="Confirma? (S/N): "
if /i not "!CONFIRMA!"=="S" (
    echo.
    echo Cancelado.
    pause
    exit /b 0
)

echo.
echo Removendo do tracking do git...
echo.

git rm -r --cached "DESIGN DO PROJETO" 2>nul
git rm -r --cached "entrada" 2>nul
git rm -r --cached "bckps" 2>nul
git rm -r --cached "logs" 2>nul
git rm --cached "migrar_para_json_separado.py" 2>nul

REM Re-adiciona o que deve ficar (caso tenha entrada/COLE_OS_XLSX_AQUI.txt)
if exist "entrada\COLE_OS_XLSX_AQUI.txt" (
    git add -f "entrada\COLE_OS_XLSX_AQUI.txt"
)

REM Adiciona o .gitignore
git add .gitignore

echo.
echo ----------------------------------------------------------------------
echo Resumo do que vai ser commitado:
echo ----------------------------------------------------------------------
git status --short
echo ----------------------------------------------------------------------
echo.

set /p CONF2="Continuar com commit + push? (S/N): "
if /i not "!CONF2!"=="S" (
    echo.
    echo Cancelado. Use 'git reset' pra desfazer o stage.
    pause
    exit /b 0
)

git commit -m "Limpa repo: remove pastas pesadas e dados sensiveis (gitignore)"
git push

echo.
echo ======================================================================
echo   LIMPEZA CONCLUIDA
echo ======================================================================
echo.
echo Os arquivos continuam na sua pasta local. So sairam do GitHub.
echo A partir de agora, .gitignore garante que esses itens nao voltam.
echo.
pause
exit /b 0
