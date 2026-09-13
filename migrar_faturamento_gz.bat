@echo off
REM ===========================================================================
REM  migrar_faturamento_gz.bat  ·  Sprint 9.32.426  ·  RODAR UMA VEZ SO
REM ===========================================================================
REM  POR QUE ISTO EXISTE
REM  O faturamento_data_inline.json tem 20,5 MB e entra no git 2x por dia.
REM  O git guarda CADA versao para sempre, entao o repositorio crescia cerca
REM  de 41 MB por dia. Perto de 1 GB o GitHub Pages PARA de publicar — foi
REM  exatamente o que aconteceu em 06/09/2026.
REM
REM  A partir de agora so o arquivo COMPRIMIDO (.json.gz, 1,9 MB) vai pro
REM  repositorio. Crescimento cai de 41 MB/dia para menos de 4.
REM
REM  Este script destrava o arquivo cru do git. So o .gitignore nao bastava:
REM  ele nao vale para arquivo que ja esta sendo rastreado.
REM
REM  IMPORTANTE: o .json continua na sua maquina, intacto. So deixa de ser
REM  enviado pro GitHub. Nada e apagado.
REM ===========================================================================

setlocal EnableDelayedExpansion
title Migrar faturamento para comprimido - B^&N Logistica
cd /d "%~dp0"

echo.
echo ======================================================================
echo   MIGRAR FATURAMENTO PARA COMPRIMIDO
echo ======================================================================
echo.

REM ---- Checagens -------------------------------------------------------
if not exist "faturamento_data_inline.json" (
    echo   [ERRO] faturamento_data_inline.json nao encontrado.
    echo   Rode o atualizar_dashboard.bat antes.
    pause
    exit /b 1
)
if not exist "faturamento_data_inline.json.gz" (
    echo   [AVISO] O comprimido ainda nao existe. Gerando agora...
    python atualizar_index.py
    if errorlevel 1 (
        echo   [ERRO] Falha ao gerar o comprimido.
        pause
        exit /b 1
    )
)

for %%A in (faturamento_data_inline.json)    do set /a CRU=%%~zA/1048576
for %%A in (faturamento_data_inline.json.gz) do set /a GZ=%%~zA/1048576

echo   Arquivo cru ........ !CRU! MB  (sai do repositorio, fica na maquina)
echo   Comprimido ......... !GZ! MB  (passa a ser o publicado)
echo.

REM ---- Destrava o arquivo cru -------------------------------------------
echo [1/3] Tirando o arquivo cru do controle do git...
git rm --cached faturamento_data_inline.json >nul 2>&1
if errorlevel 1 (
    echo   [OK] Ja estava fora do controle do git.
) else (
    echo   [OK] Destravado. O arquivo continua na pasta.
)

REM ---- Commit ------------------------------------------------------------
echo.
echo [2/3] Registrando a mudanca...
git add .gitignore index.html atualizar_index.py atualizar_dashboard.bat faturamento_data_inline.json.gz
git commit -m "Faturamento passa a ser publicado comprimido (20,5 MB -> 1,9 MB)"
if errorlevel 1 (
    echo   [AVISO] Nada a commitar — talvez ja tenha rodado antes.
)

REM ---- Push --------------------------------------------------------------
echo.
echo [3/3] Enviando pro GitHub...
git push
if errorlevel 1 (
    echo   Reconfigurando vinculo com o GitHub...
    git push -u origin main
    if errorlevel 1 (
        echo   [ERRO] Push falhou. Tente manualmente: git push -u origin main
        pause
        exit /b 1
    )
)

echo.
echo ======================================================================
echo   CONCLUIDO
echo ======================================================================
echo.
echo   A partir de agora o atualizar_dashboard.bat envia so o comprimido.
echo   Voce NAO precisa rodar este script de novo.
echo.
echo   TESTE AGORA: abra o site e entre na tela de Faturamento.
echo   Se os graficos carregarem, esta tudo certo.
echo.
echo   Se a tela der erro, o caminho de volta e:
echo     git revert HEAD ^&^& git push
echo.
pause
