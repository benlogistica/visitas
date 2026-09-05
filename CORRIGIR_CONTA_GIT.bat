@echo off
chcp 65001 >nul
cd /d "%~dp0"

echo ============================================
echo   Corrigir a conta do GitHub deste projeto
echo ============================================
echo.
echo Com mais de uma conta GitHub salva no Windows, o git
echo abre uma janela perguntando qual usar. No agendador de
echo tarefas nao ha ninguem para clicar, e a tarefa trava.
echo.
echo Esta correcao grava a conta na URL do repositorio.
echo Roda uma vez so e vale para TODOS os .bat desta pasta.
echo.

echo --- Antes ---
git remote -v
echo.

git remote set-url origin https://nutricionais@github.com/benlogistica/visitas.git
git config credential.username nutricionais

echo --- Depois ---
git remote -v
echo.
echo ============================================
echo   Pronto. Pode fechar.
echo ============================================
echo.
timeout /t 10 >nul
