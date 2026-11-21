import "server-only";
import {createServerClient} from "@supabase/ssr";
import {createClient} from "@supabase/supabase-js";
import {cookies} from "next/headers";
import {supabaseUrl,supabasePublishableKey} from "./public-config";
export function configured(){return !!(supabaseUrl && supabasePublishableKey)}
export async function db(){
 if(!configured()) throw new Error("Configure as credenciais do Supabase.");
 const jar=await cookies();
 return createServerClient(supabaseUrl,supabasePublishableKey,{cookies:{
  getAll:()=>jar.getAll(),
  setAll:(items)=>{try{items.forEach(({name,value,options})=>jar.set(name,value,options))}catch{/* proxy handles refresh */}}
 }});
}
export function service(){
 if(!configured()||!process.env.SUPABASE_SERVICE_ROLE_KEY) throw new Error("Integração Supabase incompleta.");
 return createClient(supabaseUrl,process.env.SUPABASE_SERVICE_ROLE_KEY,{auth:{persistSession:false,autoRefreshToken:false}});
}
