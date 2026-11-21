"use server";
import {z} from "zod";
import {redirect} from "next/navigation";
import {db,configured} from "@/lib/supabase";
import {requireUser} from "@/lib/auth";
const credentials=z.object({email:z.string().email().max(254),password:z.string().min(8).max(128)});
function fail(path:string,code:string):never{redirect(path+"?erro="+encodeURIComponent(code))}
export async function signIn(form:FormData){
 if(!configured())fail("/entrar","configuracao");
 const parsed=credentials.safeParse({email:form.get("email"),password:form.get("password")});if(!parsed.success)fail("/entrar","dados");
 const client=await db();const {error}=await client.auth.signInWithPassword(parsed.data);
 if(error)fail("/entrar","credenciais");redirect("/painel");
}
export async function signUp(form:FormData){
 if(!configured())fail("/cadastro","configuracao");
 const parsed=credentials.safeParse({email:form.get("email"),password:form.get("password")});
 if(!parsed.success||form.get("consent")!=="on")fail("/cadastro","dados");
 const client=await db();const {data,error}=await client.auth.signUp({...parsed.data,options:{emailRedirectTo:new URL("/auth/callback",process.env.APP_URL||"http://localhost:3000").toString()}});
 if(error)fail("/cadastro","cadastro");if(data.session)redirect("/onboarding");redirect("/entrar?confirmacao=1");
}
export async function signOut(){const client=await db();await client.auth.signOut();redirect("/")}
export async function resetPassword(form:FormData){
 const email=z.string().email().safeParse(form.get("email"));
 if(!configured())fail("/recuperar","configuracao");
 if(!email.success)fail("/recuperar","dados");
 const client=await db();await client.auth.resetPasswordForEmail(email.data,{redirectTo:new URL("/auth/callback?next=/nova-senha",process.env.APP_URL||"http://localhost:3000").toString()});redirect("/recuperar?enviado=1");
}
export async function changePassword(form:FormData){
 const {client}=await requireUser();const p=z.string().min(8).max(128).safeParse(form.get("password"));
 if(!p.success)fail("/nova-senha","dados");const {error}=await client.auth.updateUser({password:p.data});if(error)fail("/nova-senha","dados");redirect("/painel");
}
export async function onboard(form:FormData){
 const {client}=await requireUser();
 const parsed=z.object({name:z.string().trim().min(2).max(100),slug:z.string().regex(/^[a-z0-9][a-z0-9-]{2,49}$/)}).safeParse({name:form.get("name"),slug:form.get("slug")});
 if(!parsed.success)fail("/onboarding","dados");
 const {data,error}=await client.rpc("create_establishment",{p_name:parsed.data.name,p_slug:parsed.data.slug});
 if(error||!data)fail("/onboarding","estabelecimento");redirect("/painel/"+data+"/visao-geral");
}
