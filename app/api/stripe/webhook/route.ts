import {NextRequest,NextResponse} from "next/server";
import {stripe,pricePlan} from "@/lib/billing";
import {service} from "@/lib/supabase";
import {uuid} from "@/lib/domain";
import type Stripe from "stripe";
export async function POST(req:NextRequest){
 const signature=req.headers.get("stripe-signature");const secret=process.env.STRIPE_WEBHOOK_SECRET;
 if(!secret||!signature)return NextResponse.json({error:"Webhook indisponível"},{status:400});
 let event;
 try{event=await stripe().webhooks.constructEventAsync(await req.text(),signature,secret)}catch{return NextResponse.json({error:"Assinatura inválida"},{status:400})}
 const subscriptionEvents=["customer.subscription.created","customer.subscription.updated","customer.subscription.deleted"];
 const invoiceEvents=["invoice.paid","invoice.payment_failed"];
 if(!subscriptionEvents.includes(event.type)&&!invoiceEvents.includes(event.type))return NextResponse.json({received:true});
 try{
  const obj=event.data.object;
  const reference=invoiceEvents.includes(event.type)?(obj as Stripe.Invoice).parent?.subscription_details?.subscription:(obj as Stripe.Subscription).id;
  const subscriptionId=typeof reference==="string"?reference:reference?.id;
  if(!subscriptionId)return NextResponse.json({received:true});
  // Read current status instead of trusting delivery order.
  const sub=await stripe().subscriptions.retrieve(subscriptionId);
  const db=service();
  const {data:linked,error:lookupError}=await db.from("subscriptions").select("tenant_id").eq("stripe_subscription",sub.id).maybeSingle();
  if(lookupError)throw lookupError;
  // Metadata is the bootstrap reference only; subsequent events use the association in PostgreSQL.
  if(!linked&&!sub.metadata.tenant_id)return NextResponse.json({received:true});
  const t=uuid.parse(linked?.tenant_id??sub.metadata.tenant_id);
  const plan=pricePlan(sub.items.data[0]?.price.id);if(!plan)throw new Error("Preço desconhecido");
  const {error}=await db.rpc("apply_subscription_event",{p_event:event.id,t,p_plan:plan,p_status:sub.status,p_customer:typeof sub.customer==="string"?sub.customer:sub.customer.id,p_subscription:sub.id,p_created:event.created});
  if(error)throw error;
  return NextResponse.json({received:true});
 }catch{return NextResponse.json({error:"Falha no processamento"},{status:500})}
}
