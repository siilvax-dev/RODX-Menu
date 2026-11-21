import {AuthCard} from "@/components/auth-card";
import {changePassword} from "../auth-actions";
import {requireUser} from "@/lib/auth";
export const dynamic="force-dynamic";
export default async function Page(){await requireUser();return <AuthCard title="Nova senha" subtitle="Defina uma senha segura."><form action={changePassword} className="form-grid"><label>Nova senha<input type="password" name="password" minLength={8} maxLength={128} required/></label><button className="btn">Salvar senha</button></form></AuthCard>}
