import {beforeAll,afterAll,describe,it,expect} from "vitest";
import {PGlite} from "@electric-sql/pglite";
import {readFileSync,readdirSync} from "node:fs";
import {randomUUID} from "node:crypto";
const pg=new PGlite();
const ownerA=randomUUID(),ownerB=randomUUID(),kitchen=randomUUID();
let a:string,b:string,menuA:string,categoryA:string,productA:string,productB:string,addonA:string,tableToken:string,coupon:string;
let order:string,request=randomUUID();
async function sql(query:string,params:unknown[]=[]){return (await pg.query<Record<string,any>>(query,params)).rows}
async function actor(role:string,user?:string){await pg.exec("reset role");await pg.query("select set_config('request.jwt.claim.sub',$1,false)",[user||""]);await pg.exec("set role "+role)}
async function actOwner(user:string){await actor("authenticated",user)}
const place=async (options:{slug?:string;request?:string;product?:string;qty?:number;coupon?:string;mode?:string;token?:string;payment?:string}={})=>{
 await actor("service_role");return (await sql("select public.place_order($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11::jsonb) as result",[options.slug||"tenant-a",options.request||randomUUID(),options.mode||"retirada","Cliente","14999999999",null,null,options.token||null,options.coupon||null,options.payment||"pix",JSON.stringify([{product_id:options.product||productA,quantity:options.qty||1,addons:options.product?[]:[addonA]}])]))[0].result;
};
beforeAll(async()=>{
 await pg.exec(`create role anon; create role authenticated; create role service_role bypassrls;
 create schema auth; create table auth.users(id uuid primary key,email text,email_confirmed_at timestamptz);
 create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$;
 grant usage on schema auth,public to anon,authenticated,service_role;
 create publication supabase_realtime;`);
 for(const filename of readdirSync(new URL("../supabase/migrations/",import.meta.url)).filter(f=>f.endsWith(".sql")).sort()){
  let migration=readFileSync(new URL("../supabase/migrations/"+filename,import.meta.url),"utf8");
  // PGlite has gen_random_uuid natively; Supabase's auth schema and roles above are a local harness.
  migration=migration.replace("create extension if not exists pgcrypto;","");
  await pg.exec(migration);
 }
 await sql("insert into auth.users values($1,'owner-a@example.com',now()),($2,'owner-b@example.com',now()),($3,'kitchen@example.com',now())",[ownerA,ownerB,kitchen]);
 await actOwner(ownerA);a=(await sql("select public.create_establishment('Loja A','tenant-a') id"))[0].id;
 menuA=(await sql("select id from public.menus where tenant_id=$1",[a]))[0].id;
 categoryA=(await sql("insert into public.categories(tenant_id,menu_id,name) values($1,$2,'Pizzas') returning id",[a,menuA]))[0].id;
 productA=(await sql("insert into public.products(tenant_id,category_id,name,price,stock) values($1,$2,'Pizza',2500,10) returning id",[a,categoryA]))[0].id;
 addonA=(await sql("insert into public.addons(tenant_id,product_id,name,price) values($1,$2,'Extra',500) returning id",[a,productA]))[0].id;
 tableToken=(await sql("insert into public.dining_tables(tenant_id,name) values($1,'Mesa 1') returning token",[a]))[0].token;
 coupon=(await sql("insert into public.coupons(tenant_id,code,percent,max_uses) values($1,'TESTE10',10,1) returning id",[a]))[0].id;
 await sql("update public.establishments set published=true where id=$1",[a]);
 await sql("select public.set_staff($1,'kitchen@example.com','kitchen')",[a]);
 await actOwner(ownerB);b=(await sql("select public.create_establishment('Loja B','tenant-b') id"))[0].id;
 const menuB=(await sql("select id from public.menus where tenant_id=$1",[b]))[0].id;
 const categoryB=(await sql("insert into public.categories(tenant_id,menu_id,name) values($1,$2,'Pratos') returning id",[b,menuB]))[0].id;
 productB=(await sql("insert into public.products(tenant_id,category_id,name,price,stock) values($1,$2,'Prato',1000,10) returning id",[b,categoryB]))[0].id;
},30000);
afterAll(async()=>{await pg.close()});
describe("PostgreSQL: isolamento e regras de negócio",()=>{
 it("bloqueia acesso de outro tenant e FKs cruzadas",async()=>{
  await actOwner(ownerB);expect(await sql("select * from public.products where tenant_id=$1",[a])).toEqual([]);
  await expect(sql("insert into public.products(tenant_id,category_id,name,price) values($1,$2,'Invasão',100)",[b,categoryA])).rejects.toThrow();
  expect(await sql("update public.products set stock=0 where id=$1 returning id",[productA])).toEqual([]);
 });
 it("publica somente dados seguros e cardápios publicados",async()=>{
  await actor("anon");const result=(await sql("select public.public_menu('tenant-a') result"))[0].result;
  expect(result.categories[0].products[0].price).toBe(2500);expect(result.categories[0].products[0]).not.toHaveProperty("stock");
  expect((await sql("select public.public_menu('tenant-b') result"))[0].result).toBeNull();
  await expect(sql("select * from public.orders")).rejects.toThrow();
 });
 it("protege papéis e contadores do cupom de alterações diretas",async()=>{
  await actOwner(ownerA);
  await expect(sql("update public.coupons set uses=99 where id=$1",[coupon])).rejects.toThrow();
  await expect(sql("insert into public.platform_admins values($1)",[ownerA])).rejects.toThrow();
  await expect(sql("select public.set_staff($1,'kitchen@example.com','owner')",[a])).rejects.toThrow();
  await actor("authenticated",kitchen);
  await expect(sql("select public.staff_list($1)",[a]).then(r=>{if(!r.length)throw new Error("Bloqueado")})).rejects.toThrow();
 });
 it("exige token válido para mesa e bloqueia cardápio fechado",async()=>{
  await expect(place({mode:"mesa",token:randomUUID()})).rejects.toThrow("Mesa inválida");
  await actOwner(ownerA);await sql("update public.establishments set accepting_orders=false where id=$1",[a]);
  await expect(place()).rejects.toThrow("Estabelecimento fechado");
  await actOwner(ownerA);await sql("update public.establishments set accepting_orders=true where id=$1",[a]);
 });
 it("impede chamada de checkout diretamente por usuários autenticados",async()=>{
  await actOwner(ownerA);
  await expect(sql("select public.place_order('tenant-a',$1,'retirada','Cliente','14999999999',null,null,null,null,'pix','[]')",[randomUUID()])).rejects.toThrow();
 });
 it("rejeita produtos de outro tenant sem efeito parcial",async()=>{
  await expect(place({product:productB})).rejects.toThrow("Produto indisponível");
  await actOwner(ownerA);expect(await sql("select * from public.orders")).toHaveLength(0);
 });
 it("recalcula preço, adicional, desconto e estoque em transação",async()=>{
  const r=await place({request,qty:2,coupon:"TESTE10",mode:"mesa",token:tableToken});order=r.id;expect(r.total).toBe(5400);
  await actOwner(ownerA);expect((await sql("select stock from public.products where id=$1",[productA]))[0].stock).toBe(8);
  expect((await sql("select uses from public.coupons where id=$1",[coupon]))[0].uses).toBe(1);
 });
 it("repete pedido sem nova baixa; cupom esgotado e falta de estoque revertem",async()=>{
  expect((await place({request,qty:2,coupon:"TESTE10",mode:"mesa",token:tableToken})).id).toBe(order);
  await expect(place({coupon:"TESTE10"})).rejects.toThrow("Cupom inválido");
  await expect(place({qty:50})).rejects.toThrow("Produto indisponível");
  await actOwner(ownerA);expect((await sql("select stock from public.products where id=$1",[productA]))[0].stock).toBe(8);
  expect(await sql("select * from public.orders")).toHaveLength(1);
 });
 it("restringe papel cozinha e estorna cancelamento uma única vez",async()=>{
  await actor("authenticated",kitchen);
  expect(await sql("select * from public.orders")).toHaveLength(0);
  await expect(sql("select public.transition_order($1,$2,'cancelado')",[a,order])).rejects.toThrow();
  await expect(sql("update public.products set stock=0 where id=$1 returning id",[productA]).then(r=>{if(!r.length)throw new Error("Bloqueado")})).rejects.toThrow();
  await actOwner(ownerA);await sql("select public.transition_order($1,$2,'cancelado')",[a,order]);await sql("select public.transition_order($1,$2,'cancelado')",[a,order]);
  expect((await sql("select stock from public.products where id=$1",[productA]))[0].stock).toBe(10);
  expect((await sql("select uses from public.coupons where id=$1",[coupon]))[0].uses).toBe(0);
 });
 it("conclui pedido e credita pontos apenas uma vez",async()=>{
  const r=await place();await actOwner(ownerA);await sql("select public.transition_order($1,$2,'confirmado')",[a,r.id]);
  await actor("authenticated",kitchen);
  const queue=(await sql("select public.kitchen_queue($1) q",[a]))[0].q;
  expect(queue[0].order_items[0].name).toBe("Pizza");expect(queue[0]).not.toHaveProperty("phone");
  expect((await sql("select public.kitchen_queue($1) q",[b]))[0].q).toBeNull();
  await sql("select public.transition_order($1,$2,'preparando')",[a,r.id]);await sql("select public.transition_order($1,$2,'pronto')",[a,r.id]);
  await actOwner(ownerA);for(const status of ["concluido","concluido"])await sql("select public.transition_order($1,$2,$3)",[a,r.id,status]);
  expect((await sql("select points from public.loyalty_accounts where tenant_id=$1",[a]))[0].points).toBe(30);
  expect((await sql("select public.metrics($1) m",[a]))[0].m.revenue).toBe(3000);
 });
 it("webhook deduplica e não pode ser chamado pelo usuário",async()=>{
  await actOwner(ownerA);
  const attempt=(await sql("select public.reserve_checkout($1,'pro') result",[a]))[0].result;
  expect((await sql("select public.reserve_checkout($1,'pro') result",[a]))[0].result.attempt).toBe(attempt.attempt);
  await expect(sql("select public.reserve_checkout($1,'essencial')",[a])).rejects.toThrow("Checkout em andamento");
  await expect(sql("select public.apply_subscription_event('evt_1',$1,'pro','active','cus','sub')",[a])).rejects.toThrow();
  await actor("service_role");expect((await sql("select public.apply_subscription_event('evt_1',$1,'pro','active','cus','sub') ok",[a]))[0].ok).toBe(true);
  expect((await sql("select public.apply_subscription_event('evt_1',$1,'pro','canceled','cus','sub') ok",[a]))[0].ok).toBe(false);
  await actOwner(ownerA);expect((await sql("select status from public.subscriptions where tenant_id=$1",[a]))[0].status).toBe("active");
 });
 it("anonimiza cliente sem apagar faturamento",async()=>{
  await actOwner(ownerA);expect((await sql("select public.anonymize_customer($1,'14999999999') n",[a]))[0].n).toBe(2);
  expect((await sql("select phone from public.orders where tenant_id=$1 limit 1",[a]))[0].phone).toBe("anonimizado");
  expect(await sql("select * from public.loyalty_accounts where tenant_id=$1",[a])).toHaveLength(0);
 });
 it("isola chamados e permite resolução somente ao Super Admin",async()=>{
  await actOwner(ownerA);
  const id=(await sql("insert into public.support_tickets(tenant_id,subject,message) values($1,'Dúvida','Como alterar meu cardápio?') returning id",[a]))[0].id;
  expect(await sql("update public.support_tickets set status='resolvido' where id=$1 returning id",[id])).toEqual([]);
  await actOwner(ownerB);expect(await sql("select * from public.support_tickets where tenant_id=$1",[a])).toHaveLength(0);
  await pg.exec("reset role");await sql("insert into public.platform_admins values($1)",[ownerB]);
  await actOwner(ownerB);expect((await sql("update public.support_tickets set status='resolvido' where id=$1 returning status",[id]))[0].status).toBe("resolvido");
 });
 it("publica somente as formas de pagamento e perfil escolhidos pelo proprietário",async()=>{
  await actOwner(ownerA);
  expect((await sql("select payment_methods from public.establishments where id=$1",[a]))[0].payment_methods).toEqual(["pix","cartao_credito","cartao_debito","dinheiro"]);
  await actOwner(ownerB);expect(await sql("update public.establishments set payment_methods=array['pix'] where id=$1 returning id",[a])).toEqual([]);
  await actor("authenticated",kitchen);expect(await sql("update public.establishments set payment_methods=array['pix'] where id=$1 returning id",[a])).toEqual([]);
  await actOwner(ownerA);
  for(const invalid of ["array[]::text[]","array['pix','pix']","array['boleto']","array['pix',null]"])await expect(sql("update public.establishments set payment_methods="+invalid+" where id=$1",[a])).rejects.toThrow();
  await sql("update public.establishments set payment_methods=array['pix','cartao_credito','vale_refeicao'],description='Pizza artesanal',opening_hours='18h às 23h' where id=$1",[a]);
  await actor("anon");const profile=(await sql("select public.public_menu('tenant-a') result"))[0].result;
  expect(profile).toMatchObject({payment_methods:["pix","cartao_credito","vale_refeicao"],description:"Pizza artesanal",opening_hours:"18h às 23h"});
 });
 it("rejeita pagamentos desativados antes de alterar estoque e aceita os habilitados",async()=>{
  await actOwner(ownerA);const before=(await sql("select stock from public.products where id=$1",[productA]))[0].stock;
  for(const payment of ["dinheiro","cartao_debito","cartao"])await expect(place({payment})).rejects.toThrow("Forma de pagamento indisponível");
  await actOwner(ownerA);expect((await sql("select stock from public.products where id=$1",[productA]))[0].stock).toBe(before);
  const result=await place({payment:"vale_refeicao"});
  await actOwner(ownerA);expect((await sql("select payment_method from public.orders where id=$1",[result.id]))[0].payment_method).toBe("vale_refeicao");
 });
 it("inclui tudo no teste, consulta nível apenas dentro do tenant e bloqueia RPC anônimo",async()=>{
  await actOwner(ownerB);expect((await sql("select public.tenant_plan_level($1) n",[b]))[0].n).toBe(3);expect((await sql("select public.tenant_plan_level($1) n",[a]))[0].n).toBeNull();
  await actor("anon");await expect(sql("select public.tenant_plan_level($1)",[a])).rejects.toThrow();
  await actOwner(ownerA);expect((await sql("select public.tenant_plan_level($1) n",[a]))[0].n).toBe(2);
  await actor("authenticated",kitchen);expect((await sql("select public.tenant_plan_level($1) n",[a]))[0].n).toBe(2);
 });
 it("aplica downgrade Essencial sem apagar dados nem permitir contornar as restrições",async()=>{
  await actor("service_role");await sql("select public.apply_subscription_event('evt_essencial',$1,'essencial','active','cus','sub',1)",[a]);
  await actOwner(ownerA);expect((await sql("select public.tenant_plan_level($1) n",[a]))[0].n).toBe(1);
  expect((await sql("select id from public.dining_tables where tenant_id=$1",[a])).length).toBeGreaterThan(0);
  await expect(sql("insert into public.dining_tables(tenant_id,name) values($1,'Mesa bloqueada')",[a])).rejects.toThrow();
  await expect(sql("insert into public.coupons(tenant_id,code,percent) values($1,'BLOQUEADO',10)",[a])).rejects.toThrow();
  await expect(sql("select public.set_staff($1,'kitchen@example.com','attendant')",[a])).rejects.toThrow("Gestão de equipe indisponível");
  await expect(place({mode:"mesa",token:tableToken})).rejects.toThrow("Pedido na mesa indisponível");
  await expect(place({coupon:"TESTE10"})).rejects.toThrow("Cupons indisponíveis");
  await actor("authenticated",kitchen);expect((await sql("select public.kitchen_queue($1) q",[a]))[0].q).toBeNull();await expect(sql("select public.transition_order($1,$2,'preparando')",[a,order])).rejects.toThrow("Cozinha indisponível");
  await actor("anon");expect((await sql("select public.public_menu('tenant-a') result"))[0].result).toMatchObject({table_enabled:false,coupons_enabled:false});
  await actOwner(ownerA);await sql("select public.remove_staff($1,$2)",[a,kitchen]);expect((await sql("select public.staff_list($1) u",[a])).length).toBe(1);
 });
 it("libera módulos novamente após upgrade sem perder configurações",async()=>{
  await actor("service_role");await sql("select public.apply_subscription_event('evt_premium',$1,'premium','active','cus','sub',2)",[a]);
  await actOwner(ownerA);expect((await sql("select public.tenant_plan_level($1) n",[a]))[0].n).toBe(3);expect((await sql("insert into public.dining_tables(tenant_id,name) values($1,'Mesa nova') returning id",[a])).length).toBe(1);
  await actor("anon");expect((await sql("select public.public_menu('tenant-a') result"))[0].result).toMatchObject({table_enabled:true,coupons_enabled:true});
 });
 let posOrder:string,cashId:string,deliveryOrder:string;
 const pdv=async (req:string,product:string,mode="retirada",payment="dinheiro")=>(await sql("select public.pdv_order($1,$2,$3,'Cliente PDV','14988888888','Rua do teste, 123',null,null,$4,$5::jsonb) result",[a,req,mode,payment,JSON.stringify([{product_id:product,quantity:1,addons:[]}])]))[0].result;
 const movement=(action:string,session:string|null,orderId:string|null,amount:number|null,note="",req=randomUUID())=>sql("select public.cash_action($1,$2,$3,$4,$5,$6,$7)",[a,action,req,session,orderId,amount,note]);
 it("PDV vende mesmo com cardápio fechado, recalcula e baixa estoque uma vez",async()=>{
  await actOwner(ownerA);await sql("update public.establishments set published=false,accepting_orders=false,payment_methods=array['pix','dinheiro'] where id=$1",[a]);
  const before=(await sql("select stock from public.products where id=$1",[productA]))[0].stock,req=randomUUID();
  const r=await pdv(req,productA);posOrder=r.id;expect(r.total).toBe(2500);
  expect((await pdv(req,productA)).id).toBe(posOrder);
  expect((await sql("select stock from public.products where id=$1",[productA]))[0].stock).toBe(before-1);
  expect((await sql("select source,status from public.orders where id=$1",[posOrder]))[0]).toMatchObject({source:"pdv",status:"confirmado"});
  await expect(pdv(randomUUID(),productB)).rejects.toThrow("Produto indisponível");
  await expect(pdv(randomUUID(),productA,"retirada","cartao_credito")).rejects.toThrow("Dados inválidos");
  await actOwner(ownerB);await expect(pdv(randomUUID(),productA)).rejects.toThrow("Sem permissão");
  await actor("anon");await expect(pdv(randomUUID(),productA)).rejects.toThrow();
 });
 it("caixa abre uma sessão, registra pagamento e bloqueia duplicidade",async()=>{
  await actOwner(ownerA);await movement("abrir",null,null,10000);cashId=(await sql("select id from public.cash_sessions where tenant_id=$1 and closed_at is null",[a]))[0].id;
  await expect(movement("abrir",null,null,10000)).rejects.toThrow();
  const req=randomUUID();await movement("venda",cashId,posOrder,null,"",req);await movement("venda",cashId,posOrder,null,"",req);
  await expect(movement("venda",cashId,posOrder,null)).rejects.toThrow();
  const balance=(await sql("select public.cash_summary($1,$2) result",[a,cashId]))[0].result;
  expect(balance).toMatchObject({balance:12500,receipts:2500});
  await expect(sql("update public.cash_entries set amount=1 where order_id=$1",[posOrder])).rejects.toThrow();
  await actOwner(ownerB);expect(await sql("select * from public.cash_sessions where tenant_id=$1",[a])).toEqual([]);
  await expect(movement("venda",cashId,posOrder,null)).rejects.toThrow("Sem permissão");
 });
 it("estorna antes de cancelar, controla sangria e guarda diferença de fechamento",async()=>{
  await actOwner(ownerA);
  await expect(sql("select public.transition_order($1,$2,'cancelado')",[a,posOrder])).rejects.toThrow("Registre o estorno");
  await movement("estorno",cashId,posOrder,null,"Venda devolvida");
  await sql("select public.transition_order($1,$2,'cancelado')",[a,posOrder]);
  await movement("suprimento",cashId,null,1000,"Troco");
  await expect(movement("sangria",cashId,null,50000,"Retirada")).rejects.toThrow();
  await movement("sangria",cashId,null,2000,"Retirada");
  await movement("fechar",cashId,null,8900);
  expect((await sql("select expected_amount::int,counted_amount from public.cash_sessions where id=$1",[cashId]))[0]).toMatchObject({expected_amount:9000,counted_amount:8900});
  await expect(movement("suprimento",cashId,null,1000,"Troco")).rejects.toThrow();
 });
 it("atribui entregador próprio e impede vínculos cruzados",async()=>{
  await actOwner(ownerA);deliveryOrder=(await pdv(randomUUID(),productA,"delivery","pix")).id;
  const courierA=(await sql("insert into public.couriers(tenant_id,name,phone) values($1,'Entregador A','14999999999') returning id",[a]))[0].id;
  await actOwner(ownerB);const courierB=(await sql("insert into public.couriers(tenant_id,name) values($1,'Entregador B') returning id",[b]))[0].id;
  await actOwner(ownerA);await expect(sql("select public.assign_courier($1,$2,$3)",[a,deliveryOrder,courierB])).rejects.toThrow("Entregador inválido");
  await sql("select public.assign_courier($1,$2,$3)",[a,deliveryOrder,courierA]);expect((await sql("select courier_id from public.orders where id=$1",[deliveryOrder]))[0].courier_id).toBe(courierA);
  expect((await sql("select * from public.customer_history($1)",[a])).some(c=>c.phone==="14988888888")).toBe(true);
  await actOwner(ownerB);expect(await sql("select * from public.customer_history($1)",[a])).toEqual([]);
 });
 it("protege PDV, caixa e despacho no Essencial",async()=>{
  await actor("service_role");await sql("select public.apply_subscription_event('evt_essencial_ops',$1,'essencial','active','cus','sub',3)",[a]);
  await actOwner(ownerA);await expect(pdv(randomUUID(),productA)).rejects.toThrow("Sem permissão");await expect(movement("abrir",null,null,0)).rejects.toThrow("Sem permissão");
  await expect(sql("select public.assign_courier($1,$2,null)",[a,deliveryOrder])).rejects.toThrow("Sem permissão");
 });
});
