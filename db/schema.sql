-- =====================================================================
-- Sistema da Sala de Quiropraxia — TS Teck
-- Proposta de schema relacional
-- Dialeto: PostgreSQL 13+   (notas para MySQL 8 ao final de cada bloco)
-- =====================================================================
-- Convenções:
--   * Todos os ids são TEXT porque são gerados no cliente (base36).
--     Se preferir UUID, troque para UUID e ajuste o gerador no front.
--   * Datas simples usam DATE; carimbos de auditoria usam TIMESTAMPTZ.
--   * ON DELETE RESTRICT nas fichas: histórico clínico não deve sumir
--     por exclusão acidental de cadastro.
-- =====================================================================

BEGIN;

-- ---------------------------------------------------------------------
-- Usuários (espelho do diretório corporativo; só o necessário)
-- ---------------------------------------------------------------------
CREATE TABLE usuarios (
  id            TEXT PRIMARY KEY,
  nome          TEXT NOT NULL,
  email         TEXT UNIQUE,
  perfil        TEXT NOT NULL DEFAULT 'operacional'
                CHECK (perfil IN ('clinico','operacional','admin')),
  ativo         BOOLEAN NOT NULL DEFAULT TRUE,
  criado_em     TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON COLUMN usuarios.perfil IS
  'clinico/admin => canEdit = true (acessa ficha clínica); operacional => somente compras, estoque e resumos';

-- ---------------------------------------------------------------------
-- Profissionais que realizam os atendimentos
-- ---------------------------------------------------------------------
CREATE TABLE profissionais (
  id            TEXT PRIMARY KEY,
  nome          TEXT NOT NULL,
  registro      TEXT,
  ativo         BOOLEAN NOT NULL DEFAULT TRUE,
  atualizado_em TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------
-- Colaboradores (coleção "pacientes")  ---- DADO SENSÍVEL DE SAÚDE ----
-- ---------------------------------------------------------------------
CREATE TABLE colaboradores (
  id                TEXT PRIMARY KEY,
  nome              TEXT NOT NULL,
  matricula         TEXT,
  setor             TEXT,
  funcao            TEXT,
  turno             TEXT,
  nascimento        DATE,
  admissao          DATE,
  telefone          TEXT,
  ativo             BOOLEAN NOT NULL DEFAULT TRUE,

  -- avaliação da coluna
  problema_coluna   TEXT CHECK (problema_coluna IN
                      ('Não','Sim - em investigação','Sim - diagnosticado','Não informado')),
  diagnostico       TEXT,
  exames            TEXT,
  cirurgias         TEXT,

  -- saúde geral
  usa_medicamento   BOOLEAN,
  medicamentos      TEXT,
  atividade         TEXT,
  posto             TEXT,
  esforco           TEXT,
  contraindicacoes  TEXT,

  -- liberação e consentimento
  apto              BOOLEAN NOT NULL DEFAULT TRUE,
  motivo_nao_apto   TEXT,
  consentimento     BOOLEAN NOT NULL DEFAULT FALSE,
  assinatura_id     TEXT,          -- id do arquivo no storage
  assinatura_em     DATE,

  observacoes       TEXT,

  -- anamnese preenchida pelo próprio colaborador
  origem            TEXT CHECK (origem IN ('cadastro','autoatendimento')) DEFAULT 'cadastro',
  revisado          BOOLEAN NOT NULL DEFAULT TRUE,

  exemplo           BOOLEAN NOT NULL DEFAULT FALSE,
  criado_em         TIMESTAMPTZ NOT NULL DEFAULT now(),
  criado_por        TEXT REFERENCES usuarios(id),
  atualizado_em     TIMESTAMPTZ NOT NULL DEFAULT now(),
  alterado_por      TEXT REFERENCES usuarios(id)
);
CREATE INDEX idx_colab_nome   ON colaboradores (nome);
CREATE INDEX idx_colab_setor  ON colaboradores (setor);
CREATE INDEX idx_colab_ativo  ON colaboradores (ativo);

-- Regiões afetadas declaradas na ficha (lista)
CREATE TABLE colaborador_regioes (
  colaborador_id TEXT NOT NULL REFERENCES colaboradores(id) ON DELETE CASCADE,
  regiao         TEXT NOT NULL,
  PRIMARY KEY (colaborador_id, regiao)
);

-- Anexos da ficha (laudos, exames, atestados)
CREATE TABLE colaborador_anexos (
  id             TEXT PRIMARY KEY,      -- id do arquivo no storage
  colaborador_id TEXT NOT NULL REFERENCES colaboradores(id) ON DELETE CASCADE,
  nome           TEXT NOT NULL,
  tipo           TEXT,                  -- content-type
  enviado_em     DATE NOT NULL DEFAULT CURRENT_DATE
);

-- ---------------------------------------------------------------------
-- Atendimentos  ---- DADO SENSÍVEL DE SAÚDE ----
-- ---------------------------------------------------------------------
CREATE TABLE atendimentos (
  id              TEXT PRIMARY KEY,
  colaborador_id  TEXT NOT NULL REFERENCES colaboradores(id) ON DELETE RESTRICT,
  profissional_id TEXT REFERENCES profissionais(id),
  data            DATE NOT NULL,
  hora            TIME,
  tipo            TEXT,
  status          TEXT NOT NULL DEFAULT 'Agendado'
                  CHECK (status IN ('Agendado','Realizado','Faltou','Cancelado')),
  duracao_min     INTEGER,
  queixa          TEXT,
  dor_antes       SMALLINT CHECK (dor_antes  BETWEEN 0 AND 10),
  dor_depois      SMALLINT CHECK (dor_depois BETWEEN 0 AND 10),
  avaliacao       SMALLINT CHECK (avaliacao  BETWEEN 1 AND 5),
  evolucao        TEXT,
  proxima         DATE,
  encaminhamento  TEXT,
  redflag         BOOLEAN NOT NULL DEFAULT FALSE,  -- contraindicação confirmada
  exemplo         BOOLEAN NOT NULL DEFAULT FALSE,
  criado_em       TIMESTAMPTZ NOT NULL DEFAULT now(),
  criado_por      TEXT REFERENCES usuarios(id),
  atualizado_em   TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_atend_data   ON atendimentos (data);
CREATE INDEX idx_atend_colab  ON atendimentos (colaborador_id, data DESC);
CREATE INDEX idx_atend_status ON atendimentos (status);
-- Conflito de agenda: um profissional por horário
CREATE UNIQUE INDEX uq_atend_slot ON atendimentos (profissional_id, data, hora)
  WHERE status <> 'Cancelado' AND profissional_id IS NOT NULL;
-- MySQL 8: índices parciais não existem; validar o conflito na aplicação.

CREATE TABLE atendimento_regioes (
  atendimento_id TEXT NOT NULL REFERENCES atendimentos(id) ON DELETE CASCADE,
  regiao         TEXT NOT NULL,
  PRIMARY KEY (atendimento_id, regiao)
);

CREATE TABLE atendimento_tecnicas (
  atendimento_id TEXT NOT NULL REFERENCES atendimentos(id) ON DELETE CASCADE,
  tecnica        TEXT NOT NULL,
  PRIMARY KEY (atendimento_id, tecnica)
);

-- Mapa corporal: cada ponto de dor marcado na sessão
CREATE TABLE atendimento_pontos (
  id             BIGSERIAL PRIMARY KEY,
  atendimento_id TEXT NOT NULL REFERENCES atendimentos(id) ON DELETE CASCADE,
  face           CHAR(1) NOT NULL CHECK (face IN ('f','b')),  -- frente / costas
  x              NUMERIC(6,2) NOT NULL,   -- viewBox 0..120
  y              NUMERIC(6,2) NOT NULL,   -- viewBox 0..190
  intensidade    SMALLINT NOT NULL CHECK (intensidade BETWEEN 1 AND 3)
);
-- MySQL 8: BIGSERIAL -> BIGINT AUTO_INCREMENT

-- ---------------------------------------------------------------------
-- Estoque da sala
-- ---------------------------------------------------------------------
CREATE TABLE estoque_itens (
  id            TEXT PRIMARY KEY,
  item          TEXT NOT NULL,
  categoria     TEXT,
  unidade       TEXT,
  quantidade    NUMERIC(12,2) NOT NULL DEFAULT 0,
  minimo        NUMERIC(12,2) NOT NULL DEFAULT 0,
  validade      DATE,
  fornecedor    TEXT,
  local         TEXT,
  obs           TEXT,
  exemplo       BOOLEAN NOT NULL DEFAULT FALSE,
  atualizado_em TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_estoque_item ON estoque_itens (item);

CREATE TABLE estoque_movimentacoes (
  id             TEXT PRIMARY KEY,
  item_id        TEXT REFERENCES estoque_itens(id) ON DELETE SET NULL,
  item_nome      TEXT NOT NULL,          -- nome no momento do lançamento
  tipo           TEXT NOT NULL CHECK (tipo IN
                   ('Entrada','Saída','Descarte','Ajuste de inventário')),
  quantidade     NUMERIC(12,2) NOT NULL,
  motivo         TEXT,
  atendimento_id TEXT REFERENCES atendimentos(id) ON DELETE SET NULL,
  data           DATE NOT NULL,
  usuario_id     TEXT REFERENCES usuarios(id),
  criado_em      TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_mov_item ON estoque_movimentacoes (item_id, data DESC);
CREATE INDEX idx_mov_data ON estoque_movimentacoes (data DESC);

-- ---------------------------------------------------------------------
-- Solicitações de compra (interface com Suprimentos)
-- ---------------------------------------------------------------------
CREATE TABLE solicitacoes (
  id             TEXT PRIMARY KEY,
  numero         TEXT NOT NULL UNIQUE,          -- SOL-2026-0001
  data           DATE NOT NULL,
  urgencia       TEXT NOT NULL DEFAULT 'Normal' CHECK (urgencia IN ('Normal','Urgente')),
  solicitante    TEXT,
  justificativa  TEXT,
  status         TEXT NOT NULL DEFAULT 'Pendente'
                 CHECK (status IN ('Pendente','Aprovado','Comprado','Entregue','Recusado')),
  pedido         TEXT,                          -- nº do pedido de compra / NF
  previsao       DATE,
  resposta       TEXT,
  exemplo        BOOLEAN NOT NULL DEFAULT FALSE,
  criado_em      TIMESTAMPTZ NOT NULL DEFAULT now(),
  criado_por     TEXT REFERENCES usuarios(id),
  atualizado_em  TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_sol_status ON solicitacoes (status, data DESC);

CREATE TABLE solicitacao_itens (
  id             BIGSERIAL PRIMARY KEY,
  solicitacao_id TEXT NOT NULL REFERENCES solicitacoes(id) ON DELETE CASCADE,
  descricao      TEXT NOT NULL,
  quantidade     NUMERIC(12,2) NOT NULL,
  unidade        TEXT,
  obs            TEXT
);

-- ---------------------------------------------------------------------
-- Afastamentos (base do indicador de absenteísmo e custo)
-- ---------------------------------------------------------------------
CREATE TABLE afastamentos (
  id             TEXT PRIMARY KEY,
  colaborador_id TEXT NOT NULL REFERENCES colaboradores(id) ON DELETE RESTRICT,
  inicio         DATE NOT NULL,
  dias           INTEGER NOT NULL CHECK (dias > 0),
  motivo         TEXT,
  relacionado    BOOLEAN NOT NULL DEFAULT TRUE,  -- ligado a coluna/musculoesquelético
  obs            TEXT,
  exemplo        BOOLEAN NOT NULL DEFAULT FALSE,
  criado_em      TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_afast_periodo ON afastamentos (inicio);

-- ---------------------------------------------------------------------
-- Resumos mensais publicados (visíveis ao perfil operacional)
-- ---------------------------------------------------------------------
CREATE TABLE resumos_mensais (
  competencia    CHAR(7) PRIMARY KEY,           -- 'AAAA-MM'
  atendimentos   INTEGER NOT NULL DEFAULT 0,
  colaboradores  INTEGER NOT NULL DEFAULT 0,
  alivio         NUMERIC(4,1),
  dias_perdidos  INTEGER NOT NULL DEFAULT 0,
  custo          NUMERIC(12,2) NOT NULL DEFAULT 0,
  faltas         INTEGER NOT NULL DEFAULT 0,
  satisfacao     NUMERIC(3,1),
  setores        JSONB,                          -- [["Produção",4], ...]
  regioes        JSONB,
  publicado_em   TIMESTAMPTZ NOT NULL DEFAULT now(),
  publicado_por  TEXT REFERENCES usuarios(id)
);
-- MySQL 8: JSONB -> JSON

-- ---------------------------------------------------------------------
-- Parâmetros do sistema (equivale ao documento config/geral)
-- ---------------------------------------------------------------------
CREATE TABLE parametros (
  chave  TEXT PRIMARY KEY,
  valor  TEXT NOT NULL
);
INSERT INTO parametros (chave, valor) VALUES
  ('empresa',        'TS Teck'),
  ('custoDia',       '320'),      -- custo médio de um dia de afastamento (R$)
  ('horaInicio',     '07:00'),
  ('horaFim',        '17:00'),
  ('passo',          '30'),       -- intervalo da grade da agenda (min)
  ('duracao',        '30'),       -- duração padrão da sessão (min)
  ('diasSemana',     '[1,2,3,4,5]'),
  ('diasRetorno',    '45'),       -- alerta de colaborador sem retorno
  ('diasValidade',   '45'),       -- alerta de validade próxima
  ('janelaConsumo',  '60');       -- janela do cálculo de consumo médio

-- ---------------------------------------------------------------------
-- Log de acesso a dado clínico (exigência prática de LGPD)
-- ---------------------------------------------------------------------
CREATE TABLE log_acesso (
  id             BIGSERIAL PRIMARY KEY,
  usuario_id     TEXT REFERENCES usuarios(id),
  entidade       TEXT NOT NULL,     -- 'colaborador' | 'atendimento' | 'anexo'
  entidade_id    TEXT NOT NULL,
  acao           TEXT NOT NULL,     -- 'leitura' | 'escrita' | 'exclusao' | 'exportacao'
  em             TIMESTAMPTZ NOT NULL DEFAULT now(),
  ip             INET
);
CREATE INDEX idx_log_entidade ON log_acesso (entidade, entidade_id, em DESC);

COMMIT;

-- =====================================================================
-- VIEWS ÚTEIS PARA OS INDICADORES DO SISTEMA
-- =====================================================================

-- Consumo médio diário por item, na janela de 60 dias
CREATE OR REPLACE VIEW vw_consumo_medio AS
SELECT i.id AS item_id,
       i.item,
       COALESCE(SUM(m.quantidade), 0) / 60.0 AS consumo_dia,
       CASE WHEN COALESCE(SUM(m.quantidade),0) > 0
            THEN FLOOR(i.quantidade / (SUM(m.quantidade)/60.0))
            ELSE NULL END AS dias_restantes
FROM estoque_itens i
LEFT JOIN estoque_movimentacoes m
       ON m.item_id = i.id
      AND m.tipo IN ('Saída','Descarte')
      AND m.data >= CURRENT_DATE - INTERVAL '60 days'
GROUP BY i.id, i.item, i.quantidade;

-- Indicadores consolidados por mês (base dos gráficos de variação)
CREATE OR REPLACE VIEW vw_indicadores_mensais AS
SELECT to_char(a.data,'YYYY-MM')                                   AS competencia,
       COUNT(*) FILTER (WHERE a.status='Realizado')                AS atendimentos,
       COUNT(DISTINCT a.colaborador_id)
         FILTER (WHERE a.status='Realizado')                       AS colaboradores,
       COUNT(DISTINCT a.colaborador_id)
         FILTER (WHERE a.status='Realizado' AND a.dor_antes >= 4)  AS com_dor,
       ROUND(AVG(a.dor_antes) FILTER (WHERE a.status='Realizado'),1)             AS dor_chegada,
       ROUND(AVG(a.dor_antes - a.dor_depois) FILTER (WHERE a.status='Realizado'),1) AS alivio,
       COUNT(*) FILTER (WHERE a.status='Faltou')                   AS faltas,
       ROUND(AVG(a.avaliacao) FILTER (WHERE a.status='Realizado'),1) AS satisfacao
FROM atendimentos a
GROUP BY 1;

-- =====================================================================
-- ALTERNATIVA SIMPLIFICADA (primeira versão, sem normalizar)
-- ---------------------------------------------------------------------
-- O front funciona sem nenhuma alteração com uma tabela por coleção
-- guardando o documento inteiro em JSONB. Útil para subir rápido e
-- normalizar depois, sem mexer na aplicação.
--
-- CREATE TABLE documentos (
--   colecao   TEXT NOT NULL,     -- pacientes, atendimentos, estoque, ...
--   id        TEXT NOT NULL,
--   dados     JSONB NOT NULL,
--   atualizado_em TIMESTAMPTZ NOT NULL DEFAULT now(),
--   PRIMARY KEY (colecao, id)
-- );
-- CREATE INDEX idx_doc_colecao ON documentos (colecao);
-- CREATE INDEX idx_doc_dados   ON documentos USING GIN (dados);
--
-- GET    /api/{colecao}        -> SELECT id, dados FROM documentos WHERE colecao = $1
-- PUT    /api/{colecao}/{id}   -> INSERT ... ON CONFLICT (colecao,id) DO UPDATE
-- DELETE /api/{colecao}/{id}   -> DELETE FROM documentos WHERE colecao=$1 AND id=$2
-- =====================================================================
