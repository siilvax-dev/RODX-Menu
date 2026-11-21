import {NextRequest,NextResponse} from "next/server";
import {db,configured} from "@/lib/supabase";
import {csvCell,uuid} from "@/lib/domain";
export async function GET(req:NextRequest){
 const t=uuid.safeParse(req.nextUrl.searchParams.get("tenant"));if(!t.success||!configured())return new NextResponse("Solicitação inválida",{status:400});
 const client=await db();const {data:{user}}=await client.auth.getUser();if(!user)return new NextResponse("Autenticação necessária",{status:401});
 const {data:member}=await client.from("memberships").select("role").eq("tenant_id",t.data).eq("user_id",user.id).maybeSingle();
 if(!member||!["owner","manager"].includes(member.role))return new NextResponse("Sem permissão",{status:403});
 const {data:level,error:planError}=await client.rpc("tenant_plan_level",{t:t.data});if(planError||typeof level!=="number")return new NextResponse("Não foi possível verificar a assinatura",{status:500});
 if(level<3)return new NextResponse("Exportação disponível no plano Premium",{status:403});
 const cols=["number","created_at","status","mode","subtotal","discount","delivery_fee","total","payment_method"];
 const lines=[["Pedido","Data UTC","Status","Modalidade","Subtotal (centavos)","Desconto (centavos)","Entrega (centavos)","Total (centavos)","Pagamento"].map(csvCell).join(";")];
 const since=new Date(Date.now()-30*86400000).toISOString();
 for(let i=0;i<100;i++){const {data,error}=await client.from("orders").select(cols.join(",")).eq("tenant_id",t.data).gte("created_at",since).order("number").range(i*500,i*500+499);if(error)return new NextResponse("Falha na exportação",{status:500});for(const row of data||[])lines.push(cols.map(c=>csvCell((row as unknown as Record<string,unknown>)[c])).join(";"));if(!data||data.length<500)break;if(i===99)return new NextResponse("Limite de exportação excedido",{status:413})}
 return new NextResponse("\ufeff"+lines.join("\r\n"),{headers:{"Content-Type":"text/csv; charset=utf-8","Content-Disposition":"attachment; filename=rodx-pedidos-30-dias.csv","Cache-Control":"no-store"}});
}
