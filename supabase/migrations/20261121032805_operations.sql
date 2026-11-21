-- PDV and cash management. All mutations run in a tenant-scoped transaction.
alter table public.orders add column source text not null default 'online' check(source in ('online','pdv'));
create table public.cash_sessions (
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references public.establishments(id) on delete cascade,
 opened_at timestamptz not null default now(), opened_by uuid references auth.users(id) on delete set null,
 opening_amount integer not null check(opening_amount between 0 and 100000000),
 closed_at timestamptz, closed_by uuid references auth.users(id) on delete set null,
 counted_amount integer check(counted_amount between 0 and 100000000), expected_amount bigint,
 unique(tenant_id,id), check((closed_at is null)=(counted_amount is null))
);
create unique index cash_one_open on public.cash_sessions(tenant_id) where closed_at is null;
create index cash_sessions_history on public.cash_sessions(tenant_id,opened_at desc);
create table public.cash_entries (
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references public.establishments(id) on delete cascade,
 session_id uuid not null, request_id uuid not null, order_id uuid, kind text not null check(kind in ('venda','estorno','suprimento','sangria')),
 amount integer not null check(amount between 1 and 100000000), method text not null check(method in ('pix','cartao','cartao_credito','cartao_debito','dinheiro','vale_refeicao')),
 note text not null default '' check(length(note)<=300), created_at timestamptz not null default now(), created_by uuid references auth.users(id) on delete set null,
 foreign key(tenant_id,session_id) references public.cash_sessions(tenant_id,id),
 foreign key(tenant_id,order_id) references public.orders(tenant_id,id),
 unique(tenant_id,request_id), check((kind in ('venda','estorno'))=(order_id is not null)),
 check(kind in ('venda','estorno') or method='dinheiro')
);
create unique index cash_order_kind on public.cash_entries(tenant_id,order_id,kind) where order_id is not null;
create index cash_entries_session on public.cash_entries(tenant_id,session_id,created_at desc);
alter table public.cash_sessions enable row level security;
alter table public.cash_entries enable row level security;
revoke all on public.cash_sessions,public.cash_entries from public,anon,authenticated;
grant select on public.cash_sessions,public.cash_entries to authenticated;
create policy cash_session_read on public.cash_sessions for select to authenticated using(public.has_role(tenant_id,array['owner','manager','attendant']::public.staff_role[]) and public.tenant_plan_level(tenant_id)>=2);
create policy cash_entry_read on public.cash_entries for select to authenticated using(public.has_role(tenant_id,array['owner','manager','attendant']::public.staff_role[]) and public.tenant_plan_level(tenant_id)>=2);

create function public.cash_action(t uuid,p_action text,p_request uuid,p_session uuid,p_order uuid,p_amount integer,p_note text)
returns void language plpgsql security definer set search_path='' as $$
declare s public.cash_sessions%rowtype; o public.orders%rowtype; sale public.cash_entries%rowtype; balance bigint;
begin
 if auth.uid() is null or not public.has_role(t,array['owner','manager','attendant']::public.staff_role[]) or rodx_private.plan_level(t)<2 then raise exception 'Sem permissão'; end if;
 if p_request is null or p_action not in ('abrir','fechar','suprimento','sangria','venda','estorno') or length(coalesce(p_note,''))>300 then raise exception 'Dados inválidos';end if;
 perform 1 from public.establishments where id=t for update;
 if exists(select 1 from public.cash_entries where tenant_id=t and request_id=p_request) then return;end if;
 select * into s from public.cash_sessions where tenant_id=t and closed_at is null for update;
 if p_action='abrir' then
  if s.id is not null or p_amount is null or p_amount not between 0 and 100000000 then raise exception 'Caixa já aberto ou valor inválido';end if;
  insert into public.cash_sessions(tenant_id,opened_by,opening_amount) values(t,auth.uid(),p_amount);
  return;
 end if;
 if s.id is null or p_session is distinct from s.id then raise exception 'Abra o caixa ou atualize a página';end if;
 select s.opening_amount+coalesce(sum(case when kind in ('venda','suprimento') then amount else -amount end) filter(where method='dinheiro'),0) into balance from public.cash_entries where tenant_id=t and session_id=s.id;
 if p_action='fechar' then
  if p_amount is null or p_amount not between 0 and 100000000 then raise exception 'Valor inválido';end if;
  update public.cash_sessions set closed_at=now(),closed_by=auth.uid(),counted_amount=p_amount,expected_amount=balance where id=s.id;return;
 elsif p_action in ('suprimento','sangria') then
  if p_amount is null or p_amount not between 1 and 100000000 or length(trim(coalesce(p_note,'')))<3 or (p_action='sangria' and p_amount>balance) then raise exception 'Valor ou justificativa inválidos';end if;
  insert into public.cash_entries(tenant_id,session_id,request_id,kind,amount,method,note,created_by) values(t,s.id,p_request,p_action,p_amount,'dinheiro',trim(p_note),auth.uid());return;
 end if;
 select * into o from public.orders where tenant_id=t and id=p_order for update;
 if not found then raise exception 'Pedido inválido';end if;
 if p_action='venda' then
  if o.status='cancelado' or o.total<=0 then raise exception 'Pagamento indisponível';end if;
  insert into public.cash_entries(tenant_id,session_id,request_id,order_id,kind,amount,method,created_by) values(t,s.id,p_request,o.id,'venda',o.total,o.payment_method,auth.uid());
 elsif p_action='estorno' then
  if not public.has_role(t,array['owner','manager']::public.staff_role[]) or length(trim(coalesce(p_note,'')))<3 then raise exception 'Estorno exige gerente e justificativa';end if;
  select * into sale from public.cash_entries where tenant_id=t and order_id=o.id and kind='venda';
  if not found or (sale.method='dinheiro' and sale.amount>balance) then raise exception 'Pagamento inexistente ou saldo insuficiente';end if;
  insert into public.cash_entries(tenant_id,session_id,request_id,order_id,kind,amount,method,note,created_by) values(t,s.id,p_request,o.id,'estorno',sale.amount,sale.method,trim(p_note),auth.uid());
 end if;
end $$;
revoke all on function public.cash_action(uuid,text,uuid,uuid,uuid,integer,text) from public,anon,authenticated;
grant execute on function public.cash_action(uuid,text,uuid,uuid,uuid,integer,text) to authenticated;

-- Preserve the ledger: a paid order needs a recorded refund before cancellation.
create function rodx_private.guard_paid_cancel() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if new.status='cancelado' and old.status<>'cancelado' and exists(select 1 from public.cash_entries where tenant_id=new.tenant_id and order_id=new.id and kind='venda') and not exists(select 1 from public.cash_entries where tenant_id=new.tenant_id and order_id=new.id and kind='estorno') then raise exception 'Registre o estorno no caixa antes de cancelar';end if;
 return new;
end $$;
revoke all on function rodx_private.guard_paid_cancel() from public,anon,authenticated;
create trigger guard_paid_cancel before update of status on public.orders for each row execute function rodx_private.guard_paid_cancel();

-- Authenticated POS: catalog, inventory and pricing are authoritative on the server.
-- In-person orders stay available when the public menu is unpublished or paused.
create function public.pdv_order(t uuid,p_request uuid,p_mode public.order_mode,p_name text,p_phone text,p_address text,p_notes text,p_table uuid,p_payment text,p_items jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare e public.establishments%rowtype; o public.orders%rowtype; p public.products%rowtype; a public.addons%rowtype;
 item jsonb; aid uuid; qty integer; itemid uuid; tbl uuid; v_subtotal bigint:=0; fee integer:=0; unit_price bigint;
begin
 if auth.uid() is null or not public.has_role(t,array['owner','manager','attendant']::public.staff_role[]) or rodx_private.plan_level(t)<2 then raise exception 'Sem permissão';end if;
 select * into e from public.establishments where id=t for update;
 if not found then raise exception 'Estabelecimento inválido';end if;
 select * into o from public.orders where tenant_id=t and request_id=p_request;
 if found then return jsonb_build_object('id',o.id,'number',o.number,'total',o.total);end if;
 if p_request is null or p_mode is null or p_name is null or length(trim(p_name)) not between 2 and 100 or p_phone !~ '^[0-9]{10,13}$' or p_phone is null or length(coalesce(p_notes,''))>500 or length(coalesce(p_address,''))>400 or p_payment is null or not (p_payment=any(e.payment_methods)) then raise exception 'Dados inválidos';end if;
 if p_mode='delivery' then
  if length(trim(coalesce(p_address,'')))<10 then raise exception 'Endereço inválido';end if;fee:=e.delivery_fee;
 elsif p_mode='mesa' then
  select id into tbl from public.dining_tables where tenant_id=t and id=p_table and active;
  if tbl is null then raise exception 'Mesa inválida';end if;
 end if;
 if p_items is null or jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items) not between 1 and 30 then raise exception 'Carrinho inválido';end if;
 insert into public.orders(tenant_id,request_id,source,status,mode,customer_name,phone,address,notes,table_id,subtotal,discount,delivery_fee,total,payment_method)
 values(t,p_request,'pdv','confirmado',p_mode,trim(p_name),p_phone,case when p_mode='delivery' then p_address end,p_notes,tbl,0,0,fee,fee,p_payment) returning * into o;
 for item in select value from jsonb_array_elements(p_items) loop
  qty:=(item->>'quantity')::integer;
  if qty is null or qty not between 1 and 50 then raise exception 'Quantidade inválida';end if;
  select pr.* into p from public.products pr join public.categories ca on ca.tenant_id=pr.tenant_id and ca.id=pr.category_id join public.menus m on m.tenant_id=ca.tenant_id and m.id=ca.menu_id where pr.id=(item->>'product_id')::uuid and pr.tenant_id=t and pr.active and ca.active and m.active for update of pr;
  if not found or (p.stock is not null and p.stock<qty) then raise exception 'Produto indisponível';end if;
  if p.stock is not null then update public.products set stock=stock-qty where id=p.id;end if;
  insert into public.order_items(tenant_id,order_id,product_id,name,price,quantity,stock_reserved) values(t,o.id,p.id,p.name,p.price,qty,p.stock is not null) returning id into itemid;
  unit_price:=p.price;
  if jsonb_array_length(coalesce(item->'addons','[]'::jsonb))>10 then raise exception 'Adicionais em excesso';end if;
  for aid in select distinct value::uuid from jsonb_array_elements_text(coalesce(item->'addons','[]'::jsonb)) loop
   select * into a from public.addons where tenant_id=t and product_id=p.id and id=aid and active;
   if not found then raise exception 'Adicional indisponível';end if;
   unit_price:=unit_price+a.price;insert into public.order_item_addons(tenant_id,item_id,addon_id,name,price) values(t,itemid,a.id,a.name,a.price);
  end loop;
  v_subtotal:=v_subtotal+unit_price*qty;
  if v_subtotal+fee>100000000 then raise exception 'Pedido excede limite';end if;
 end loop;
 update public.orders set subtotal=v_subtotal::integer,total=v_subtotal::integer+fee where id=o.id;
 insert into public.order_events(tenant_id,order_id,status,user_id) values(t,o.id,'confirmado',auth.uid());
 insert into public.notifications(tenant_id,message) values(t,'Novo pedido PDV #'||o.number);
 return jsonb_build_object('id',o.id,'number',o.number,'total',v_subtotal+fee);
end $$;
revoke all on function public.pdv_order(uuid,uuid,public.order_mode,text,text,text,text,uuid,text,jsonb) from public,anon,authenticated;
grant execute on function public.pdv_order(uuid,uuid,public.order_mode,text,text,text,text,uuid,text,jsonb) to authenticated;

-- Customer summaries derive from actual order data, so existing LGPD anonymization applies.
create function public.customer_history(t uuid) returns table(phone text,name text,orders bigint,total bigint,last_order timestamptz)
language sql stable security invoker set search_path='' as $$
 select o.phone,(array_agg(o.customer_name order by o.created_at desc))[1],count(*),coalesce(sum(o.total) filter(where o.status='concluido'),0),max(o.created_at)
 from public.orders o where o.tenant_id=t and o.phone ~ '^[0-9]{10,13}$' and public.has_role(t,array['owner','manager','attendant']::public.staff_role[]) and public.tenant_plan_level(t)>=2
 group by o.phone order by max(o.created_at) desc limit 500;
$$;
revoke all on function public.customer_history(uuid) from public,anon,authenticated;
grant execute on function public.customer_history(uuid) to authenticated;

create function public.cash_summary(t uuid,p_session uuid) returns jsonb language sql stable security invoker set search_path='' as $$
 select jsonb_build_object('balance',s.opening_amount+coalesce(sum(case when e.kind in ('venda','suprimento') then e.amount else -e.amount end) filter(where e.method='dinheiro'),0),
 'receipts',coalesce(sum(case when e.kind='venda' then e.amount when e.kind='estorno' then -e.amount else 0 end),0))
 from public.cash_sessions s left join public.cash_entries e on e.tenant_id=s.tenant_id and e.session_id=s.id
 where s.tenant_id=t and s.id=p_session group by s.id;
$$;
revoke all on function public.cash_summary(uuid,uuid) from public,anon,authenticated;
grant execute on function public.cash_summary(uuid,uuid) to authenticated;

-- Own delivery team: assignments are scoped to the same establishment.
create table public.couriers(
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null references public.establishments(id) on delete cascade,
 name text not null check(length(trim(name)) between 2 and 100),phone text check(phone is null or phone ~ '^[0-9]{10,13}$'),active boolean not null default true,
 unique(tenant_id,id)
);
create index couriers_by_tenant on public.couriers(tenant_id,active);
alter table public.couriers enable row level security;
revoke all on public.couriers from public,anon,authenticated;
grant select on public.couriers to authenticated;
grant insert(tenant_id,name,phone,active),update(name,phone,active) on public.couriers to authenticated;
create policy courier_read on public.couriers for select to authenticated using(public.has_role(tenant_id,array['owner','manager','attendant']::public.staff_role[]) and public.tenant_plan_level(tenant_id)>=2);
create policy courier_add on public.couriers for insert to authenticated with check(public.has_role(tenant_id,array['owner','manager']::public.staff_role[]) and public.tenant_plan_level(tenant_id)>=2);
create policy courier_update on public.couriers for update to authenticated using(public.has_role(tenant_id,array['owner','manager']::public.staff_role[]) and public.tenant_plan_level(tenant_id)>=2) with check(public.has_role(tenant_id,array['owner','manager']::public.staff_role[]) and public.tenant_plan_level(tenant_id)>=2);
alter table public.orders add column courier_id uuid;
alter table public.orders add constraint order_courier_tenant_fk foreign key(tenant_id,courier_id) references public.couriers(tenant_id,id);
create index orders_courier on public.orders(tenant_id,courier_id) where courier_id is not null;
create function public.assign_courier(t uuid,p_order uuid,p_courier uuid) returns void language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null or not public.has_role(t,array['owner','manager','attendant']::public.staff_role[]) or rodx_private.plan_level(t)<2 then raise exception 'Sem permissão';end if;
 if p_courier is not null and not exists(select 1 from public.couriers where tenant_id=t and id=p_courier and active) then raise exception 'Entregador inválido';end if;
 update public.orders set courier_id=p_courier where tenant_id=t and id=p_order and mode='delivery' and status not in ('concluido','cancelado');
 if not found then raise exception 'Pedido não disponível para entrega';end if;
end $$;
revoke all on function public.assign_courier(uuid,uuid,uuid) from public,anon,authenticated;
grant execute on function public.assign_courier(uuid,uuid,uuid) to authenticated;
