# RODX Menu — arquitetura v1

## Objetivo
SaaS B2B brasileiro, com checkout de pedidos sem pagamento online (pagamento
na entrega/retirada/mesa) e cobrança recorrente do SaaS via Stripe.
Nenhuma conta de produção ou credencial é criada pelo projeto.

## Componentes
- Next.js App Router, TypeScript, Tailwind CSS: landing, painel administrativo,
  cardápio público e APIs HTTP.
- Supabase Auth: cadastro, confirmação de e-mail, login e sessão SSR.
- PostgreSQL: tabelas, constraints, RLS, funções transacionais e auditoria.
- Supabase Realtime: invalidação do painel de pedidos, com polling de fallback.
- Stripe Checkout/Portal: assinatura em BRL; webhook assinado e deduplicado.
- WhatsApp: link oficial wa.me com resumo do pedido, sem fingir envio automático.

## Modelo de dados
- Operação: orders.source e orders.courier_id, couriers, cash_sessions,
  cash_entries. FK composta por tenant, índices, RLS e escritas de caixa
  apenas por RPC autenticada. Histórico de cliente calculado pelos pedidos.
  PDV lança pedidos confirmados em transação com baixa de estoque. O caixa
  calcula saldo por método, registra recebimento/estorno local (sem integração
  bancária) e impede cancelamento de pedido pago sem estorno.
- establishments (tenant), memberships (usuário + papel), platform_admins.
- Perfil do estabelecimento: descrição, endereço, horário informativo,
  contato e formas de pagamento aceitas, editáveis apenas pelo proprietário.
  `public_menu` divulga esses campos apenas de cardápios publicados e
  `place_order` valida a forma selecionada dentro da transação do pedido.
- menus, categories, products, addons, tables, coupons: catálogo por tenant.
- orders, order_items, order_item_addons, order_events: pedidos e snapshots de preço.
- loyalty_accounts: pontos vinculados ao telefone; ganhos na conclusão.
- subscriptions, webhook_events: cobrança e deduplicação.
- Níveis de assinatura: o nível de acesso é calculado a partir de subscriptions
  (trial vigente=Premium, Essencial=1, Pro=2, Premium=3). A RPC de consulta
  só retorna o nível a membros do estabelecimento, sem expor dados de cobrança.
  Políticas restritivas de RLS controlam criação/edição de mesas e cupons e
  leitura da fidelidade; RPCs verificam plano antes de operações especiais.
  A API de exportação verifica nível e papel. Dados existentes não são apagados.
- support_tickets, notifications: atendimento e alertas internos.
- Todo FK entre entidades de tenant usa a chave composta (tenant_id, id).

## Papéis
owner: proprietário, financeiro, equipe, configurações e catálogo.
manager: operação, catálogo, relatórios, suporte.
kitchen: leitura dos pedidos e avanço limitado do preparo.
attendant: pedidos, mesas e operação.
platform_admin: leitura administrativa global via RLS, sem autoconcessão.

## Rotas
| Rota | Uso |
| --- | --- |
| / | comercial |
| /entrar, /cadastro, /auth/callback | autenticação |
| /onboarding | novo estabelecimento |
| /painel | seleção de estabelecimento |
| /painel/[tenant]/[module] | visão geral, catálogo, PDV, pedidos, cozinha, caixa, salão, mesas, entregas, entregadores, clientes, cupons, fidelidade, equipe, relatórios, assinatura, configurações, suporte |
| /menu/[slug] | catálogo público e checkout |
| /admin | Super Admin |
| /api/pedidos | criação pública validada e idempotente |
| /api/exportar | CSV autenticado |
| /api/stripe/webhook | eventos assinados e aplicados atomicamente |

## Regras críticas
1. A sessão é validada no servidor; o banco valida cada leitura/escrita.
2. O cardápio público expõe somente campos permitidos via RPC.
3. O checkout recalcula preços, cupom, disponibilidade e estoque no banco.
4. Pedido e baixa de estoque são atômicos; idempotência por tenant e UUID.
5. Transições de status e estorno de estoque são controlados por RPC.
6. Senhas são gerenciadas pelo Supabase; service role somente no servidor.
7. Valores monetários em centavos; timestamps em UTC, exibição pt-BR.
8. Checkout Stripe é distinto do pagamento do consumidor. Webhook é a fonte de
   atualização da assinatura e consulta o estado atual do provedor.
9. Princípios LGPD: minimização, acesso restrito, exportação, retenção configurada
   operacionalmente e procedimento de anonimização. Conformidade jurídica exige
   validação do controlador, política de privacidade e revisão antes do lançamento.

## Plano de implementação
1. Schema, constraints, RLS e RPCs; revisão e testes SQL de isolamento.
2. Shell de UI, autenticação, onboarding e autorização.
3. Catálogo, estoque, mesas, promoções e cardápio público.
4. Checkout, pedidos, cozinha, notificações, fidelidade e relatórios.
5. Assinaturas, equipe, configurações, suporte e Super Admin.
6. Testes unitários, typecheck, build, documentação e checklist de implantação.

## Referências técnicas
- https://supabase.com/docs/guides/database/postgres/row-level-security
- https://supabase.com/docs/guides/auth/server-side/creating-a-client
- https://nextjs.org/docs/app
- https://docs.stripe.com/billing/subscriptions/webhooks
