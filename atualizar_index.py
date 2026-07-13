#!/usr/bin/env python3
"""
atualizar_index.py — Sprint 9.32.385
Mantém o index.html sincronizado com faturamento_data_inline.json.

O que faz:
  • Injeta o hash do JSON entre os marcadores
    // __FAT_VERSION_START__ ... // __FAT_VERSION_END__
    pra servir como cache buster (faturamento_data_inline.json?v=<hash>).
  • Remove o bloco inline antigo (`const FATURAMENTO_DATA_INLINE = ...`) se existir.

────────────────────────────────────────────────────────────────────────────
POR QUE ESTE SCRIPT VALIDA ANTES DE GRAVAR (Sprint 9.32.385)
────────────────────────────────────────────────────────────────────────────
Este script lê o index.html INTEIRO e o regrava INTEIRO — mesmo mudando só um
bloquinho de versão. Um arquivo de 2,7 MB reescrito por completo a cada
atualização de faturamento é uma operação de risco: se a leitura vier
incompleta, ou se a gravação for interrompida no meio, o resultado é um
index.html quebrado — e o app inteiro para de carregar.

Isso nunca aconteceu aqui, mas a proteção é barata e o estrago seria caro.
Então o script passou a ser paranoico:

  1. VALIDA o index.html antes de encostar nele. Se estiver corrompido (não
     termina em </html>, tamanho absurdo, tags desbalanceadas), ABORTA sem
     gravar nada — melhor falhar alto do que salvar lixo por cima do bom.
  2. Grava de forma ATÔMICA (arquivo temporário + os.replace). Uma queda de
     energia no meio da gravação deixa o arquivo antigo intacto, nunca um
     arquivo pela metade.
  3. RELÊ do disco e confere o resultado depois de gravar.

Se o script abortar dizendo que o index.html está corrompido, restaure com:
    git checkout -- index.html

Uso: python3 atualizar_index.py
"""
import hashlib
import json
import os
import re
import sys
from pathlib import Path


VERSION_BLOCK_RE = re.compile(
    r'// __FAT_VERSION_START__.*?// __FAT_VERSION_END__',
    re.DOTALL,
)
INLINE_BLOCK_RE = re.compile(
    r'const FATURAMENTO_DATA_INLINE = `[^`]*`;\s*',
)

# Um index.html saudável nunca fica abaixo disso. Serve pra pegar truncagem grosseira.
TAMANHO_MINIMO_CHARS = 1_000_000


def validar_html(txt: str, rotulo: str) -> list:
    """Devolve a lista de problemas encontrados. Lista vazia = arquivo saudável."""
    problemas = []

    if not txt.rstrip().endswith('</html>'):
        fim = repr(txt.rstrip()[-60:])
        problemas.append(f"não termina com </html> — final do arquivo: {fim}")

    if '// __FAT_VERSION_START__' not in txt or '// __FAT_VERSION_END__' not in txt:
        problemas.append("marcadores // __FAT_VERSION_START__ / __FAT_VERSION_END__ ausentes")

    if len(txt) < TAMANHO_MINIMO_CHARS:
        problemas.append(f"tamanho suspeito: {len(txt):,} caracteres (esperado > {TAMANHO_MINIMO_CHARS:,})")

    abre = txt.count('<div')
    fecha = txt.count('</div>')
    # Alguma diferença é normal (há '<div' dentro de strings JS). Um abismo, não.
    if abs(abre - fecha) > 30:
        problemas.append(f"<div> muito desbalanceado: {abre} aberturas x {fecha} fechamentos")

    if '<script' in txt and txt.count('<script') > txt.count('</script>'):
        problemas.append(f"<script> sem fechar: {txt.count('<script')} x {txt.count('</script>')}")

    return problemas


def abortar(rotulo: str, problemas: list):
    print()
    print("=" * 70)
    print(f"  ABORTADO — o index.html parece CORROMPIDO ({rotulo})")
    print("=" * 70)
    for p in problemas:
        print(f"   ✗ {p}")
    print()
    print("   NADA foi gravado — seu arquivo não foi piorado.")
    print()
    print("   Causa provável: outro processo estava escrevendo o index.html")
    print("   ao mesmo tempo (ou a gravação anterior não terminou de sincronizar).")
    print()
    print("   Como resolver:")
    print("     1. Feche qualquer ferramenta que esteja editando o index.html.")
    print("     2. Restaure a última versão boa:   git checkout -- index.html")
    print("     3. Rode este script de novo.")
    print()
    sys.exit(1)


def gravar_atomico(html_path: Path, conteudo: str):
    """Grava em arquivo temporário, confere, e só então substitui o original.

    os.replace é atômico: ou o arquivo antigo continua inteiro, ou o novo está
    completo. Nunca existe um estado intermediário meia-boca no disco.
    """
    tmp_path = html_path.with_name(html_path.name + '.tmp')
    tmp_path.write_text(conteudo, encoding='utf-8')

    # Confere que o que foi pro disco é exatamente o que queríamos
    escrito = tmp_path.read_text(encoding='utf-8')
    if escrito != conteudo:
        tmp_path.unlink(missing_ok=True)
        print("❌ A gravação temporária saiu diferente do esperado. Nada foi alterado.")
        sys.exit(1)

    os.replace(tmp_path, html_path)  # atômico


def main():
    json_path = Path('faturamento_data_inline.json')
    html_path = Path('index.html')

    if not json_path.exists():
        print(f"❌ {json_path} não encontrado. Rode gerar_faturamento_json.py antes.")
        sys.exit(1)

    if not html_path.exists():
        print(f"❌ {html_path} não encontrado nesta pasta.")
        sys.exit(1)

    # 1) Lê JSON e calcula hash (cache buster)
    json_bytes = json_path.read_bytes()
    json_hash = hashlib.sha1(json_bytes).hexdigest()[:12]

    dados = json.loads(json_bytes.decode('utf-8'))
    periodo = f"{dados['meta']['periodo_inicio']} → {dados['meta']['periodo_fim']}"

    # 2) Lê o HTML e VALIDA ANTES DE ENCOSTAR NELE ---------------------------
    html_original = html_path.read_text(encoding='utf-8')

    problemas = validar_html(html_original, 'antes de gravar')
    if problemas:
        abortar('leitura inicial', problemas)

    print(f"   ✓ index.html íntegro na leitura ({len(html_original):,} caracteres)")
    html = html_original

    # 3) Migração one-shot: remove o bloco inline antigo se ainda existir
    inline_removido = False
    if INLINE_BLOCK_RE.search(html):
        html = INLINE_BLOCK_RE.sub('', html, count=1)
        inline_removido = True

    # 4) Injeta o hash entre os marcadores de versão
    novo_bloco = (
        "// __FAT_VERSION_START__ — substituído pelo atualizar_index.py com hash do JSON\n"
        f"const FAT_DATA_VERSION = '{json_hash}';\n"
        "// __FAT_VERSION_END__"
    )
    if not VERSION_BLOCK_RE.search(html):
        print("❌ Marcadores // __FAT_VERSION_START__ ... // __FAT_VERSION_END__ não encontrados.")
        sys.exit(1)

    html = VERSION_BLOCK_RE.sub(lambda m: novo_bloco, html, count=1)

    # 5) Valida o RESULTADO antes de mandar pro disco
    problemas = validar_html(html, 'depois da edição')
    if problemas:
        abortar('resultado da edição', problemas)

    # 6) Grava de forma atômica (só se mudou algo)
    if html != html_original:
        gravar_atomico(html_path, html)

        # 7) Relê do disco e confere que chegou inteiro
        conferido = html_path.read_text(encoding='utf-8')
        problemas = validar_html(conferido, 'depois de gravar')
        if problemas or conferido != html:
            print()
            print("❌ O arquivo no disco NÃO bateu com o esperado depois da gravação.")
            for p in problemas:
                print(f"   ✗ {p}")
            print("   Restaure com:  git checkout -- index.html")
            sys.exit(1)
        print(f"   ✓ Gravação atômica confirmada e reconferida no disco")
    else:
        print(f"   ✓ Nada a mudar (hash do JSON já era {json_hash})")

    diff = len(html) - len(html_original)
    json_mb = len(json_bytes) / 1024 / 1024
    html_mb = len(html) / 1024 / 1024
    print(f"   ✓ index.html atualizado")
    print(f"   ✓ Período: {periodo}")
    print(f"   ✓ {len(dados['mensal'])} meses, {len(dados.get('marca_mes', []))} linhas marca×mês")
    print(f"   ✓ Hash do JSON (cache buster): {json_hash}")
    print(f"   ✓ JSON: {json_mb:.2f} MB | HTML: {html_mb:.2f} MB")
    print(f"   ✓ Diferença de tamanho do HTML: {diff:+,} caracteres")
    if inline_removido:
        print(f"   ✓ Bloco inline antigo (FATURAMENTO_DATA_INLINE) removido — migração concluída")


if __name__ == '__main__':
    main()
