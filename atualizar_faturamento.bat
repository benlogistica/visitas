@echo off
setlocal enabledelayedexpansion

REM ============================================================
REM  Atualizar Faturamento - Nutricionais Visitas (v2)
REM  Detecta mes/ano via PowerShell (mais confiavel que wmic)
REM  Ignora arquivos temporarios do Excel (~$*.xlsx)
REM ============================================================

set "ORIGEM=C:\Users\Edu\OneDrive\Paula"
set "DESTINO=C:\Users\Edu\Documents\nutricionais-visitas\entrada"
set "PREFIXO=faturamento - "

REM ----- Detectar mes/ano via PowerShell -----
for /f "delims=" %%a in ('powershell -NoProfile -Command "Get-Date -Format MM"') do set "mm=%%a"
for /f "delims=" %%a in ('powershell -NoProfile -Command "Get-Date -Format yy"') do set "aa=%%a"

if "!mm!"=="" (
    echo [ERRO] Nao foi possivel detectar o mes atual.
    pause
    exit /b 1
)

if "!mm!"=="01" set "mes=janeiro"
if "!mm!"=="02" set "mes=fevereiro"
if "!mm!"=="03" set "mes=marco"
if "!mm!"=="04" set "mes=abril"
if "!mm!"=="05" set "mes=maio"
if "!mm!"=="06" set "mes=junho"
if "!mm!"=="07" set "mes=julho"
if "!mm!"=="08" set "mes=agosto"
if "!mm!"=="09" set "mes=setembro"
if "!mm!"=="10" set "mes=outubro"
if "!mm!"=="11" set "mes=novembro"
if "!mm!"=="12" set "mes=dezembro"

echo.
echo ============================================================
echo  Mes detectado : !mes! (!mm!/20!aa!)
echo  Origem        : !ORIGEM!
echo  Destino       : !DESTINO!
echo ============================================================
echo.

REM ----- Verificar pasta origem -----
if not exist "!ORIGEM!" (
    echo [ERRO] Pasta origem nao encontrada.
    pause
    exit /b 1
)

REM ----- Pegar o arquivo Excel mais recente (ignora temp ~$) -----
set "ULTIMO="
pushd "!ORIGEM!"
for /f "delims=" %%f in ('dir /b /o-d /a-d *.xls* 2^>nul ^| findstr /v /b /c:"~$" /c:"~"') do (
    if not defined ULTIMO set "ULTIMO=%%f"
)
popd

if not defined ULTIMO (
    echo [ERRO] Nenhum arquivo Excel valido encontrado em:
    echo        !ORIGEM!
    pause
    exit /b 1
)

REM ----- Manter a extensao original do arquivo -----
for %%x in ("!ULTIMO!") do set "EXT=%%~xx"

set "NOME_FINAL=!PREFIXO!!mes!!aa!!EXT!"

echo Arquivo origem : !ULTIMO!
echo Nome destino   : !NOME_FINAL!
echo.

REM ----- Criar pasta destino se necessario -----
if not exist "!DESTINO!" mkdir "!DESTINO!"

REM ----- Copiar com substituicao -----
copy /Y "!ORIGEM!\!ULTIMO!" "!DESTINO!\!NOME_FINAL!" >nul

if !errorlevel! equ 0 (
    echo [OK] Arquivo copiado com sucesso para:
    echo      !DESTINO!\!NOME_FINAL!
) else (
    echo [ERRO] Falha ao copiar o arquivo.
    pause
    exit /b 1
)

echo.

endlocal
