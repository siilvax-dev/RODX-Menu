import {NextRequest,NextResponse} from "next/server";
import {db} from "@/lib/supabase";
export async function GET(req:NextRequest){
 const code=req.nextUrl.searchParams.get("code");const next=req.nextUrl.searchParams.get("next")==="/nova-senha"?"/nova-senha":"/painel";
 if(code){const client=await db();const {error}=await client.auth.exchangeCodeForSession(code);if(!error)return NextResponse.redirect(new URL(next,process.env.APP_URL||req.url))}
 return NextResponse.redirect(new URL("/entrar?erro=credenciais",process.env.APP_URL||req.url));
}
