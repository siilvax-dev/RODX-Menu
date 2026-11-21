"use server";
import {requireTenant} from "@/lib/auth";
import {stripe,planPrice,appUrl,billingStatus} from "@/lib/billing";
import {redirect} from "next/navigation";
export async function subscribe(t:string,form:FormData){
 const {client,user}=await requireTenant(t,["owner"]);const plan=String(form.get("plan"));const price=planPrice(plan);
 const path="/painel/"+t+"/assinatura";let url:string|null=null;
 try{
  if(!price||!billingStatus().ready)throw new Error("Plano não configurado");
  const {data:s,error}=await client.rpc("reserve_checkout",{t,p_plan:plan});
  if(error||!s)throw new Error("Checkout indisponível");
  const session=await stripe().checkout.sessions.create({mode:"subscription",line_items:[{price,quantity:1}],customer:s.customer||undefined,customer_email:s.customer?undefined:user.email,client_reference_id:t,subscription_data:{metadata:{tenant_id:t}},metadata:{tenant_id:t},expires_at:s.expires,success_url:appUrl()+path+"?encaminhado=1",cancel_url:appUrl()+path},{idempotencyKey:"subscription-"+s.attempt});
  url=session.url;
 }catch{/* do not leak Stripe errors */}
 redirect(url||path+"?erro=1");
}
export async function portal(t:string){
 const {client}=await requireTenant(t,["owner"]);const path="/painel/"+t+"/assinatura";let url:string|null=null;
 try{if(!billingStatus().ready)throw new Error("Stripe não configurado");const {data}=await client.from("subscriptions").select("stripe_customer").eq("tenant_id",t).single();if(data?.stripe_customer)url=(await stripe().billingPortal.sessions.create({customer:data.stripe_customer,return_url:appUrl()+path})).url}catch{/* unavailable */}
 redirect(url||path+"?erro=1");
}
