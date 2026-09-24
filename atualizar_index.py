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
import gzip
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


def ler_chave_faturamento() -> bytes:
    """Le a chave AES de 32 bytes (base64) do arquivo local faturamento.key."""
    import base64
    p = Path('faturamento.key')
    if not p.exists():
        print("❌ faturamento.key nao encontrado nesta pasta.")
        print("   E a chave que cifra o faturamento publicado. Ela nao vai para o git.")
        print("   Se perdeu, gere outra e grave a mesma no banco (tabela app_segredos,")
        print("   nome 'faturamento_chave') — veja email_fila_servidor.sql, item 7.")
        sys.exit(1)
    chave = base64.b64decode(p.read_text(encoding='utf-8').strip())
    if len(chave) != 32:
        print("❌ faturamento.key invalido (esperado 32 bytes em base64).")
        sys.exit(1)
    return chave


# ---- Sprint 9.32.468: fatias por hospital (para a nutricionista) --------------
# A nutricionista precisava do arquivo INTEIRO para ver a própria performance —
# e com ele, o faturamento de todos os clientes. Agora cada cliente PJ vira um
# arquivo cifrado com chave própria em fat_cli/. O banco entrega a cada
# nutricionista só as chaves dos hospitais que ela visita (faturamento_chaves_perf).
# Nome do arquivo e chave saem de HMAC da chave mestra: sem a mestra, não dá
# para saber de qual CNPJ é cada arquivo nem abrir nenhum.
FATIA_CAMPOS = {
    'clientes_top': 'CNPJ/CPF', 'clientes_lista': 'cnpj',
    'devolucoes_clientes_top': 'CNPJ/CPF', 'cliente_devolucao_mes': 'CNPJ/CPF',
    'produtos_por_cliente': 'CNPJ/CPF', 'cliente_produto_mes': 'CNPJ/CPF',
    'clientes_mes': 'CNPJ/CPF',
}


def gerar_fatias(dados: dict, mestra: bytes) -> int:
    import hmac
    from cryptography.hazmat.primitives.ciphers.aead import AESGCM
    pasta = Path('fat_cli')
    pasta.mkdir(exist_ok=True)
    so_digitos = lambda v: re.sub(r'\D', '', str(v or ''))
    por_cli = {}
    for campo, chave_cnpj in FATIA_CAMPOS.items():
        for linha in dados.get(campo) or []:
            c = so_digitos(linha.get(chave_cnpj))
            if len(c) != 14:          # só PJ: hospital/clínica. Pessoa física fica fora.
                continue
            por_cli.setdefault(c, {}).setdefault(campo, []).append(linha)
    comum = {'meta': dados.get('meta'),
             'mensal': [{'ano_mes': m.get('ano_mes')} for m in dados.get('mensal') or []]}
    fatias = {'comum': comum, **por_cli}

    magic = b'BNC1'
    feitos = set()
    for nome, conteudo in fatias.items():
        ident = hmac.new(mestra, b'id:' + nome.encode(), hashlib.sha256).hexdigest()[:24]
        chave = hmac.new(mestra, b'k:' + nome.encode(), hashlib.sha256).digest()
        corpo = gzip.compress(json.dumps(conteudo, ensure_ascii=False, separators=(',', ':')).encode('utf-8'),
                              compresslevel=9, mtime=0)
        iv = hmac.new(chave, corpo, hashlib.sha256).digest()[:12]
        blob = magic + iv + AESGCM(chave).encrypt(iv, corpo, magic)
        destino = pasta / f'{ident}.bin'
        if not destino.exists() or destino.read_bytes() != blob:
            destino.write_bytes(blob)
        feitos.add(destino.name)
    # cliente que saiu do faturamento: a fatia antiga não pode ficar publicada
    for velho in pasta.glob('*.bin'):
        if velho.name not in feitos:
            velho.unlink()
    return len(por_cli)


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

    # ---- Sprint 9.32.426: gera a versao COMPRIMIDA -----------------------
    # O JSON tem ~20 MB e entra no git 2x por dia. Como o git guarda cada
    # versao para sempre, o repositorio crescia ~41 MB/dia — e perto de 1 GB
    # o GitHub Pages para de publicar (aconteceu em 06/09/2026).
    # Comprimido cai ~91%. So o .gz e versionado; o .json fica local.
    # mtime=0 deixa a saida deterministica: mesmo conteudo, mesmo arquivo,
    # entao rodar o script duas vezes nao gera commit a toa.
    gz_bytes = gzip.compress(json_bytes, compresslevel=9, mtime=0)
    if gzip.decompress(gz_bytes) != json_bytes:
        print("❌ O arquivo comprimido nao confere com o original. Abortado.")
        sys.exit(1)
    print(f"   ✓ Comprimido: {len(gz_bytes)/1024/1024:.2f} MB "
          f"({100 - 100 * len(gz_bytes) / len(json_bytes):.0f}% menor) — descompressao conferida")

    # ---- Sprint 9.32.464: publica CIFRADO -----------------------------------
    # O .gz aberto em benlogistica.com.br deixava qualquer um baixar nomes,
    # CPF/CNPJ e compras de todos os clientes. Agora vai cifrado (AES-256-GCM)
    # em faturamento_data.enc. A chave fica no arquivo local faturamento.key
    # (fora do git) e no banco (app_segredos), que so a entrega a quem esta
    # logado com conta ativa (funcao faturamento_chave).
    # O IV sai de um HMAC do conteudo: mesmo dado => mesmo arquivo (sem commit
    # a toa), dado diferente => IV diferente.
    enc_path = Path('faturamento_data.enc')
    chave = ler_chave_faturamento()
    try:
        from cryptography.hazmat.primitives.ciphers.aead import AESGCM
    except ImportError:
        print("❌ Falta o pacote 'cryptography'. Rode:  python -m pip install cryptography")
        sys.exit(1)
    import hmac
    magic = b'BNF1'
    iv = hmac.new(chave, gz_bytes, hashlib.sha256).digest()[:12]
    blob = magic + iv + AESGCM(chave).encrypt(iv, gz_bytes, magic)
    tmp_enc = enc_path.with_suffix('.enc.tmp')
    tmp_enc.write_bytes(blob)
    os.replace(tmp_enc, enc_path)

    # Confere que decifra de volta — publicar um arquivo ilegivel deixaria a
    # tela de faturamento morta.
    lido = enc_path.read_bytes()
    if gzip.decompress(AESGCM(chave).decrypt(lido[4:16], lido[16:], magic)) != json_bytes:
        print("❌ O arquivo cifrado nao confere com o original. Abortado.")
        sys.exit(1)
    print(f"   ✓ Cifrado em {enc_path} ({len(lido)/1024/1024:.2f} MB) — decifragem conferida")

    # O .gz aberto nao deve mais existir (nem ser publicado).
    antigo = Path('faturamento_data_inline.json.gz')
    if antigo.exists():
        antigo.unlink()
        print("   ✓ faturamento_data_inline.json.gz (aberto) removido")

    dados = json.loads(json_bytes.decode('utf-8'))
    n_fatias = gerar_fatias(dados, chave)
    print(f"   ✓ Fatias por hospital em fat_cli/: {n_fatias} clientes PJ + resumo comum")
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
