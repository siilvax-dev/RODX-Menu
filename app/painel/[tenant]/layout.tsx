import Link from "next/link";
import {requireTenant} from "@/lib/auth";
import {PanelNav} from "@/components/panel-nav";
import {Brand} from "@/components/brand";
import {roleLabels} from "@/lib/domain";
import {signOut} from "@/app/auth-actions";
import {ExternalLink} from "lucide-react";
export default async function Layout({children,params}:{children:React.ReactNode;params:Promise<{tenant:string}>}){
 const {tenant:id}=await params;const {tenant,role,level}=await requireTenant(id);
 return <div className="min-h-screen md:flex"><aside className="md:fixed md:inset-y-0 md:w-60 bg-[#111] text-white p-5 flex flex-col overflow-y-auto"><div className="ml-2 mt-2"><Brand dark/><p className="text-neutral-500 text-[10px] uppercase tracking-widest mt-3">Painel do estabelecimento</p></div><Link href="/painel" className="border border-white/15 rounded-xl p-3 mt-6 flex justify-between gap-3 items-center"><div className="min-w-0"><p className="truncate font-semibold">{tenant.name}</p><p className="text-xs text-neutral-400 mt-1">{roleLabels[role]}</p></div><span>⇄</span></Link><PanelNav tenant={id} role={role} level={level}/><div className="mt-auto pt-5 flex md:flex-col gap-3"><Link href={"/menu/"+tenant.slug} target="_blank" className="text-sm flex gap-2 items-center text-neutral-400"><ExternalLink size={14}/>Cardápio público</Link><form action={signOut}><button className="text-neutral-400 text-sm">Sair da conta</button></form></div></aside><main className="min-w-0 flex-1 md:ml-60 p-5 md:p-8 lg:p-10">{children}</main></div>
}
