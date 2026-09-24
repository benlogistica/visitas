#!/usr/bin/env python3
"""
limpar_historico_dados.py — Sprint 9.32.466

POR QUE ISTO EXISTE
  O site é publicado pelo GitHub, e o repositório guarda TODAS as versões de
  tudo que já foi commitado. Mesmo depois de o faturamento passar a ir cifrado,
  quem clonar o repositório ainda baixa as versões antigas ABERTAS, com nome,
  CPF/CNPJ e compras de clientes:
    - faturamento_data_inline.json / .json.gz (todas as versões)
    - faturamento_dados.js, clientes_lista.json, bckps/clientes_lista.json
    - planilhas do Omie em entrada/ e logs/
    - o index.html de 23 a 26/04/2026, que trazia o faturamento embutido

O QUE FAZ
  1. Confere que não há nada pendente de commit.
  2. Faz backup completo da pasta (ao lado desta).
  3. Reescreve o histórico removendo esses arquivos e trocando o bloco de
     faturamento embutido do index.html antigo por um bloco vazio.
  4. Confere que sumiram e envia pro GitHub com push forçado.

O que NÃO muda: o site atual, o código, os commits (só mudam os identificadores),
e os arquivos locais fora do git (faturamento.key, o .json, as planilhas).

Uso:  python limpar_historico_dados.py          (ou dê dois cliques no .bat)
      python limpar_historico_dados.py --sem-push   (só limpa local, para testar)
"""
import datetime
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

CAMINHOS = [
    'faturamento_data_inline.json',
    'faturamento_data_inline.json.gz',
    'faturamento_dados.js',
    'clientes_lista.json',
    'bckps/clientes_lista.json',
]
GLOBS = ['entrada/*.xlsx', 'entrada/*.xlsm', 'entrada/*.xls', 'logs/*']
# index.html de abril/2026 trazia o faturamento inteiro dentro do HTML
TROCA_TEXTO = b"regex:const FATURAMENTO_DATA_INLINE = `[^`]*`;==>const FATURAMENTO_DATA_INLINE = `{}`;\n"
# arquivos locais (fora do git) que precisam continuar existindo
PRESERVAR = ['faturamento.key', 'faturamento_data_inline.json']


def git(*args, check=True, capture=True):
    r = subprocess.run(['git', *args], capture_output=capture, text=True)
    if check and r.returncode != 0:
        print(f"❌ git {' '.join(args)} falhou:\n{r.stderr}")
        sys.exit(1)
    return (r.stdout or '').strip()


def parar(msg):
    print(msg)
    input('\nAperte Enter para sair...')
    sys.exit(1)


def main():
    sem_push = '--sem-push' in sys.argv
    os.chdir(Path(__file__).resolve().parent)
    if not Path('.git').exists():
        parar('❌ Esta pasta não é um repositório git.')

    pend = git('status', '--porcelain')
    if pend:
        print(pend)
        parar('❌ Há alterações não commitadas. Rode o commit_rapido.bat antes.')

    print('=' * 70)
    print('  LIMPEZA DO HISTÓRICO — dados de clientes')
    print('=' * 70)
    print('  Remove do histórico do GitHub as versões antigas ABERTAS do')
    print('  faturamento e as planilhas. O site atual não muda.')
    print('  Reescreve o histórico e faz push forçado (por isso o backup).')
    print()
    if not sem_push and input('Digite CONFIRMO para prosseguir: ').strip().upper() != 'CONFIRMO':
        print('Cancelado. Nada foi alterado.')
        return

    # 1) backup completo
    carimbo = datetime.datetime.now().strftime('%Y-%m-%d-%H%M')
    bkp = Path('..') / f'nutricionais-visitas-BACKUP-{carimbo}'
    print(f'\n[1/5] Backup completo em {bkp.resolve()} ...')
    # logs/ (2,5 GB de cópias das planilhas) fica fora: está fora do git e a
    # limpeza não encosta nele.
    shutil.copytree('.', bkp, symlinks=True, ignore=shutil.ignore_patterns('logs'))
    print('      OK')

    # 2) git-filter-repo
    print('\n[2/5] Verificando git-filter-repo...')
    if subprocess.run([sys.executable, '-c', 'import git_filter_repo']).returncode != 0:
        if subprocess.run([sys.executable, '-m', 'pip', 'install', '--quiet', 'git-filter-repo']).returncode != 0:
            parar('❌ Não consegui instalar. Rode: python -m pip install git-filter-repo')
    print('      OK')

    remoto = git('remote', 'get-url', 'origin', check=False)
    guardados = {}
    for nome in PRESERVAR:
        if Path(nome).exists():
            dst = Path(tempfile.gettempdir()) / f'bn_preservar_{nome}'
            shutil.copy2(nome, dst)
            guardados[nome] = dst

    # 3) reescreve
    print('\n[3/5] Reescrevendo o histórico (pode levar alguns minutos)...')
    troca = Path(tempfile.gettempdir()) / 'bn_troca_texto.txt'
    troca.write_bytes(TROCA_TEXTO)
    # Uma limpeza anterior deixa esta marca e o filter-repo pergunta Y/N.
    # Cada rodada aqui é completa, então começa do zero.
    Path('.git/filter-repo/already_ran').unlink(missing_ok=True)
    cmd = [sys.executable, '-m', 'git_filter_repo', '--force', '--invert-paths']
    for c in CAMINHOS:
        cmd += ['--path', c]
    for g in GLOBS:
        cmd += ['--path-glob', g]
    cmd += ['--replace-text', str(troca)]
    if subprocess.run(cmd).returncode != 0:
        parar(f'❌ Falha ao reescrever. Seu backup está em: {bkp.resolve()}')

    for nome, src in guardados.items():
        if not Path(nome).exists():
            shutil.copy2(src, nome)

    # 4) confere
    print('\n[4/5] Conferindo...')
    restos = git('log', '--all', '--pretty=format:', '--name-only', '--', *CAMINHOS, 'entrada', 'logs')
    restos = [l for l in restos.splitlines() if l.strip() and not l.endswith('COLE_OS_XLSX_AQUI.txt')]
    if restos:
        parar('❌ Ainda sobrou no histórico:\n  ' + '\n  '.join(sorted(set(restos))))
    embutido = subprocess.run(['git', 'log', '--all', '--format=%h', '-S', 'const FATURAMENTO_DATA_INLINE = `{"', '--', 'index.html'],
                              capture_output=True, text=True).stdout.strip()
    if embutido:
        parar('❌ Ainda há index.html antigo com faturamento embutido: ' + embutido)
    print('      OK: nada disso existe mais no histórico.')

    # 5) envia
    if remoto:
        git('remote', 'remove', 'origin', check=False)
        git('remote', 'add', 'origin', remoto)
    git('reflog', 'expire', '--expire=now', '--all', check=False)
    git('gc', '--prune=now', '--aggressive', check=False, capture=False)
    if sem_push:
        print('\n[5/5] --sem-push: não enviei nada pro GitHub.')
        return
    print('\n[5/5] Enviando pro GitHub (push forçado)...')
    r = subprocess.run(['git', 'push', '-u', 'origin', 'main', '--force'])
    if r.returncode != 0:
        parar('❌ Push falhou. O repositório LOCAL já está limpo.\n'
              '   Tente de novo com:  git push -u origin main --force')
    subprocess.run(['git', 'push', 'origin', '--tags', '--force'])

    print('\n' + '=' * 70)
    print('  CONCLUÍDO')
    print('=' * 70)
    print(f'  Backup: {bkp.resolve()}')
    print('  1. Abra o site e confira que carrega normalmente.')
    print('  2. Se tudo certo, pode apagar o backup depois de uns dias.')
    input('\nAperte Enter para sair...')


if __name__ == '__main__':
    main()
