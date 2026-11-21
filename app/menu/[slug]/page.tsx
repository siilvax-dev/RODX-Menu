import {db,configured} from "@/lib/supabase";
import {notFound} from "next/navigation";
import {PublicMenu} from "@/lib/domain";
import {MenuClient} from "@/components/menu-client";
export const dynamic="force-dynamic";
export default async function Page({params,searchParams}:{params:Promise<{slug:string}>;searchParams:Promise<{mesa?:string}>}){
 const {slug}=await params;const {mesa}=await searchParams;
 if(!configured())return <main className="max-w-xl mx-auto p-10 surface mt-12"><h1 className="section-title">Cardápio indisponível</h1><p className="muted mt-3">A conexão com o banco de dados ainda não está configurada.</p></main>;
 const client=await db();const {data,error}=await client.rpc("public_menu",{p_slug:slug});
 if(error)throw new Error("Não foi possível carregar o cardápio");if(!data)notFound();
 return <MenuClient menu={data as PublicMenu} table={mesa}/>;
}
