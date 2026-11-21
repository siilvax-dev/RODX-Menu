create function public.metrics(t uuid) returns jsonb language sql stable security definer set search_path='' as $$
 select case when public.has_role(t,array['owner','manager','attendant']::public.staff_role[]) then
 jsonb_build_object(
 'orders',count(*),
 'completed',count(*) filter(where status='concluido'),
 'pending',count(*) filter(where status not in('concluido','cancelado')),
 'revenue',case when public.has_role(t,array['owner','manager']::public.staff_role[]) then coalesce(sum(total) filter(where status='concluido'),0) else 0 end,
 'average',case when public.has_role(t,array['owner','manager']::public.staff_role[]) then coalesce(round(avg(total) filter(where status='concluido')),0) else 0 end,
 'delivery',count(*) filter(where mode='delivery'),
 'pickup',count(*) filter(where mode='retirada'),
 'table',count(*) filter(where mode='mesa'))
 else null end from public.orders where tenant_id=t and created_at>=now()-interval '30 days';
$$;
revoke all on function public.metrics(uuid) from public,anon,authenticated;
grant execute on function public.metrics(uuid) to authenticated;

-- Owner-only anonymization: preserve transactional totals, delete customer identifiers.
create function public.anonymize_customer(t uuid,p_phone text) returns integer language plpgsql security definer set search_path='' as $$
declare n integer;
begin
 if not public.has_role(t,array['owner']::public.staff_role[]) then raise exception 'Sem permissão';end if;
 if exists(select 1 from public.orders where tenant_id=t and phone=p_phone and status not in('concluido','cancelado')) then raise exception 'Existem pedidos em andamento';end if;
 update public.orders set customer_name='Anonimizado',phone='anonimizado',address=null,notes=null where tenant_id=t and phone=p_phone;
 get diagnostics n=row_count;
 delete from public.loyalty_accounts where tenant_id=t and phone=p_phone;
 return n;
end $$;
revoke all on function public.anonymize_customer(uuid,text) from public,anon,authenticated;
grant execute on function public.anonymize_customer(uuid,text) to authenticated;

-- Kitchen sees preparation data instead of addresses, prices or customer history.
do $$ declare tab text;
begin
 foreach tab in array array['orders','order_items','order_item_addons','order_events'] loop
  execute format('drop policy read_tenant on public.%I',tab);
  execute format('create policy read_tenant on public.%I for select to authenticated using (public.has_role(tenant_id,array[''owner'',''manager'',''attendant'']::public.staff_role[]))',tab);
 end loop;
end $$;
create function public.kitchen_queue(t uuid) returns jsonb language sql stable security definer set search_path='' as $$
 select case when public.is_member(t) then coalesce(jsonb_agg(j order by j->>'created_at'),'[]'::jsonb) else null end
 from (select jsonb_build_object('id',o.id,'number',o.number,'status',o.status,'mode',o.mode,
 'created_at',o.created_at,'notes',o.notes,'dining_tables',(select jsonb_build_object('name',d.name) from public.dining_tables d where d.tenant_id=t and d.id=o.table_id),
 'order_items',coalesce((select jsonb_agg(jsonb_build_object('name',i.name,'quantity',i.quantity,'order_item_addons',coalesce((select jsonb_agg(jsonb_build_object('name',a.name)) from public.order_item_addons a where a.tenant_id=t and a.item_id=i.id),'[]'::jsonb))) from public.order_items i where i.tenant_id=t and i.order_id=o.id),'[]'::jsonb)) j
 from public.orders o where o.tenant_id=t and o.status in ('confirmado','preparando','pronto') order by o.created_at limit 100) rows;
$$;
revoke all on function public.kitchen_queue(uuid) from public,anon,authenticated;
grant execute on function public.kitchen_queue(uuid) to authenticated;
