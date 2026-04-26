@echo off
REM Atualizador de Dashboard Nutricionais
REM Le XLSX do Omie, gera JSON, atualiza index.html e faz push pro GitHub

setlocal EnableDelayedExpansion
title Atualizador Dashboard Nutricionais

cd /d "%~dp0"

echo.
echo ======================================================================
echo   ATUALIZADOR DE DASHBOARD NUTRICIONAIS
echo ======================================================================
echo.

REM ---- [1/6] Checa Python ------------------------------------------------
echo [1/6] Verificando Python...
python --version >nul 2>&1
if errorlevel 1 (
    echo.
    echo [ERRO] Python nao encontrado no PATH!
    echo   Instale em: https://www.python.org/downloads/
    echo   IMPORTANTE: marque "Add Python to PATH" na instalacao
    echo.
    pause
    exit /b 1
)
python --version
echo.

REM ---- [2/6] Checa Git ---------------------------------------------------
echo [2/6] Verificando Git...
git --version >nul 2>&1
if errorlevel 1 (
    echo.
    echo [ERRO] Git nao encontrado no PATH!
    echo   Instale em: https://git-scm.com/download/win
    echo.
    pause
    exit /b 1
)
git --version
echo.

REM ---- [3/6] Checa dependencias Python -----------------------------------
echo [3/6] Verificando dependencias Python...
python -c "import pandas, openpyxl" >nul 2>&1
if errorlevel 1 (
    echo   Instalando dependencias ^(pode levar 1-2 minutos^)...
    python -m pip install --quiet pandas openpyxl
    if errorlevel 1 (
        echo [ERRO] Falha ao instalar dependencias
        pause
        exit /b 1
    )
)
echo   OK pandas + openpyxl
echo.

REM ---- [4/6] Checa repositorio Git ---------------------------------------
echo [4/6] Verificando repositorio Git local...
if not exist "index.html" (
    echo.
    echo [ERRO] Nao encontrei index.html nesta pasta!
    echo.
    echo Certifique-se que voce esta rodando este .bat de DENTRO
    echo da pasta onde voce clonou o repo nutricionais-visitas.
    echo.
    echo Pasta atual: %CD%
    echo.
    pause
    exit /b 1
)
if not exist ".git" (
    echo.
    echo [ERRO] Esta pasta nao e um repositorio Git!
    echo   Pasta atual: %CD%
    echo.
    pause
    exit /b 1
)
echo   OK repositorio Git encontrado
echo.

REM ---- [5/6] Encontra XLSX ----------------------------------------------
echo [5/6] Procurando XLSX na pasta entrada...
if not exist "entrada" mkdir entrada

set FOUND=0
set XLSX_LIST=
for %%f in (entrada\*.xlsx) do (
    set /a FOUND+=1
    set XLSX_LIST=!XLSX_LIST! "entrada\%%~nxf"
    echo   ^> %%~nxf
)

if %FOUND%==0 (
    echo.
    echo [AVISO] Nenhum XLSX encontrado em entrada!
    echo.
    echo Coloque os arquivos .xlsx do Omie em:
    echo   %CD%\entrada\
    echo.
    echo Depois rode este .bat novamente.
    echo.
    pause
    exit /b 1
)
echo   Total: %FOUND% arquivo^(s^)
echo.

REM ---- [6/6] Gera JSON ---------------------------------------------------
echo ======================================================================
echo   Gerando JSON atualizado...
echo ======================================================================
python gerar_faturamento_json.py %XLSX_LIST%
if errorlevel 1 (
    echo.
    echo [ERRO] Falha ao gerar JSON. Verifique os arquivos XLSX.
    pause
    exit /b 1
)
echo.

REM ---- Atualiza index.html -----------------------------------------------
echo ======================================================================
echo   Atualizando index.html...
echo ======================================================================
python atualizar_index.py
if errorlevel 1 (
    echo [ERRO] Falha ao atualizar index.html
    pause
    exit /b 1
)
echo.

REM ---- Commit + Push -----------------------------------------------------
echo ======================================================================
echo   Enviando para o GitHub...
echo ======================================================================
echo.

REM Pega periodo do JSON gerado pra usar na mensagem de commit
for /f "usebackq delims=" %%p in (`python -c "import json; d=json.load(open('faturamento_data_inline.json',encoding='utf-8')); print(d['meta']['periodo_inicio']+' a '+d['meta']['periodo_fim'])"`) do set PERIODO=%%p

echo   Arquivos modificados:
git status --short index.html faturamento_data_inline.json
echo.

git add index.html faturamento_data_inline.json
git commit -m "Sync faturamento: %PERIODO%"
if errorlevel 1 (
    echo.
    echo [AVISO] Nada para commitar ^(dados nao mudaram^).
    goto :fim_sucesso
)

echo.
echo   Enviando pro GitHub...
git push
if errorlevel 1 (
    echo.
    echo [ERRO] Push falhou!
    echo.
    echo Possiveis causas:
    echo   1^) Autenticacao GitHub nao configurada
    echo   2^) Sem permissao no repositorio
    echo   3^) Sem conexao com internet
    echo.
    pause
    exit /b 1
)

:fim_sucesso
echo.
echo ======================================================================
echo   SUCESSO! Dashboard atualizado!
echo ======================================================================
echo.
echo   Periodo: %PERIODO%
echo.
echo   Acesse o dashboard em:
echo   https://nutricionais.github.io/nutricionais-visitas
echo.
echo   ^(Aguarde 1-2 minutos pro GitHub Pages publicar^)
echo.

REM Faz backup dos XLSX em logs\ano-mes-dia\
for /f "tokens=1-3 delims=/- " %%a in ("%date%") do (
    set DIA=%%a
    set MES=%%b
    set ANO=%%c
)
set LOG_DIR=logs\%ANO%-%MES%-%DIA%
if not exist "%LOG_DIR%" mkdir "%LOG_DIR%"
copy /Y entrada\*.xlsx "%LOG_DIR%\" >nul 2>&1
echo   Backup dos XLSX em: %LOG_DIR%
echo   ^(arquivos mantidos em entrada\ pro proximo sync^)
echo.

pause
exit /b 0
