#!/usr/bin/env python3
"""
gerar_faturamento_json.py — Sprint 9.32.35
──────────────────────────────────────────────────────────────────────────
Gera o faturamento_data_inline.json a partir dos XLSX exportados do Omie.

Fluxo atual (Sprint 9.32.35 em diante):
  XLSX → faturamento_data_inline.json (arquivo separado, ~13MB)
        ↓
  atualizar_index.py: calcula hash do JSON e injeta em FAT_DATA_VERSION
                      no index.html (cache buster)

Sprint 9.32.31-33: gera todos os cruzamentos cliente×X que o front usa
quando há filtro de cliente (vendedor, marca, empresa, produto, devolução).

Uso:
  python gerar_faturamento_json.py arquivo1.xlsx [arquivo2.xlsx ...]
  python gerar_faturamento_json.py entrada\\*.xlsx

Cada XLSX deve ser o export "Sell Out2 Faturamento por Período" do Omie,
com cabeçalho na linha 2 (1-indexada) e linha de totais na 3.

Saída:
  - faturamento_data_inline.json  → JSON puro consumido via fetch()

Autor: Claude + Eduardo (Hospital Ana Costa / Haverim)
──────────────────────────────────────────────────────────────────────────
"""

import json
import sys
from pathlib import Path
from datetime import datetime
from collections import defaultdict

import pandas as pd

# ══════════════════════════════════════════════════════════════════════════
# CONFIGURAÇÃO
# ══════════════════════════════════════════════════════════════════════════

# Operações classificadas
OPS_VENDA = [
    'Pedido de Venda',
    'Venda de Produto pelo PDV',
    'NFe de Saída',
]
OPS_DEVOLUCAO = [
    'Devolução de Venda',
    'Devolução (Emissão do Cliente)',
]
OPS_CONSIGNADO = [
    'Remessa de Produto',
]
OPS_IGNORADAS = [
    'Devolução ao Fornecedor',  # é input, não output
]

# Quantos itens top manter em cada ranking
TOP_CLIENTES = 50
TOP_PRODUTOS = 100


# ══════════════════════════════════════════════════════════════════════════
# LEITURA
# ══════════════════════════════════════════════════════════════════════════

def ler_xlsx(caminho: str) -> pd.DataFrame:
    """Lê um XLSX do Omie e retorna DataFrame normalizado."""
    print(f"📂 Lendo: {caminho}")

    df = pd.read_excel(
        caminho,
        header=1,                        # cabeçalho na linha 2 (1-indexada)
        skiprows=lambda x: x == 2,       # pula linha 3 (totais)
    )

    # Converte tipos
    df['Total de Mercadoria'] = pd.to_numeric(df['Total de Mercadoria'], errors='coerce')
    df['Quantidade']          = pd.to_numeric(df['Quantidade'], errors='coerce')
    df['Valor Unitário']      = pd.to_numeric(df['Valor Unitário'], errors='coerce')
    df['Data de Emissão (completa)'] = pd.to_datetime(df['Data de Emissão (completa)'], errors='coerce')

    # Remove linhas sem data ou valor (pode acontecer em finais de planilha)
    df = df[df['Data de Emissão (completa)'].notna()].copy()
    df = df[df['Total de Mercadoria'].notna()].copy()

    # Normaliza strings — remove espaços extras
    # Sprint 9.32.28: incluído 'Cliente (Razão Social)' pra evitar NaN no JSON gerado
    for col in ['Cliente (Nome Fantasia)', 'Cliente (Razão Social)',
                'Marca', 'Vendedor', 'Estado',
                'Cidade', 'Operação', 'Minha Empresa (Nome Fantasia)',
                'Descrição do Produto']:
        if col in df.columns:
            df[col] = df[col].fillna('N/D').astype(str).str.strip()
            df.loc[df[col] == '', col] = 'N/D'

    # CNPJ — só dígitos pra normalizar depois
    df['_cnpj_norm'] = df['CNPJ/CPF'].fillna('').astype(str).apply(
        lambda v: ''.join(c for c in v if c.isdigit())
    )

    # Tipo pessoa derivado
    def derivar_tipo(cnpj):
        dig = ''.join(c for c in str(cnpj) if c.isdigit())
        if len(dig) == 11: return 'PF'
        if len(dig) == 14: return 'PJ'
        return 'N/D'
    df['tipo_pessoa'] = df['CNPJ/CPF'].apply(derivar_tipo)

    # Categoria da operação
    def categorizar(op):
        if op in OPS_VENDA: return 'Venda'
        if op in OPS_DEVOLUCAO: return 'Devolução'
        if op in OPS_CONSIGNADO: return 'Consignado'
        return 'Ignorar'
    df['_categoria'] = df['Operação'].apply(categorizar)

    # Ano-mês
    df['_ano_mes'] = df['Data de Emissão (completa)'].dt.strftime('%Y-%m')
    df['_data'] = df['Data de Emissão (completa)'].dt.strftime('%Y-%m-%d')

    print(f"   → {len(df):,} linhas válidas")
    return df


# ══════════════════════════════════════════════════════════════════════════
# AGREGAÇÕES
# ══════════════════════════════════════════════════════════════════════════

def gerar_mensal(df_vendas: pd.DataFrame) -> list:
    """Faturamento total por mês (Venda apenas)."""
    g = df_vendas.groupby('_ano_mes').agg(
        faturamento=('Total de Mercadoria', 'sum'),
        qtd_notas=('Nota Fiscal', 'nunique'),
        qtd_itens=('Quantidade', 'sum'),
        qtd_clientes=('CNPJ/CPF', 'nunique'),
    ).reset_index().rename(columns={'_ano_mes': 'ano_mes'})
    g['ticket_medio'] = g['faturamento'] / g['qtd_notas'].replace(0, 1)
    g = g.sort_values('ano_mes')
    return [
        {
            'ano_mes': r['ano_mes'],
            'faturamento': round(r['faturamento'], 2),
            'qtd_notas': int(r['qtd_notas']),
            'qtd_itens': round(r['qtd_itens'], 2) if pd.notna(r['qtd_itens']) else 0,
            'qtd_clientes': int(r['qtd_clientes']),
            'ticket_medio': round(r['ticket_medio'], 2),
        }
        for _, r in g.iterrows()
    ]


def gerar_vendedor_mes(df_vendas: pd.DataFrame) -> list:
    """Faturamento de cada vendedor por mês."""
    g = df_vendas.groupby(['Vendedor', '_ano_mes']).agg(
        faturamento=('Total de Mercadoria', 'sum'),
        qtd_notas=('Nota Fiscal', 'nunique'),
    ).reset_index().rename(columns={'_ano_mes': 'ano_mes'})
    g = g.sort_values(['Vendedor', 'ano_mes'])
    return [
        {
            'Vendedor': r['Vendedor'],
            'ano_mes': r['ano_mes'],
            'faturamento': round(r['faturamento'], 2),
            'qtd_notas': int(r['qtd_notas']),
        }
        for _, r in g.iterrows()
    ]


def gerar_produtos_por_cliente(df_vendas: pd.DataFrame, n_clientes: int = TOP_CLIENTES, n_produtos_por_cliente: int = 50) -> list:
    """Para cada cliente do top N, lista os produtos comprados (ordenados por faturamento)."""
    # Pega os mesmos top N clientes que o gerar_clientes_top
    top_cnpjs = (
        df_vendas.groupby('CNPJ/CPF')['Total de Mercadoria']
        .sum()
        .sort_values(ascending=False)
        .head(n_clientes)
        .index
        .tolist()
    )

    df_top = df_vendas[df_vendas['CNPJ/CPF'].isin(top_cnpjs)]

    # Agrupa por cliente + produto pra rankear produtos dentro de cada hospital
    g = df_top.groupby(['CNPJ/CPF', 'Descrição do Produto', 'Marca']).agg(
        faturamento=('Total de Mercadoria', 'sum'),
    ).reset_index()

    out = []
    for cnpj in top_cnpjs:
        produtos_cli = (
            g[g['CNPJ/CPF'] == cnpj]
            .sort_values('faturamento', ascending=False)
            .head(n_produtos_por_cliente)
        )
        out.append({
            'CNPJ/CPF': cnpj,
            # Lista só nome + marca, sem valor (decisão UX: nutri não vê quanto vendeu por produto)
            'produtos': [
                {
                    'descricao': r['Descrição do Produto'],
                    'marca': r['Marca'],
                }
                for _, r in produtos_cli.iterrows()
            ],
            'qtd_produtos_distintos': int(produtos_cli.shape[0]),
        })
    return out


def gerar_clientes_mes(df_vendas: pd.DataFrame) -> list:
    """⭐ Sprint 9.32.31: TODOS os clientes × mês (sem mais limite top N).

    Antes só agregava top 50 → clientes fora do top (Hospital Ana Costa, etc.)
    retornavam zero ao filtrar. Agora pega tudo.
    Estrutura: lista de objetos {CNPJ/CPF, ano_mes, faturamento, qtd_notas}
    """
    g = df_vendas.groupby(['CNPJ/CPF', '_ano_mes']).agg(
        faturamento=('Total de Mercadoria', 'sum'),
        qtd_notas=('Nota Fiscal', 'nunique'),
    ).reset_index().rename(columns={'_ano_mes': 'ano_mes'})

    g = g.sort_values(['CNPJ/CPF', 'ano_mes'])
    return [
        {
            'CNPJ/CPF': r['CNPJ/CPF'],
            'ano_mes': r['ano_mes'],
            'faturamento': float(round(r['faturamento'], 2)),
            'qtd_notas': int(r['qtd_notas']),
        }
        for _, r in g.iterrows()
    ]


def gerar_clientes_top(df_vendas: pd.DataFrame, n: int = TOP_CLIENTES) -> list:
    """Top N clientes por faturamento."""
    # Sprint 9.32.27: incluir Razão Social separada (se existir no XLSX)
    tem_razao = 'Cliente (Razão Social)' in df_vendas.columns
    agg = {
        'faturamento': ('Total de Mercadoria', 'sum'),
        'qtd_notas': ('Nota Fiscal', 'nunique'),
        'primeira_compra': ('Data de Emissão (completa)', 'min'),
        'ultima_compra': ('Data de Emissão (completa)', 'max'),
        'cnpj': ('CNPJ/CPF', 'first'),
        'cidade': ('Cidade', 'first'),
        'estado': ('Estado', 'first'),
    }
    if tem_razao:
        agg['razao_social'] = ('Cliente (Razão Social)', 'first')

    g = df_vendas.groupby(['Cliente (Nome Fantasia)']).agg(**agg).reset_index()
    g = g.sort_values('faturamento', ascending=False).head(n)
    return [
        {
            'Cliente (Nome Fantasia)': r['Cliente (Nome Fantasia)'],
            'Cliente (Razão Social)': r['razao_social'] if tem_razao else r['Cliente (Nome Fantasia)'],
            'CNPJ/CPF': r['cnpj'],
            'Cidade': r['cidade'],
            'Estado': r['estado'],
            'faturamento': round(r['faturamento'], 2),
            'qtd_notas': int(r['qtd_notas']),
            'primeira_compra': r['primeira_compra'].strftime('%Y-%m-%d') if pd.notna(r['primeira_compra']) else None,
            'ultima_compra': r['ultima_compra'].strftime('%Y-%m-%d') if pd.notna(r['ultima_compra']) else None,
        }
        for _, r in g.iterrows()
    ]


def gerar_clientes_lista(df_vendas: pd.DataFrame) -> list:
    """Sprint 9.32.27: lista ENXUTA de TODOS os clientes pra busca no front.

    Sem faturamento (já temos em clientes_top + clientes_mes pros top 50).
    Apenas CNPJ + Razão Social + Nome Fantasia + Cidade + Estado.
    Permite busca por qualquer cliente, mesmo fora do top 50.
    """
    tem_razao = 'Cliente (Razão Social)' in df_vendas.columns
    cols = ['CNPJ/CPF', 'Cliente (Nome Fantasia)', 'Cidade', 'Estado']
    if tem_razao:
        cols.insert(2, 'Cliente (Razão Social)')
    df = df_vendas[cols].drop_duplicates(subset=['CNPJ/CPF']).copy()
    # CRÍTICO: trata NaN -> '' antes de exportar pra JSON (NaN não é JSON válido!)
    df = df.fillna('')
    # Ordena por Razão Social (ou Nome Fantasia se não tem) pra busca alfabética
    chave_ord = 'Cliente (Razão Social)' if tem_razao else 'Cliente (Nome Fantasia)'
    df = df.sort_values(chave_ord)

    def _safe(v):
        """Garante que retorna string mesmo com NaN/None."""
        if v is None: return ''
        s = str(v).strip()
        return '' if s.lower() == 'nan' else s

    out = []
    for _, r in df.iterrows():
        cnpj = _safe(r['CNPJ/CPF'])
        if not cnpj:
            continue  # pula linhas sem CNPJ
        out.append({
            'cnpj': cnpj,
            'nome_fantasia': _safe(r['Cliente (Nome Fantasia)']),
            'razao_social': _safe(r.get('Cliente (Razão Social)') if tem_razao else r['Cliente (Nome Fantasia)']),
            'cidade': _safe(r['Cidade']),
            'estado': _safe(r['Estado']),
        })
    return out


def gerar_cliente_vendedor_mes(df_vendas: pd.DataFrame) -> list:
    """⭐ Sprint 9.32.31: cliente × vendedor × mês.

    Permite o front recompor o ranking de vendedores quando filtra por cliente.
    Quem vende pra esse hospital específico? Aqui responde.
    """
    g = df_vendas.groupby(['CNPJ/CPF', 'Vendedor', '_ano_mes']).agg(
        faturamento=('Total de Mercadoria', 'sum'),
        qtd_notas=('Nota Fiscal', 'nunique'),
    ).reset_index().rename(columns={'_ano_mes': 'ano_mes'})
    g = g.sort_values(['CNPJ/CPF', 'ano_mes', 'faturamento'], ascending=[True, True, False])
    return [
        {
            'CNPJ/CPF': r['CNPJ/CPF'],
            'Vendedor': r['Vendedor'],
            'ano_mes': r['ano_mes'],
            'faturamento': round(r['faturamento'], 2),
            'qtd_notas': int(r['qtd_notas']),
        }
        for _, r in g.iterrows()
    ]


def gerar_cliente_marca_mes(df_vendas: pd.DataFrame) -> list:
    """⭐ Sprint 9.32.31: cliente × marca × mês.

    Quais marcas esse hospital compra? Pra recompor o donut de marcas
    quando há filtro de cliente.
    """
    g = df_vendas.groupby(['CNPJ/CPF', 'Marca', '_ano_mes']).agg(
        faturamento=('Total de Mercadoria', 'sum'),
        qtd_notas=('Nota Fiscal', 'nunique'),
        qtd_itens=('Quantidade', 'sum'),
    ).reset_index().rename(columns={'_ano_mes': 'ano_mes'})
    g = g.sort_values(['CNPJ/CPF', 'ano_mes', 'faturamento'], ascending=[True, True, False])
    return [
        {
            'CNPJ/CPF': r['CNPJ/CPF'],
            'Marca': r['Marca'],
            'ano_mes': r['ano_mes'],
            'faturamento': round(r['faturamento'], 2),
            'qtd_notas': int(r['qtd_notas']),
            'qtd_itens': round(r['qtd_itens'], 2) if pd.notna(r['qtd_itens']) else 0,
        }
        for _, r in g.iterrows()
    ]


def gerar_cliente_empresa_mes(df_vendas: pd.DataFrame) -> list:
    """⭐ Sprint 9.32.32: cliente × empresa (filial) × mês.

    Quais empresas (Haverim/Nutricionais Santos/PG) atendem esse hospital?
    Pra recompor o painel de Faturamento por Empresa quando filtra cliente.
    """
    g = df_vendas.groupby(['CNPJ/CPF', 'Minha Empresa (Nome Fantasia)', '_ano_mes']).agg(
        faturamento=('Total de Mercadoria', 'sum'),
        qtd_notas=('Nota Fiscal', 'nunique'),
    ).reset_index().rename(columns={
        '_ano_mes': 'ano_mes',
        'Minha Empresa (Nome Fantasia)': 'Empresa',
    })
    g = g.sort_values(['CNPJ/CPF', 'ano_mes', 'faturamento'], ascending=[True, True, False])
    return [
        {
            'CNPJ/CPF': r['CNPJ/CPF'],
            'Empresa': r['Empresa'],
            'ano_mes': r['ano_mes'],
            'faturamento': round(r['faturamento'], 2),
            'qtd_notas': int(r['qtd_notas']),
        }
        for _, r in g.iterrows()
    ]


def gerar_cliente_produto_mes(df_vendas: pd.DataFrame, top_produtos_por_cliente: int = 30) -> list:
    """⭐ Sprint 9.32.31: cliente × produto × mês.

    Limita a top 30 produtos por cliente (overall) pra evitar JSON gigante,
    depois inclui série mensal só pra esses 30.
    """
    # 1) Pra cada cliente, descobre os top 30 produtos por faturamento
    g_cli_prod = df_vendas.groupby(['CNPJ/CPF', 'Código do Produto']).agg(
        fat_total=('Total de Mercadoria', 'sum'),
    ).reset_index()
    # Rank dentro de cada cliente
    g_cli_prod['rank'] = g_cli_prod.groupby('CNPJ/CPF')['fat_total'].rank(method='dense', ascending=False)
    pares_validos = g_cli_prod[g_cli_prod['rank'] <= top_produtos_por_cliente][['CNPJ/CPF', 'Código do Produto']]
    # Set pra lookup rápido
    pares_set = set(zip(pares_validos['CNPJ/CPF'], pares_validos['Código do Produto']))

    # 2) Filtra df_vendas só pelos pares (cliente, produto) que entraram no top
    df_filt = df_vendas[df_vendas.apply(
        lambda r: (r['CNPJ/CPF'], r['Código do Produto']) in pares_set, axis=1
    )]

    # 3) Agrega por cliente × produto × mês
    g = df_filt.groupby(['CNPJ/CPF', 'Código do Produto', 'Descrição do Produto', 'Marca', '_ano_mes']).agg(
        faturamento=('Total de Mercadoria', 'sum'),
        qtd_itens=('Quantidade', 'sum'),
        qtd_notas=('Nota Fiscal', 'nunique'),
    ).reset_index().rename(columns={'_ano_mes': 'ano_mes'})
    g = g.sort_values(['CNPJ/CPF', 'ano_mes', 'faturamento'], ascending=[True, True, False])
    return [
        {
            'CNPJ/CPF': r['CNPJ/CPF'],
            'Código do Produto': str(r['Código do Produto']) if pd.notna(r['Código do Produto']) else 'N/D',
            'Descrição do Produto': r['Descrição do Produto'],
            'Marca': r['Marca'],
            'ano_mes': r['ano_mes'],
            'faturamento': round(r['faturamento'], 2),
            'qtd_itens': round(r['qtd_itens'], 2) if pd.notna(r['qtd_itens']) else 0,
            'qtd_notas': int(r['qtd_notas']),
        }
        for _, r in g.iterrows()
    ]


def gerar_marcas(df_vendas: pd.DataFrame) -> list:
    """Totais por marca (agregado do período inteiro)."""
    g = df_vendas.groupby('Marca').agg(
        faturamento=('Total de Mercadoria', 'sum'),
        qtd_notas=('Nota Fiscal', 'nunique'),
        qtd_itens=('Quantidade', 'sum'),
    ).reset_index()
    g = g.sort_values('faturamento', ascending=False)
    return [
        {
            'Marca': r['Marca'],
            'faturamento': round(r['faturamento'], 2),
            'qtd_notas': int(r['qtd_notas']),
            'qtd_itens': round(r['qtd_itens'], 2) if pd.notna(r['qtd_itens']) else 0,
        }
        for _, r in g.iterrows()
    ]


def gerar_marca_mes(df_vendas: pd.DataFrame) -> list:
    """⭐ NOVO: série temporal de cada marca por mês."""
    g = df_vendas.groupby(['Marca', '_ano_mes']).agg(
        faturamento=('Total de Mercadoria', 'sum'),
        qtd_notas=('Nota Fiscal', 'nunique'),
    ).reset_index().rename(columns={'_ano_mes': 'ano_mes'})
    g = g.sort_values(['ano_mes', 'faturamento'], ascending=[True, False])
    return [
        {
            'Marca': r['Marca'],
            'ano_mes': r['ano_mes'],
            'faturamento': round(r['faturamento'], 2),
            'qtd_notas': int(r['qtd_notas']),
        }
        for _, r in g.iterrows()
    ]


def gerar_produtos_top(df_vendas: pd.DataFrame, n: int = TOP_PRODUTOS) -> list:
    """Top N produtos."""
    g = df_vendas.groupby(['Código do Produto', 'Descrição do Produto', 'Marca']).agg(
        faturamento=('Total de Mercadoria', 'sum'),
        qtd_itens=('Quantidade', 'sum'),
    ).reset_index()
    g = g.sort_values('faturamento', ascending=False).head(n)
    return [
        {
            'Código do Produto': str(r['Código do Produto']) if pd.notna(r['Código do Produto']) else 'N/D',
            'Descrição do Produto': r['Descrição do Produto'],
            'Marca': r['Marca'],
            'faturamento': round(r['faturamento'], 2),
            'qtd_itens': round(r['qtd_itens'], 2) if pd.notna(r['qtd_itens']) else 0,
        }
        for _, r in g.iterrows()
    ]


def gerar_estados(df_vendas: pd.DataFrame) -> list:
    """Faturamento por estado."""
    g = df_vendas.groupby('Estado').agg(
        faturamento=('Total de Mercadoria', 'sum'),
        qtd_clientes=('CNPJ/CPF', 'nunique'),
    ).reset_index()
    g = g.sort_values('faturamento', ascending=False)
    return [
        {
            'Estado': r['Estado'],
            'faturamento': round(r['faturamento'], 2),
            'qtd_clientes': int(r['qtd_clientes']),
        }
        for _, r in g.iterrows()
    ]


def gerar_devolucoes_mensal(df_devolucoes: pd.DataFrame) -> list:
    """Devoluções por mês (valor positivo)."""
    g = df_devolucoes.groupby('_ano_mes').agg(
        valor_devolucao=('Total de Mercadoria', lambda x: abs(x.sum())),
        qtd=('Nota Fiscal', 'nunique'),
    ).reset_index().rename(columns={'_ano_mes': 'ano_mes'})
    g = g.sort_values('ano_mes')
    return [
        {
            'ano_mes': r['ano_mes'],
            'valor_devolucao': round(r['valor_devolucao'], 2),
            'qtd': int(r['qtd']),
        }
        for _, r in g.iterrows()
    ]


def gerar_devolucoes_empresa(df_devolucoes: pd.DataFrame) -> list:
    """Devoluções totalizadas por empresa (filial)."""
    if df_devolucoes.empty:
        return []
    g = df_devolucoes.groupby('Minha Empresa (Nome Fantasia)').agg(
        valor_devolucao=('Total de Mercadoria', lambda x: abs(x.sum())),
        qtd=('Nota Fiscal', 'nunique'),
    ).reset_index().rename(columns={'Minha Empresa (Nome Fantasia)': 'Empresa'})
    g = g.sort_values('valor_devolucao', ascending=False)
    return [
        {
            'Empresa': r['Empresa'],
            'valor_devolucao': round(r['valor_devolucao'], 2),
            'qtd': int(r['qtd']),
        }
        for _, r in g.iterrows()
    ]


def gerar_devolucoes_marca(df_devolucoes: pd.DataFrame, top_n: int = 20) -> list:
    """Top N marcas com maior volume de devolução."""
    if df_devolucoes.empty:
        return []
    g = df_devolucoes.groupby('Marca').agg(
        valor_devolucao=('Total de Mercadoria', lambda x: abs(x.sum())),
        qtd=('Nota Fiscal', 'nunique'),
    ).reset_index()
    g = g.sort_values('valor_devolucao', ascending=False).head(top_n)
    return [
        {
            'Marca': r['Marca'],
            'valor_devolucao': round(r['valor_devolucao'], 2),
            'qtd': int(r['qtd']),
        }
        for _, r in g.iterrows()
    ]


def gerar_devolucoes_clientes_top(df_devolucoes: pd.DataFrame, top_n: int = 30) -> list:
    """Top N clientes/hospitais que mais devolvem."""
    if df_devolucoes.empty:
        return []
    g = df_devolucoes.groupby('Cliente (Nome Fantasia)').agg(
        valor_devolucao=('Total de Mercadoria', lambda x: abs(x.sum())),
        qtd=('Nota Fiscal', 'nunique'),
        cnpj=('CNPJ/CPF', 'first'),
        estado=('Estado', 'first'),
        cidade=('Cidade', 'first'),
    ).reset_index()
    g = g.sort_values('valor_devolucao', ascending=False).head(top_n)
    return [
        {
            'Cliente (Nome Fantasia)': r['Cliente (Nome Fantasia)'],
            'CNPJ/CPF': r['cnpj'],
            'Estado': r['estado'],
            'Cidade': r['cidade'],
            'valor_devolucao': round(r['valor_devolucao'], 2),
            'qtd': int(r['qtd']),
        }
        for _, r in g.iterrows()
    ]


def gerar_devolucoes_produtos(df_devolucoes: pd.DataFrame, top_n: int = 30) -> list:
    """Top N produtos mais devolvidos (por valor)."""
    if df_devolucoes.empty:
        return []
    g = df_devolucoes.groupby(['Código do Produto', 'Descrição do Produto', 'Marca']).agg(
        valor_devolucao=('Total de Mercadoria', lambda x: abs(x.sum())),
        qtd_itens=('Quantidade', 'sum'),
        qtd_notas=('Nota Fiscal', 'nunique'),
    ).reset_index()
    g = g.sort_values('valor_devolucao', ascending=False).head(top_n)
    return [
        {
            'Código do Produto': str(r['Código do Produto']) if pd.notna(r['Código do Produto']) else 'N/D',
            'Descrição do Produto': r['Descrição do Produto'],
            'Marca': r['Marca'],
            'valor_devolucao': round(r['valor_devolucao'], 2),
            'qtd_itens': round(abs(r['qtd_itens']), 2) if pd.notna(r['qtd_itens']) else 0,
            'qtd_notas': int(r['qtd_notas']),
        }
        for _, r in g.iterrows()
    ]


def gerar_devolucoes_cidades(df_devolucoes: pd.DataFrame, top_n: int = 30) -> list:
    """Top N cidades que mais devolvem."""
    if df_devolucoes.empty:
        return []
    g = df_devolucoes.groupby(['Cidade', 'Estado']).agg(
        valor_devolucao=('Total de Mercadoria', lambda x: abs(x.sum())),
        qtd_notas=('Nota Fiscal', 'nunique'),
        qtd_clientes=('CNPJ/CPF', 'nunique'),
    ).reset_index()
    g = g.sort_values('valor_devolucao', ascending=False).head(top_n)
    return [
        {
            'Cidade': r['Cidade'],
            'Estado': r['Estado'],
            'valor_devolucao': round(r['valor_devolucao'], 2),
            'qtd_notas': int(r['qtd_notas']),
            'qtd_clientes': int(r['qtd_clientes']),
        }
        for _, r in g.iterrows()
    ]


def gerar_cliente_devolucao_mes(df_devolucoes: pd.DataFrame) -> list:
    """⭐ Sprint 9.32.33: cliente × mês de DEVOLUÇÃO.

    Pra recompor o gráfico mensal e KPIs de devolução quando filtra cliente.
    Estrutura: {CNPJ/CPF, ano_mes, valor_devolucao, qtd}
    """
    if df_devolucoes.empty:
        return []
    g = df_devolucoes.groupby(['CNPJ/CPF', '_ano_mes']).agg(
        valor_devolucao=('Total de Mercadoria', lambda x: abs(x.sum())),
        qtd=('Nota Fiscal', 'nunique'),
    ).reset_index().rename(columns={'_ano_mes': 'ano_mes'})
    g = g.sort_values(['CNPJ/CPF', 'ano_mes'])
    return [
        {
            'CNPJ/CPF': r['CNPJ/CPF'],
            'ano_mes': r['ano_mes'],
            'valor_devolucao': round(r['valor_devolucao'], 2),
            'qtd': int(r['qtd']),
        }
        for _, r in g.iterrows()
    ]


def gerar_cliente_devolucao_empresa_mes(df_devolucoes: pd.DataFrame) -> list:
    """⭐ Sprint 9.32.33: cliente × empresa × mês de DEVOLUÇÃO."""
    if df_devolucoes.empty:
        return []
    g = df_devolucoes.groupby(['CNPJ/CPF', 'Minha Empresa (Nome Fantasia)', '_ano_mes']).agg(
        valor_devolucao=('Total de Mercadoria', lambda x: abs(x.sum())),
        qtd=('Nota Fiscal', 'nunique'),
    ).reset_index().rename(columns={
        '_ano_mes': 'ano_mes',
        'Minha Empresa (Nome Fantasia)': 'Empresa',
    })
    g = g.sort_values(['CNPJ/CPF', 'ano_mes', 'valor_devolucao'], ascending=[True, True, False])
    return [
        {
            'CNPJ/CPF': r['CNPJ/CPF'],
            'Empresa': r['Empresa'],
            'ano_mes': r['ano_mes'],
            'valor_devolucao': round(r['valor_devolucao'], 2),
            'qtd': int(r['qtd']),
        }
        for _, r in g.iterrows()
    ]


def gerar_cliente_devolucao_marca_mes(df_devolucoes: pd.DataFrame) -> list:
    """⭐ Sprint 9.32.33: cliente × marca × mês de DEVOLUÇÃO."""
    if df_devolucoes.empty:
        return []
    g = df_devolucoes.groupby(['CNPJ/CPF', 'Marca', '_ano_mes']).agg(
        valor_devolucao=('Total de Mercadoria', lambda x: abs(x.sum())),
        qtd=('Nota Fiscal', 'nunique'),
    ).reset_index().rename(columns={'_ano_mes': 'ano_mes'})
    g = g.sort_values(['CNPJ/CPF', 'ano_mes', 'valor_devolucao'], ascending=[True, True, False])
    return [
        {
            'CNPJ/CPF': r['CNPJ/CPF'],
            'Marca': r['Marca'],
            'ano_mes': r['ano_mes'],
            'valor_devolucao': round(r['valor_devolucao'], 2),
            'qtd': int(r['qtd']),
        }
        for _, r in g.iterrows()
    ]


def gerar_cliente_devolucao_produto_mes(df_devolucoes: pd.DataFrame) -> list:
    """⭐ Sprint 9.32.33: cliente × produto × mês de DEVOLUÇÃO.

    Sem limite de top porque devoluções têm volume baixo (~400 linhas brutas).
    """
    if df_devolucoes.empty:
        return []
    g = df_devolucoes.groupby(['CNPJ/CPF', 'Código do Produto', 'Descrição do Produto', 'Marca', '_ano_mes']).agg(
        valor_devolucao=('Total de Mercadoria', lambda x: abs(x.sum())),
        qtd_itens=('Quantidade', 'sum'),
        qtd_notas=('Nota Fiscal', 'nunique'),
    ).reset_index().rename(columns={'_ano_mes': 'ano_mes'})
    g = g.sort_values(['CNPJ/CPF', 'ano_mes', 'valor_devolucao'], ascending=[True, True, False])
    return [
        {
            'CNPJ/CPF': r['CNPJ/CPF'],
            'Código do Produto': str(r['Código do Produto']) if pd.notna(r['Código do Produto']) else 'N/D',
            'Descrição do Produto': r['Descrição do Produto'],
            'Marca': r['Marca'],
            'ano_mes': r['ano_mes'],
            'valor_devolucao': round(r['valor_devolucao'], 2),
            'qtd_itens': round(abs(r['qtd_itens']), 2) if pd.notna(r['qtd_itens']) else 0,
            'qtd_notas': int(r['qtd_notas']),
        }
        for _, r in g.iterrows()
    ]


# ─── Agregações POR MÊS (para filtro de mês isolado no dashboard) ──────
# Sprint 9.30.5: dados granulares para permitir recalcular rankings
# quando o usuário clica num mês específico no gráfico.
# Dados menores porque só incluem meses onde houve devolução daquela entidade.

def gerar_devolucoes_empresa_mes(df_devolucoes: pd.DataFrame) -> list:
    """Devoluções por empresa × mês (todos os meses com devolução)."""
    if df_devolucoes.empty:
        return []
    g = df_devolucoes.groupby(['_ano_mes', 'Minha Empresa (Nome Fantasia)']).agg(
        valor_devolucao=('Total de Mercadoria', lambda x: abs(x.sum())),
        qtd=('Nota Fiscal', 'nunique'),
    ).reset_index().rename(columns={'_ano_mes': 'ano_mes', 'Minha Empresa (Nome Fantasia)': 'Empresa'})
    g = g.sort_values(['ano_mes', 'valor_devolucao'], ascending=[True, False])
    return [
        {
            'ano_mes': r['ano_mes'],
            'Empresa': r['Empresa'],
            'valor_devolucao': round(r['valor_devolucao'], 2),
            'qtd': int(r['qtd']),
        }
        for _, r in g.iterrows()
    ]


def gerar_devolucoes_marca_mes(df_devolucoes: pd.DataFrame) -> list:
    """Devoluções por marca × mês."""
    if df_devolucoes.empty:
        return []
    g = df_devolucoes.groupby(['_ano_mes', 'Marca']).agg(
        valor_devolucao=('Total de Mercadoria', lambda x: abs(x.sum())),
        qtd=('Nota Fiscal', 'nunique'),
    ).reset_index().rename(columns={'_ano_mes': 'ano_mes'})
    g = g.sort_values(['ano_mes', 'valor_devolucao'], ascending=[True, False])
    return [
        {
            'ano_mes': r['ano_mes'],
            'Marca': r['Marca'],
            'valor_devolucao': round(r['valor_devolucao'], 2),
            'qtd': int(r['qtd']),
        }
        for _, r in g.iterrows()
    ]


def gerar_devolucoes_produtos_mes(df_devolucoes: pd.DataFrame) -> list:
    """Devoluções por produto × mês."""
    if df_devolucoes.empty:
        return []
    g = df_devolucoes.groupby(['_ano_mes', 'Código do Produto', 'Descrição do Produto', 'Marca']).agg(
        valor_devolucao=('Total de Mercadoria', lambda x: abs(x.sum())),
        qtd_itens=('Quantidade', 'sum'),
        qtd_notas=('Nota Fiscal', 'nunique'),
    ).reset_index().rename(columns={'_ano_mes': 'ano_mes'})
    g = g.sort_values(['ano_mes', 'valor_devolucao'], ascending=[True, False])
    return [
        {
            'ano_mes': r['ano_mes'],
            'Código do Produto': str(r['Código do Produto']) if pd.notna(r['Código do Produto']) else 'N/D',
            'Descrição do Produto': r['Descrição do Produto'],
            'Marca': r['Marca'],
            'valor_devolucao': round(r['valor_devolucao'], 2),
            'qtd_itens': round(abs(r['qtd_itens']), 2) if pd.notna(r['qtd_itens']) else 0,
            'qtd_notas': int(r['qtd_notas']),
        }
        for _, r in g.iterrows()
    ]


def gerar_devolucoes_cidades_mes(df_devolucoes: pd.DataFrame) -> list:
    """Devoluções por cidade × mês."""
    if df_devolucoes.empty:
        return []
    g = df_devolucoes.groupby(['_ano_mes', 'Cidade', 'Estado']).agg(
        valor_devolucao=('Total de Mercadoria', lambda x: abs(x.sum())),
        qtd_notas=('Nota Fiscal', 'nunique'),
        qtd_clientes=('CNPJ/CPF', 'nunique'),
    ).reset_index().rename(columns={'_ano_mes': 'ano_mes'})
    g = g.sort_values(['ano_mes', 'valor_devolucao'], ascending=[True, False])
    return [
        {
            'ano_mes': r['ano_mes'],
            'Cidade': r['Cidade'],
            'Estado': r['Estado'],
            'valor_devolucao': round(r['valor_devolucao'], 2),
            'qtd_notas': int(r['qtd_notas']),
            'qtd_clientes': int(r['qtd_clientes']),
        }
        for _, r in g.iterrows()
    ]


def gerar_consignado_mensal(df_consignado: pd.DataFrame) -> list:
    """Consignado por mês."""
    g = df_consignado.groupby('_ano_mes').agg(
        valor_consignado=('Total de Mercadoria', 'sum'),
        qtd=('Nota Fiscal', 'nunique'),
    ).reset_index().rename(columns={'_ano_mes': 'ano_mes'})
    g = g.sort_values('ano_mes')
    return [
        {
            'ano_mes': r['ano_mes'],
            'valor_consignado': round(r['valor_consignado'], 2),
            'qtd': int(r['qtd']),
        }
        for _, r in g.iterrows()
    ]


def gerar_empresa_total(df_vendas: pd.DataFrame) -> list:
    """Total por empresa."""
    g = df_vendas.groupby('Minha Empresa (Nome Fantasia)').agg(
        faturamento=('Total de Mercadoria', 'sum'),
        qtd_notas=('Nota Fiscal', 'nunique'),
    ).reset_index().rename(columns={'Minha Empresa (Nome Fantasia)': 'Empresa'})
    g['ticket_medio'] = g['faturamento'] / g['qtd_notas'].replace(0, 1)
    g = g.sort_values('faturamento', ascending=False)
    return [
        {
            'Empresa': r['Empresa'],
            'faturamento': round(r['faturamento'], 2),
            'qtd_notas': int(r['qtd_notas']),
            'ticket_medio': round(r['ticket_medio'], 2),
        }
        for _, r in g.iterrows()
    ]


def gerar_empresa_mes(df_vendas: pd.DataFrame) -> list:
    """Empresa × mês."""
    g = df_vendas.groupby(['Minha Empresa (Nome Fantasia)', '_ano_mes']).agg(
        faturamento=('Total de Mercadoria', 'sum'),
        qtd_notas=('Nota Fiscal', 'nunique'),
    ).reset_index().rename(columns={
        'Minha Empresa (Nome Fantasia)': 'Empresa',
        '_ano_mes': 'ano_mes',
    })
    g = g.sort_values(['Empresa', 'ano_mes'])
    return [
        {
            'Empresa': r['Empresa'],
            'ano_mes': r['ano_mes'],
            'faturamento': round(r['faturamento'], 2),
            'qtd_notas': int(r['qtd_notas']),
        }
        for _, r in g.iterrows()
    ]


def gerar_empresa_clientes_top(df_vendas: pd.DataFrame, n: int = TOP_CLIENTES) -> list:
    """Top N clientes POR EMPRESA. Sprint 9.32.30."""
    tem_razao = 'Cliente (Razão Social)' in df_vendas.columns
    agg = {
        'faturamento': ('Total de Mercadoria', 'sum'),
        'qtd_notas': ('Nota Fiscal', 'nunique'),
        'cnpj': ('CNPJ/CPF', 'first'),
        'cidade': ('Cidade', 'first'),
        'estado': ('Estado', 'first'),
    }
    if tem_razao:
        agg['razao_social'] = ('Cliente (Razão Social)', 'first')

    g = df_vendas.groupby(['Minha Empresa (Nome Fantasia)', 'Cliente (Nome Fantasia)']).agg(**agg).reset_index()
    g = g.rename(columns={'Minha Empresa (Nome Fantasia)': 'Empresa'})

    # Pra cada empresa, pega top N
    resultado = []
    for empresa in g['Empresa'].unique():
        topn = g[g['Empresa'] == empresa].sort_values('faturamento', ascending=False).head(n)
        for _, r in topn.iterrows():
            resultado.append({
                'Empresa': r['Empresa'],
                'Cliente (Nome Fantasia)': r['Cliente (Nome Fantasia)'],
                'Cliente (Razão Social)': r['razao_social'] if tem_razao else r['Cliente (Nome Fantasia)'],
                'CNPJ/CPF': r['cnpj'],
                'Cidade': r['cidade'],
                'Estado': r['estado'],
                'faturamento': round(r['faturamento'], 2),
                'qtd_notas': int(r['qtd_notas']),
            })
    return resultado


def gerar_tipo_pessoa_total(df_vendas: pd.DataFrame) -> list:
    """PF vs PJ totalizado."""
    g = df_vendas.groupby('tipo_pessoa').agg(
        faturamento=('Total de Mercadoria', 'sum'),
        qtd_notas=('Nota Fiscal', 'nunique'),
        qtd_clientes=('CNPJ/CPF', 'nunique'),
    ).reset_index()
    g['ticket_medio'] = g['faturamento'] / g['qtd_notas'].replace(0, 1)
    return [
        {
            'tipo_pessoa': r['tipo_pessoa'],
            'faturamento': round(r['faturamento'], 2),
            'qtd_notas': int(r['qtd_notas']),
            'qtd_clientes': int(r['qtd_clientes']),
            'ticket_medio': round(r['ticket_medio'], 2),
        }
        for _, r in g.iterrows() if r['tipo_pessoa'] != 'N/D'
    ]


def gerar_tipo_pessoa_mes(df_vendas: pd.DataFrame) -> list:
    """PF/PJ × mês."""
    g = df_vendas[df_vendas['tipo_pessoa'] != 'N/D'].groupby(['tipo_pessoa', '_ano_mes']).agg(
        faturamento=('Total de Mercadoria', 'sum'),
        qtd_notas=('Nota Fiscal', 'nunique'),
    ).reset_index().rename(columns={
        'tipo_pessoa': 'tipo',
        '_ano_mes': 'ano_mes',
    })
    g = g.sort_values(['tipo', 'ano_mes'])
    return [
        {
            'tipo': r['tipo'],
            'ano_mes': r['ano_mes'],
            'faturamento': round(r['faturamento'], 2),
            'qtd_notas': int(r['qtd_notas']),
        }
        for _, r in g.iterrows()
    ]


# ══════════════════════════════════════════════════════════════════════════
# VALIDAÇÃO
# ══════════════════════════════════════════════════════════════════════════

def validar(dados: dict, df: pd.DataFrame) -> list:
    """Roda sanity checks e retorna lista de avisos."""
    avisos = []

    # 1. Soma mensal == soma clientes_top limitado?  (NÃO deve bater, clientes_top é só top N)
    #    Mas soma do mensal deve bater com soma total de vendas do df
    soma_mensal = sum(m['faturamento'] for m in dados['mensal'])
    soma_df = df[df['_categoria'] == 'Venda']['Total de Mercadoria'].sum()
    diff_pct = abs(soma_mensal - soma_df) / soma_df * 100 if soma_df else 0
    if diff_pct > 0.5:
        avisos.append(f"⚠ Soma mensal ({soma_mensal:,.2f}) diverge da soma do DF ({soma_df:,.2f}) em {diff_pct:.2f}%")

    # 2. Se marca_mes existe, soma por mês deve bater com mensal
    if dados.get('marca_mes'):
        por_mes_marca = defaultdict(float)
        for mm in dados['marca_mes']:
            por_mes_marca[mm['ano_mes']] += mm['faturamento']
        for m in dados['mensal']:
            esperado = m['faturamento']
            obtido = por_mes_marca.get(m['ano_mes'], 0)
            diff = abs(esperado - obtido) / esperado * 100 if esperado else 0
            if diff > 1:
                avisos.append(f"⚠ marca_mes de {m['ano_mes']}: soma {obtido:,.2f} vs mensal {esperado:,.2f} ({diff:.1f}% diff)")

    # 3. Verifica se alguma marca tem faturamento nulo
    marcas_zeradas = [m for m in dados['marcas'] if m['faturamento'] == 0]
    if marcas_zeradas:
        avisos.append(f"⚠ {len(marcas_zeradas)} marca(s) com faturamento zerado")

    # 4. Verifica se há muitos N/D em Estado
    estado_nd = next((e for e in dados['estados'] if e['Estado'] == 'N/D'), None)
    if estado_nd and estado_nd['qtd_clientes'] > 10:
        avisos.append(f"⚠ {estado_nd['qtd_clientes']} clientes sem Estado definido (N/D)")

    return avisos


# ══════════════════════════════════════════════════════════════════════════
# MAIN
# ══════════════════════════════════════════════════════════════════════════

def main():
    if len(sys.argv) < 2:
        print("Uso: python gerar_faturamento_json.py arquivo1.xlsx [arquivo2.xlsx ...]")
        sys.exit(1)

    caminhos = sys.argv[1:]
    for c in caminhos:
        if not Path(c).exists():
            print(f"❌ Arquivo não encontrado: {c}")
            sys.exit(1)

    print("\n" + "═" * 70)
    print("  GERADOR DE FATURAMENTO JSON — Sprint 9.32.35")
    print("═" * 70 + "\n")

    # Lê e concatena todos os XLSX
    dfs = [ler_xlsx(c) for c in caminhos]
    df = pd.concat(dfs, ignore_index=True)
    print(f"\n📊 Total após concatenação: {len(df):,} linhas")

    # Deduplica (se mesma nota aparecer em 2 arquivos — pode acontecer em overlaps)
    antes = len(df)
    # Chave de dedupe: Nota Fiscal + Código do Produto + CNPJ (+ Operação pra segurança)
    df = df.drop_duplicates(subset=['Nota Fiscal', 'Código do Produto', 'CNPJ/CPF', 'Operação'], keep='first')
    if len(df) < antes:
        print(f"🔍 Deduplicação removeu {antes - len(df):,} duplicatas")

    # Filtra por categoria
    df_vendas     = df[df['_categoria'] == 'Venda'].copy()
    df_devolucoes = df[df['_categoria'] == 'Devolução'].copy()
    df_consignado = df[df['_categoria'] == 'Consignado'].copy()

    print(f"\n  Vendas:     {len(df_vendas):,} linhas / R$ {df_vendas['Total de Mercadoria'].sum():,.2f}")
    print(f"  Devoluções: {len(df_devolucoes):,} linhas / R$ {abs(df_devolucoes['Total de Mercadoria'].sum()):,.2f}")
    print(f"  Consignado: {len(df_consignado):,} linhas / R$ {df_consignado['Total de Mercadoria'].sum():,.2f}")

    # Gera todas as agregações
    print("\n🔨 Gerando agregações...")
    dados = {
        'meta': {
            'gerado_em': datetime.now().isoformat(),
            'periodo_inicio': df_vendas['Data de Emissão (completa)'].min().strftime('%Y-%m-%d'),
            'periodo_fim': df_vendas['Data de Emissão (completa)'].max().strftime('%Y-%m-%d'),
            'total_vendas': int(df_vendas['Nota Fiscal'].nunique()),
            'faturamento_total': round(df_vendas['Total de Mercadoria'].sum(), 2),
            'total_devolucoes': round(abs(df_devolucoes['Total de Mercadoria'].sum()), 2),
            'total_consignado': round(df_consignado['Total de Mercadoria'].sum(), 2),
            'qtd_clientes_unicos': int(df_vendas['CNPJ/CPF'].nunique()),
            'qtd_produtos_unicos': int(df_vendas['Código do Produto'].nunique()),
            'qtd_marcas': int(df_vendas['Marca'].nunique()),
            'qtd_vendedores': int(df_vendas['Vendedor'].nunique()),
            'arquivos_origem': [Path(c).name for c in caminhos],
        },
        'mensal':              gerar_mensal(df_vendas),
        'vendedor_mes':        gerar_vendedor_mes(df_vendas),
        'clientes_top':        gerar_clientes_top(df_vendas),
        'clientes_lista':      gerar_clientes_lista(df_vendas),  # ⭐ Sprint 9.32.27 — todos os clientes pra busca
        'clientes_mes':        gerar_clientes_mes(df_vendas),  # ⭐ Sprint 9.32.31 — TODOS os clientes (sem mais top N)
        'cliente_vendedor_mes': gerar_cliente_vendedor_mes(df_vendas),  # ⭐ Sprint 9.32.31 — cruzamento cliente × vendedor
        'cliente_marca_mes':    gerar_cliente_marca_mes(df_vendas),     # ⭐ Sprint 9.32.31 — cruzamento cliente × marca
        'cliente_empresa_mes':  gerar_cliente_empresa_mes(df_vendas),   # ⭐ Sprint 9.32.32 — cruzamento cliente × empresa
        'cliente_produto_mes':  gerar_cliente_produto_mes(df_vendas),   # ⭐ Sprint 9.32.31 — cruzamento cliente × produto (top 30/cli)
        'produtos_por_cliente': gerar_produtos_por_cliente(df_vendas),
        'marcas':              gerar_marcas(df_vendas),
        'marca_mes':           gerar_marca_mes(df_vendas),
        'produtos_top':        gerar_produtos_top(df_vendas),
        'estados':             gerar_estados(df_vendas),
        'devolucoes_mensal':   gerar_devolucoes_mensal(df_devolucoes),
        'devolucoes_empresa':        gerar_devolucoes_empresa(df_devolucoes),
        'devolucoes_marca':          gerar_devolucoes_marca(df_devolucoes),
        'devolucoes_clientes_top':   gerar_devolucoes_clientes_top(df_devolucoes),
        'devolucoes_produtos':       gerar_devolucoes_produtos(df_devolucoes),
        'devolucoes_cidades':        gerar_devolucoes_cidades(df_devolucoes),
        # Granulares por mês (para filtro de mês isolado)
        'devolucoes_empresa_mes':    gerar_devolucoes_empresa_mes(df_devolucoes),
        'devolucoes_marca_mes':      gerar_devolucoes_marca_mes(df_devolucoes),
        'devolucoes_produtos_mes':   gerar_devolucoes_produtos_mes(df_devolucoes),
        'devolucoes_cidades_mes':    gerar_devolucoes_cidades_mes(df_devolucoes),
        # Sprint 9.32.33 — cruzamentos de devolução por cliente
        'cliente_devolucao_mes':         gerar_cliente_devolucao_mes(df_devolucoes),
        'cliente_devolucao_empresa_mes': gerar_cliente_devolucao_empresa_mes(df_devolucoes),
        'cliente_devolucao_marca_mes':   gerar_cliente_devolucao_marca_mes(df_devolucoes),
        'cliente_devolucao_produto_mes': gerar_cliente_devolucao_produto_mes(df_devolucoes),
        'consignado_mensal':   gerar_consignado_mensal(df_consignado),
        'empresa_total':       gerar_empresa_total(df_vendas),
        'empresa_mes':         gerar_empresa_mes(df_vendas),
        'empresa_clientes_top': gerar_empresa_clientes_top(df_vendas),  # Sprint 9.32.30 — top clientes por empresa
        'tipo_pessoa_total':   gerar_tipo_pessoa_total(df_vendas),
        'tipo_pessoa_mes':     gerar_tipo_pessoa_mes(df_vendas),
    }
    print(f"   ✓ mensal: {len(dados['mensal'])} meses")
    print(f"   ✓ vendedor_mes: {len(dados['vendedor_mes'])} linhas")
    print(f"   ✓ clientes_top: {len(dados['clientes_top'])} clientes")
    print(f"   ✓ clientes_lista: {len(dados['clientes_lista'])} clientes (lista enxuta pra busca)")
    print(f"   ✓ clientes_mes: {len(dados['clientes_mes'])} linhas (cliente × mês — TODOS)")
    print(f"   ✓ cliente_vendedor_mes: {len(dados['cliente_vendedor_mes'])} linhas (cliente × vendedor × mês)")
    print(f"   ✓ cliente_marca_mes: {len(dados['cliente_marca_mes'])} linhas (cliente × marca × mês)")
    print(f"   ✓ cliente_empresa_mes: {len(dados['cliente_empresa_mes'])} linhas (cliente × empresa × mês)")
    print(f"   ✓ cliente_produto_mes: {len(dados['cliente_produto_mes'])} linhas (cliente × top 30 produtos × mês)")
    print(f"   ✓ produtos_por_cliente: {len(dados['produtos_por_cliente'])} hospitais c/ lista de produtos")
    print(f"   ✓ marcas: {len(dados['marcas'])} marcas")
    print(f"   ✓ marca_mes: {len(dados['marca_mes'])} linhas (marca × mês)")
    print(f"   ✓ produtos_top: {len(dados['produtos_top'])} produtos")
    print(f"   ✓ estados: {len(dados['estados'])} estados")
    print(f"   ✓ empresa_total: {len(dados['empresa_total'])} empresas")
    print(f"   ✓ empresa_mes: {len(dados['empresa_mes'])} linhas")
    print(f"   ✓ empresa_clientes_top: {len(dados['empresa_clientes_top'])} linhas (top clientes por empresa)")
    print(f"   ✓ tipo_pessoa_mes: {len(dados['tipo_pessoa_mes'])} linhas")

    # Validação
    print("\n🔎 Validação:")
    avisos = validar(dados, df)
    if avisos:
        for a in avisos: print(f"   {a}")
    else:
        print("   ✅ Todos os checks passaram!")

    # Sprint 9.32.28b: SOLUÇÃO NUCLEAR — limpa TODOS os NaN do JSON recursivamente
    # antes de salvar. Garante que NaN nunca sai pro JSON, independente de qual
    # função geradora deixou passar.
    import math
    def limpar_nan(obj):
        """Remove NaN/Infinity de qualquer estrutura aninhada (dict, list, valores).
        NaN/None/pd.NA sempre vira '' (string vazia).
        Infinity vira 0.0.
        """
        if isinstance(obj, dict):
            return {k: limpar_nan(v) for k, v in obj.items()}
        if isinstance(obj, list):
            return [limpar_nan(v) for v in obj]
        if obj is None:
            return ''
        if isinstance(obj, float):
            if math.isnan(obj):
                return ''  # NaN sempre vira string vazia (mais seguro pra strings)
            if math.isinf(obj):
                return 0.0
            return obj
        try:
            # Pandas NA / NaT / NaN podem não bater isinstance float
            if pd.isna(obj):
                return ''
        except (TypeError, ValueError):
            pass
        return obj

    print("\n🧹 Limpando NaN/Infinity do JSON antes de salvar...")
    dados = limpar_nan(dados)
    print("   ✓ Limpeza concluída")

    # Sprint 9.32.35: salva APENAS o JSON puro. O index.html consome via fetch().
    # atualizar_index.py vai calcular o hash e injetar como cache buster.
    out_json = 'faturamento_data_inline.json'
    try:
        with open(out_json, 'w', encoding='utf-8') as f:
            json.dump(dados, f, ensure_ascii=False, separators=(',', ':'), allow_nan=False)
    except ValueError as e:
        print(f"\n❌ ERRO: JSON contém NaN/Infinity! {e}")
        print("   → Algum campo do XLSX está vazio e a normalização não pegou.")
        print("   → Arquivo NÃO foi salvo. Ajuste o script ou o XLSX.")
        sys.exit(1)
    tamanho_mb = Path(out_json).stat().st_size / 1024 / 1024
    print(f"💾 Salvo: {out_json} ({tamanho_mb:.2f} MB)")

    print("\n" + "═" * 70)
    print("  PRÓXIMO PASSO")
    print("═" * 70)
    print(f"""
  Período: {dados['meta']['periodo_inicio']} → {dados['meta']['periodo_fim']}

  Agora rode atualizar_index.py pra calcular o hash do JSON
  e injetar no index.html como cache buster:

      python atualizar_index.py

  Ou use atualizar_dashboard.bat que já faz tudo: gerar JSON +
  atualizar HTML + git add/commit/push.
""")


if __name__ == '__main__':
    main()
