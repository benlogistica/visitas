@echo off
REM ===========================================================================
REM  limpar_historico_git.bat  ·  Sprint 9.32.415
REM ===========================================================================
REM  POR QUE ISTO EXISTE
REM  O faturamento_data_inline.json tem ~20 MB e e' recommitado 2 a 4x por dia.
REM  O git guarda CADA versao para sempre, entao o repositorio ja acumulou 231
REM  versoes do mesmo arquivo = ~700 MB de historico. O site publicado tem so 31 MB.
REM
REM  Quando o repositorio se aproxima de 1 GB, o GitHub Pages fica instavel e
REM  PARA DE PUBLICAR (foi o que aconteceu: 4 commits hoje nao subiram).
REM
REM  ESTE SCRIPT remove as versoes ANTIGAS do JSON do historico, mantendo:
REM    - todos os commits (o historico do codigo fica intacto)
REM    - o JSON atual (o site continua funcionando)
REM  Resultado esperado: ~700 MB  ->  ~30 MB
REM
REM  ATENCAO: reescreve o historico e faz push forcado.
REM  - Faz BACKUP COMPLETO antes (pasta ao lado).
REM  - Se outra pessoa tiver clone do repo, ela precisara clonar de novo.
REM  - Rode com o site fora do horario de pico.
REM ===========================================================================

setlocal EnableDelayedExpansion
title Limpar historico do Git - B^&N Logistica
cd /d "%~dp0"

echo.
echo ======================================================================
echo   LIMPEZA DO HISTORICO DO GIT
echo ======================================================================
echo.
echo   O QUE VAI ACONTECER:
echo     1. Backup completo da pasta (ao lado desta)
echo     2. Remove versoes antigas do JSON do historico do git
echo     3. Recoloca o JSON atual e commita
echo     4. Envia pro GitHub com push forcado
echo.
echo   O historico de commits do CODIGO sera preservado.
echo   O site continuara funcionando normalmente.
echo.
echo   ISTO E IRREVERSIVEL (por isso o backup).
echo.
set /p CONF="Digite CONFIRMO para prosseguir: "
if /I not "!CONF!"=="CONFIRMO" (
    echo.
    echo   Cancelado. Nada foi alterado.
    pause
    exit /b 0
)

REM ---- [1/7] Checagens ---------------------------------------------------
echo.
echo [1/7] Verificando ambiente...
if not exist ".git" (
    echo   [ERRO] Esta pasta nao e um repositorio Git.
    pause
    exit /b 1
)
if not exist "faturamento_data_inline.json" (
    echo   [ERRO] faturamento_data_inline.json nao encontrado.
    pause
    exit /b 1
)
git --version >nul 2>&1
if errorlevel 1 ( echo   [ERRO] Git nao encontrado no PATH. & pause & exit /b 1 )
python --version >nul 2>&1
if errorlevel 1 ( echo   [ERRO] Python nao encontrado no PATH. & pause & exit /b 1 )

REM Nao pode haver alteracoes pendentes
for /f %%i in ('git status --porcelain 2^>nul ^| find /c /v ""') do set PEND=%%i
if not "!PEND!"=="0" (
    echo.
    echo   [ATENCAO] Existem alteracoes nao commitadas.
    echo   Rode o commit_rapido.bat ou o atualizar_dashboard.bat ANTES desta limpeza.
    echo.
    git status -s
    pause
    exit /b 1
)
echo   OK.

REM ---- [2/7] Backup ------------------------------------------------------
echo.
echo [2/7] Criando backup completo...
for /f "tokens=1-3 delims=/ " %%a in ('date /t') do set DT=%%c-%%b-%%a
for /f "tokens=1-2 delims=: " %%a in ('time /t') do set HR=%%a%%b
set BKP=..\nutricionais-visitas-BACKUP-!DT!-!HR!
echo   Destino: !BKP!
xcopy /E /I /H /Y /Q "." "!BKP!" >nul
if errorlevel 1 (
    echo   [ERRO] Falha ao criar backup. Abortando por seguranca.
    pause
    exit /b 1
)
echo   Backup criado com sucesso.

REM ---- [3/7] git-filter-repo --------------------------------------------
echo.
echo [3/7] Verificando git-filter-repo...
python -c "import git_filter_repo" >nul 2>&1
if errorlevel 1 (
    echo   Instalando git-filter-repo...
    python -m pip install --quiet git-filter-repo
    if errorlevel 1 (
        echo   [ERRO] Nao consegui instalar. Rode manualmente:
        echo          python -m pip install git-filter-repo
        pause
        exit /b 1
    )
)
echo   OK.

REM ---- [4/7] Guarda o JSON atual e o remote ------------------------------
echo.
echo [4/7] Preservando o JSON atual...
copy /Y "faturamento_data_inline.json" "%TEMP%\fat_atual.json" >nul
for /f "tokens=*" %%u in ('git remote get-url origin') do set REMOTO=%%u
echo   Remote: !REMOTO!

REM ---- [5/7] Remove o JSON do historico ---------------------------------
echo.
echo [5/7] Removendo versoes antigas do JSON do historico...
echo   (pode levar alguns minutos)
python -m git_filter_repo --path faturamento_data_inline.json --invert-paths --force
if errorlevel 1 (
    echo.
    echo   [ERRO] Falha ao reescrever o historico.
    echo   Seu backup esta em: !BKP!
    pause
    exit /b 1
)
echo   Historico reescrito.

REM ---- [6/7] Recoloca o JSON e commita ----------------------------------
echo.
echo [6/7] Recolocando o JSON atual...
copy /Y "%TEMP%\fat_atual.json" "faturamento_data_inline.json" >nul
git remote remove origin >nul 2>&1
git remote add origin "!REMOTO!"
git add faturamento_data_inline.json
git commit -m "Restaura faturamento (historico do JSON enxugado)" >nul
if errorlevel 1 (
    echo   [AVISO] Nada a commitar - seguindo.
)

REM ---- [7/7] Limpeza + push forcado -------------------------------------
echo.
echo [7/7] Compactando e enviando pro GitHub...
git reflog expire --expire=now --all >nul 2>&1
git gc --prune=now --aggressive
git push origin main --force
if errorlevel 1 (
    echo.
    echo   [ERRO] Push falhou. O repositorio LOCAL ja esta limpo.
    echo   Tente manualmente:  git push origin main --force
    pause
    exit /b 1
)

echo.
echo ======================================================================
echo   CONCLUIDO
echo ======================================================================
for /f %%s in ('powershell -NoProfile -Command "'{0:N0}' -f ((Get-ChildItem .git -Recurse -File ^| Measure-Object Length -Sum).Sum/1MB)"') do echo   Tamanho do .git agora: %%s MB
echo   Backup preservado em: !BKP!
echo.
echo   PROXIMOS PASSOS:
echo     1. Abra o site e confirme que carrega normalmente.
echo     2. Se estiver tudo certo, pode apagar o backup depois de uns dias.
echo.
pause
