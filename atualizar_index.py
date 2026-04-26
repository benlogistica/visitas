#!/usr/bin/env python3
"""
atualizar_index.py — Sprint 9.32.35
Mantém o index.html sincronizado com faturamento_data_inline.json.

Mudanças desta sprint:
  • Não embute mais o JSON dentro do HTML (saiu de ~16MB pra ~3MB).
  • Apenas injeta um hash do JSON entre os marcadores
    // __FAT_VERSION_START__ ... // __FAT_VERSION_END__
    pra servir como cache buster (faturamento_data_inline.json?v=<hash>).
  • Na primeira execução após a migração, remove o bloco antigo
    `const FATURAMENTO_DATA_INLINE = ` ... `;` se ainda existir.

Uso: python3 atualizar_index.py
"""
import hashlib
import json
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

    # Carrega o JSON pra extrair metadados (período, contagens) só pra log
    dados = json.loads(json_bytes.decode('utf-8'))
    periodo = f"{dados['meta']['periodo_inicio']} → {dados['meta']['periodo_fim']}"

    # 2) Lê HTML
    html_original = html_path.read_text(encoding='utf-8')
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
        print("   Verifique se você já está com a versão Sprint 9.32.35+ do index.html.")
        sys.exit(1)

    html = VERSION_BLOCK_RE.sub(lambda m: novo_bloco, html, count=1)

    # 5) Grava
    if html != html_original:
        html_path.write_text(html, encoding='utf-8')

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
