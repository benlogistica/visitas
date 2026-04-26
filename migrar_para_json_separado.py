#!/usr/bin/env python3
"""
migrar_para_json_separado.py — Sprint 9.32.35 (rodar UMA vez)

Extrai o bloco FATURAMENTO_DATA_INLINE que ainda está embutido no index.html
e cria o arquivo separado faturamento_data_inline.json. Depois remove o bloco
inline do HTML e injeta o hash do JSON no marcador de versão.

Resultado:
  • faturamento_data_inline.json criado (~13 MB)
  • index.html cai de ~16 MB pra ~3 MB
  • Hash do JSON gravado em FAT_DATA_VERSION (cache buster do fetch)

Depois de rodar este script:
  git add index.html faturamento_data_inline.json
  git commit -m "Sprint 9.32.35: JSON separado do HTML"
  git push

A partir daí, atualizar_dashboard.bat funciona normal e nunca mais precisa
deste script.
"""
import hashlib
import json
import re
import sys
from pathlib import Path


INLINE_BLOCK_RE = re.compile(
    r'const FATURAMENTO_DATA_INLINE = `(?P<conteudo>[^`]*)`;\s*',
    re.DOTALL,
)
VERSION_BLOCK_RE = re.compile(
    r'// __FAT_VERSION_START__.*?// __FAT_VERSION_END__',
    re.DOTALL,
)


def main():
    html_path = Path('index.html')
    json_path = Path('faturamento_data_inline.json')

    if not html_path.exists():
        print(f"❌ {html_path} não encontrado.")
        sys.exit(1)

    print("→ Lendo index.html...")
    html = html_path.read_text(encoding='utf-8')
    print(f"   tamanho atual: {len(html)/1024/1024:.2f} MB")

    # 1) Procurar o bloco inline
    m = INLINE_BLOCK_RE.search(html)
    if not m:
        print("ℹ️  Nenhum bloco FATURAMENTO_DATA_INLINE encontrado no HTML.")
        if json_path.exists():
            print("✓ faturamento_data_inline.json já existe — migração já feita.")
        else:
            print("❌ Mas faturamento_data_inline.json também não existe.")
            print("   Você precisa rodar gerar_faturamento_json.py pra criar o JSON.")
            sys.exit(1)
        sys.exit(0)

    conteudo_template = m.group('conteudo')
    print(f"→ Bloco inline encontrado: {len(conteudo_template)/1024/1024:.2f} MB de conteúdo")

    # 2) Reverter as transformações que o atualizar_index.py original fazia
    #    Original injectava: json_str.replace('\\', '\\\\').replace('${', '\\${')
    #    Pra reverter: primeiro desfaz o \${, depois colapsa os \\.
    print("→ Revertendo escapes de template literal...")
    json_str = conteudo_template.replace('\\${', '${').replace('\\\\', '\\')

    # 3) Validar que é JSON válido
    print("→ Validando JSON extraído...")
    try:
        dados = json.loads(json_str)
    except json.JSONDecodeError as e:
        print(f"❌ JSON extraído é inválido: {e}")
        print(f"   Posição do erro: {e.pos}")
        print(f"   Trecho ao redor: ...{json_str[max(0,e.pos-80):e.pos+80]}...")
        sys.exit(1)
    print(f"   ✓ JSON válido — {len(dados.get('mensal', []))} meses, "
          f"{len(dados.get('clientes_lista', []))} clientes na lista")

    # 4) Salvar como arquivo separado (compacto, igual o gerar_faturamento_json.py faz)
    print(f"→ Salvando {json_path}...")
    json_bytes = json.dumps(dados, ensure_ascii=False, separators=(',', ':')).encode('utf-8')
    json_path.write_bytes(json_bytes)
    print(f"   ✓ {len(json_bytes)/1024/1024:.2f} MB")

    # 5) Hash pra cache buster
    json_hash = hashlib.sha1(json_bytes).hexdigest()[:12]
    print(f"   ✓ Hash: {json_hash}")

    # 6) Remover o bloco inline do HTML
    print("→ Removendo bloco inline do HTML...")
    html_novo = INLINE_BLOCK_RE.sub('', html, count=1)

    # 7) Injetar o hash no marcador de versão
    if not VERSION_BLOCK_RE.search(html_novo):
        print("❌ Marcadores // __FAT_VERSION_START__ / __FAT_VERSION_END__ não encontrados.")
        print("   Verifica se o index.html já é o da Sprint 9.32.35.")
        sys.exit(1)

    novo_bloco = (
        "// __FAT_VERSION_START__ — substituído pelo atualizar_index.py com hash do JSON\n"
        f"const FAT_DATA_VERSION = '{json_hash}';\n"
        "// __FAT_VERSION_END__"
    )
    html_novo = VERSION_BLOCK_RE.sub(lambda mm: novo_bloco, html_novo, count=1)

    # 8) Salvar HTML
    print("→ Gravando index.html novo...")
    html_path.write_text(html_novo, encoding='utf-8')
    diff = len(html_novo) - len(html)
    print(f"   ✓ tamanho final: {len(html_novo)/1024/1024:.2f} MB ({diff:+,} chars)")

    print()
    print("✅ Migração concluída com sucesso.")
    print()
    print("Próximos passos:")
    print("   git add index.html faturamento_data_inline.json")
    print('   git commit -m "Sprint 9.32.35: JSON separado do HTML"')
    print("   git push")
    print()
    print("A partir de agora, use atualizar_dashboard.bat normalmente — ele já está atualizado.")


if __name__ == '__main__':
    main()
