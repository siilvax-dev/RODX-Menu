"use server";
import {z} from "zod";
import {requireTenant} from "@/lib/auth";
import {uuid,checkoutSchema,parseMoney} from "@/lib/domain";
import {redirect} from "next/navigation";
import {revalidatePath} from "next/cache";
const roles=["owner","manager","attendant"] as const;
export async function pdvSubmit(t:string,form:FormData){
 const {client,tenant,level}=await requireTenant(t,[...roles]);
 let ok=false;
 try{
  if(level<2)throw new Error("Plano");
  const data=checkoutSchema.parse({slug:tenant.slug,request_id:form.get("request_id"),mode:form.get("mode"),name:form.get("name"),phone:String(form.get("phone")).replace(/\D/g,""),address:form.get("address")||undefined,notes:form.get("notes")||undefined,table:form.get("table")||undefined,payment:form.get("payment"),items:JSON.parse(String(form.get("items")))});
  const {error}=await client.rpc("pdv_order",{t,p_request:data.request_id,p_mode:data.mode,p_name:data.name,p_phone:data.phone,p_address:data.address??null,p_notes:data.notes??null,p_table:data.table??null,p_payment:data.payment,p_items:data.items});
  ok=!error;
 }catch{}
 revalidatePath("/painel/"+t);
 redirect("/painel/"+t+"/pdv?"+(ok?"ok=1":"erro=1"));
}
export async function cashSubmit(t:string,form:FormData){
 const {client,level}=await requireTenant(t,[...roles]);let ok=false;
 try{
  if(level<2)throw new Error("Plano");
  const action=z.enum(["abrir","fechar","suprimento","sangria","pagar_parcial","estornar_pagamentos"]).parse(form.get("action"));
  const session=form.get("session"),order=form.get("order"),amount=form.get("amount");
  const request=uuid.parse(form.get("request"));
  const parsedAmount=amount!==null?parseMoney(String(amount)):null;
  const method=String(form.get("method")??"");
  const note=String(form.get("note")??"");
  let error:{message:string}|null=null;
  if(action==="pagar_parcial"){
   ({error}=await client.rpc("register_order_payment",{t,p_request:request,p_session:session?uuid.parse(session):null,p_order:order?uuid.parse(order):null,p_amount:parsedAmount,p_method:method}));
  }else if(action==="estornar_pagamentos"){
   ({error}=await client.rpc("refund_order_payments",{t,p_request:request,p_session:session?uuid.parse(session):null,p_order:order?uuid.parse(order):null,p_note:note}));
  }else{
   ({error}=await client.rpc("cash_action",{t,p_action:action,p_request:request,p_session:session?uuid.parse(session):null,p_order:order?uuid.parse(order):null,p_amount:parsedAmount,p_note:note}));
  }
  ok=!error;
 }catch{}
 revalidatePath("/painel/"+t);redirect("/painel/"+t+"/caixa?"+(ok?"ok=1":"erro=1"));
}
export async function courierSubmit(t:string,form:FormData){
 const {client,level}=await requireTenant(t,[...roles]);let ok=false;
 try{
  if(level<2)throw new Error("Plano");
  const raw=form.get("courier");
  const {error}=await client.rpc("assign_courier",{t,p_order:uuid.parse(form.get("order")),p_courier:raw?uuid.parse(raw):null});ok=!error;
 }catch{}
 revalidatePath("/painel/"+t);redirect("/painel/"+t+"/entregas?"+(ok?"ok=1":"erro=1"));
}
