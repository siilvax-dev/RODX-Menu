"use client";
import {useEffect} from "react";
import {useRouter} from "next/navigation";
import {createBrowserClient} from "@supabase/ssr";
import {supabaseUrl,supabasePublishableKey} from "@/lib/public-config";
export function Live({tenant}:{tenant:string}){const router=useRouter();useEffect(()=>{
 const client=createBrowserClient(supabaseUrl,supabasePublishableKey);
 const channel=client.channel("orders-"+tenant).on("postgres_changes",{event:"*",schema:"public",table:"orders",filter:"tenant_id=eq."+tenant},()=>router.refresh()).subscribe();
 const timer=setInterval(()=>router.refresh(),15000);
 return()=>{clearInterval(timer);void client.removeChannel(channel)}
 },[tenant,router]);return <span className="pill">● Atualização automática</span>}
