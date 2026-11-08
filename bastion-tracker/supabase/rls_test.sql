\set ON_ERROR_STOP on

create or replace function public._assert(ok boolean, message text)
returns void
language plpgsql
as $$
begin
  if not ok then
    raise exception '%', message;
  end if;
end;
$$;

create or replace function public._expect_forbidden(eid uuid, cmd jsonb, key text)
returns void
language plpgsql
as $$
begin
  perform public.apply_command(eid, null, key, cmd);
  raise exception 'write_was_allowed';
exception
  when insufficient_privilege then
    return;
end;
$$;

insert into auth.users (id, email) values
  ('11111111-1111-1111-1111-111111111111', 'dm@example.com'),
  ('22222222-2222-2222-2222-222222222222', 'reader@example.com'),
  ('33333333-3333-3333-3333-333333333333', 'editor@example.com');

select set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', false);
select set_config('request.jwt.claim.role', 'authenticated', false);
set role authenticated;
select public.create_estate('Practice Hall') as estate_id \gset

-- Anonymous cannot read the estate.
reset role;
do $$
begin
  execute 'set local role anon';
  begin
    perform 1 from public.estates;
    raise exception 'anon_could_read';
  exception
    when insufficient_privilege then
      null;
  end;
end $$;

set role authenticated;
select set_config('request.jwt.claim.sub', '22222222-2222-2222-2222-222222222222', false);
select count(*) as stranger_rows from public.estates where id = :'estate_id'::uuid;
do $$
begin
  if (select count(*) from public.estates) <> 0 then
    raise exception 'stranger_could_read';
  end if;
end $$;

-- Reader can see the estate and cannot change it.
select set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', false);
select public.create_invite(:'estate_id'::uuid, 'reader@example.com', 'reader') as reader_token \gset
select set_config('request.jwt.claim.sub', '22222222-2222-2222-2222-222222222222', false);
select public.accept_invite(:'reader_token') as accepted \gset
select count(*) as reader_rows from public.estates;
select public._assert((select count(*) from public.estates) = 1, 'reader_missing_estate');
select public._expect_forbidden(:'estate_id'::uuid, '{"type":"set_clock","ordinal":3}'::jsonb, 'reader-try');

-- Editor cannot raise the level.
select set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', false);
select public.create_invite(:'estate_id'::uuid, 'editor@example.com', 'editor') as editor_token \gset
select set_config('request.jwt.claim.sub', '33333333-3333-3333-3333-333333333333', false);
select public.accept_invite(:'editor_token');
select public._expect_forbidden(:'estate_id'::uuid, '{"type":"raise_level","unitId":"unit-party","level":6}'::jsonb, 'editor-level');

-- DM sells 500 GP of goods for 550 once, even when the cadence is 10.
select set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', false);
select public.apply_command(:'estate_id'::uuid, 1, 'clock', '{"type":"set_clock","ordinal":1}'::jsonb)->>'revision' as rev_clock \gset
select public.apply_command(:'estate_id'::uuid, :rev_clock, 'cadence', '{"type":"set_settings","cadenceDays":10}'::jsonb)->>'revision' as rev_cadence \gset
select public.apply_command(:'estate_id'::uuid, :rev_cadence, 'cash', '{"type":"set_finance","cashGp":0}'::jsonb)->>'revision' as rev_cash \gset
select public.apply_command(:'estate_id'::uuid, :rev_cash, 'store', '{"type":"add_special","unitId":"unit-party","catalogId":"storehouse"}'::jsonb)->>'revision' as rev_store \gset
select public.apply_command(:'estate_id'::uuid, :rev_store, 'goods', '{"type":"record_goods","name":"Wool","standardGp":500}'::jsonb)->>'revision' as rev_goods \gset
select (document->'goods'->0->>'id') as lot_id from public.estates where id = :'estate_id'::uuid \gset
select (document->'facilities'->0->>'id') as store_id from public.estates where id = :'estate_id'::uuid \gset
select public.apply_command(
  :'estate_id'::uuid,
  :rev_goods,
  'sell',
  jsonb_build_object(
    'type', 'commit_turn',
    'unitId', 'unit-party',
    'presence', 'present',
    'mode', 'orders',
    'orders', jsonb_build_array(jsonb_build_object('facilityId', :'store_id', 'suborder', 'sell', 'lotId', :'lot_id', 'standardGp', 500))
  )
)->>'revision' as rev_sell \gset
select (document#>>'{finance,cashGp}')::int as cash_before from public.estates where id = :'estate_id'::uuid \gset
select public.apply_command(:'estate_id'::uuid, :rev_sell, 'week', '{"type":"advance_days","days":7}'::jsonb)->>'revision' as rev_week \gset
select public.apply_command(:'estate_id'::uuid, 1, 'week', '{"type":"advance_days","days":7}'::jsonb)->>'replay' as replayed \gset
select (document#>>'{finance,cashGp}')::int as cash_after, (document#>>'{clock,ordinal}')::int as day_after, (document#>>'{clock,cadenceDays}')::int as cadence
from public.estates where id = :'estate_id'::uuid \gset

select public._assert(:cash_before = 0 and :cash_after = 550 and :day_after = 8 and :cadence = 10 and :'replayed' = 'true', 'sale_settlement');

-- A second member still cannot see a different estate.
select set_config('request.jwt.claim.sub', '33333333-3333-3333-3333-333333333333', false);
select public.create_estate('Other Hall') as other_id \gset
select set_config('request.jwt.claim.sub', '22222222-2222-2222-2222-222222222222', false);
select public._assert(not exists (select 1 from public.estates where id = :'other_id'::uuid), 'reader_saw_other_estate');

reset role;
select public._assert(
  exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'empty_document'
      and p.proconfig @> array['search_path=public']
  ),
  'empty_document search_path is not pinned'
);
select 'rls_ok' as status;
