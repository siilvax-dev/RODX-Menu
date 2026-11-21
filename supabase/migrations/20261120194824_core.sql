create extension if not exists pgcrypto;
create type public.staff_role as enum ('owner','manager','kitchen','attendant');
create type public.order_status as enum ('pendente','confirmado','preparando','pronto','em_entrega','concluido','cancelado');
create type public.order_mode as enum ('delivery','retirada','mesa');

create table public.establishments (
 id uuid primary key default gen_random_uuid(), name text not null check(char_length(name) between 2 and 100),
 slug text unique not null check(slug ~ '^[a-z0-9][a-z0-9-]{2,49}$'),
 whatsapp text check(whatsapp is null or whatsapp ~ '^55[0-9]{10,11}$'),
 published boolean not null default false, accepting_orders boolean not null default true,
 delivery_enabled boolean not null default true, pickup_enabled boolean not null default true,
 delivery_fee integer not null default 0 check(delivery_fee between 0 and 100000),
 address text, created_at timestamptz not null default now()
);
create table public.memberships (
 tenant_id uuid references public.establishments(id) on delete cascade, user_id uuid references auth.users(id) on delete cascade,
 role public.staff_role not null, created_at timestamptz not null default now(), primary key(tenant_id,user_id)
);
create table public.platform_admins (user_id uuid primary key references auth.users(id) on delete cascade);
create table public.menus (
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references public.establishments(id) on delete cascade,
 name text not null check(length(name) between 1 and 100), active boolean not null default true,
 unique(tenant_id,id)
);
create table public.categories (
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references public.establishments(id) on delete cascade,
 menu_id uuid not null, name text not null check(length(name) between 1 and 100), sort_order integer not null default 0,
 active boolean not null default true, unique(tenant_id,id),
 foreign key(tenant_id,menu_id) references public.menus(tenant_id,id)
);
create table public.products (
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references public.establishments(id) on delete cascade,
 category_id uuid not null, name text not null check(length(name) between 1 and 120), description text not null default '',
 price integer not null check(price between 0 and 10000000), stock integer check(stock >= 0),
 active boolean not null default true, image_url text check(image_url is null or image_url ~ '^https://'),
 unique(tenant_id,id), foreign key(tenant_id,category_id) references public.categories(tenant_id,id)
);
create table public.addons (
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references public.establishments(id) on delete cascade,
 product_id uuid not null, name text not null check(length(name) between 1 and 100),
 price integer not null check(price between 0 and 10000000), active boolean not null default true,
 unique(tenant_id,id), foreign key(tenant_id,product_id) references public.products(tenant_id,id)
);
create table public.dining_tables (
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references public.establishments(id) on delete cascade,
 name text not null check(length(name) between 1 and 80), token uuid not null unique default gen_random_uuid(),
 active boolean not null default true, unique(tenant_id,id)
);
create table public.coupons (
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references public.establishments(id) on delete cascade,
 code text not null check(code ~ '^[A-Z0-9-]{2,24}$'), percent integer not null check(percent between 1 and 100),
 active boolean not null default true, expires_at timestamptz, max_uses integer check(max_uses > 0),
 uses integer not null default 0 check(uses >= 0), unique(tenant_id,code), unique(tenant_id,id)
);
create table public.orders (
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references public.establishments(id) on delete cascade,
 request_id uuid not null, number bigint generated always as identity,
 status public.order_status not null default 'pendente', mode public.order_mode not null,
 customer_name text not null, phone text not null, address text, notes text, table_id uuid,
 coupon_id uuid, subtotal integer not null check(subtotal >= 0), discount integer not null check(discount >= 0),
 delivery_fee integer not null check(delivery_fee >= 0), total integer not null check(total = subtotal-discount+delivery_fee and total >= 0),
 payment_method text not null check(payment_method in ('pix','dinheiro','cartao')), created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(), unique(tenant_id,id), unique(tenant_id,request_id),
 foreign key(tenant_id,table_id) references public.dining_tables(tenant_id,id),
 foreign key(tenant_id,coupon_id) references public.coupons(tenant_id,id)
);
create table public.order_items (
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references public.establishments(id) on delete cascade,
 order_id uuid not null, product_id uuid not null, name text not null, price integer not null check(price >= 0),
 quantity integer not null check(quantity between 1 and 50), stock_reserved boolean not null default false, unique(tenant_id,id),
 foreign key(tenant_id,order_id) references public.orders(tenant_id,id),
 foreign key(tenant_id,product_id) references public.products(tenant_id,id)
);
create table public.order_item_addons (
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references public.establishments(id) on delete cascade,
 item_id uuid not null, addon_id uuid not null, name text not null, price integer not null check(price >= 0),
 foreign key(tenant_id,item_id) references public.order_items(tenant_id,id),
 foreign key(tenant_id,addon_id) references public.addons(tenant_id,id)
);
create table public.order_events (
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references public.establishments(id) on delete cascade,
 order_id uuid not null, status public.order_status not null, user_id uuid references auth.users(id) on delete set null,
 created_at timestamptz not null default now(), foreign key(tenant_id,order_id) references public.orders(tenant_id,id)
);
create table public.loyalty_accounts (
 tenant_id uuid references public.establishments(id) on delete cascade, phone text not null,
 points integer not null default 0 check(points >= 0), primary key(tenant_id,phone)
);
create table public.subscriptions (
 tenant_id uuid primary key references public.establishments(id) on delete cascade,
 plan text not null default 'teste' check(plan in ('teste','essencial','pro','premium')),
 status text not null default 'trialing', trial_ends_at timestamptz not null default now()+interval '14 days',
 stripe_customer text, stripe_subscription text unique, stripe_event_created bigint not null default 0,
 checkout_attempt uuid, checkout_plan text, checkout_expires_at timestamptz,
 updated_at timestamptz not null default now()
);
create table public.webhook_events (id text primary key, created_at timestamptz not null default now());
create table public.support_tickets (
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references public.establishments(id) on delete cascade,
 subject text not null check(length(subject) between 3 and 150), message text not null check(length(message) between 3 and 3000),
 status text not null default 'aberto' check(status in ('aberto','resolvido')), created_at timestamptz not null default now()
);
create table public.notifications (
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references public.establishments(id) on delete cascade,
 message text not null, created_at timestamptz not null default now()
);
create index memberships_user on public.memberships(user_id);
create index orders_tenant_created on public.orders(tenant_id,created_at desc);
create index orders_phone on public.orders(tenant_id,phone,created_at);
create index order_items_order on public.order_items(tenant_id,order_id);
create index addons_product on public.addons(tenant_id,product_id);

create function public.is_platform_admin() returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.platform_admins where user_id=auth.uid());
$$;
create function public.has_role(t uuid, roles public.staff_role[]) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.memberships where tenant_id=t and user_id=auth.uid() and role=any(roles));
$$;
create function public.is_member(t uuid) returns boolean language sql stable security definer set search_path='' as $$
 select public.has_role(t,array['owner','manager','kitchen','attendant']::public.staff_role[]);
$$;
revoke all on function public.is_platform_admin(),public.has_role(uuid,public.staff_role[]),public.is_member(uuid) from public,anon,authenticated;
grant execute on function public.is_platform_admin(),public.has_role(uuid,public.staff_role[]),public.is_member(uuid) to authenticated;

do $$
declare tab text;
begin
 foreach tab in array array['establishments','memberships','platform_admins','menus','categories','products','addons','dining_tables','coupons','orders','order_items','order_item_addons','order_events','loyalty_accounts','subscriptions','webhook_events','support_tickets','notifications']
 loop
  execute format('alter table public.%I enable row level security',tab);
  execute format('revoke all on public.%I from anon, authenticated',tab);
 end loop;
 foreach tab in array array['menus','categories','products','addons','dining_tables','coupons']
 loop
  execute format('grant select,insert,update on public.%I to authenticated',tab);
  execute format('create policy read_tenant on public.%I for select to authenticated using (public.is_member(tenant_id) or public.is_platform_admin())',tab);
  execute format('create policy insert_tenant on public.%I for insert to authenticated with check (public.has_role(tenant_id,array[''owner'',''manager'']::public.staff_role[]))',tab);
  execute format('create policy update_tenant on public.%I for update to authenticated using (public.has_role(tenant_id,array[''owner'',''manager'']::public.staff_role[])) with check (public.has_role(tenant_id,array[''owner'',''manager'']::public.staff_role[]))',tab);
 end loop;
 foreach tab in array array['orders','order_items','order_item_addons','order_events','notifications']
 loop
  execute format('grant select on public.%I to authenticated',tab);
  execute format('create policy read_tenant on public.%I for select to authenticated using (public.is_member(tenant_id) or public.is_platform_admin())',tab);
 end loop;
 foreach tab in array array['loyalty_accounts','support_tickets','subscriptions']
 loop
  execute format('grant select on public.%I to authenticated',tab);
  execute format('create policy read_tenant on public.%I for select to authenticated using (public.has_role(tenant_id,array[''owner'',''manager'']::public.staff_role[]) or public.is_platform_admin())',tab);
 end loop;
end $$;
-- Protect immutable identity and server-controlled counters using column privileges.
do $$
declare tab text;
begin
 foreach tab in array array['menus','categories','products','addons','dining_tables','coupons'] loop
  execute format('revoke update on public.%I from authenticated',tab);
 end loop;
end $$;
grant update(name,active) on public.menus to authenticated;
grant update(menu_id,name,active,sort_order) on public.categories to authenticated;
grant update(category_id,name,description,price,stock,active,image_url) on public.products to authenticated;
grant update(product_id,name,price,active) on public.addons to authenticated;
grant update(name,active) on public.dining_tables to authenticated;
grant update(code,percent,active,expires_at,max_uses) on public.coupons to authenticated;
revoke insert on public.coupons from authenticated;
grant insert(tenant_id,code,percent,active,expires_at,max_uses) on public.coupons to authenticated;
grant select,update(name,whatsapp,published,accepting_orders,delivery_enabled,pickup_enabled,delivery_fee,address) on public.establishments to authenticated;
create policy read_establishment on public.establishments for select to authenticated using(public.is_member(id) or public.is_platform_admin());
create policy update_establishment on public.establishments for update to authenticated using(public.has_role(id,array['owner']::public.staff_role[])) with check(public.has_role(id,array['owner']::public.staff_role[]));
grant select on public.memberships to authenticated;
create policy read_memberships on public.memberships for select to authenticated using(user_id=auth.uid() or public.has_role(tenant_id,array['owner']::public.staff_role[]) or public.is_platform_admin());
grant insert(tenant_id,subject,message) on public.support_tickets to authenticated;
create policy create_ticket on public.support_tickets for insert to authenticated with check(public.has_role(tenant_id,array['owner','manager']::public.staff_role[]));
grant update(status) on public.support_tickets to authenticated;
create policy resolve_ticket on public.support_tickets for update to authenticated using(public.is_platform_admin()) with check(public.is_platform_admin());

create function public.create_establishment(p_name text,p_slug text) returns uuid language plpgsql security definer set search_path='' as $$
declare t uuid;
begin
 if auth.uid() is null then raise exception 'Autenticação necessária'; end if;
 if (select count(*) from public.memberships where user_id=auth.uid() and role='owner')>=5 then raise exception 'Limite de estabelecimentos'; end if;
 insert into public.establishments(name,slug) values(trim(p_name),lower(trim(p_slug))) returning id into t;
 insert into public.memberships values(t,auth.uid(),'owner',now());
 insert into public.menus(tenant_id,name) values(t,'Cardápio principal');
 insert into public.subscriptions(tenant_id) values(t);
 return t;
end $$;
create function public.set_staff(t uuid,p_email text,p_role public.staff_role) returns void language plpgsql security definer set search_path='' as $$
declare u uuid;
begin
 if not public.has_role(t,array['owner']::public.staff_role[]) or p_role='owner' then raise exception 'Sem permissão'; end if;
 select id into u from auth.users where lower(email)=lower(trim(p_email)) and email_confirmed_at is not null;
 if u is null then raise exception 'Conta confirmada não encontrada'; end if;
 if exists(select 1 from public.memberships where tenant_id=t and user_id=u and role='owner') then raise exception 'Proprietário protegido'; end if;
 insert into public.memberships(tenant_id,user_id,role) values(t,u,p_role) on conflict(tenant_id,user_id) do update set role=excluded.role;
end $$;
create function public.remove_staff(t uuid,u uuid) returns void language plpgsql security definer set search_path='' as $$
begin
 if not public.has_role(t,array['owner']::public.staff_role[]) then raise exception 'Sem permissão'; end if;
 delete from public.memberships where tenant_id=t and user_id=u and role<>'owner';
end $$;
create function public.staff_list(t uuid) returns table(user_id uuid,email text,role public.staff_role) language sql security definer set search_path='' as $$
 select m.user_id,u.email::text,m.role from public.memberships m join auth.users u on u.id=m.user_id where m.tenant_id=t and public.has_role(t,array['owner']::public.staff_role[]);
$$;
revoke all on function public.create_establishment(text,text),public.set_staff(uuid,text,public.staff_role),public.remove_staff(uuid,uuid),public.staff_list(uuid) from public,anon,authenticated;
grant execute on function public.create_establishment(text,text),public.set_staff(uuid,text,public.staff_role),public.remove_staff(uuid,uuid),public.staff_list(uuid) to authenticated;

create function public.public_menu(p_slug text) returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('name',e.name,'slug',e.slug,'whatsapp',e.whatsapp,'address',e.address,
 'accepting_orders',e.accepting_orders and exists(select 1 from public.subscriptions s where s.tenant_id=e.id and (s.status='active' or (s.status='trialing' and s.trial_ends_at>now()))),
 'delivery_enabled',e.delivery_enabled,'pickup_enabled',e.pickup_enabled,'delivery_fee',e.delivery_fee,
 'categories',coalesce((select jsonb_agg(jsonb_build_object('id',c.id,'name',c.name,'products',
 coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'name',p.name,'description',p.description,'price',p.price,'image_url',p.image_url,
 'addons',coalesce((select jsonb_agg(jsonb_build_object('id',a.id,'name',a.name,'price',a.price) order by a.name) from public.addons a where a.tenant_id=e.id and a.product_id=p.id and a.active),'[]'::jsonb)) order by p.name)
 from public.products p where p.tenant_id=e.id and p.category_id=c.id and p.active and (p.stock is null or p.stock>0)),'[]'::jsonb)) order by c.sort_order,c.name)
 from public.categories c join public.menus m on m.tenant_id=c.tenant_id and m.id=c.menu_id where c.tenant_id=e.id and c.active and m.active),'[]'::jsonb))
 from public.establishments e where e.slug=p_slug and e.published;
$$;
revoke all on function public.public_menu(text) from public,anon,authenticated;
grant execute on function public.public_menu(text) to anon,authenticated;

-- Public checkout is callable only by the trusted server after request validation.
create function public.place_order(p_slug text,p_request uuid,p_mode public.order_mode,p_name text,p_phone text,p_address text,p_notes text,p_table uuid,p_coupon text,p_payment text,p_items jsonb)
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
 or p_payment not in ('pix','dinheiro','cartao') or p_payment is null then raise exception 'Dados inválidos'; end if;
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
revoke all on function public.place_order(text,uuid,public.order_mode,text,text,text,text,uuid,text,text,jsonb) from public,anon,authenticated;
grant execute on function public.place_order(text,uuid,public.order_mode,text,text,text,text,uuid,text,text,jsonb) to service_role;

create function public.transition_order(t uuid,p_id uuid,p_status public.order_status) returns void language plpgsql security definer set search_path='' as $$
declare o public.orders%rowtype; can_manage boolean; line record;
begin
 if not public.is_member(t) then raise exception 'Sem permissão'; end if;
 can_manage:=public.has_role(t,array['owner','manager','attendant']::public.staff_role[]);
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
 elsif p_status='concluido' then
  insert into public.loyalty_accounts(tenant_id,phone,points) values(t,o.phone,(o.subtotal-o.discount)/100)
  on conflict(tenant_id,phone) do update set points=public.loyalty_accounts.points+excluded.points;
 end if;
 update public.orders set status=p_status,updated_at=now() where id=o.id;
 insert into public.order_events(tenant_id,order_id,status,user_id) values(t,o.id,p_status,auth.uid());
end $$;
revoke all on function public.transition_order(uuid,uuid,public.order_status) from public,anon,authenticated;
grant execute on function public.transition_order(uuid,uuid,public.order_status) to authenticated;

create function public.apply_subscription_event(p_event text,t uuid,p_plan text,p_status text,p_customer text,p_subscription text,p_created bigint default 0) returns boolean language plpgsql security definer set search_path='' as $$
begin
 perform 1 from public.establishments where id=t for update;
 if not found then raise exception 'Tenant inválido'; end if;
 insert into public.webhook_events(id) values(p_event) on conflict do nothing;
 if not found then return false; end if;
 -- An older cancelled subscription must not overwrite a replacement.
 if p_status='canceled' and exists(select 1 from public.subscriptions where tenant_id=t and stripe_subscription is not null and stripe_subscription<>p_subscription) then return true; end if;
 update public.subscriptions set plan=p_plan,status=p_status,stripe_customer=p_customer,stripe_subscription=p_subscription,
 stripe_event_created=p_created,checkout_attempt=null,checkout_plan=null,checkout_expires_at=null,updated_at=now()
 where tenant_id=t and stripe_event_created<=p_created;
 return true;
end $$;
revoke all on function public.apply_subscription_event(text,uuid,text,text,text,text,bigint) from public,anon,authenticated;
grant execute on function public.apply_subscription_event(text,uuid,text,text,text,text,bigint) to service_role;

create function public.reserve_checkout(t uuid,p_plan text) returns jsonb language plpgsql security definer set search_path='' as $$
declare s public.subscriptions%rowtype;
begin
 if not public.has_role(t,array['owner']::public.staff_role[]) or p_plan not in ('essencial','pro','premium') then raise exception 'Sem permissão'; end if;
 select * into s from public.subscriptions where tenant_id=t for update;
 if s.stripe_subscription is not null and s.status<>'canceled' then raise exception 'Use o portal de cobrança'; end if;
 if s.checkout_expires_at>now() then
  if s.checkout_plan<>p_plan then raise exception 'Checkout em andamento';end if;
 else
  update public.subscriptions set checkout_attempt=gen_random_uuid(),checkout_plan=p_plan,checkout_expires_at=date_trunc('second',now())+interval '45 minutes' where tenant_id=t returning * into s;
 end if;
 return jsonb_build_object('attempt',s.checkout_attempt,'expires',extract(epoch from s.checkout_expires_at)::bigint,'customer',s.stripe_customer);
end $$;
revoke all on function public.reserve_checkout(uuid,text) from public,anon,authenticated;
grant execute on function public.reserve_checkout(uuid,text) to authenticated;

-- Used by Supabase Realtime; initial state is fetched via RLS.
alter publication supabase_realtime add table public.orders;
