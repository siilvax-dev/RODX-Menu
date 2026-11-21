# RODX Menu

Plataforma SaaS gastronômica da RODX Design — versão 0.7.

**Stack:** Next.js 16, React 19, TypeScript, Tailwind CSS 4, PostgreSQL,
Supabase (Auth/PostgREST/Realtime), Stripe Billing e QR Code.

Leia [ARQUITETURA.md](ARQUITETURA.md) para decisões, schema, papéis e rotas.

## Instalação local

Requisitos: Node.js 22.12+ (recomendado Node 24), npm, projeto Supabase
(ou CLI Supabase + Docker para ambiente local).

Esta edição local v0.7 não instala vinext, cf, workerd nem os adaptadores
da Cloudflare. Os componentes de hospedagem ficam separados em deploy/cloudflare.
Se já utilizava a v0.3.1, v0.4, v0.5 ou v0.6 local, faça uma cópia de segurança e substitua os
arquivos com esta edição preservando node_modules e .env.local. As dependências
não mudaram; basta reiniciar npm run dev.
No Windows, extraia o ZIP em uma pasta, abra no VS Code a pasta que contém
package.json e execute `npm ci --no-audit --no-fund --prefer-offline`,
depois `npm run dev`. Acesse http://localhost:3000. O arquivo
INICIAR-RODX.bat é uma alternativa para instalar e iniciar pelo Windows.

```bash
npm ci
cp .env.example .env.local
```

Preencha `.env.local` sem compartilhar segredos:

| Variável | Origem |
|---|---|
| NEXT_PUBLIC_SUPABASE_URL | URL do projeto Supabase |
| NEXT_PUBLIC_SUPABASE_ANON_KEY | Chave pública anon/publishable |
| SUPABASE_SERVICE_ROLE_KEY | Chave secreta service_role (servidor apenas) |
| APP_URL | URL real da aplicação, sem barra final |
| STRIPE_SECRET_KEY | Chave secreta Stripe de teste (sk_test_...) |
| STRIPE_WEBHOOK_SECRET | Segredo do endpoint (whsec_...) |
| STRIPE_PRICE_ESSENCIAL | ID de Price recorrente em BRL |
| STRIPE_PRICE_PRO | ID de Price recorrente em BRL |
| STRIPE_PRICE_PREMIUM | ID de Price recorrente em BRL |

### Banco de dados

Projeto dedicado RODX Menu já provisionado no Supabase, região São Paulo:
https://supabase.com/dashboard/project/opzuiwgquwtsvgxarhsr
As migrations core, metrics, indexes_and_policies, payment_profiles,
plan_entitlements, operations, partial_order_payments,
partial_payment_ledger_guard e require_full_refund_before_cancel estão aplicadas
no projeto Supabase RODX Menu.
As chaves públicas já estão configuradas; a chave de serviço deve ser
inserida exclusivamente em ambiente privado.

Em ambiente local com Docker e Supabase CLI:

```bash
supabase start
supabase db reset
supabase status
```

Copie a URL e as chaves exibidas para o ambiente local. **db reset apaga
somente o banco local**; não use em banco de produção. Alternativamente crie
um projeto Supabase dedicado e execute as migrations, na ordem, pelo CLI:

```bash
supabase login
supabase link --project-ref SEU_PROJECT_REF
supabase db push
```

Não aplique essas migrations sobre um banco existente com tabelas de mesmo nome.
Configure Auth > URL Configuration: Site URL = APP_URL e permita os callbacks
`/auth/callback` e `/auth/callback?next=/nova-senha`. Ative confirmação por e-mail,
SMTP em produção, rate limits e proteção contra senhas vazadas quando disponível.

```bash
npm run dev
```

Acesse http://localhost:3000.

## Fluxo de uso

1. Crie a conta, confirme o e-mail e acesse o onboarding.
2. Cadastre o estabelecimento. Ele inicia com 14 dias de avaliação.
3. Em categorias, associe categorias ao cardápio principal. Em produtos,
   informe preço, estoque opcional e imagem HTTPS opcional. Cadastre adicionais.
4. Em Configurações → Perfil do estabelecimento, informe WhatsApp com DDI 55,
   descrição, horário, endereço/taxa, formas de pagamento aceitas e publique.
5. Abra o cardápio público. Inclua produtos e adicionais, escolha entrega,
   retirada ou mesa (QR Code), informe contato e envie.
6. Em pedidos, confirme o pedido; na cozinha, marque preparo e pronto.
   Conclua na operação. Cancelar antes da entrega restaura estoque reservado.
7. Crie mesas para obter QR codes com tokens; crie cupons de percentual e limite.
8. Relatórios usam últimos 30 dias e exportam CSV sem dados pessoais.
9. Funcionários precisam ter criado uma conta e confirmado o e-mail.
   O proprietário vincula e remove funcionários pelo menu Equipe.

Fidelidade atribui automaticamente um ponto por real inteiro em produtos
concluídos, pós-desconto. A versão inicial não possui resgate de pontos.

Cada proprietário configura Pix, crédito, débito, dinheiro e/ou vale-refeição.
O cardápio e o checkout exibem apenas as escolhas daquele estabelecimento.
O banco rejeita opções desativadas mesmo em chamadas diretas ao servidor.
O consumidor paga **fora do sistema**, na entrega, retirada ou mesa; a seleção
não representa autorização de pagamento nem confirmação bancária. Pedidos
antigos com cartão genérico são preservados. O horário é informativo; a
disponibilidade continua sendo controlada pelo botão Aceitar pedidos.
O WhatsApp usa um link oficial para iniciar uma conversa; não há bot,
envio automático ou alegação de integração com a API Business.

### Super Admin

Após criar a conta administrativa e confirmar o e-mail, no SQL Editor do
Supabase, um operador autorizado executa:

```sql
insert into public.platform_admins(user_id)
select id from auth.users where lower(email)=lower('EMAIL_ADMIN_VERIFICADO');
```

Depois acesse /admin. Não há senha padrão ou elevação de privilégio via UI.

### PDV, caixa, salão e entregas (v0.7)

Durante o teste ou com plano Pro/Premium, entre no painel e acesse PDV.
Escolha itens e adicionais, modalidade (balcão/retirada, entrega, mesa), cliente,
telefone e forma de pagamento. O pedido nasce confirmado e aparece na cozinha.
O estoque e os preços são validados novamente no PostgreSQL.

No Caixa, abra a sessão com o saldo inicial em dinheiro. Registre pagamentos
parciais ou integrais, inclusive divididos entre formas aceitas pelo
estabelecimento. O saldo restante é calculado no banco e as vendas anteriores continuam
compatíveis. Registre somente pagamentos efetivamente recebidos pelo estabelecimento. Suprimentos, sangrias
e estornos exigem justificativa; estorno exige gerente/proprietário. O caixa
calcula saldo esperado e diferença de fechamento. Um pedido pago precisa de
um estorno registrado antes do cancelamento. Não realiza cobrança ou estorno
bancário: a operação financeira acontece no provedor/meio usado pelo lojista.
O saldo é calculado no banco, não pela quantidade de linhas na tela.

Em Salão, acompanhe contas por mesa dos 300 pedidos mais recentes; o pagamento
é registrado por pedido no caixa. Em Entregadores, cadastre a equipe própria,
e em Controle de entregas atribua pedidos e envie endereço por WhatsApp de
forma manual. O histórico de Clientes usa os pedidos reais, sem copiar os
dados pessoais para outra tabela; a anonimização existente continua aplicável.
Pedidos e cozinha têm visualização em Kanban/lista, busca e impressão manual
pelo diálogo do navegador (não fiscal, não automática).

### Stripe (ambiente de teste)

Leia [CONFIGURAR-STRIPE.md](CONFIGURAR-STRIPE.md). A página de assinatura
mostra as variáveis faltantes, sem exibir valores de credenciais. Os IDs
pré-configurados são usados como fallback apenas para chaves de teste.
Não abra Checkout sem webhook e chave de serviço configurados.

1. Os três produtos já foram criados e conferidos no sandbox Stripe RODX:
   Essencial R$ 49,90; Pro R$ 99,90; Premium R$ 149,90 por mês.
   A API retornou que Stripe Tax não está disponível para a conta. Antes de
   cobrar clientes reais, confirme o tratamento tributário com o contador.
2. Os IDs de teste já estão preenchidos em .env.example e na configuração
   em deploy/cloudflare/cloudflare.config.ts.
   Nunca use os preços de teste com credenciais de produção.
3. O Customer Portal de teste foi criado como configuração padrão, com troca
   de planos, faturas, atualização do método de pagamento e cancelamento no
   fim do ciclo. Confira no Dashboard Stripe em modo de teste.
4. Configure webhook HTTPS em `APP_URL/api/stripe/webhook`, assinando
   customer.subscription.created, customer.subscription.updated e
   customer.subscription.deleted, invoice.paid e invoice.payment_failed.
   Para teste local:

```bash
stripe listen --events customer.subscription.created,customer.subscription.updated,customer.subscription.deleted,invoice.paid,invoice.payment_failed --forward-to localhost:3000/api/stripe/webhook
```

Copie o whsec exibido para STRIPE_WEBHOOK_SECRET e reinicie. Entre como owner,
acesse Assinatura e complete o Checkout com cartão de teste do Stripe.
O estado passa a ativo apenas após o webhook assinado. Mudança/cancelamento
via portal também deve atualizar o estado. Reenvie o evento e verifique que
webhook_events registra apenas um ID. A configuração de preço é externa;
não existe cobrança simulada. Consulte a comparação na página inicial e
na área Assinatura. Os planos têm níveis diferenciados no banco e na aplicação:

| Plano | Recursos |
|---|---|
| Essencial | Cardápio, perfil, delivery e retirada, pagamentos locais, pedidos, catálogo, estoque, indicadores e suporte |
| Pro | Essencial + mesas/QR, salão, PDV, caixa, entregadores, clientes, cozinha dedicada, cupons e gestão da equipe |
| Premium | Pro + fidelidade por pontos, relatórios e exportação CSV |

O teste de 14 dias libera todos os módulos até seu vencimento. A perda de
acesso a módulos ao mudar de plano não elimina dados existentes. É possível
remover funcionários já vinculados mesmo sem o plano Pro. A funcionalidade
de retirada, delivery e gestão dos pedidos permanece no plano Essencial.
Consulte ROADMAP-PRODUTO.md para as próximas etapas e recursos ainda não
implementados.

## Testes e qualidade

```bash
npm test
npm run typecheck
npm run build
npm audit --omit=dev --audit-level=high
```

Vitest: validação, moeda, transições e CSV. PGlite executa as migrations em
PostgreSQL embarcado; o harness cria apenas roles e auth.uid equivalentes de
teste. Verifica isolamento RLS, FK cross-tenant, checkout transacional,
rollback, idempotência, camada de cozinha sem PII e anonimização.

Resultado da v0.6: 34 testes aprovados, incluindo PDV com cardápio fechado,
estoque e preço, duplicidade de pagamento, sangria, estorno e fechamento,
atribuição de entregador, isolamento e bloqueio por plano.
Typecheck e build Next.js de produção aprovados. A verificação remota confirmou
RLS nas três novas tabelas, execução do PDV bloqueada para anônimos e os dois
estabelecimentos anteriores preservados. Smoke de navegador bloqueado pelas
restrições de sockets do ambiente de execução; realize-o localmente.

Resultado da v0.5: 27 testes aprovados, incluindo acesso por plano, período de
teste, isolamento entre estabelecimentos e preservação de dados após downgrade.
Typecheck e build Next.js de produção aprovados.

Resultado da v0.4: 23 testes aprovados, incluindo perfil, formas de pagamento,
validação do checkout e isolamento por estabelecimento. Typecheck e build
Next.js de produção aprovados.

Resultado da entrega anterior: 19 testes aprovados, typecheck aprovado, build Next.js
de produção aprovado e auditoria npm de dependências de produção sem
vulnerabilidades reportadas na execução. O smoke de Chromium não pôde rodar
neste ambiente por restrição a sockets; execute-o no ambiente local/staging.

Smoke de interface com Chromium instalado:

```bash
npm run start
# Em outro terminal
CHROMIUM_PATH=/usr/bin/chromium node tests/smoke.mjs
```

Testes completos com Supabase Auth + Realtime e Stripe real em modo test
requerem as credenciais acima. O harness de PostgreSQL local não substitui
esses testes de integração. Para produção, acrescente testes e2e com duas
contas, diferentes funções, pedidos concorrentes e falhas de rede/webhook.

## Deploy

1. Crie um repositório privado com esta pasta; não inclua node_modules, .next
   ou .env.local. Use o package-lock.json.
2. Crie um projeto Supabase de staging e aplique migrations.
3. Para Cloudflare Workers, leia deploy/cloudflare/README.md e ative a
   configuração de hospedagem em uma cópia separada do projeto. Só então
   execute npm ci, npm run build:vinext, npx cf auth login,
   e npm run deploy:vinext -- --dry-run para revisar antes do deploy.
   Configure os segredos privados pelo dashboard do Worker (Settings →
   Variables and Secrets): SUPABASE_SERVICE_ROLE_KEY, STRIPE_SECRET_KEY
   (chave restrita de teste, com permissões mínimas para Checkout, Customer
   Portal, Customers e Subscriptions), STRIPE_WEBHOOK_SECRET (assinatura do
   destino de eventos). Nunca envie chaves privadas no chat ou no código.
   Publique com npm run deploy:vinext. APP_URL deve ser a URL real HTTPS.
   O deploy e a associação do domínio dependem de autorização Cloudflare.
4. Configure redirects de Auth, SMTP, Stripe webhook e Portal de teste.
5. Execute testes de aceitação com duas lojas e múltiplos papéis; só então
   crie projeto e chaves de produção. Configure domínio próprio
   (por exemplo, menu.rodxdesign.com.br, sujeito à disponibilidade/configuração).
6. Rotacione segredos, ative backups e teste restauração. Não exponha o
   service_role. Exija MFA para os operadores da RODX.

## Limites e checklist antes de lançar comercialmente

- A aplicação está implementada em versão v0.7; o banco Supabase está
  provisionado com 22 tabelas e RLS habilitado. As migrations de pagamento
  parcial e proteção do livro-caixa estão aplicadas no projeto RODX Menu.
  Os três planos e o portal Stripe existem em sandbox. A publicação do Worker, segredos,
  webhook e testes integrados ainda estão pendentes; não está homologada.
- Antes de produção, implemente e teste o tratamento de disputas, reembolsos
  e alertas de fraude do Stripe, incluindo o fluxo operacional de revisão.
- Os indicadores do Supabase sobre SECURITY DEFINER e tabelas sem policies
  foram revisados: os RPCs públicos têm exposição intencional com GRANT
  restrito e verificações internas; platform_admins e webhook_events não têm
  acesso por papéis anônimos/autenticados. Antes de lançar, faça uma nova
  revisão independente de segurança.
- Adicione CAPTCHA/Turnstile e rate limiting distribuído por IP/tenant
  no gateway. O checkout limita pedidos por telefone, mas não substitui
  defesa contra abuso distribuído. QR Codes identificam a mesa, não provam
  presença física. Implemente janela/rotação de tokens de mesa se necessário.
- Defina políticas de retenção e exportação para titulares, procedimentos de
  incidente e DPA. O recurso de anonimização preserva valores, remove PII e
  solicita confirmação; a LGPD exige processos organizacionais além de código.
- Imagens remotas devem ser de provedores autorizados. Para produção, adicione
  storage com políticas e otimização própria. Nenhum dado de cartão é armazenado.
- Relatórios limitados a 30 dias; filas e listagens administrativas têm
  limites documentados. Evoluir paginação, filtros avançados, métricas de
  disponibilidade, alertas e observabilidade antes de tráfego de alto volume.
- Não incluídos: gateway de pagamento do consumidor, resgate de pontos,
  automação WhatsApp Business, cálculo de frete geográfico, emissão fiscal,
  impressão na cozinha e gestão de motoboys. São extensões da próxima etapa.
- Realize revisão independente de segurança e carga; os testes presentes
  não provam conformidade integral com LGPD nem ausência de vulnerabilidades.

## Documentação técnica oficial

- https://supabase.com/docs/guides/auth/server-side
- https://supabase.com/docs/guides/database/postgres/row-level-security
- https://docs.stripe.com/billing/subscriptions/webhooks
- https://docs.stripe.com/testing
- https://nextjs.org/docs/app/getting-started/deploying
