-- Add public profile information and per-establishment assisted payment options.
-- Existing checkouts offered Pix, cash and generic card by default; preserve that behavior.
alter table public.establishments
 add column description text not null default '' check(char_length(description)<=500),
 add column opening_hours text not null default '' check(char_length(opening_hours)<=200),
 add column payment_methods text[] not null default array['pix','cartao_credito','cartao_debito','dinheiro']::text[],
 add constraint establishments_payment_methods_check check (
  array_ndims(payment_methods)=1 and cardinality(payment_methods) between 1 and 5
  and array_position(payment_methods,null) is null
  and payment_methods <@ array['pix','cartao_credito','cartao_debito','dinheiro','vale_refeicao']::text[]
  and cardinality(payment_methods) = (('pix'=any(payment_methods))::int + ('cartao_credito'=any(payment_methods))::int + ('cartao_debito'=any(payment_methods))::int + ('dinheiro'=any(payment_methods))::int + ('vale_refeicao'=any(payment_methods))::int)
 );
-- Keep RLS and its existing owner-only update policy. Grant only the new profile columns.
grant update(description,opening_hours,payment_methods) on public.establishments to authenticated;
-- Keep old orders readable and permit new, more precise choices.
alter table public.orders drop constraint orders_payment_method_check;
alter table public.orders add constraint orders_payment_method_check check(payment_method in ('pix','dinheiro','cartao','cartao_credito','cartao_debito','vale_refeicao'));

create or replace function public.public_menu(p_slug text) returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('name',e.name,'slug',e.slug,'whatsapp',e.whatsapp,'address',e.address,'description',e.description,'opening_hours',e.opening_hours,'payment_methods',e.payment_methods,
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

-- Preserve the existing explicit execution boundaries.
revoke all on function public.public_menu(text) from public,anon,authenticated;
grant execute on function public.public_menu(text) to anon,authenticated;
revoke all on function public.place_order(text,uuid,public.order_mode,text,text,text,text,uuid,text,text,jsonb) from public,anon,authenticated;
grant execute on function public.place_order(text,uuid,public.order_mode,text,text,text,text,uuid,text,text,jsonb) to service_role;
