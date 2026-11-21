"use client";
import Link from "next/link";
import {usePathname} from "next/navigation";
import {LayoutDashboard,Receipt,ChefHat,BookOpen,FolderOpen,Package,PlusCircle,ScanLine,Tag,Heart,ChartNoAxesCombined,Users,CreditCard,Settings,LifeBuoy,Lock,LucideIcon,ShoppingCart,Wallet,ContactRound,Truck,Bike,Utensils} from "lucide-react";
import {moduleList,canAccess} from "@/lib/modules";
import {canUseModule} from "@/lib/plans";
import {Role} from "@/lib/domain";

const icons:Record<string,LucideIcon>={"visao-geral":LayoutDashboard,pdv:ShoppingCart,pedidos:Receipt,cozinha:ChefHat,caixa:Wallet,clientes:ContactRound,entregas:Truck,entregadores:Bike,salao:Utensils,cardapios:BookOpen,categorias:FolderOpen,produtos:Package,adicionais:PlusCircle,mesas:ScanLine,cupons:Tag,fidelidade:Heart,relatorios:ChartNoAxesCombined,equipe:Users,assinatura:CreditCard,configuracoes:Settings,suporte:LifeBuoy};
const groups=[{title:"Operação",modules:["visao-geral","pdv","pedidos","salao","mesas","cozinha","entregas","entregadores"]},{title:"Gestão",modules:["cardapios","categorias","produtos","adicionais","caixa","relatorios","equipe"]},{title:"Clientes e marketing",modules:["clientes","cupons","fidelidade"]},{title:"Configurações e conta",modules:["assinatura","configuracoes","suporte"]}];
export function PanelNav({tenant,role,level}:{tenant:string;role:Role;level:number}){
 const pathname=usePathname();
 return <nav aria-label="Módulos do estabelecimento" className="flex md:flex-col md:overflow-y-auto overflow-x-auto gap-4 mt-5 md:mt-6 pb-2">{groups.map(group=>{const entries=group.modules.filter(m=>canAccess(m,role));if(!entries.length)return null;return <section key={group.title} className="flex flex-col shrink-0 md:shrink"><p className="hidden md:block px-3 mb-1 text-[10px] text-neutral-500 uppercase font-bold tracking-widest">{group.title}</p><div className="flex md:flex-col gap-1">{entries.map(slug=>{const Icon=icons[slug],title=moduleList.find(m=>m.slug===slug)?.title??slug;const href="/painel/"+tenant+"/"+slug,active=pathname===href,locked=!canUseModule(slug,level);return <Link key={slug} href={href} aria-current={active?"page":undefined} className={"flex whitespace-nowrap items-center gap-3 rounded-lg px-3 py-2.5 "+(active?"bg-white text-black font-bold":"text-neutral-300 hover:bg-white/10 hover:text-white")}><Icon size={16} className="shrink-0"/><span>{title}</span>{locked&&<Lock size={13} className="text-neutral-500 ml-auto shrink-0" aria-label="Requer outro plano"/>}</Link>})}</div></section>})}</nav>
}
