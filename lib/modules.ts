import {z} from "zod";
import {Role,parseMoney,uuid,acceptedPaymentsSchema} from "./domain";
export type Field={key:string;label:string;kind?:"money"|"integer"|"checkbox"|"select"|"textarea"|"date"|"payments";required?:boolean;source?:string;placeholder?:string;max?:number};
const fields:Record<string,Field[]>={
 menus:[{key:"name",label:"Nome",required:true},{key:"active",label:"Ativo",kind:"checkbox"}],
 categories:[{key:"name",label:"Nome",required:true},{key:"menu_id",label:"Cardápio",kind:"select",source:"menus",required:true},{key:"sort_order",label:"Ordem",kind:"integer",required:true},{key:"active",label:"Ativa",kind:"checkbox"}],
 products:[{key:"name",label:"Nome",required:true},{key:"category_id",label:"Categoria",kind:"select",source:"categories",required:true},{key:"description",label:"Descrição",kind:"textarea"},{key:"price",label:"Preço (R$)",kind:"money",required:true},{key:"stock",label:"Estoque (vazio = ilimitado)",kind:"integer"},{key:"image_url",label:"URL HTTPS da imagem"},{key:"active",label:"Disponível",kind:"checkbox"}],
 addons:[{key:"product_id",label:"Produto",kind:"select",source:"products",required:true},{key:"name",label:"Nome",required:true},{key:"price",label:"Preço (R$)",kind:"money",required:true},{key:"active",label:"Ativo",kind:"checkbox"}],
 dining_tables:[{key:"name",label:"Nome da mesa",required:true},{key:"active",label:"Ativa",kind:"checkbox"}],
 couriers:[{key:"name",label:"Nome do entregador",required:true,max:100},{key:"phone",label:"Telefone (DDD + número)"},{key:"active",label:"Disponível",kind:"checkbox"}],
 coupons:[{key:"code",label:"Código",required:true},{key:"percent",label:"Desconto (%)",kind:"integer",required:true},{key:"max_uses",label:"Limite de usos",kind:"integer"},{key:"expires_at",label:"Validade (UTC)",kind:"date"},{key:"active",label:"Ativo",kind:"checkbox"}],
 establishments:[{key:"name",label:"Nome do estabelecimento",required:true},{key:"whatsapp",label:"WhatsApp (55 + DDD + número)"},{key:"address",label:"Endereço"},{key:"opening_hours",label:"Horário de atendimento (informativo)",max:200,placeholder:"Seg a sáb · 18h às 23h"},{key:"description",label:"Sobre o estabelecimento",kind:"textarea",max:500,placeholder:"Conte aos clientes o que torna sua loja especial."},{key:"delivery_fee",label:"Taxa de entrega (R$)",kind:"money",required:true},{key:"payment_methods",label:"Formas de pagamento aceitas",kind:"payments"},{key:"published",label:"Publicar cardápio",kind:"checkbox"},{key:"accepting_orders",label:"Aceitar pedidos",kind:"checkbox"},{key:"delivery_enabled",label:"Delivery ativo",kind:"checkbox"},{key:"pickup_enabled",label:"Retirada ativa",kind:"checkbox"}]
};
export const catalog=[
 {slug:"cardapios",table:"menus",title:"Cardápios"},{slug:"categorias",table:"categories",title:"Categorias"},{slug:"produtos",table:"products",title:"Produtos e estoque"},{slug:"adicionais",table:"addons",title:"Adicionais"},{slug:"mesas",table:"dining_tables",title:"Mesas e QR Codes"},{slug:"cupons",table:"coupons",title:"Cupons e promoções"},{slug:"entregadores",table:"couriers",title:"Entregadores"}
];
export const moduleList=[{slug:"visao-geral",title:"Início"},{slug:"pdv",title:"PDV · Nova venda"},{slug:"pedidos",title:"Pedidos"},{slug:"cozinha",title:"Painel de cozinha"},{slug:"caixa",title:"Caixa"},{slug:"clientes",title:"Clientes"},{slug:"entregas",title:"Controle de entregas"},{slug:"salao",title:"Salão · contas por mesa"},...catalog.map(({slug,title})=>({slug,title})),{slug:"fidelidade",title:"Fidelidade"},{slug:"relatorios",title:"Relatórios"},{slug:"equipe",title:"Equipe"},{slug:"assinatura",title:"Planos e assinatura"},{slug:"configuracoes",title:"Configurações"},{slug:"suporte",title:"Suporte"}];
export function canAccess(slug:string,role:Role){
 if(role==="owner")return true;
 if(role==="manager")return !["equipe","assinatura","configuracoes"].includes(slug);
 if(role==="kitchen")return slug==="cozinha";
 return ["visao-geral","pedidos","cozinha","pdv","caixa","clientes","entregas","salao"].includes(slug);
}
export function getFields(table:string){return fields[table]}
export function formPayload(table:string,form:FormData){
 const config=fields[table];if(!config)throw new Error("Módulo inválido");
 const out:Record<string,string|boolean|number|string[]|null>={};
 for(const f of config){
  if(f.kind==="payments"){out[f.key]=acceptedPaymentsSchema.parse(form.getAll(f.key));continue}
  const value=String(form.get(f.key)||"").trim();
  if(f.kind==="checkbox"){out[f.key]=form.has(f.key);continue}
  if(!value){if(f.required)throw new Error("Campo obrigatório");out[f.key]=["description","opening_hours"].includes(f.key)?"":null;continue}
  if(f.kind==="money")out[f.key]=parseMoney(value);
  else if(f.kind==="integer")out[f.key]=z.coerce.number().int().min(0).max(10000000).parse(value);
  else if(f.kind==="select")out[f.key]=uuid.parse(value);
  else if(f.kind==="date")out[f.key]=z.iso.datetime().parse(new Date(value+"Z").toISOString());
  else if(f.key==="code")out[f.key]=z.string().regex(/^[A-Z0-9-]{2,24}$/).parse(value.toUpperCase());
  else if(f.key==="image_url")out[f.key]=z.url({protocol:/^https$/}).max(2048).parse(value);
  else if(f.key==="whatsapp")out[f.key]=z.string().regex(/^55\d{10,11}$/).parse(value);
  else if(f.key==="phone")out[f.key]=z.string().regex(/^\d{10,13}$/).parse(value.replace(/\D/g,""));
  else out[f.key]=z.string().max(f.max??(f.kind==="textarea"?3000:400)).parse(value);
 }
 return out;
}
