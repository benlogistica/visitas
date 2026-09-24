@echo off
REM Sprint 9.32.466: tira do historico do GitHub as versoes antigas ABERTAS
REM do faturamento e as planilhas (nome, CPF/CNPJ e compras de clientes).
REM A logica toda esta em limpar_historico_dados.py (faz backup antes).
title Limpar historico de dados - B^&N Logistica
cd /d "%~dp0"
python limpar_historico_dados.py
if errorlevel 1 pause
