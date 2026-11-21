import {AuthCard} from "@/components/auth-card";
import {requireUser} from "@/lib/auth";
import {onboard} from "../auth-actions";
export const dynamic="force-dynamic";
export default async function Page({searchParams}:{searchParams:Promise<{erro?:string}>}){await requireUser();return <AuthCard title="Seu estabelecimento" subtitle="Configure o endereço exclusivo do seu cardápio." error={(await searchParams).erro}><form action={onboard} className="form-grid"><label>Nome do estabelecimento<input name="name" required minLength={2} maxLength={100} placeholder="Ex.: Pizzaria da casa"/></label><label>URL do cardápio<input name="slug" required pattern="[a-z0-9][a-z0-9-]{2,49}" placeholder="pizzaria-da-casa"/><span className="muted font-normal">Use letras minúsculas, números e hífens.</span></label><button className="btn">Criar estabelecimento</button></form></AuthCard>}
