create function rodx_private.guard_order_payment_ledger() returns trigger
language plpgsql security definer set search_path='' as $$
declare order_total integer; net_received bigint;
begin
 if new.kind not in ('venda','estorno') then return new; end if;
 select total into order_total from public.orders where tenant_id=new.tenant_id and id=new.order_id for update;
 if not found then raise exception 'Pedido inválido'; end if;
 select coalesce(sum(case when kind='venda' then amount when kind='estorno' then -amount else 0 end),0)
   into net_received from public.cash_entries where tenant_id=new.tenant_id and order_id=new.order_id;
 if new.kind='venda' and new.amount>order_total-net_received then raise exception 'O valor ultrapassa o saldo do pedido'; end if;
 if new.kind='estorno' and new.amount>net_received then raise exception 'O estorno ultrapassa o valor recebido'; end if;
 return new;
end $$;
revoke all on function rodx_private.guard_order_payment_ledger() from public,anon,authenticated;
create trigger guard_order_payment_ledger before insert on public.cash_entries for each row execute function rodx_private.guard_order_payment_ledger();
