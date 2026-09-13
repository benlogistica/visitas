@echo off
REM ===========================================================================
REM  commit_rapido.bat  ·  Sprint 9.32.438
REM ===========================================================================
REM  Atalho pra commit + push de mudancas que NAO mexem no JSON (so HTML/CSS/JS).
REM  Pra atualizacao de DADOS (XLSX novos), use atualizar_dashboard.bat.
REM
REM  MUDOU NESTA VERSAO
REM  Antes o script parava tres vezes: confirmar S/N, digitar a mensagem, e um
REM  Enter no fim. Como a resposta era sempre a mesma, as paradas so' atrasavam
REM  - e o "Ajuste rapido" repetido deixou o historico do git ilegivel.
REM
REM  Agora:
REM    · nao pergunta nada e fecha sozinho quando da' certo
REM    · a mensagem sai da APP_VERSION do index.html, entao o historico passa
REM      a dizer o que cada commit publicou
REM    · SO PARA se der erro - e ai fica aberto ate voce ler
REM
REM  Se quiser uma mensagem propria:  commit_rapido.bat "texto da mensagem"
REM ===========================================================================

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
if exist "index.html" (
    git add index.html >nul 2>&1
)

REM ---- Sprint 9.32.313: valida index.html ANTES de commitar -----------
REM Detecta truncagem (final do arquivo perdido), tags desbalanceadas, etc.
REM Esta e a protecao mais importante do script: sem ela, um arquivo quebrado
REM iria pro ar sem ninguem notar - ainda mais agora que nao ha confirmacao.
if exist "scripts\validate-index.ps1" (
    powershell -ExecutionPolicy Bypass -NoProfile -File "scripts\validate-index.ps1"
    if errorlevel 1 (
        echo.
        echo [ERRO] Validacao do index.html falhou. Commit cancelado.
        echo        Corrija o arquivo antes de tentar de novo.
        pause
        exit /b 1
    )
)

REM ---- Mostra o que vai subir ---------------------------------------
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
    timeout /t 4 >nul
    exit /b 0
)

REM ---- Monta a mensagem ----------------------------------------------
REM Prioridade: 1) o que voce passou na linha de comando
REM             2) a APP_VERSION do index.html
REM             3) data e hora, se as duas falharem
set "MSG=%~1"

if "!MSG!"=="" (
    REM A linha procurada e:   APP_VERSION: '1.0.0-alpha.sprintX',
    REM O delimitador ' separa: [1] antes  [2] a versao  [3] depois
    for /f "tokens=2 delims='" %%v in ('findstr /C:"APP_VERSION: '" index.html 2^>nul') do (
        if not defined VERSAO set "VERSAO=%%v"
    )
    if defined VERSAO set "MSG=Publica !VERSAO!"
)

if "!MSG!"=="" (
    REM Sem versao legivel no arquivo - nao deixa o commit sem identificacao.
    set "MSG=Ajuste rapido %DATE% %TIME:~0,5%"
)

echo Mensagem: !MSG!
echo.

git add .
if errorlevel 1 (
    echo [AVISO] git add . falhou - seguindo com o index.html que ja foi adicionado.
)

git commit -m "!MSG!"
if errorlevel 1 (
    echo.
    echo [ERRO] Falha ao commitar.
    pause
    exit /b 1
)

REM Sprint 9.32.120: git pull --rebase ANTES do push pra evitar "rejected (fetch first)"
REM Acontece quando algum commit foi feito no GitHub web e nao foi baixado aqui.
echo.
echo Sincronizando com o GitHub (pull --rebase)...
git pull --rebase origin main
if errorlevel 1 (
    echo.
    echo [ERRO] Pull falhou! Provavel conflito de merge. Resolva manualmente:
    echo    1^) git status              ^(ver arquivos em conflito^)
    echo    2^) edita os arquivos para resolver
    echo    3^) git add ^<arquivo^>
    echo    4^) git rebase --continue
    echo Ou aborta tudo com: git rebase --abort
    pause
    exit /b 1
)

echo.
echo Enviando pro GitHub...
REM Sprint 9.32.415: se o branch nao tiver upstream (acontece apos reescrita de
REM historico), configura na hora em vez de falhar.
git push
if errorlevel 1 (
    echo   Reconfigurando vinculo com o GitHub...
    git push -u origin main
)
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
echo   !MSG!
echo.
echo   https://www.benlogistica.com.br
echo   (aguarde 1-2 min pro GitHub Pages publicar)
echo.
echo   Fechando...
timeout /t 5 >nul
exit /b 0
