import "server-only";
import {db,configured} from "./supabase";
import {redirect,notFound} from "next/navigation";
import {uuid,Role} from "./domain";
export async function requireUser(){
 if(!configured())redirect("/entrar?erro=configuracao");
 const client=await db();
 const {data:{user}}=await client.auth.getUser();
 if(!user)redirect("/entrar");
 return {client,user};
}
export async function requireTenant(id:string,allowed?:Role[]){
 if(!uuid.safeParse(id).success)notFound();
 const {client,user}=await requireUser();
 const {data:membership}=await client.from("memberships").select("role").eq("tenant_id",id).eq("user_id",user.id).maybeSingle();
 if(!membership)notFound();
 const role=membership.role as Role;
 if(allowed&&!allowed.includes(role))notFound();
 const {data:tenant,error}=await client.from("establishments").select("*").eq("id",id).single();
 if(error||!tenant)notFound();
 const {data:level,error:planError}=await client.rpc("tenant_plan_level",{t:id});
 if(planError||typeof level!=="number")throw new Error("Não foi possível verificar o plano do estabelecimento");
 return {client,user,role,tenant,level};
}
export async function requireAdmin(){
 const {client,user}=await requireUser();
 const {data}=await client.rpc("is_platform_admin");
 if(data!==true)notFound();
 return {client,user};
}
