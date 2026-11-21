import {NextRequest,NextResponse} from "next/server";
import {checkoutSchema} from "@/lib/domain";
import {service} from "@/lib/supabase";
export async function POST(req:NextRequest){
 try{
  if(!(req.headers.get("content-type")||"").includes("application/json"))return NextResponse.json({error:"Formato inválido."},{status:415});
  const raw=await req.text();if(raw.length>24000)return NextResponse.json({error:"Pedido muito grande."},{status:413});
  const parsed=checkoutSchema.safeParse(JSON.parse(raw));
  if(!parsed.success)return NextResponse.json({error:"Revise os dados do pedido.",fields:parsed.error.flatten().fieldErrors},{status:400});
  const p=parsed.data;const client=service();
  const {data,error}=await client.rpc("place_order",{p_slug:p.slug,p_request:p.request_id,p_mode:p.mode,p_name:p.name,p_phone:p.phone,p_address:p.address||null,p_notes:p.notes||null,p_table:p.table||null,p_coupon:p.coupon||null,p_payment:p.payment,p_items:p.items});
  if(error){const safe=["Cardápio indisponível","Estabelecimento fechado","Limite de pedidos atingido","Entrega indisponível ou endereço inválido","Retirada indisponível","Mesa inválida","Produto indisponível","Adicional indisponível","Cupom inválido ou expirado","Pedido excede limite","Forma de pagamento indisponível","Pedido na mesa indisponível no plano atual","Cupons indisponíveis no plano atual"];return NextResponse.json({error:safe.includes(error.message)?error.message:"Não foi possível finalizar o pedido."},{status:409})}
  return NextResponse.json(data,{status:201});
 }catch{return NextResponse.json({error:"Não foi possível processar o pedido."},{status:400})}
}
