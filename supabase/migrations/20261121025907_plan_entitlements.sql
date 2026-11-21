-- Plan entitlements: preserve all data and active trial access.
create schema if not exists rodx_private;
revoke all on schema rodx_private from public,anon,authenticated;
grant usage on schema rodx_private to authenticated;
-- Invoker: RLS remains in force when invoked from table policies.
create function rodx_private.plan_level(t uuid) returns integer language sql stable security invoker set search_path='' as $$
 select coalesce((select case
  when s.plan='teste' and s.status='trialing' and s.trial_ends_at>now() then 3
  when s.status in ('active','trialing') and s.plan='premium' then 3
  when s.status in ('active','trialing') and s.plan='pro' then 2
  else 1 end from public.subscriptions s where s.tenant_id=t),1);
$$;
revoke all on function rodx_private.plan_level(uuid) from public,anon,authenticated;
grant execute on function rodx_private.plan_level(uuid) to authenticated;
-- Return only the entitlement level, never billing identifiers, to verified members.
create function public.tenant_plan_level(t uuid) returns integer language sql stable security definer set search_path='' as $$
 select case when public.is_member(t) then rodx_private.plan_level(t) else null end;
$$;
revoke all on function public.tenant_plan_level(uuid) from public,anon,authenticated;
grant execute on function public.tenant_plan_level(uuid) to authenticated;
-- Restrictive policies AND the pre-existing tenant/role policies. Keep rows and historical orders readable.
create policy pro_insert on public.dining_tables as restrictive for insert to authenticated with check (rodx_private.plan_level(tenant_id)>=2);
create policy pro_update on public.dining_tables as restrictive for update to authenticated using (rodx_private.plan_level(tenant_id)>=2) with check (rodx_private.plan_level(tenant_id)>=2);
create policy pro_insert on public.coupons as restrictive for insert to authenticated with check (rodx_private.plan_level(tenant_id)>=2);
create policy pro_update on public.coupons as restrictive for update to authenticated using (rodx_private.plan_level(tenant_id)>=2) with check (rodx_private.plan_level(tenant_id)>=2);
create policy premium_read on public.loyalty_accounts as restrictive for select to authenticated using (rodx_private.plan_level(tenant_id)>=3 or public.is_platform_admin());

create or replace function public.public_menu(p_slug text) returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('name',e.name,'slug',e.slug,'whatsapp',e.whatsapp,'address',e.address,'description',e.description,'opening_hours',e.opening_hours,'payment_methods',e.payment_methods,'table_enabled',rodx_private.plan_level(e.id)>=2,'coupons_enabled',rodx_private.plan_level(e.id)>=2,
 'accepting_orders',e.accepting_orders and exists(select 1 from public.subscriptions s where s.tenant_id=e.id and (s.status='active' or (s.status='trialing' and s.trial_ends_at>now()))),
 'delivery_enabled',e.delivery_enabled,'pickup_enabled',e.pickup_enabled,'delivery_fee',e.delivery_fee,
 'categories',coalesce((select jsonb_agg(jsonb_build_object('id',c.id,'name',c.name,'products',
 coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'name',p.name,'description',p.description,'price',p.price,'image_url',p.image_url,
 'addons',coalesce((select jsonb_agg(jsonb_build_object('id',a.id,'name',a.name,'price',a.price) order by a.name) from public.addons a where a.tenant_id=e.id and a.product_id=p.id and a.active),'[]'::jsonb)) order by p.name)
 from public.products p where p.tenant_id=e.id and p.category_id=c.id and p.active and (p.stock is null or p.stock>0)),'[]'::jsonb)) order by c.sort_order,c.name)
 from public.categories c join public.menus m on m.tenant_id=c.tenant_id and m.id=c.menu_id where c.tenant_id=e.id and c.active and m.active),'[]'::jsonb))
 from public.establishments e where e.slug=p_slug and e.published;
$$;
create or replace function public.place_order(p_slug text,p_request uuid,p_mode public.order_mode,p_name text,p_phone text,p_address text,p_notes text,p_table uuid,p_coupon text,p_payment text,p_items jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare e public.establishments%rowtype; o public.orders%rowtype; p public.products%rowtype; a public.addons%rowtype;
 c public.coupons%rowtype; item jsonb; aid uuid; qty integer; itemid uuid; tbl uuid;
 v_subtotal bigint:=0; v_discount integer:=0; fee integer:=0; unit_price bigint;
begin
 select * into e from public.establishments where slug=p_slug and published for update;
 if not found then raise exception 'Cardápio indisponível'; end if;
 select * into o from public.orders where tenant_id=e.id and request_id=p_request;
 if found then return jsonb_build_object('id',o.id,'number',o.number,'total',o.total); end if;
 if not e.accepting_orders or not exists(select 1 from public.subscriptions s where s.tenant_id=e.id and (s.status='active' or(s.status='trialing' and s.trial_ends_at>now()))) then raise exception 'Estabelecimento fechado'; end if;
 if p_name is null or length(trim(p_name)) not between 2 and 100 or p_phone is null or p_phone !~ '^[0-9]{10,13}$'
 or length(coalesce(p_notes,''))>500 or length(coalesce(p_address,''))>400
 or p_payment not in ('pix','dinheiro','cartao','cartao_credito','cartao_debito','vale_refeicao') or p_payment is null then raise exception 'Dados inválidos'; end if;
 -- Compatibility for the old checkout: generic card is valid only when both card types are accepted.
 if not (p_payment=any(e.payment_methods) or (p_payment='cartao' and e.payment_methods @> array['cartao_credito','cartao_debito']::text[])) then raise exception 'Forma de pagamento indisponível'; end if;
 if p_mode='mesa' and rodx_private.plan_level(e.id)<2 then raise exception 'Pedido na mesa indisponível no plano atual';end if;
 if nullif(trim(p_coupon),'') is not null and rodx_private.plan_level(e.id)<2 then raise exception 'Cupons indisponíveis no plano atual';end if;
 if (select count(*) from public.orders where tenant_id=e.id and phone=p_phone and created_at>now()-interval '10 minutes')>=5 then raise exception 'Limite de pedidos atingido'; end if;
 if p_mode='delivery' then
  if not e.delivery_enabled or length(trim(coalesce(p_address,'')))<10 then raise exception 'Entrega indisponível ou endereço inválido'; end if;
  fee:=e.delivery_fee;
 elsif p_mode='retirada' then
  if not e.pickup_enabled then raise exception 'Retirada indisponível'; end if;
 elsif p_mode='mesa' then
  select id into tbl from public.dining_tables where tenant_id=e.id and token=p_table and active;
  if tbl is null then raise exception 'Mesa inválida'; end if;
 end if;
 if p_items is null or jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items) not between 1 and 30 then raise exception 'Carrinho inválido'; end if;
 insert into public.orders(tenant_id,request_id,mode,customer_name,phone,address,notes,table_id,subtotal,discount,delivery_fee,total,payment_method)
 values(e.id,p_request,p_mode,trim(p_name),p_phone,case when p_mode='delivery' then p_address end,p_notes,tbl,0,0,fee,fee,p_payment) returning * into o;
 for item in select value from jsonb_array_elements(p_items) loop
  qty:=(item->>'quantity')::integer;
  if qty not between 1 and 50 or qty is null then raise exception 'Quantidade inválida'; end if;
  select pr.* into p from public.products pr join public.categories ca on ca.tenant_id=pr.tenant_id and ca.id=pr.category_id join public.menus m on m.tenant_id=ca.tenant_id and m.id=ca.menu_id
   where pr.id=(item->>'product_id')::uuid and pr.tenant_id=e.id and pr.active and ca.active and m.active for update of pr;
  if not found or (p.stock is not null and p.stock<qty) then raise exception 'Produto indisponível'; end if;
  if p.stock is not null then update public.products set stock=stock-qty where id=p.id; end if;
  insert into public.order_items(tenant_id,order_id,product_id,name,price,quantity,stock_reserved) values(e.id,o.id,p.id,p.name,p.price,qty,p.stock is not null) returning id into itemid;
  unit_price:=p.price;
  if jsonb_array_length(coalesce(item->'addons','[]'::jsonb))>10 then raise exception 'Adicionais em excesso'; end if;
  for aid in select distinct value::uuid from jsonb_array_elements_text(coalesce(item->'addons','[]'::jsonb)) loop
   select * into a from public.addons where tenant_id=e.id and product_id=p.id and id=aid and active;
   if not found then raise exception 'Adicional indisponível'; end if;
   unit_price:=unit_price+a.price;
   insert into public.order_item_addons(tenant_id,item_id,addon_id,name,price) values(e.id,itemid,a.id,a.name,a.price);
  end loop;
  v_subtotal:=v_subtotal+unit_price*qty;
  if v_subtotal>100000000 then raise exception 'Pedido excede limite'; end if;
 end loop;
 if nullif(trim(p_coupon),'') is not null then
  select * into c from public.coupons where tenant_id=e.id and code=upper(trim(p_coupon)) and active and (expires_at is null or expires_at>now()) and (max_uses is null or uses<max_uses) for update;
  if not found then raise exception 'Cupom inválido ou expirado'; end if;
  v_discount:=floor(v_subtotal*c.percent/100.0);
  update public.coupons set uses=uses+1 where id=c.id;
 end if;
 update public.orders set subtotal=v_subtotal::integer,discount=v_discount, total=v_subtotal::integer-v_discount+fee,coupon_id=c.id
 where id=o.id;
 insert into public.order_events(tenant_id,order_id,status) values(e.id,o.id,'pendente');
 insert into public.notifications(tenant_id,message) values(e.id,'Novo pedido #'||o.number);
 return jsonb_build_object('id',o.id,'number',o.number,'total',v_subtotal-v_discount+fee);
end $$;
create or replace function public.set_staff(t uuid,p_email text,p_role public.staff_role) returns void language plpgsql security definer set search_path='' as $$
declare u uuid;
begin
 if not public.has_role(t,array['owner']::public.staff_role[]) or p_role='owner' then raise exception 'Sem permissão'; end if;
 if rodx_private.plan_level(t)<2 then raise exception 'Gestão de equipe indisponível no plano atual';end if;
 select id into u from auth.users where lower(email)=lower(trim(p_email)) and email_confirmed_at is not null;
 if u is null then raise exception 'Conta confirmada não encontrada'; end if;
 if exists(select 1 from public.memberships where tenant_id=t and user_id=u and role='owner') then raise exception 'Proprietário protegido'; end if;
 insert into public.memberships(tenant_id,user_id,role) values(t,u,p_role) on conflict(tenant_id,user_id) do update set role=excluded.role;
end $$;
create or replace function public.kitchen_queue(t uuid) returns jsonb language sql stable security definer set search_path='' as $$
 select case when public.is_member(t) and rodx_private.plan_level(t)>=2 then coalesce(jsonb_agg(j order by j->>'created_at'),'[]'::jsonb) else null end
 from (select jsonb_build_object('id',o.id,'number',o.number,'status',o.status,'mode',o.mode,
 'created_at',o.created_at,'notes',o.notes,'dining_tables',(select jsonb_build_object('name',d.name) from public.dining_tables d where d.tenant_id=t and d.id=o.table_id),
 'order_items',coalesce((select jsonb_agg(jsonb_build_object('name',i.name,'quantity',i.quantity,'order_item_addons',coalesce((select jsonb_agg(jsonb_build_object('name',a.name)) from public.order_item_addons a where a.tenant_id=t and a.item_id=i.id),'[]'::jsonb))) from public.order_items i where i.tenant_id=t and i.order_id=o.id),'[]'::jsonb)) j
 from public.orders o where o.tenant_id=t and o.status in ('confirmado','preparando','pronto') order by o.created_at limit 100) rows;
$$;
create or replace function public.transition_order(t uuid,p_id uuid,p_status public.order_status) returns void language plpgsql security definer set search_path='' as $$
declare o public.orders%rowtype; can_manage boolean; line record;
begin
 if not public.is_member(t) then raise exception 'Sem permissão'; end if;
 can_manage:=public.has_role(t,array['owner','manager','attendant']::public.staff_role[]);
 if not can_manage and rodx_private.plan_level(t)<2 then raise exception 'Cozinha indisponível no plano atual';end if;
 perform 1 from public.establishments where id=t for update;
 select * into o from public.orders where tenant_id=t and id=p_id for update;
 if not found then raise exception 'Pedido inexistente'; end if;
 if p_status=o.status then return; end if;
 if not ((o.status='pendente' and p_status='confirmado' and can_manage)
 or (o.status='confirmado' and p_status='preparando')
 or (o.status='preparando' and p_status='pronto')
 or (o.status='pronto' and p_status='em_entrega' and o.mode='delivery' and can_manage)
 or (o.status='pronto' and p_status='concluido' and o.mode<>'delivery' and can_manage)
 or (o.status='em_entrega' and p_status='concluido' and can_manage)
 or (p_status='cancelado' and o.status in ('pendente','confirmado','preparando','pronto') and public.has_role(t,array['owner','manager']::public.staff_role[]))) then raise exception 'Transição não permitida'; end if;
 if p_status='cancelado' then
  for line in select product_id,sum(quantity)::integer as qty from public.order_items where tenant_id=t and order_id=o.id and stock_reserved group by product_id loop
   update public.products set stock=stock+line.qty where tenant_id=t and id=line.product_id and stock is not null;
  end loop;
  update public.coupons set uses=greatest(0,uses-1) where tenant_id=t and id=o.coupon_id;
 elsif p_status='concluido' and rodx_private.plan_level(t)>=3 then
  insert into public.loyalty_accounts(tenant_id,phone,points) values(t,o.phone,(o.subtotal-o.discount)/100)
  on conflict(tenant_id,phone) do update set points=public.loyalty_accounts.points+excluded.points;
 end if;
 update public.orders set status=p_status,updated_at=now() where id=o.id;
 insert into public.order_events(tenant_id,order_id,status,user_id) values(t,o.id,p_status,auth.uid());
end $$;
-- CREATE OR REPLACE preserves original privileges. Explicitly reaffirm restricted checkout.
revoke all on function public.place_order(text,uuid,public.order_mode,text,text,text,text,uuid,text,text,jsonb) from public,anon,authenticated;
grant execute on function public.place_order(text,uuid,public.order_mode,text,text,text,text,uuid,text,text,jsonb) to service_role;
