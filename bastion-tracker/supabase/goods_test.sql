\set ON_ERROR_STOP on

insert into auth.users (id, email) values
  ('eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee', 'goods-dm@example.com'),
  ('ffffffff-ffff-ffff-ffff-ffffffffffff', 'goods-editor@example.com'),
  ('10101010-1010-1010-1010-101010101010', 'goods-reader@example.com'),
  ('20202020-2020-2020-2020-202020202020', 'goods-stranger@example.com')
on conflict (id) do nothing;

create or replace function public._run_goods_checks()
returns void
language plpgsql
as $$
declare
  eid uuid;
  rev bigint;
  out jsonb;
  doc jsonb;
  before_rev bigint;
  lot_id text;
  cash jsonb;
  token text;
begin
  perform set_config('request.jwt.claim.sub', 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee', false);
  perform set_config('request.jwt.claim.role', 'authenticated', false);
  eid := public.create_estate('Practice Hold');
  select revision into rev from public.estates where id = eid;

  before_rev := rev;
  begin
    perform public.apply_command(eid, rev, 'blank-name', '{"type":"record_goods","name":"   ","standardGp":10}'::jsonb);
    raise exception 'blank name was stored';
  exception when invalid_parameter_value then
    if SQLERRM not like 'Goods need a name%' then raise; end if;
  end;
  begin
    perform public.apply_command(eid, rev, 'zero-gp', '{"type":"record_goods","name":"Wool","standardGp":0}'::jsonb);
    raise exception 'zero goods were stored';
  exception when invalid_parameter_value then
    if SQLERRM not like 'Goods need a list price above zero%' then raise; end if;
  end;
  begin
    perform public.apply_command(eid, rev, 'blank-reserve', '{"type":"reserve_goods","name":"  ","standardGp":20}'::jsonb);
    raise exception 'blank committed goods were stored';
  exception when invalid_parameter_value then
    if SQLERRM not like 'Goods need a name%' then raise; end if;
  end;
  select revision, document into rev, doc from public.estates where id = eid;
  if rev <> before_rev or jsonb_array_length(doc->'goods') <> 0 then
    raise exception 'refused goods changed the record';
  end if;

  out := public.apply_command(eid, rev, 'wool', '{"type":"record_goods","name":" Wool bolts ","standardGp":200}'::jsonb);
  rev := (out->>'revision')::bigint;
  doc := out->'document';
  if doc#>>'{goods,0,name}' <> 'Wool bolts' or (doc#>>'{finance,cashKnown}')::boolean then
    raise exception 'named goods were not stored free of cash';
  end if;
  lot_id := doc#>>'{goods,0,id}';
  cash := doc#>'{finance,cashGp}';
  out := public.apply_command(eid, rev, 'drop-wool', jsonb_build_object('type', 'remove_goods', 'lotId', lot_id));
  rev := (out->>'revision')::bigint;
  doc := out->'document';
  if jsonb_array_length(doc->'goods') <> 0 or doc#>'{finance,cashGp}' is distinct from cash then
    raise exception 'remove changed cash or left the goods';
  end if;
  if not exists (
    select 1 from public.audit_log
    where estate_id = eid and command_type = 'remove_goods' and summary like 'Removed Wool bolts%'
  ) then
    raise exception 'remove was not audited';
  end if;

  out := public.apply_command(eid, rev, 'wool-again', '{"type":"record_goods","name":"Wool bolts","standardGp":200}'::jsonb);
  rev := (out->>'revision')::bigint;
  doc := out->'document';
  lot_id := doc#>>'{goods,0,id}';
  out := public.apply_command(eid, rev, 'hold', jsonb_build_object('type', 'reserve_goods', 'lotId', lot_id, 'standardGp', 50, 'note', 'Already in a sell'));
  rev := (out->>'revision')::bigint;
  before_rev := rev;
  begin
    perform public.apply_command(eid, rev, 'drop-held', jsonb_build_object('type', 'remove_goods', 'lotId', lot_id));
    raise exception 'reserved goods were removed';
  exception when invalid_parameter_value then
    if SQLERRM not like 'Those goods are still reserved%' then raise; end if;
  end;
  select revision, document into rev, doc from public.estates where id = eid;
  if rev <> before_rev or jsonb_array_length(doc->'goods') <> 1 or doc#>'{finance,cashGp}' is distinct from cash then
    raise exception 'refused removal changed cash or goods';
  end if;

  begin
    perform public.apply_command(eid, 1, 'stale-remove', jsonb_build_object('type', 'remove_goods', 'lotId', lot_id));
    raise exception 'stale removal was accepted';
  exception when serialization_failure then
    if SQLERRM not like '%revision_conflict%' then raise; end if;
  end;

  perform set_config('request.jwt.claim.sub', 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee', false);
  token := public.create_invite(eid, 'goods-editor@example.com', 'editor');
  perform set_config('request.jwt.claim.sub', 'ffffffff-ffff-ffff-ffff-ffffffffffff', false);
  perform public.accept_invite(token);
  begin
    perform public.apply_command(eid, null, 'editor-remove', jsonb_build_object('type', 'remove_goods', 'lotId', lot_id));
    raise exception 'editor removed goods';
  exception when insufficient_privilege then null;
  end;

  perform set_config('request.jwt.claim.sub', 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee', false);
  token := public.create_invite(eid, 'goods-reader@example.com', 'reader');
  perform set_config('request.jwt.claim.sub', '10101010-1010-1010-1010-101010101010', false);
  perform public.accept_invite(token);
  begin
    perform public.apply_command(eid, null, 'reader-remove', jsonb_build_object('type', 'remove_goods', 'lotId', lot_id));
    raise exception 'reader removed goods';
  exception when insufficient_privilege then null;
  end;

  perform set_config('request.jwt.claim.sub', '20202020-2020-2020-2020-202020202020', false);
  begin
    perform public.apply_command(eid, null, 'stranger-remove', jsonb_build_object('type', 'remove_goods', 'lotId', lot_id));
    raise exception 'stranger removed goods';
  exception when insufficient_privilege then null;
  end;

  if exists (
    select 1 from pg_proc where proname = '_bastion_cmd_remove_goods' and prosecdef
  ) then
    raise exception 'remove helper is security definer';
  end if;
  if not exists (
    select 1 from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'apply_command' and p.prosecdef
      and p.proconfig @> array['search_path=public']
  ) then
    raise exception 'apply_command lost its definer or search_path';
  end if;
end;
$$;

set role authenticated;
select set_config('request.jwt.claim.sub', 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee', false);
select set_config('request.jwt.claim.role', 'authenticated', false);
select public._run_goods_checks();

reset role;
do $$
begin
  execute 'set local role anon';
  begin
    perform public.apply_command('eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee'::uuid, null, 'anon-goods', '{"type":"remove_goods","lotId":"good-1"}'::jsonb);
    raise exception 'anon_could_remove_goods';
  exception
    when insufficient_privilege then
      null;
  end;
end $$;
