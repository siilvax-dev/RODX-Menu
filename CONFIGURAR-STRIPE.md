# Configurar assinaturas do RODX Menu no localhost

Os preços mensais Essencial (R$ 49,90), Pro (R$ 99,90) e Premium (R$ 149,90)
estão cadastrados no sandbox RODX. O ambiente de teste não cobra dinheiro real.

1. Abra a pasta que contém package.json no VS Code. Se já existe .env.local,
   mantenha o arquivo. Se não existe, copie .env.example para .env.local.
2. No Dashboard Stripe, selecione o sandbox RODX que possui os três produtos.
   Em [Chaves de API](https://dashboard.stripe.com/apikeys), obtenha uma chave
   restrita de teste com acesso aos recursos utilizados (Checkout Sessions,
   Customers, Subscriptions, Billing Portal e Prices). Guarde-a no valor
   STRIPE_SECRET_KEY do .env.local. Não use chave live em testes.
3. No painel do projeto Supabase, obtenha a chave de serviço de servidor e
   configure SUPABASE_SERVICE_ROLE_KEY. Nunca a exponha em páginas públicas.
4. Confira os IDs de preços em .env.example. Em sandbox, o sistema usa os IDs
   do catálogo RODX quando estas variáveis estão ausentes. Se usar outro sandbox,
   informe os IDs correspondentes, explicitamente.
5. Instale o [Stripe CLI](https://docs.stripe.com/stripe-cli) e conecte ao **mesmo**
   sandbox. Em outro terminal, execute:

```bash
stripe listen --events customer.subscription.created,customer.subscription.updated,customer.subscription.deleted,invoice.paid,invoice.payment_failed --forward-to localhost:3000/api/stripe/webhook
```

6. Copie o signing secret `whsec_...` exibido pelo CLI para a variável
   STRIPE_WEBHOOK_SECRET, no .env.local. Mantenha o CLI em execução.
7. Pare o servidor com Ctrl+C e execute npm run dev novamente. Acesse
   http://localhost:3000, faça login e entre em Planos e assinatura.
8. A mensagem de configuração desaparece quando todas as variáveis necessárias
   são carregadas. O botão Assinar plano abre o checkout de teste; a assinatura
   só muda de estado após a confirmação do webhook. Valores configurados não
   garantem por si só que as credenciais são válidas: valide checkout e webhook.

Não copie nem envie chaves privadas em mensagens, repositórios ou ZIPs.
Na Cloudflare, configure os segredos pelo painel/secret store do ambiente.
Antes da produção, cadastre preços live próprios, valide webhooks e tratamento
de chargebacks/reembolsos/fraude, obrigações tributárias/Stripe Tax com contador
e os demais requisitos de homologação. Pagamentos de consumidores dos
restaurantes são independentes da assinatura da plataforma.
