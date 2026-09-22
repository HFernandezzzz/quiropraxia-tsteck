# Sistema da Sala de Quiropraxia — TS Teck
## Documentação técnica para integração com banco de dados

Versão 4 · Henrique Fernandez · 22/09/2026

---

## 1. O que tem neste pacote

| Arquivo | Para que serve |
|---|---|
| `index.html` | Aplicação completa, pronta para abrir no navegador. Contém um **adaptador de persistência stub** (localStorage) que deve ser substituído pela API da TS Teck. É este o arquivo que o desenvolvedor vai editar. |
| `schema.sql` | Proposta de schema relacional (PostgreSQL, com notas para MySQL). |
| `dados-exemplo.json` | Os registros de demonstração, no formato exato que a aplicação consome. Útil para popular o ambiente de testes. |
| `DOCUMENTACAO-TECNICA.md` | Este documento. |

Abrir `index.html` com duplo clique já executa o sistema inteiro, com dados gravados no navegador. Nenhum servidor, build ou dependência é necessário para isso.

---

## 2. Arquitetura

- **Arquivo único**, HTML + CSS + JavaScript puro (sem framework, sem build, sem `node_modules`).
- Única dependência externa: as fontes do Google Fonts (`Archivo`, `IBM Plex Sans`, `IBM Plex Mono`). Se o ambiente for offline, basta remover a tag `<link>` e as fontes de sistema assumem.
- O logo da TS Teck está embutido como SVG vetorial (`<symbol id="tsteck">`).
- Renderização: o estado fica em memória no objeto `state`, e a função `render()` redesenha a view atual. Não há virtual DOM nem roteamento por URL.
- **A aplicação não conhece banco de dados.** Toda a persistência passa por um adaptador único, descrito na seção 3.

### Organização do código (dentro do `<script>`)

| Bloco | Conteúdo |
|---|---|
| CONSTANTES | listas de setores, regiões, técnicas, status, unidades |
| UTIL | datas, formatação, moeda, plural, toast |
| ESTADO | `state`, `put()`, `del()`, `boot()` — **ponto de integração** |
| DERIVADOS | estoque baixo, consumo médio, previsão, alertas |
| MAPA CORPORAL | SVG clicável de frente e costas |
| NAV / RENDER | menu, títulos, roteamento interno |
| VIEWS | painel, colaboradores, ficha, agenda, solicitações, estoque, indicadores, configurações |
| MÉTRICAS E VARIAÇÃO | `metricasMes()`, `variacao()`, gráficos comparativos |
| MODAL / FORMS | todos os formulários |
| EXPORTAÇÃO | CSV, JSON, relatório mensal |
| EVENTOS | delegação de clique, teclado, submit |

---

## 3. Ponto de integração — o adaptador de persistência

Todo acesso a dados acontece através de `window.Sistema.servico(nome)`, que devolve uma `Promise` com um dos quatro serviços. No `index.html` isso está implementado como stub no topo do `<body>`, com o comentário `ADAPTADOR DE PERSISTÊNCIA — SUBSTITUIR PELA API DA TS TECK`.

**Basta reescrever esse bloco.** Nenhuma outra parte do sistema precisa ser alterada.

### 3.1 Serviço `db` (obrigatório)

Banco de documentos JSON. A aplicação chama exatamente estes três métodos:

```js
db.collection(colecao).onSnapshot(next, erro)   // assinatura contínua; devolve função de cancelamento
db.collection(colecao).doc(id).set(objeto)      // cria ou substitui o documento inteiro; devolve Promise
db.collection(colecao).doc(id).delete()         // remove; devolve Promise
```

O callback `next` recebe um objeto no formato:

```js
{ docs: [ { id: "abc123", exists: true, data: () => ({ ...campos }) } ] }
```

Notas importantes:

- **O `id` é gerado no cliente** (função `uid()`, base36 de timestamp + aleatório) e enviado no `set`. O backend deve aceitar o id vindo do cliente (`PUT`), não gerar o seu.
- `set` é substituição total do documento, não merge.
- A aplicação grava sozinha os campos `atualizadoEm` (ISO 8601), `criadoPor` e `alteradoPor` (id do usuário) em cada `set`.
- `onSnapshot` precisa reemitir quando o dado muda em outro cliente. Se não houver WebSocket/SSE, um *polling* a cada 15–30 segundos atende bem o volume desta sala.

**Mapeamento REST sugerido:**

| Chamada da aplicação | Endpoint |
|---|---|
| `collection(c).onSnapshot` | `GET /api/{c}` (+ SSE em `/api/{c}/stream`, ou polling) |
| `doc(id).set(obj)` | `PUT /api/{c}/{id}` |
| `doc(id).delete()` | `DELETE /api/{c}/{id}` |

### 3.2 Serviço `user` (obrigatório)

```js
user.me()            // -> { id, name, canEdit: boolean, isOwner: boolean }
user.profiles(ids)   // -> { [id]: { id, name } }   usado para exibir "registrado por"
user.can("data.write") // -> boolean
```

`canEdit` é o que define o nível de acesso (seção 5). Mapear para `GET /api/me`, lendo a sessão/JWT.

### 3.3 Serviço `downloads` (obrigatório para CSV e backup)

```js
downloads.save({ filename, data })  // -> Promise
```

O stub já faz isso com `Blob` + `<a download>`, e essa implementação serve para produção.

### 3.4 Serviço `assets` (opcional — anexos e assinatura)

```js
assets.upload(blob, { type })  // -> { id, url, sizeBytes, contentType }
assets.delete(id)              // -> { deleted: boolean }
```

Se `assets` for `null`, o sistema simplesmente esconde os botões de anexo e assinatura — nada quebra. Para habilitar, implemente upload em disco, S3 ou MinIO.

**Atenção:** a aplicação monta a URL de exibição como `"/_blob/" + id` em **3 pontos do código** (busque por `_blob`). Ou o backend expõe a rota `GET /_blob/{id}`, ou troque essas três ocorrências pela rota real.

---

## 4. Modelo de dados

São 9 coleções. Campos marcados com `*` são obrigatórios na prática.

### 4.1 `pacientes` — ficha do colaborador

| Campo | Tipo | Observação |
|---|---|---|
| `nome`* | texto | |
| `matricula` | texto | matrícula funcional |
| `setor`, `funcao`, `turno` | texto | setor vem de lista fixa no código |
| `nascimento`, `admissao` | data `AAAA-MM-DD` | |
| `telefone` | texto | ramal ou celular |
| `ativo` | booleano | `false` = colaborador desligado/inativo |
| `problemaColuna` | texto | `Não` \| `Sim - em investigação` \| `Sim - diagnosticado` \| `Não informado` |
| `diagnostico` | texto | |
| `regioes` | lista de texto | Cervical, Torácica, Lombar, Sacroilíaca, Ombro, Quadril, Joelho, Punho/Mão |
| `exames`, `cirurgias` | texto | |
| `usaMedicamento` | texto | `Sim` \| `Não` |
| `medicamentos` | texto | |
| `atividade`, `posto`, `esforco` | texto | perfil ocupacional |
| `contraindicacoes` | texto | dispara alerta obrigatório antes do atendimento |
| `apto` | texto | `Sim` \| `Não` — liberação para atendimento |
| `motivoNaoApto` | texto | |
| `consentimento` | texto | `Sim` \| `Não` — termo LGPD |
| `observacoes` | texto | |
| `anexos` | lista de objetos | `{ id, nome, tipo, em }` — `id` é o id do arquivo no storage |
| `assinaturaId`, `assinaturaEm` | texto / data | assinatura do termo, imagem PNG no storage |
| `origem` | texto | `autoatendimento` quando preenchido pelo próprio colaborador |
| `revisado` | booleano | fichas de autoatendimento começam `false` |
| `criadoEm`, `atualizadoEm` | ISO 8601 | |
| `criadoPor`, `alteradoPor` | texto | id do usuário |
| `exemplo` | booleano | marca registro de demonstração |

### 4.2 `atendimentos`

| Campo | Tipo | Observação |
|---|---|---|
| `pacienteId`* | texto | FK → `pacientes.id` |
| `data`* | data `AAAA-MM-DD` | |
| `hora` | texto `HH:MM` | |
| `tipo` | texto | Avaliação inicial, Sessão de manutenção, Retorno, Urgência / dor aguda, Orientação ergonômica |
| `status` | texto | `Agendado` \| `Realizado` \| `Faltou` \| `Cancelado` |
| `duracao` | inteiro | minutos |
| `profissionalId` | texto | FK → `profissionais.id` |
| `queixa` | texto | |
| `regioes`, `tecnicas` | listas de texto | |
| `pontos` | lista de objetos | mapa corporal: `{ f: "f"\|"b", x, y, i: 1..3 }` — face (frente/costas), coordenadas no viewBox 120×190, intensidade |
| `dorAntes`, `dorDepois` | inteiro 0–10 ou `null` | escala visual analógica |
| `avaliacao` | inteiro 1–5 ou `null` | satisfação do colaborador |
| `materiais` | lista de objetos | `{ nome, qtd }` — gera baixa automática no estoque |
| `evolucao` | texto | |
| `proxima` | data | agendamento automático de retorno |
| `encaminhamento` | texto | |
| `redflag` | booleano | confirmação de leitura das contraindicações |
| `criadoEm`, `criadoPor`, `atualizadoEm` | | |

### 4.3 `solicitacoes` — pedidos ao setor de Suprimentos

| Campo | Tipo | Observação |
|---|---|---|
| `numero`* | texto | `SOL-AAAA-0001`, gerado no cliente a partir do maior número do ano |
| `data` | data | |
| `urgencia` | texto | `Normal` \| `Urgente` |
| `solicitante` | texto | |
| `justificativa` | texto | |
| `itens` | lista de objetos | `{ descricao, qtd, unidade, obs }` |
| `status` | texto | `Pendente` → `Aprovado` → `Comprado` → `Entregue`, ou `Recusado` |
| `pedido` | texto | nº do pedido de compra / NF |
| `previsao` | data | |
| `resposta` | texto | retorno do Suprimentos |

> Se houver ERP, este é o ponto natural de integração: espelhar `status`, `pedido` e `previsao` a partir do pedido de compra real.

### 4.4 `estoque`

`item`*, `categoria`, `unidade`, `quantidade` (número), `minimo` (número), `validade` (data), `fornecedor`, `local`, `obs`.

### 4.5 `movimentacoes` — razão do estoque

`itemId` (FK), `item` (nome no momento do lançamento), `tipo` (`Saída` \| `Entrada` \| `Descarte` \| `Ajuste de inventário`), `qtd`, `motivo`, `atendimentoId` (quando veio de uma sessão), `data`, `por` (id do usuário), `criadoEm`.

> A aplicação mantém os **500 lançamentos mais recentes** e apaga os mais antigos. Num banco relacional essa poda não é necessária — remova a chamada de limpeza em `registrarMov()`.

### 4.6 `afastamentos`

`pacienteId` (FK), `inicio` (data), `dias` (inteiro), `motivo`, `relacionado` (booleano — ligado à coluna), `obs`.

### 4.7 `profissionais`

`nome`*, `registro`, `ativo`.

### 4.8 `resumos` — fechamento mensal publicado

O **id do documento é a competência** (`2026-09`). Campos: `atendimentos`, `colaboradores`, `alivio`, `diasPerdidos`, `custo`, `faltas`, `satisfacao`, `setores` e `regioes` (listas de pares `[nome, quantidade]`), `publicadoEm`.

### 4.9 `config` — documento único de id `geral`

`empresa`, `custoDia`, `horaInicio`, `horaFim`, `passo`, `duracao`, `diasSemana` (lista de 0–6, domingo = 0), `diasRetorno`, `diasValidade`, `janelaConsumo`.

---

## 5. Controle de acesso

O sistema trabalha com **dois níveis**, e a separação precisa ser feita no servidor, não só na tela.

| Nível | Quem | Lê | Escreve |
|---|---|---|---|
| **Clínico** (`canEdit = true`) | quiropraxista e administrador | todas as coleções | todas |
| **Operacional** (`canEdit = false`) | Suprimentos, RH, SESMT | `solicitacoes`, `estoque`, `movimentacoes`, `config`, `resumos`, `profissionais` | `solicitacoes`, `estoque`, `movimentacoes` |

As coleções `pacientes`, `atendimentos` e `afastamentos` **não podem sequer ser retornadas** para o perfil operacional — é dado de saúde, protegido pelo art. 11 da LGPD. Hoje isso é garantido por regra no banco da plataforma; na API, implemente como filtro de autorização por rota.

O front já se adapta sozinho: com `canEdit = false`, o menu não mostra Colaboradores, Agenda e Configurações, e Indicadores exibe apenas os resumos mensais agregados.

### Requisitos de segurança da implantação

O tratamento de dado sensível de saúde exige controles definidos com a área de segurança da informação da empresa: registro de auditoria, política de retenção e criptografia dos dados clínicos e dos anexos. O `schema.sql` já contempla a estrutura de auditoria; os parâmetros e o alcance de cada controle são definidos na implantação.

---

## 6. Automações já implementadas (preservar no backend)

1. **Baixa de estoque**: materiais informados num atendimento subtraem o saldo e geram um registro em `movimentacoes`. Ao editar o atendimento, apenas a diferença é aplicada.
2. **Entrada por entrega**: solicitação marcada como `Entregue` com a opção ligada soma as quantidades ao estoque (cria o item se não existir) e registra a movimentação.
3. **Numeração automática** de solicitações por ano.
4. **Consumo médio e previsão**: média diária das saídas na janela configurada (padrão 60 dias) → dias restantes de estoque.
5. **Sugestão de compra**: junta o que está abaixo do mínimo com o que acaba em menos de 15 dias e pré-preenche a solicitação.
6. **Conflito de agenda**: bloqueia (com confirmação) dois atendimentos no mesmo dia, hora e profissional.
7. **Série de sessões**: agenda de 2 a 12 sessões semanais de uma vez.
8. **Retorno automático**: preencher "próxima sessão" cria o agendamento.
9. **Alerta ergonômico**: 3 ou mais colaboradores do mesmo setor com queixa na mesma região.
10. **Red flags**: contraindicação ou colaborador não liberado exige confirmação explícita antes de salvar o atendimento.
11. **Variação mês a mês**: percentual sobre o mês anterior em 9 indicadores, com cor pelo sentido desejado de cada um.

---

## 7. Relatórios e exportações

- **Relatório mensal em PDF**: gerado pela própria impressão do navegador (`window.print()`), com CSS `@page A4` e quebras controladas. Não usa biblioteca de PDF.
- **CSV**: colaboradores, atendimentos, solicitações, estoque e movimentações. Separador `;` e BOM UTF-8, para abrir direto no Excel em português.
- **Backup JSON**: dump completo de todas as coleções — formato idêntico ao `dados-exemplo.json`.

---

## 8. Checklist de adaptação

1. [ ] Subir a API com as rotas da seção 3.1 e autenticação corporativa.
2. [ ] Reescrever o bloco do adaptador no `index.html` (uma função, ~60 linhas).
3. [ ] Criar o schema (`schema.sql`) ou usar colunas JSON, conforme a seção 9.
4. [ ] Implementar a autorização por perfil da seção 5 **no servidor**.
5. [ ] Implementar o storage de anexos e a rota `/_blob/{id}`, ou desativar `assets`.
6. [ ] Remover a poda dos 500 lançamentos em `registrarMov()`.
7. [ ] Importar `dados-exemplo.json` no ambiente de homologação e apagar antes de ir para produção (os registros têm o campo `exemplo: true`; há um botão no sistema que remove todos).
8. [ ] Aplicar os controles de segurança definidos com a área de TI (auditoria, retenção e criptografia).

---

## 9. Sobre o `schema.sql`

O arquivo traz uma modelagem **relacional normalizada**, com tabelas filhas para as listas (regiões, técnicas, materiais, pontos do mapa corporal, itens da solicitação, anexos).

Se a equipe preferir menos atrito na primeira versão, há alternativa igualmente válida: uma tabela por coleção com `id TEXT PRIMARY KEY` e uma coluna `dados JSONB`, guardando o documento inteiro. O front funciona sem nenhuma alteração, e a normalização pode vir depois. O arquivo tem essa variante comentada no final.
