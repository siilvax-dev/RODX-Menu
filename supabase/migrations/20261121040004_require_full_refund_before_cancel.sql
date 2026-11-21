create or replace function rodx_private.guard_paid_cancel() returns trigger
language plpgsql security definer set search_path='' as $$
declare net_received bigint;
begin
 if new.status='cancelado' and old.status<>'cancelado' then
  select coalesce(sum(case when kind='venda' then amount when kind='estorno' then -amount else 0 end),0)
    into net_received from public.cash_entries where tenant_id=new.tenant_id and order_id=new.id;
  if net_received>0 then raise exception 'Registre o estorno integral no caixa antes de cancelar'; end if;
 end if;
 return new;
end $$;
revoke all on function rodx_private.guard_paid_cancel() from public,anon,authenticated;
