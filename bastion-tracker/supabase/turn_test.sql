\set ON_ERROR_STOP on

insert into auth.users (id, email) values
  ('e1111111-1111-1111-1111-111111111111', 'turn-dm@example.com'),
  ('e2222222-2222-2222-2222-222222222222', 'turn-reader@example.com'),
  ('e3333333-3333-3333-3333-333333333333', 'turn-editor@example.com'),
  ('e4444444-4444-4444-4444-444444444444', 'turn-stranger@example.com');

do $$
declare
  raw jsonb := jsonb_build_object(
    'finance', jsonb_build_object('cashGp', 50),
    'clock', jsonb_build_object('ordinal', 12, 'cadenceDays', 10, 'label', 'Session'),
    'orders', jsonb_build_array(jsonb_build_object('id', 'ord-51', 'startedDay', 30)),
    'tasks', jsonb_build_array(jsonb_build_object('id', 'task-1', 'dueOrdinal', 20)),
    'events', jsonb_build_array(jsonb_build_object('detail', jsonb_build_object('dueInDays', 7)))
  );
  once jsonb;
  twice jsonb;
begin
  once := public._bastion_migrate_turns(raw);
  if (once#>>'{finance,cashGp}')::int is distinct from 50 then
    raise exception 'migration changed cash';
  end if;
  if (once#>>'{clock,turn}')::int is distinct from 12 or (once#>>'{clock,turnNeedsCheck}')::boolean is distinct from true then
    raise exception 'counter was not kept and flagged';
  end if;
  if once#>>'{clock,ordinal}' is not null or once->'clock' ? 'cadenceDays' then
    raise exception 'old clock fields remained';
  end if;
  if once#>>'{orders,0,startedTurn}' is not null
     or (once#>>'{orders,0,startNeedsCheck}')::boolean is distinct from true
     or (once#>>'{orders,0,previousStartNumber}')::int is distinct from 30
     or once->'orders'->0 ? 'startedDay' then
    raise exception 'order start was guessed';
  end if;
  if once#>>'{tasks,0,dueTurn}' is not null or (once#>>'{tasks,0,previousDue}')::int is distinct from 20 then
    raise exception 'timer was guessed';
  end if;
  if (once#>>'{events,0,detail,dueInTurns}')::int is distinct from 1 or once->'events'->0->'detail' ? 'dueInDays' then
    raise exception 'guest duration stayed in days';
  end if;
  twice := public._bastion_migrate_turns(once);
  if (twice#>>'{orders,0,previousStartNumber}')::int is distinct from 30 then
    raise exception 'second migration rewrote the review number';
  end if;
  twice := jsonb_set(twice, '{orders,0,startedTurn}', '2'::jsonb);
  twice := jsonb_set(twice, '{orders,0,startNeedsCheck}', 'false'::jsonb);
  twice := public._bastion_migrate_turns(twice);
  if (twice#>>'{orders,0,startedTurn}')::int is distinct from 2 or (twice#>>'{orders,0,startNeedsCheck}')::boolean then
    raise exception 'confirmed start was wiped';
  end if;
  once := public._bastion_migrate_turns(jsonb_build_object('clock', jsonb_build_object('ordinal', 3), 'finance', jsonb_build_object('cashGp', 50)));
  if (once#>>'{clock,turn}')::int is distinct from 3 or coalesce((once#>>'{clock,turnNeedsCheck}')::boolean, false) or (once#>>'{finance,cashGp}')::int is distinct from 50 then
    raise exception 'turn 3 was flagged or cash moved';
  end if;
  once := public._bastion_migrate_turns(jsonb_build_object('clock', jsonb_build_object('ordinal', null)));
  if once#>>'{clock,turn}' is not null or (once#>>'{clock,turnNeedsCheck}')::boolean is distinct from true then
    raise exception 'unknown counter was invented';
  end if;
end $$;

set role authenticated;
select set_config('request.jwt.claim.sub', 'e1111111-1111-1111-1111-111111111111', false);
select set_config('request.jwt.claim.role', 'authenticated', false);
select public.create_estate('Turn Hall') as turn_estate \gset
select public.apply_command(:'turn_estate'::uuid, 1, 'turn-clock', '{"type":"set_clock","turn":1}'::jsonb)->>'revision' as turn_rev \gset
select public.apply_command(:'turn_estate'::uuid, :turn_rev, 'turn-cash', '{"type":"set_finance","cashGp":40}'::jsonb)->>'revision' as turn_rev \gset
select public.create_invite(:'turn_estate'::uuid, 'turn-reader@example.com', 'reader') as turn_reader_token \gset
select public.create_invite(:'turn_estate'::uuid, 'turn-editor@example.com', 'editor') as turn_editor_token \gset

select set_config('request.jwt.claim.sub', 'e2222222-2222-2222-2222-222222222222', false);
select public.accept_invite(:'turn_reader_token');
select public._expect_forbidden(:'turn_estate'::uuid, '{"type":"take_turn"}'::jsonb, 'reader-turn');
select public._expect_forbidden(:'turn_estate'::uuid, '{"type":"set_clock","turn":3}'::jsonb, 'reader-clock');
select public.apply_command(
  :'turn_estate'::uuid,
  :turn_rev,
  'reader-anchor',
  '{"type":"set_calendar_anchor","turn":1,"month":"tarkesh","day":10}'::jsonb
)->>'revision' as turn_rev \gset

select public._assert(
  (select document#>>'{clock,anchor,month}' from public.estates where id = :'turn_estate'::uuid) = 'tarsakh'
  and (select (document#>>'{clock,turn}')::int from public.estates where id = :'turn_estate'::uuid) = 1
  and (select (document#>>'{finance,cashGp}')::int from public.estates where id = :'turn_estate'::uuid) = 40
  and (select document#>>'{audit,-1,actorRole}' from public.estates where id = :'turn_estate'::uuid) = 'reader'
  and (select document#>>'{audit,-1,actorEmail}' from public.estates where id = :'turn_estate'::uuid) = 'turn-reader@example.com'
  and (select document#>>'{audit,-1,type}' from public.estates where id = :'turn_estate'::uuid) = 'set_calendar_anchor',
  'reader_anchor'
);

select public.apply_command(
  :'turn_estate'::uuid,
  :turn_rev,
  'reader-reanchor',
  '{"type":"reanchor_calendar","turn":1,"month":"hammer","day":1,"reason":"The party lost time on the road."}'::jsonb
)->>'revision' as turn_rev \gset

select public._assert(
  (select document#>>'{clock,anchor,month}' from public.estates where id = :'turn_estate'::uuid) = 'hammer'
  and (select (document#>>'{clock,turn}')::int from public.estates where id = :'turn_estate'::uuid) = 1
  and (select document#>>'{audit,-1,actorRole}' from public.estates where id = :'turn_estate'::uuid) = 'reader'
  and (select document#>>'{audit,-1,actorEmail}' from public.estates where id = :'turn_estate'::uuid) = 'turn-reader@example.com'
  and (select document#>>'{audit,-1,reason}' from public.estates where id = :'turn_estate'::uuid) = 'The party lost time on the road.'
  and (select document#>>'{audit,-1,summary}' from public.estates where id = :'turn_estate'::uuid) like 'Re-anchored turn 1%',
  'reader_reanchor'
);

select set_config('request.jwt.claim.sub', 'e4444444-4444-4444-4444-444444444444', false);
select public._expect_forbidden(:'turn_estate'::uuid, '{"type":"set_calendar_anchor","turn":1,"month":"hammer","day":1}'::jsonb, 'stranger-anchor');
select public._expect_forbidden(:'turn_estate'::uuid, '{"type":"reanchor_calendar","turn":1,"month":"hammer","day":1,"reason":"No."}'::jsonb, 'stranger-reanchor');

reset role;
do $$
declare
  eid uuid;
begin
  select id into eid from public.estates where document->>'name' = 'Turn Hall' limit 1;
  execute 'set local role anon';
  begin
    perform public.apply_command(eid, null, 'anon-date', '{"type":"set_calendar_anchor","turn":1,"month":"hammer","day":1}'::jsonb);
    raise exception 'anon_set_date';
  exception
    when insufficient_privilege then
      null;
  end;
end $$;

set role authenticated;
select set_config('request.jwt.claim.sub', 'e3333333-3333-3333-3333-333333333333', false);
select public.accept_invite(:'turn_editor_token');
select public._expect_forbidden(:'turn_estate'::uuid, '{"type":"set_order_start","orderId":"missing","unknown":true}'::jsonb, 'editor-order-start');
reset role;
