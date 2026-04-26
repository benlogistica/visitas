"""
Gera SQL de seed pro catalogo_produtos a partir dos XLSX do faturamento.

Uso:
    python3 gerar_seed_catalogo.py entrada/faturamento*.xlsx

Saída: catalogo_produtos_seed.sql

Estratégia:
- Lê todos XLSX da pasta entrada/
- Extrai pares únicos (Descrição do Produto, Marca)
- Filtra apenas vendas (CFOP 5.1xx, 5.4xx, 6.1xx, 6.4xx, ou Pedido/PDV/NFe)
- Gera INSERT ... ON CONFLICT DO NOTHING
"""

import sys
import glob
import pandas as pd
from pathlib import Path


def main():
    if len(sys.argv) < 2:
        print("Uso: python gerar_seed_catalogo.py arquivo1.xlsx [arquivo2.xlsx ...]")
        print("     python gerar_seed_catalogo.py entrada/*.xlsx")
        sys.exit(1)

    # Expande wildcards manualmente (Windows não expande * automaticamente)
    caminhos = []
    for arg in sys.argv[1:]:
        if '*' in arg or '?' in arg:
            achados = glob.glob(arg)
            if not achados:
                print(f"⚠ Nenhum arquivo encontrado pra padrão: {arg}")
            caminhos.extend(achados)
        else:
            caminhos.append(arg)

    # Remove duplicatas mantendo ordem
    caminhos = list(dict.fromkeys(caminhos))

    if not caminhos:
        print("❌ Nenhum arquivo XLSX encontrado.")
        print("   Verifique se a pasta 'entrada/' existe e tem arquivos .xlsx")
        sys.exit(1)

    print(f"Lendo {len(caminhos)} arquivo(s) XLSX...\n")

    dfs = []
    for c in caminhos:
        if not Path(c).exists():
            print(f"❌ Não encontrado: {c}")
            continue
        try:
            df = pd.read_excel(c, header=1, skiprows=[2])
            dfs.append(df)
            print(f"  ✓ {Path(c).name} → {len(df)} linhas")
        except Exception as e:
            print(f"  ❌ Erro lendo {c}: {e}")

    if not dfs:
        print("Nenhum arquivo lido.")
        sys.exit(1)

    df = pd.concat(dfs, ignore_index=True)
    print(f"\nTotal de linhas: {len(df):,}")

    # Filtra só vendas (não inclui devoluções)
    if 'Operação' in df.columns:
        op = df['Operação'].astype(str)
        mask = op.str.contains('Pedido|PDV|NFe|Venda', case=False, na=False)
        df = df[mask]
        print(f"Após filtro de vendas: {len(df):,}")

    # Pega pares únicos (Descrição, Marca)
    df = df.dropna(subset=['Descrição do Produto', 'Marca'])
    df['Descrição do Produto'] = df['Descrição do Produto'].astype(str).str.strip()
    df['Marca'] = df['Marca'].astype(str).str.strip()

    # Filtra strings vazias após o strip
    df = df[(df['Descrição do Produto'] != '') & (df['Marca'] != '')]

    # Conta uso (proxy pra ranking de relevância)
    grupo = df.groupby(['Descrição do Produto', 'Marca']).size().reset_index(name='qtd_uso')

    # ─── Deduplica case-insensitive (mesmo que o ON CONFLICT do SQL) ───
    # A constraint unique é (lower(descricao), lower(marca)) — então preciso
    # deduplicar com a mesma regra antes de inserir, senão dá conflito.
    # Estratégia: pra cada chave (lower-desc, lower-marca), mantém a versão
    # MAIS USADA (qtd_uso maior), agregando os usos das duplicatas.
    grupo['_key'] = grupo['Descrição do Produto'].str.lower() + '||' + grupo['Marca'].str.lower()
    soma_por_key = grupo.groupby('_key')['qtd_uso'].sum().to_dict()
    # Mantém a primeira ocorrência de cada key (a mais usada por causa do sort)
    grupo = grupo.sort_values('qtd_uso', ascending=False)
    grupo = grupo.drop_duplicates(subset=['_key'], keep='first')
    # Atualiza qtd_uso pra somar todas as variantes (case)
    grupo['qtd_uso'] = grupo['_key'].map(soma_por_key)
    grupo = grupo.drop(columns=['_key']).sort_values('qtd_uso', ascending=False)

    print(f"Pares únicos (Descrição × Marca, case-insensitive): {len(grupo):,}")

    # Gera SQL
    out_path = 'catalogo_produtos_seed.sql'
    with open(out_path, 'w', encoding='utf-8') as f:
        f.write("-- Seed do catalogo_produtos a partir do faturamento\n")
        f.write(f"-- Gerado em: {pd.Timestamp.now().strftime('%Y-%m-%d %H:%M:%S')}\n")
        f.write(f"-- Total de produtos únicos: {len(grupo):,}\n\n")
        f.write("BEGIN;\n\n")
        f.write("-- Limpa catálogo de fonte 'faturamento' (preserva os manuais)\n")
        f.write("DELETE FROM catalogo_produtos WHERE fonte = 'faturamento';\n\n")
        f.write("INSERT INTO catalogo_produtos (descricao, marca, fonte, qtd_uso) VALUES\n")

        linhas = []
        for _, r in grupo.iterrows():
            desc = r['Descrição do Produto'].replace("'", "''")
            marca = r['Marca'].replace("'", "''")
            qtd = int(r['qtd_uso'])
            linhas.append(f"  ('{desc}', '{marca}', 'faturamento', {qtd})")
        f.write(',\n'.join(linhas))
        f.write("\nON CONFLICT (lower(descricao), lower(marca)) DO UPDATE SET\n")
        f.write("  qtd_uso = EXCLUDED.qtd_uso,\n")
        f.write("  updated_at = now();\n\n")
        f.write("COMMIT;\n")

    print(f"\n✅ SQL gerado em: {out_path}")
    print(f"   Tamanho: {Path(out_path).stat().st_size / 1024:.1f} KB")
    print(f"\nPróximo passo:")
    print(f"  1. Roda primeiro: migration_09_itens_padronizados_v2.sql")
    print(f"  2. Depois roda: {out_path}")


if __name__ == '__main__':
    main()
