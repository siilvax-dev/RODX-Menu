# RODX Menu — evolução do produto

Objetivo: competir no mercado brasileiro de sistemas para gastronomia com
experiência premium, navegação clara, gestão por estabelecimento, permissões
granulares e indicadores úteis. Identidade e código próprios da RODX Design.

Referências de mercado: site oficial e manual público do WhatsMenu
(https://ww.whatsmenu.com.br/ e https://docs.whatsmenu.com.br/). Não se trata
de cópia visual nem de promessa de equivalência funcional nesta versão.

## Etapa entregue: v0.5

- Landing e painel com três planos, comparação e benefícios reais.
- Navegação do painel agrupada por operação, cardápio, gestão e conta.
- Controle de módulos por plano, preservação de registros e avaliação de 14 dias.
- Perfil público, métodos de pagamento presencial, catálogo, estoque,
  pedidos, cozinha, mesas, cupons, fidelidade simples e relatórios.
- Stripe Billing no ambiente de teste (assinaturas da plataforma).

## Etapa entregue: v0.6

- PDV de balcão, retirada, delivery e mesa com estoque transacional.
- Caixa com abertura, fechamento, recebimentos, estorno, suprimento e sangria.
- Visão de contas por mesa (recebimento individual por pedido).
- Clientes derivados do histórico de pedidos; despacho de entregadores próprios.
- Pedidos em Kanban/lista, busca e impressão manual não fiscal.
- Diagnóstico de configuração de assinaturas, sem expor segredos.

## Etapa entregue: v0.7

- Recebimentos parciais por pedido, com seleção de meio de pagamento.
- Saldo pendente calculado a partir do livro-caixa, sem alterar o valor original do pedido.
- Estorno integral distribuído pelos meios usados e com justificativa, idempotência e limite de saldo em dinheiro.
- Proteção transacional contra recebimentos acima do total do pedido e estornos acima do valor recebido.
- Salão mostra quanto já foi recebido e o saldo em aberto de cada pedido.

## Etapa seguinte: aprofundamento operacional

Prioridade: comandas individuais, transferência e divisão de itens por pessoa,
impressão automática (integração local), encomendas,
cadastro completo de clientes, pizzas de vários sabores/tamanhos,
fiado e taxa de entrega por região.
Cada módulo deve possuir regras transacionais, RLS, testes e instruções de uso.

## Etapa seguinte: recebimento e automação

- Pix e cartão online por estabelecimento com confirmação assinada do gateway,
  conciliação, estorno e prevenção de duplicidade.
- WhatsApp Business API e automação de atendimento, com consentimento e modelos
  aprovados quando necessários; ambiente de teste e credenciais próprias.
- Rotas e rastreamento de entregas em tempo real.
- Integrações fiscal e de marketplaces somente com credenciais, homologação e
  regras de cada provedor. Não são recursos disponíveis na v0.6.

## Pré-lançamento comercial

Validar integrações reais em staging, backups/restauração, políticas LGPD,
tratamento fiscal, testes E2E e webhook Stripe, segurança e inclusão das
funcionalidades contratadas em cada plano. Não habilitar cobrança real antes
da homologação.
