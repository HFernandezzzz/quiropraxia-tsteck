# Dados

## ⚠️ Nenhum dado real neste diretório

O arquivo `dados-exemplo.json` contém **registros inteiramente fictícios**, criados para demonstrar o funcionamento do sistema. Nomes, matrículas, ramais, diagnósticos, medicamentos, afastamentos e movimentações de estoque são inventados. **Nenhuma informação corresponde a colaborador real da TS Teck.**

As matrículas seguem o padrão `DEMO-000` e os ramais são `Ramal 000` justamente para que ninguém confunda o conjunto com dado de produção. Todo registro carrega os campos `ficticio: true` e `exemplo: true`.

Dentro do sistema, esses registros aparecem sob um aviso permanente e podem ser removidos de uma vez pelo botão **"Apagar dados de exemplo"**, no Painel ou em Configurações.

## Regra para este repositório

**Nunca faça commit de dado real de colaborador.** Ficha clínica é dado pessoal sensível de saúde, protegido pelo art. 11 da LGPD, e deve existir apenas no banco da empresa, com acesso restrito ao profissional responsável pelo atendimento — jamais em repositório de código, mesmo privado.

O `.gitignore` na raiz já bloqueia os padrões de risco (`db/backup-*.json`, `db/producao*.json`, `*.sqlite`, `*.db`, `.env`, chaves). Isso é uma rede de proteção, não uma autorização: a responsabilidade continua sendo de quem faz o commit.

Para popular um ambiente de homologação, use este arquivo. Para produção, comece com a base vazia.

## Arquivos

| Arquivo | Conteúdo |
|---|---|
| `schema.sql` | Schema relacional proposto (PostgreSQL, com notas para MySQL), índices, views dos indicadores e tabela de log de acesso. No final há uma alternativa simplificada em JSONB. |
| `dados-exemplo.json` | 54 registros fictícios: 4 colaboradores, 26 atendimentos ao longo de 5 meses, 6 afastamentos, 6 itens de estoque, 8 movimentações, 2 solicitações de compra, 1 profissional e os parâmetros do sistema. |

O formato do `dados-exemplo.json` é exatamente o mesmo do backup gerado pelo próprio sistema (Configurações → Backup completo), então serve tanto para importar quanto como referência da estrutura de cada coleção.
