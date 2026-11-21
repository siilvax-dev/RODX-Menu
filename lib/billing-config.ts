import type {PaidPlan} from "./plans";
const sandboxPrices:Record<PaidPlan,string>={essencial:"price_1Udxx6CNxSYaUXAzby11NsFu",pro:"price_1UdxxHCNxSYaUXAzNrchdOXb",premium:"price_1UdxxOCNxSYaUXAzbCfHiLsU"};
const priceVars:Record<PaidPlan,string>={essencial:"STRIPE_PRICE_ESSENCIAL",pro:"STRIPE_PRICE_PRO",premium:"STRIPE_PRICE_PREMIUM"};
export function resolvePrice(plan:string,env:Record<string,string|undefined>){
 if(!Object.hasOwn(sandboxPrices,plan))return undefined;
 const p=plan as PaidPlan,explicit=env[priceVars[p]]?.trim();
 if(explicit)return /^price_[A-Za-z0-9]+$/.test(explicit)?explicit:undefined;
 // These values belong to RODX's existing Stripe sandbox. Never fall back for live mode.
 return /^(?:sk|rk)_test_/.test(env.STRIPE_SECRET_KEY??"")?sandboxPrices[p]:undefined;
}
export function billingSetup(env:Record<string,string|undefined>){
 const missing:string[]=[];
 const key=env.STRIPE_SECRET_KEY??"";
 if(!/^(?:sk|rk)_(?:test|live)_\S+$/.test(key))missing.push("STRIPE_SECRET_KEY");
 if(!/^whsec_\S+$/.test(env.STRIPE_WEBHOOK_SECRET??""))missing.push("STRIPE_WEBHOOK_SECRET");
 if(!env.SUPABASE_SERVICE_ROLE_KEY?.trim())missing.push("SUPABASE_SERVICE_ROLE_KEY");
 for(const p of Object.keys(priceVars) as PaidPlan[]){
  const price=resolvePrice(p,env);
  if(!price||(/^(?:sk|rk)_live_/.test(key)&&price===sandboxPrices[p]))missing.push(priceVars[p]);
 }
 return {ready:missing.length===0,missing,test:/^(?:sk|rk)_test_/.test(key)};
}
