-- AKSA StockFlow: single-business workspace. Run once in a dedicated Supabase project.
-- Browser clients never write these tables. The authenticated Edge Function is the command boundary.
create schema if not exists stockflow;
revoke all on schema stockflow from public,anon,authenticated;
grant usage on schema stockflow to service_role;

create table stockflow.profiles (
 id uuid primary key references auth.users(id) on delete restrict,
 name text not null check(length(name)>0),
 role text not null check(role in ('OWNER','ADMIN','WAREHOUSE STAFF','STOCK COUNTER','SUPERVISOR','VIEWER')),
 active boolean not null default true
);
create table stockflow.meta (
 id boolean primary key default true check(id),revision bigint not null default 0,
 settings jsonb not null,sequences jsonb not null default '{}',requests jsonb not null default '[]',
 updated_at timestamptz not null default now(),last_result jsonb
);
insert into stockflow.meta(id,settings) values(true,'{"businessName":"Aruna Mart","currency":"IDR","allowNegative":false,"largeVarianceQty":10,"largeVariancePercent":10}');
create table stockflow.categories(id text primary key,data jsonb not null);
create table stockflow.units(name text primary key,discrete boolean not null);
insert into stockflow.units values('Piece',true),('Pack',true),('Box',true),('Bottle',true),('Kilogram',false),('Meter',false);
create table stockflow.locations(id text primary key,data jsonb not null,code text generated always as(data->>'code') stored unique not null);
insert into stockflow.locations values('loc-store','{"id":"loc-store","name":"Main Store","code":"STR","type":"Retail","active":true,"description":"Shop floor"}'),('loc-warehouse','{"id":"loc-warehouse","name":"Warehouse","code":"WH","type":"Warehouse","active":true,"description":"Backroom storage"}');
create table stockflow.suppliers(id text primary key,data jsonb not null);
create table stockflow.products(
 id text primary key,data jsonb not null,
 sku text generated always as(upper(data->>'sku')) stored unique not null,
 barcode text generated always as(nullif(data->>'barcode','')) stored unique,
 category_id text generated always as(data->>'categoryId') stored references stockflow.categories(id),
 base_unit text generated always as(data->>'unit') stored references stockflow.units(name),
 check(length(data->>'name')>0),check((data->>'minimum')::numeric>=0)
);
create table stockflow.stock_receipts(id text primary key,data jsonb not null,location_id text generated always as(data->>'locationId') stored references stockflow.locations(id));
create table stockflow.stock_receipt_items(id text primary key,receipt_id text not null references stockflow.stock_receipts(id),product_id text not null references stockflow.products(id),data jsonb not null,check((data->>'baseQuantity')::numeric>0));
create table stockflow.stock_issues(id text primary key,data jsonb not null,location_id text generated always as(data->>'locationId') stored references stockflow.locations(id));
create table stockflow.stock_issue_items(id text primary key,issue_id text not null references stockflow.stock_issues(id),product_id text not null references stockflow.products(id),data jsonb not null,check((data->>'baseQuantity')::numeric>0));
create table stockflow.transfers(
 id text primary key,data jsonb not null,
 source_id text generated always as(data->>'sourceId') stored references stockflow.locations(id),
 destination_id text generated always as(data->>'destinationId') stored references stockflow.locations(id),
 check(data->>'status' in ('DRAFT','IN TRANSIT','COMPLETED','CANCELLED')),check(data->>'sourceId'<>data->>'destinationId')
);
create table stockflow.transfer_items(id text primary key,transfer_id text not null references stockflow.transfers(id),product_id text not null references stockflow.products(id),data jsonb not null,check((data->>'baseQuantity')::numeric>0));
create table stockflow.stock_counts(id text primary key,data jsonb not null,location_id text generated always as(data->>'locationId') stored references stockflow.locations(id),check(data->>'status' in ('DRAFT','COUNTING','SUBMITTED','UNDER REVIEW','APPROVED','ADJUSTED','CANCELLED')));
create table stockflow.stock_count_items(id text primary key,count_id text not null references stockflow.stock_counts(id),product_id text not null references stockflow.products(id),data jsonb not null,unique(count_id,product_id));
create table stockflow.stock_count_entries(id text primary key,item_id text not null references stockflow.stock_count_items(id),data jsonb not null,check((data->>'quantity')::numeric>=0));
create table stockflow.stock_movements(
 id text primary key,data jsonb not null,
 product_id text generated always as(data->>'productId') stored not null references stockflow.products(id),
 location_id text generated always as(data->>'locationId') stored not null references stockflow.locations(id),
 delta numeric generated always as((data->>'delta')::numeric) stored not null,
 balance numeric generated always as((data->>'balance')::numeric) stored not null,
 session_id text generated always as(nullif(data->>'sessionId','')) stored references stockflow.stock_counts(id),
 check((data->>'delta')::numeric<>0),check((data->>'balance')::numeric>=0)
);
create index movements_product_location on stockflow.stock_movements(product_id,location_id);
create unique index one_adjustment_per_count_product on stockflow.stock_movements(session_id,product_id,location_id) where session_id is not null;
create table stockflow.audit_logs(id text primary key,data jsonb not null);
create view stockflow.inventory_balances as select product_id,location_id,sum(delta) as quantity from stockflow.stock_movements group by product_id,location_id;
create view stockflow.stock_adjustments as select * from stockflow.stock_movements where data->>'type' in ('STOCK OPNAME ADJUSTMENT','MANUAL ADJUSTMENT');

-- All data access is behind JWT verification + a provisioned active profile in the Edge Function.
do $$ declare t record; begin for t in select tablename from pg_tables where schemaname='stockflow' loop execute format('alter table stockflow.%I enable row level security',t.tablename); end loop; end $$;
grant all on all tables in schema stockflow to service_role;

create or replace function public.stockflow_profile(p_user uuid) returns jsonb
language sql security definer set search_path=stockflow,pg_temp as $$
 select jsonb_build_object('id',id,'name',name,'role',role) from stockflow.profiles where id=p_user and active;
$$;
create or replace function public.stockflow_read() returns jsonb
language plpgsql security definer set search_path=stockflow,pg_temp as $$
declare m stockflow.meta; s jsonb; t text; k text; v jsonb;
begin
 select * into m from stockflow.meta where id=true;
 s=jsonb_build_object('schemaVersion',1,'revision',m.revision,'settings',m.settings,'sequences',m.sequences,'requests',m.requests,'updatedAt',m.updated_at,'lastResult',m.last_result);
 for t,k in select * from (values('categories','categories'),('locations','locations'),('suppliers','suppliers'),('products','products'),('stock_receipts','receipts'),('stock_issues','issues'),('transfers','transfers'),('stock_counts','counts'),('audit_logs','audit')) v(t,k) loop
  execute format('select coalesce(jsonb_agg(data order by coalesce(data->>''createdAt'',data->>''at'',''''),id),''[]''::jsonb) from stockflow.%I',t) into v;
  s=jsonb_set(s,array[k],v);
 end loop;
 -- Use insertion order for the balance ledger, including same-timestamp multi-line postings.
 select coalesce(jsonb_agg(data order by data->>'_order'),'[]'::jsonb) into v from stockflow.stock_movements;
 s=jsonb_set(s,array['movements'],v);
 select coalesce(jsonb_agg(jsonb_build_object('id',id,'name',name,'role',role) order by name),'[]'::jsonb) into v from stockflow.profiles where active;
 s=jsonb_set(s,array['profiles'],v);
 return s;
end $$;

create or replace function public.stockflow_commit(p_state jsonb,p_expected bigint) returns void
language plpgsql security definer set search_path=stockflow,pg_temp as $$
declare current_revision bigint; t text;k text;r jsonb;item jsonb;entry jsonb;previous numeric;delta numeric;existing jsonb;position integer:=0;rowid text;parent_field text;
begin
 select revision into current_revision from stockflow.meta where id=true for update;
 if current_revision<>p_expected then raise exception 'WORKSPACE_CONFLICT: another staff operation was committed; retry'; end if;
 if (p_state->>'revision')::bigint<>p_expected+1 then raise exception 'Invalid revision';end if;
 if coalesce((p_state->'settings'->>'allowNegative')::boolean,true) then raise exception 'Negative inventory is disabled';end if;
 for t,k in select * from (values('categories','categories'),('locations','locations'),('suppliers','suppliers'),('products','products'),('stock_receipts','receipts'),('stock_issues','issues'),('transfers','transfers'),('stock_counts','counts')) v(t,k) loop
  for r in select value from jsonb_array_elements(p_state->k) loop
   execute format('insert into stockflow.%I(id,data) values($1,$2) on conflict(id) do update set data=excluded.data',t) using r->>'id',r;
  end loop;
 end loop;
 for t,k,parent_field in select * from (values('stock_receipt_items','receipts','receipt_id'),('stock_issue_items','issues','issue_id'),('transfer_items','transfers','transfer_id')) v(t,k,f) loop
  for r in select value from jsonb_array_elements(p_state->k) loop
   position=0;
   for item in select value from jsonb_array_elements(r->'lines') loop
    position=position+1;rowid=(r->>'id')||':'||position;
    execute format('insert into stockflow.%I(id,%I,product_id,data) values($1,$2,$3,$4) on conflict(id) do nothing',t,parent_field) using rowid,r->>'id',item->>'productId',item;
   end loop;
  end loop;
 end loop;
 for r in select value from jsonb_array_elements(p_state->'counts') loop
  for item in select value from jsonb_array_elements(r->'items') loop
   insert into stockflow.stock_count_items(id,count_id,product_id,data) values(item->>'id',r->>'id',item->>'productId',item-'entries') on conflict(id) do update set data=excluded.data;
   for entry in select value from jsonb_array_elements(item->'entries') loop
    select data into existing from stockflow.stock_count_entries where id=entry->>'id';
    if existing is not null and existing<>entry then raise exception 'Count history is immutable';end if;
    insert into stockflow.stock_count_entries(id,item_id,data) values(entry->>'id',item->>'id',entry) on conflict do nothing;
   end loop;
  end loop;
 end loop;
 if exists(select 1 from stockflow.stock_movements m where not exists(select 1 from jsonb_array_elements(p_state->'movements') payload where payload.value->>'id'=m.id)) then raise exception 'Ledger entries cannot be deleted';end if;
 position=0;
 for r in select value from jsonb_array_elements(p_state->'movements') loop
  position=position+1;
  select data into existing from stockflow.stock_movements where id=r->>'id';
  if existing is not null then
   if (existing-'_order')<>(r-'_order') then raise exception 'Ledger entries cannot be edited';end if;
  else
   select coalesce(sum(m.delta),0) into previous from stockflow.stock_movements m where m.product_id=r->>'productId' and m.location_id=r->>'locationId';
   delta=(r->>'delta')::numeric;
   if previous<>(r->>'previous')::numeric or previous+delta<>(r->>'balance')::numeric or previous+delta<0 then raise exception 'Invalid ledger balance';end if;
   insert into stockflow.stock_movements(id,data) values(r->>'id',(r-'_order')||jsonb_build_object('_order',lpad(position::text,14,'0')));
  end if;
 end loop;
 for r in select value from jsonb_array_elements(p_state->'audit') loop
  select data into existing from stockflow.audit_logs where id=r->>'id';
  if existing is not null and existing<>r then raise exception 'Audit records cannot be edited';end if;
  insert into stockflow.audit_logs(id,data) values(r->>'id',r) on conflict do nothing;
 end loop;
 update stockflow.meta set revision=(p_state->>'revision')::bigint,settings=p_state->'settings',sequences=p_state->'sequences',requests=p_state->'requests',last_result=p_state->'lastResult',updated_at=now() where id=true;
end $$;
revoke all on function public.stockflow_profile(uuid),public.stockflow_read(),public.stockflow_commit(jsonb,bigint) from public,anon,authenticated;
grant execute on function public.stockflow_profile(uuid),public.stockflow_read(),public.stockflow_commit(jsonb,bigint) to service_role;

-- Product media stays private. Only the authenticated Edge Function creates short-lived signed URLs.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('stockflow-products','stockflow-products',false,1048576,array['image/webp','image/png','image/jpeg']) on conflict(id) do nothing;
