import { bindings, defineConfig, defineWorker } from "cf/config";

export default defineConfig({
  worker: defineWorker({
    name: "rodx-menu",
    entrypoint: "vinext/server/fetch-handler",
    compatibilityDate: "2026-11-20",
    assets: {
      htmlHandling: "none",
      notFoundHandling: "none",
      runWorkerFirst: ["/*", "!/_next/static/*", "!/*/_next/static/*"],
    },
    env: {
      ASSETS: bindings.assets(),
      APP_URL: bindings.text("https://menu.rodxdesign.com.br"),
      SUPABASE_SERVICE_ROLE_KEY: bindings.secret(),
      STRIPE_SECRET_KEY: bindings.secret(),
      STRIPE_WEBHOOK_SECRET: bindings.secret(),
      // Identificadores públicos dos preços recorrentes do sandbox RODX.
      STRIPE_PRICE_ESSENCIAL: bindings.text("price_1Udxx6CNxSYaUXAzby11NsFu"),
      STRIPE_PRICE_PRO: bindings.text("price_1UdxxHCNxSYaUXAzNrchdOXb"),
      STRIPE_PRICE_PREMIUM: bindings.text("price_1UdxxOCNxSYaUXAzbCfHiLsU"),
    },
  }),
});
