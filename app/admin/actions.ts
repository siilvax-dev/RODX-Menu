"use server";
import {requireAdmin} from "@/lib/auth";
import {uuid} from "@/lib/domain";
import {redirect} from "next/navigation";
export async function resolveTicket(form:FormData){const {client}=await requireAdmin();const id=uuid.parse(form.get("id"));const {error}=await client.from("support_tickets").update({status:"resolvido"}).eq("id",id);redirect("/admin"+(error?"?erro=1":"?ok=1"))}
