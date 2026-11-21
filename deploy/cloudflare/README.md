# Publicar no Cloudflare Workers

Esta pasta guarda o manifesto completo, lockfile e configurações do deploy
v0.5, separados do ambiente de trabalho local para evitar baixar o workerd.

Quando for publicar, faça uma cópia do projeto inteiro e, no terminal
PowerShell da **cópia**, execute os comandos abaixo. Eles substituem o
manifesto local pelo manifesto de hospedagem e restauram os dois arquivos
de configuração.

```powershell
Copy-Item .\deploy\cloudflare\package.json .\package.json -Force
Copy-Item .\deploy\cloudflare\package-lock.json .\package-lock.json -Force
Copy-Item .\deploy\cloudflare\cloudflare.config.ts .\cloudflare.config.ts -Force
Copy-Item .\deploy\cloudflare\vite.config.ts .\vite.config.ts -Force
npm ci --no-audit --no-fund
npm run build:vinext
npx cf auth login
npm run deploy:vinext -- --dry-run
```

Use uma versão de Node.js compatível com o manifesto da hospedagem.
Configure o APP_URL real, as três variáveis secretas de serviço e cobrança,
a autenticação do Supabase e o webhook do Stripe conforme README.md.
Só publique depois de confirmar o Worker, a configuração e os segredos.
Não inclua e nem compartilhe as chaves privadas no projeto.
