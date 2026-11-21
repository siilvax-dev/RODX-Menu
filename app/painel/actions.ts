"use server";
import {revalidatePath} from "next/cache";
import {redirect} from "next/navigation";
import {z} from "zod";
import {requireTenant} from "@/lib/auth";
import {catalog,formPayload} from "@/lib/modules";
import {uuid,statuses} from "@/lib/domain";
function end(t:string,m:string,ok:boolean):never{const path="/painel/"+t+"/"+m;revalidatePath(path);redirect(path+(ok?"?ok=1":"?erro=1"))}
export async function saveRecord(t:string,m:string,form:FormData){
 const config=catalog.find(x=>x.slug===m);const table=m==="configuracoes"?"establishments":config?.table;
 if(!table)throw new Error("Módulo inválido");
 const {client}=await requireTenant(t,m==="configuracoes"?["owner"]:["owner","manager"]);
 let valid=false;
 try{
  const payload=formPayload(table,form);
  const raw=form.get("id");const id=raw?uuid.parse(raw):null;
  const result=table==="establishments"?await client.from(table).update(payload).eq("id",t).select("id").single():
   id?await client.from(table).update(payload).eq("tenant_id",t).eq("id",id).select("id").single():
   await client.from(table).insert({...payload,tenant_id:t}).select("id").single();
  valid=!result.error;
 }catch{/* validation failure */}
 end(t,m,valid);
}
export async function changeStatus(t:string,m:string,form:FormData){
 const {client}=await requireTenant(t);const id=uuid.safeParse(form.get("id"));const status=z.enum(Object.keys(statuses) as [keyof typeof statuses,...(keyof typeof statuses)[]]).safeParse(form.get("status"));
 const target=m==="cozinha"?"cozinha":"pedidos";
 if(!id.success||!status.success)end(t,target,false);
 const {error}=await client.rpc("transition_order",{t,p_id:id.data,p_status:status.data});end(t,target,!error);
}
export async function addStaff(t:string,form:FormData){
 const {client}=await requireTenant(t,["owner"]);const data=z.object({email:z.email(),role:z.enum(["manager","kitchen","attendant"])}).safeParse({email:form.get("email"),role:form.get("role")});
 if(!data.success)end(t,"equipe",false);
 const {error}=await client.rpc("set_staff",{t,p_email:data.data.email,p_role:data.data.role});end(t,"equipe",!error);
}
export async function removeStaff(t:string,form:FormData){const {client}=await requireTenant(t,["owner"]);const user=uuid.safeParse(form.get("user"));if(!user.success)end(t,"equipe",false);const {error}=await client.rpc("remove_staff",{t,u:user.data});end(t,"equipe",!error)}
export async function ticket(t:string,form:FormData){
 const {client}=await requireTenant(t,["owner","manager"]);const data=z.object({subject:z.string().trim().min(3).max(150),message:z.string().trim().min(3).max(3000)}).safeParse({subject:form.get("subject"),message:form.get("message")});
 if(!data.success)end(t,"suporte",false);const {error}=await client.from("support_tickets").insert({tenant_id:t,...data.data});end(t,"suporte",!error);
}
export async function anonymize(t:string,form:FormData){
 const {client}=await requireTenant(t,["owner"]);const phone=z.string().regex(/^\d{10,13}$/).safeParse(String(form.get("phone")).replace(/\D/g,""));
 if(!phone.success||form.get("confirm")!=="on")end(t,"configuracoes",false);
 const {error}=await client.rpc("anonymize_customer",{t,p_phone:phone.data});end(t,"configuracoes",!error);
}
