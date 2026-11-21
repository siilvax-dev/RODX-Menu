import {createServerClient} from "@supabase/ssr";
import {NextRequest,NextResponse} from "next/server";
import {supabaseUrl,supabasePublishableKey} from "./lib/public-config";
export async function proxy(request:NextRequest){
 let response=NextResponse.next({request});
 if(!supabaseUrl||!supabasePublishableKey)return response;
 const client=createServerClient(supabaseUrl,supabasePublishableKey,{cookies:{
 getAll:()=>request.cookies.getAll(),
 setAll(items){items.forEach(({name,value})=>request.cookies.set(name,value));response=NextResponse.next({request});items.forEach(({name,value,options})=>response.cookies.set(name,value,options))}
 }});
 await client.auth.getUser();
 return response;
}
export const config={matcher:["/((?!_next/static|_next/image|favicon.ico|api/stripe/webhook|.*\\.(?:svg|png|jpg|jpeg|gif|webp)$).*)"]};
