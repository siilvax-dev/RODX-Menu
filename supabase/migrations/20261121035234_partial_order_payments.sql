-- Allow one order to be settled in multiple installments and payment methods.
drop index if exists public.cash_order_kind;
create index cash_order_ledger_idx on public.cash_entries(tenant_id,order_id,created_at) where order_id is not null;

-- Keep refund operation idempotency independent from the number of tender methods.
create table public.cash_refund_requests (
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references public.establishments(id) on delete cascade,
 request_id uuid not null, session_id uuid not null, order_id uuid not null,
 note text not null check(length(trim(note)) between 3 and 300), created_at timestamptz not null default now(),
 created_by uuid references auth.users(id) on delete set null, unique(tenant_id,request_id),
 foreign key(tenant_id,session_id) references public.cash_sessions(tenant_id,id),
 foreign key(tenant_id,order_id) references public.orders(tenant_id,id)
);
alter table public.cash_refund_requests enable row level security;
revoke all on public.cash_refund_requests from public,anon,authenticated;

create function public.register_order_payment(t uuid,p_request uuid,p_session uuid,p_order uuid,p_amount integer,p_method text)
returns void language plpgsql security definer set search_path='' as $$
declare s public.cash_sessions%rowtype; o public.orders%rowtype; e public.establishments%rowtype; received bigint;
begin
 if auth.uid() is null or not public.has_role(t,array['owner','manager','attendant']::public.staff_role[]) or rodx_private.plan_level(t)<2 then raise exception 'Sem permissão';end if;
 if p_request is null or p_order is null or p_session is null or p_amount is null or p_amount not between 1 and 100000000 or p_method not in ('pix','cartao','cartao_credito','cartao_debito','dinheiro','vale_refeicao') then raise exception 'Dados de pagamento inválidos';end if;
 perform 1 from public.establishments where id=t for update;
 if exists(select 1 from public.cash_entries where tenant_id=t and request_id=p_request) then return;end if;
 select * into s from public.cash_sessions where tenant_id=t and closed_at is null for update;
 if s.id is null or s.id<>p_session then raise exception 'Abra o caixa ou atualize a página';end if;
 select * into e from public.establishments where id=t;
 if not p_method=any(e.payment_methods) then raise exception 'Forma de pagamento não aceita pelo estabelecimento';end if;
 select * into o from public.orders where tenant_id=t and id=p_order for update;
 if not found or o.status='cancelado' or o.total<=0 then raise exception 'Pedido indisponível';end if;
 select coalesce(sum(case when kind='venda' then amount when kind='estorno' then -amount else 0 end),0) into received from public.cash_entries where tenant_id=t and order_id=o.id;
 if p_amount>o.total-received then raise exception 'O valor ultrapassa o saldo do pedido';end if;
 insert into public.cash_entries(tenant_id,session_id,request_id,order_id,kind,amount,method,created_by) values(t,s.id,p_request,o.id,'venda',p_amount,p_method,auth.uid());
end $$;
revoke all on function public.register_order_payment(uuid,uuid,uuid,uuid,integer,text) from public,anon,authenticated;
grant execute on function public.register_order_payment(uuid,uuid,uuid,uuid,integer,text) to authenticated;

create function public.refund_order_payments(t uuid,p_request uuid,p_session uuid,p_order uuid,p_note text)
returns void language plpgsql security definer set search_path='' as $$
declare s public.cash_sessions%rowtype; o public.orders%rowtype; sale record; cash_balance bigint; cash_refund bigint:=0; gross bigint; refunded bigint;
begin
 if auth.uid() is null or not public.has_role(t,array['owner','manager']::public.staff_role[]) or rodx_private.plan_level(t)<2 then raise exception 'Estorno exige gerente ou proprietário';end if;
 if p_request is null or p_order is null or p_session is null or length(trim(coalesce(p_note,''))) not between 3 and 300 then raise exception 'Dados de estorno inválidos';end if;
 perform 1 from public.establishments where id=t for update;
 if exists(select 1 from public.cash_refund_requests where tenant_id=t and request_id=p_request) then return;end if;
 select * into s from public.cash_sessions where tenant_id=t and closed_at is null for update;
 if s.id is null or s.id<>p_session then raise exception 'Abra o caixa ou atualize a página';end if;
 select * into o from public.orders where tenant_id=t and id=p_order for update;
 if not found then raise exception 'Pedido inválido';end if;
 select coalesce(sum(amount),0) into gross from public.cash_entries where tenant_id=t and order_id=o.id and kind='venda';
 select coalesce(sum(amount),0) into refunded from public.cash_entries where tenant_id=t and order_id=o.id and kind='estorno';
 if gross<=0 or refunded>0 then raise exception 'Pagamento inexistente ou já estornado';end if;
 select s.opening_amount+coalesce(sum(case when kind in ('venda','suprimento') then amount else -amount end) filter(where method='dinheiro'),0) into cash_balance from public.cash_entries where tenant_id=t and session_id=s.id;
 select coalesce(sum(amount),0) into cash_refund from public.cash_entries where tenant_id=t and order_id=o.id and kind='venda' and method='dinheiro';
 if cash_refund>cash_balance then raise exception 'Saldo em dinheiro insuficiente para o estorno';end if;
 insert into public.cash_refund_requests(tenant_id,request_id,session_id,order_id,note,created_by) values(t,p_request,s.id,o.id,trim(p_note),auth.uid());
 for sale in select method,sum(amount)::integer as amount from public.cash_entries where tenant_id=t and order_id=o.id and kind='venda' group by method loop
  insert into public.cash_entries(tenant_id,session_id,request_id,order_id,kind,amount,method,note,created_by) values(t,s.id,gen_random_uuid(),o.id,'estorno',sale.amount,sale.method,trim(p_note),auth.uid());
 end loop;
end $$;
revoke all on function public.refund_order_payments(uuid,uuid,uuid,uuid,text) from public,anon,authenticated;
grant execute on function public.refund_order_payments(uuid,uuid,uuid,uuid,text) to authenticated;
