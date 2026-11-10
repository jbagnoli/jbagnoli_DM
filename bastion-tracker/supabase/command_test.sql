\set ON_ERROR_STOP on

insert into auth.users (id, email) values
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'dm-practice@example.com'),
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'editor-practice@example.com'),
  ('cccccccc-cccc-cccc-cccc-cccccccccccc', 'reader-practice@example.com'),
  ('dddddddd-dddd-dddd-dddd-dddddddddddd', 'stranger-practice@example.com')
on conflict (id) do nothing;

create or replace function public._cmd_fail(message text)
returns void
language plpgsql
as $$
begin
  raise exception '%', message;
end;
$$;

create or replace function public._run_command_parity()
returns void
language plpgsql
as $$
declare
  eid uuid;
  other uuid;
  rev bigint;
  column_rev bigint;
  out jsonb;
  doc jsonb;
  before_rev bigint;
  barrack_id text;
  store_id text;
  garden_id text;
  storage_id text;
  lot_id text;
  loan_id text;
  basic_id text;
  wing_id text;
  library_id text;
  hire_id text;
  event_id text;
  armory_id text;
  drill uuid;
  drill_rev bigint;
  token text;
begin
  perform set_config('request.jwt.claim.sub', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', false);
  perform set_config('request.jwt.claim.role', 'authenticated', false);
  eid := public.create_estate('Hearthwatch Hold');
  select document, revision into doc, rev from public.estates where id = eid;
  if (doc#>>'{clock,cadenceDays}')::int <> 10 or doc#>>'{clock,ordinal}' is not null then
    perform public._cmd_fail('new estate is not a 10-day turn with an unknown day');
  end if;
  if rev <> 1 or (doc->>'revision')::int <> 1 then
    perform public._cmd_fail('new estate revision');
  end if;

  out := public.apply_command(eid, rev, 'imp-basic', '{"type":"import_accept","item":{"kind":"facility","facilityKind":"basic","roomId":"storage","space":"roomy"}}'::jsonb);
  rev := (out->>'revision')::bigint;
  doc := out->'document';
  if rev <> 2 or (doc->>'revision')::int <> rev or doc#>>'{facilities,0,acquired}' <> 'inherited' or (doc#>>'{finance,cashKnown}')::boolean then
    perform public._cmd_fail('inherited basic import');
  end if;
  out := public.apply_command(eid, rev, 'imp-special', '{"type":"import_accept","item":{"kind":"facility","catalogId":"barrack"}}'::jsonb);
  rev := (out->>'revision')::bigint;
  doc := out->'document';
  if doc#>>'{facilities,1,acquired}' <> 'inherited' or doc#>>'{facilities,1,name}' <> 'Barrack' then
    perform public._cmd_fail('inherited special import');
  end if;
  out := public.apply_command(eid, rev, 'imp-roster', '{"type":"import_accept","item":{"kind":"roster","person":{"name":"Bram Holt","category":"household","role":"Steward","unitId":"unit-party"}}}'::jsonb);
  rev := (out->>'revision')::bigint;
  doc := out->'document';
  if rev <> 4 or doc#>>'{roster,0,name}' <> 'Bram Holt' or (doc->>'revision')::int <> rev then
    perform public._cmd_fail('roster import revision');
  end if;

  before_rev := rev;
  begin
    perform public.apply_command(eid, rev, 'imp-loan', '{"type":"import_accept","item":{"kind":"loan"}}'::jsonb);
    perform public._cmd_fail('loan import was accepted');
  exception when invalid_parameter_value then
    if SQLERRM not like 'Turns, dates%' then raise; end if;
  end;
  begin
    perform public.apply_command(eid, rev, 'imp-date', '{"type":"import_accept","item":{"kind":"date"}}'::jsonb);
    perform public._cmd_fail('date import was accepted');
  exception when invalid_parameter_value then
    if SQLERRM not like 'Turns, dates%' then raise; end if;
  end;
  begin
    perform public.apply_command(eid, rev, 'imp-goods', '{"type":"import_accept","item":{"kind":"goods"}}'::jsonb);
    perform public._cmd_fail('goods import was accepted');
  exception when invalid_parameter_value then
    if SQLERRM not like 'Turns, dates%' then raise; end if;
  end;
  begin
    perform public.apply_command(eid, rev, 'imp-turn', '{"type":"import_accept","item":{"kind":"turn"}}'::jsonb);
    perform public._cmd_fail('turn import was accepted');
  exception when invalid_parameter_value then
    if SQLERRM not like 'Turns, dates%' then raise; end if;
  end;
  begin
    perform public.apply_command(eid, rev, 'imp-def', '{"type":"import_accept","item":{"kind":"defender"}}'::jsonb);
    perform public._cmd_fail('defender import was accepted');
  exception when invalid_parameter_value then
    if SQLERRM not like 'Turns, dates%' then raise; end if;
  end;
  select revision into column_rev from public.estates where id = eid;
  if column_rev <> before_rev then
    perform public._cmd_fail('refused import changed the revision');
  end if;
  begin
    perform public.apply_command(eid, 1, 'stale', '{"type":"set_clock","ordinal":3}'::jsonb);
    perform public._cmd_fail('stale revision was accepted');
  exception when serialization_failure then
    if SQLERRM not like '%revision_conflict%' then raise; end if;
  end;

  out := public.apply_command(eid, rev, 'clock', '{"type":"set_clock","ordinal":1,"label":"Practice day"}'::jsonb);
  rev := (out->>'revision')::bigint;
  out := public.apply_command(eid, rev, 'cash', '{"type":"set_finance","cashGp":8000}'::jsonb);
  rev := (out->>'revision')::bigint;
  out := public.apply_command(eid, rev, 'settings', '{"type":"set_settings","name":"Hearthwatch Hold","owner":"The company","unitId":"unit-party","cadenceDays":10}'::jsonb);
  rev := (out->>'revision')::bigint;
  doc := out->'document';
  if doc#>>'{units,0,owner}' <> 'The company' then
    perform public._cmd_fail('settings did not save the owner');
  end if;
  out := public.apply_command(eid, rev, 'caps', '{"type":"set_capabilities","unitId":"unit-party","capabilities":["arcane_or_tool","not_a_real_one"]}'::jsonb);
  rev := (out->>'revision')::bigint;
  doc := out->'document';
  if doc#>>'{units,0,capabilities,0}' <> 'arcane_or_tool' or jsonb_array_length(doc#>'{units,0,capabilities}') <> 1 then
    perform public._cmd_fail('capabilities');
  end if;
  out := public.apply_command(eid, rev, 'parlor', '{"type":"add_basic","unitId":"unit-party","roomId":"parlor","space":"cramped"}'::jsonb);
  rev := (out->>'revision')::bigint;
  doc := out->'document';
  if (doc#>>'{finance,cashGp}')::int <> 7500 or (doc#>>'{projects,0,days}')::int <> 20 then
    perform public._cmd_fail('paid basic room');
  end if;
  out := public.apply_command(eid, rev, 'store', '{"type":"add_special","unitId":"unit-party","catalogId":"storehouse"}'::jsonb);
  rev := (out->>'revision')::bigint;
  doc := out->'document';
  select elem->>'id' into store_id from jsonb_array_elements(doc->'facilities') elem where elem->>'catalogId' = 'storehouse' limit 1;
  out := public.apply_command(eid, rev, 'wool', '{"type":"record_goods","name":"Wool","standardGp":500,"unitId":"unit-party"}'::jsonb);
  rev := (out->>'revision')::bigint;
  doc := out->'document';
  select elem->>'id' into lot_id from jsonb_array_elements(doc->'goods') elem limit 1;
  out := public.apply_command(eid, rev, 'sell', jsonb_build_object(
    'type', 'commit_turn', 'unitId', 'unit-party', 'presence', 'present', 'mode', 'orders',
    'orders', jsonb_build_array(jsonb_build_object('facilityId', store_id, 'suborder', 'sell', 'lotId', lot_id, 'standardGp', 500))
  ));
  rev := (out->>'revision')::bigint;
  doc := out->'document';
  if (doc#>>'{finance,cashGp}')::int <> 7500 or (doc#>>'{tasks,0,proceeds}')::int <> 550 or (doc#>>'{tasks,0,dueOrdinal}')::int <> 8 then
    perform public._cmd_fail('sell preview');
  end if;
  out := public.apply_command(eid, rev, 'week', '{"type":"advance_days","days":7}'::jsonb);
  rev := (out->>'revision')::bigint;
  doc := out->'document';
  if (doc#>>'{finance,cashGp}')::int <> 8050 or (doc#>>'{clock,ordinal}')::int <> 8 then
    perform public._cmd_fail('sale settlement');
  end if;
  out := public.apply_command(eid, rev, 'build-days', '{"type":"advance_days","days":13}'::jsonb);
  rev := (out->>'revision')::bigint;
  doc := out->'document';
  if not exists (select 1 from jsonb_array_elements(doc->'facilities') elem where elem->>'name' = 'Parlor' and elem->>'acquired' = 'built') then
    perform public._cmd_fail('basic room did not finish');
  end if;

  out := public.apply_command(eid, rev, 'level6', '{"type":"raise_level","unitId":"unit-party","level":6}'::jsonb);
  rev := (out->>'revision')::bigint;
  doc := out->'document';
  if (doc#>>'{units,0,replacementBank}')::int <> 1 then
    perform public._cmd_fail('level up did not grant one replacement');
  end if;
  select elem->>'id' into barrack_id from jsonb_array_elements(doc->'facilities') elem where elem->>'catalogId' = 'barrack' and elem->>'status' = 'active' limit 1;
  out := public.apply_command(eid, rev, 'replace', jsonb_build_object('type', 'replace_special', 'unitId', 'unit-party', 'facilityId', barrack_id, 'catalogId', 'garden'));
  rev := (out->>'revision')::bigint;
  doc := out->'document';
  if (doc#>>'{units,0,replacementBank}')::int <> 0 or jsonb_array_length(doc->'archive') < 1 then
    perform public._cmd_fail('replacement');
  end if;
  out := public.apply_command(eid, rev, 'direct9', '{"type":"set_level","unitId":"unit-party","level":9,"grantReplacements":false}'::jsonb);
  rev := (out->>'revision')::bigint;
  doc := out->'document';
  if (doc#>>'{units,0,level}')::int <> 9 or (doc#>>'{units,0,replacementBank}')::int <> 0 then
    perform public._cmd_fail('direct level granted a replacement');
  end if;
  out := public.apply_command(eid, rev, 'library', '{"type":"add_special","unitId":"unit-party","catalogId":"library"}'::jsonb);
  rev := (out->>'revision')::bigint;
  doc := out->'document';
  select elem->>'id' into garden_id from jsonb_array_elements(doc->'facilities') elem where elem->>'catalogId' = 'garden' limit 1;
  out := public.apply_command(eid, rev, 'enlarge', jsonb_build_object('type', 'enlarge_special', 'facilityId', garden_id));
  rev := (out->>'revision')::bigint;
  doc := out->'document';
  if (doc#>>'{finance,cashGp}')::int <> 6050 then
    perform public._cmd_fail('enlarge price');
  end if;
  select elem->>'id' into storage_id from jsonb_array_elements(doc->'facilities') elem where elem->>'catalogId' = 'storage' limit 1;
  out := public.apply_command(eid, rev, 'upgrade', jsonb_build_object('type', 'upgrade_basic', 'facilityId', storage_id));
  rev := (out->>'revision')::bigint;
  out := public.apply_command(eid, rev, 'walls', '{"type":"add_wall_squares","squares":1}'::jsonb);
  rev := (out->>'revision')::bigint;
  doc := out->'document';
  if (doc#>>'{finance,cashGp}')::int <> 3800 then
    perform public._cmd_fail('wall and upgrade cost');
  end if;
  out := public.apply_command(eid, rev, 'wall-mark', '{"type":"mark_enclosure","complete":true,"reason":"The company walked the practice wall."}'::jsonb);
  rev := (out->>'revision')::bigint;
  out := public.apply_command(eid, rev, 'level13', '{"type":"set_level","unitId":"unit-party","level":13}'::jsonb);
  rev := (out->>'revision')::bigint;
  doc := out->'document';
  if (doc#>>'{units,0,replacementBank}')::int <> 0 then
    perform public._cmd_fail('second direct level granted a replacement');
  end if;
  out := public.apply_command(eid, rev, 'barrack2', '{"type":"add_special","unitId":"unit-party","catalogId":"barrack"}'::jsonb);
  rev := (out->>'revision')::bigint;
  doc := out->'document';
  select elem->>'id' into barrack_id from jsonb_array_elements(doc->'facilities') elem where elem->>'catalogId' = 'barrack' and elem->>'status' = 'active' limit 1;
  out := public.apply_command(eid, rev, 'recruit', jsonb_build_object(
    'type', 'commit_turn', 'unitId', 'unit-party', 'presence', 'present', 'mode', 'orders',
    'orders', jsonb_build_array(jsonb_build_object('facilityId', barrack_id, 'suborder', 'recruit', 'count', 1))
  ));
  rev := (out->>'revision')::bigint;
  before_rev := rev;
  out := public.apply_command(eid, rev, 'defenders', jsonb_build_object(
    'type', 'record_defenders', 'facilityId', barrack_id, 'count', 2, 'names', jsonb_build_array('Pell Ash', 'Sarn Wick')
  ));
  rev := (out->>'revision')::bigint;
  doc := out->'document';
  if (select count(*) from jsonb_array_elements(doc->'roster') elem where elem->>'category' = 'defender' and elem->>'status' = 'active') <> 2 then
    perform public._cmd_fail('defender count');
  end if;
  if jsonb_array_length(doc->'turns') <> (select jsonb_array_length(document->'turns') from public.estates where false) then
    null;
  end if;
  if rev <> before_rev + 1 then
    perform public._cmd_fail('defender command revision');
  end if;

  out := public.apply_command(eid, rev, 'loan', '{"type":"set_loan","creditor":"Mill at Northbridge","amountGp":250,"note":"Seed money"}'::jsonb);
  rev := (out->>'revision')::bigint;
  doc := out->'document';
  loan_id := doc#>>'{finance,loans,0,id}';
  if (doc#>>'{finance,cashGp}')::int <> 3800 or (doc#>>'{finance,loans,0,amountGp}')::int <> 250 then
    perform public._cmd_fail('loan changed cash or amount');
  end if;
  out := public.apply_command(eid, rev, 'loan-edit', jsonb_build_object('type', 'set_loan', 'loanId', loan_id, 'creditor', 'Mill at Northbridge', 'amountGp', 200, 'note', 'Seed money'));
  rev := (out->>'revision')::bigint;
  doc := out->'document';
  if (doc#>>'{finance,loans,0,amountGp}')::int <> 200 or jsonb_array_length(doc#>'{finance,loans}') <> 1 then
    perform public._cmd_fail('loan edit');
  end if;
  before_rev := (doc#>>'{finance,cashGp}')::int;
  out := public.apply_command(eid, rev, 'reserve', '{"type":"reserve_goods","name":"Timber","standardGp":500,"note":"Trade sell already underway","unitId":"unit-party"}'::jsonb);
  rev := (out->>'revision')::bigint;
  doc := out->'document';
  if (doc#>>'{finance,cashGp}')::int <> before_rev then
    perform public._cmd_fail('reserved goods changed cash');
  end if;
  if not exists (select 1 from jsonb_array_elements(doc->'goods') elem where elem->>'name' = 'Timber' and (elem->>'reservedGp')::int = 500) then
    perform public._cmd_fail('goods were not reserved');
  end if;
  out := public.apply_command(eid, rev, 'running', jsonb_build_object('type', 'record_order', 'facilityId', store_id, 'suborder', 'sell', 'startedTurn', 2, 'note', 'Already listed'));
  rev := (out->>'revision')::bigint;
  doc := out->'document';
  if not exists (
    select 1 from jsonb_array_elements(doc->'orders') elem
    where elem->>'facilityId' = store_id and elem->>'status' = 'in_progress' and coalesce((elem->>'recorded')::boolean, false) and (elem->>'startedDay')::int = 2 and elem->>'startedTurn' is null
  ) then
    perform public._cmd_fail('in-progress order');
  end if;
  if (doc#>>'{finance,cashGp}')::int <> before_rev then
    perform public._cmd_fail('recording an order moved cash');
  end if;

  out := public.apply_command(eid, rev, 'split', '{"type":"split_unit","name":"East wing","level":5,"acknowledgeNewCap":true}'::jsonb);
  rev := (out->>'revision')::bigint;
  doc := out->'document';
  select elem->>'id' into wing_id from jsonb_array_elements(doc->'units') elem where elem->>'name' = 'East wing' limit 1;
  if (select count(*) from jsonb_array_elements(doc->'facilities') elem where elem->>'unitId' = wing_id) <> 0 then
    perform public._cmd_fail('split copied rooms');
  end if;
  out := public.apply_command(eid, rev, 'wing-lib', jsonb_build_object('type', 'add_special', 'unitId', wing_id, 'catalogId', 'library'));
  rev := (out->>'revision')::bigint;
  doc := out->'document';
  select elem->>'id' into library_id from jsonb_array_elements(doc->'facilities') elem where elem->>'unitId' = wing_id and elem->>'catalogId' = 'library' limit 1;
  out := public.apply_command(eid, rev, 'research', jsonb_build_object(
    'type', 'commit_turn', 'unitId', wing_id, 'presence', 'present', 'mode', 'orders',
    'orders', jsonb_build_array(jsonb_build_object('facilityId', library_id, 'suborder', 'research'))
  ));
  rev := (out->>'revision')::bigint;
  doc := out->'document';
  if not exists (select 1 from jsonb_array_elements(doc->'tasks') elem where elem->>'auto' = 'manual' and elem->>'status' = 'open') then
    perform public._cmd_fail('research order');
  end if;
  out := public.apply_command(eid, rev, 'hire', '{"type":"roster_save","person":{"name":"Nell Cooper","category":"hireling","role":"Cook","unitId":"unit-party"}}'::jsonb);
  rev := (out->>'revision')::bigint;
  doc := out->'document';
  select elem->>'id' into hire_id from jsonb_array_elements(doc->'roster') elem where elem->>'name' = 'Nell Cooper' limit 1;
  out := public.apply_command(eid, rev, 'hire-gone', jsonb_build_object('type', 'roster_remove', 'personId', hire_id));
  rev := (out->>'revision')::bigint;
  out := public.apply_command(eid, rev, 'maintain', jsonb_build_object('type', 'commit_turn', 'unitId', wing_id, 'presence', 'present', 'mode', 'maintain'));
  rev := (out->>'revision')::bigint;
  doc := out->'document';
  select elem->>'id' into event_id from jsonb_array_elements(doc->'events') elem where elem->>'status' = 'pending' limit 1;
  out := public.apply_command(eid, rev, 'event', jsonb_build_object('type', 'resolve_event', 'eventId', event_id, 'roll', 10, 'detail', jsonb_build_object('note', 'Quiet')));
  rev := (out->>'revision')::bigint;
  doc := out->'document';
  if not exists (select 1 from jsonb_array_elements(doc->'events') elem where elem->>'id' = event_id and elem->>'type' = 'all_is_well' and elem->>'status' = 'resolved') then
    perform public._cmd_fail('event resolve');
  end if;
  out := public.apply_command(eid, rev, 'override', '{"type":"dm_override","reason":"Practice note","summary":"Noted a drill"}'::jsonb);
  rev := (out->>'revision')::bigint;
  out := public.apply_command(eid, rev, 'fall', jsonb_build_object('type', 'confirm_fall', 'unitId', wing_id, 'reason', 'The drill ended and the wing was given up.'));
  rev := (out->>'revision')::bigint;
  doc := out->'document';
  if not exists (select 1 from jsonb_array_elements(doc->'units') elem where elem->>'id' = wing_id and (elem->>'fallen')::boolean) then
    perform public._cmd_fail('fall');
  end if;
  before_rev := rev;
  out := public.apply_command(eid, rev, 'save', jsonb_build_object(
    'type', 'save_settings', 'name', 'Hearthwatch Hold', 'owner', 'The company', 'unitId', 'unit-party',
    'cadenceDays', 12, 'label', 'A spring day', 'ordinal', 30, 'level', 13, 'grantReplacements', false,
    'capabilities', jsonb_build_array('arcane_or_tool', 'holy_or_druid')
  ));
  rev := (out->>'revision')::bigint;
  doc := out->'document';
  if rev <> before_rev + 1 or (doc#>>'{clock,cadenceDays}')::int <> 12 or (doc#>>'{clock,ordinal}')::int <> 30
     or (doc#>>'{units,0,level}')::int <> 13 or (doc#>>'{units,0,replacementBank}')::int <> 0
     or jsonb_array_length(doc#>'{units,0,capabilities}') <> 2 then
    perform public._cmd_fail('atomic settings');
  end if;
  before_rev := rev;
  begin
    perform public.apply_command(eid, rev, 'save-bad', '{"type":"save_settings","name":"Renamed","unitId":"unit-party","level":1,"cadenceDays":3}'::jsonb);
    perform public._cmd_fail('illegal level was saved');
  exception when invalid_parameter_value then
    if SQLERRM not like 'Level 1 allows%' then raise; end if;
  end;
  select document, revision into doc, column_rev from public.estates where id = eid;
  if column_rev <> before_rev or doc->>'name' <> 'Hearthwatch Hold' or (doc#>>'{clock,cadenceDays}')::int <> 12 then
    perform public._cmd_fail('failed settings save changed the record');
  end if;
  out := public.apply_command(eid, rev, 'grant', '{"type":"set_level","unitId":"unit-party","level":14,"grantReplacements":true}'::jsonb);
  rev := (out->>'revision')::bigint;
  doc := out->'document';
  if (doc#>>'{units,0,replacementBank}')::int <> 1 then
    perform public._cmd_fail('explicit level-up did not grant one replacement');
  end if;

  perform set_config('request.jwt.claim.sub', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', false);
  token := public.create_invite(eid, 'editor-practice@example.com', 'editor');
  perform set_config('request.jwt.claim.sub', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', false);
  perform public.accept_invite(token);
  begin
    perform public.apply_command(eid, null, 'ed-import', '{"type":"import_accept","item":{"kind":"facility","facilityKind":"basic","roomId":"bedroom","space":"cramped"}}'::jsonb);
    perform public._cmd_fail('editor imported');
  exception when insufficient_privilege then null;
  end;
  begin
    perform public.apply_command(eid, null, 'ed-level', '{"type":"set_level","unitId":"unit-party","level":14}'::jsonb);
    perform public._cmd_fail('editor set the level');
  exception when insufficient_privilege then null;
  end;
  begin
    perform public.apply_command(eid, null, 'ed-def', jsonb_build_object('type', 'record_defenders', 'facilityId', barrack_id, 'count', 1));
    perform public._cmd_fail('editor recorded defenders');
  exception when insufficient_privilege then null;
  end;
  begin
    perform public.apply_command(eid, null, 'ed-loan', '{"type":"set_loan","creditor":"X","amountGp":1}'::jsonb);
    perform public._cmd_fail('editor recorded a loan');
  exception when insufficient_privilege then null;
  end;
  begin
    perform public.apply_command(eid, null, 'ed-goods', '{"type":"reserve_goods","name":"Salt","standardGp":10}'::jsonb);
    perform public._cmd_fail('editor reserved goods');
  exception when insufficient_privilege then null;
  end;
  begin
    perform public.apply_command(eid, null, 'ed-order', jsonb_build_object('type', 'record_order', 'facilityId', store_id, 'suborder', 'buy', 'startedTurn', 1));
    perform public._cmd_fail('editor recorded an order');
  exception when insufficient_privilege then null;
  end;
  begin
    perform public.apply_command(eid, null, 'ed-save', '{"type":"save_settings","unitId":"unit-party","level":14}'::jsonb);
    perform public._cmd_fail('editor saved settings');
  exception when insufficient_privilege then null;
  end;
  out := public.apply_command(eid, null, 'ed-room', '{"type":"add_basic","unitId":"unit-party","roomId":"bedroom","space":"cramped","inherited":true}'::jsonb);
  if out->'document' is null then
    perform public._cmd_fail('editor could not add an inherited room');
  end if;

  perform set_config('request.jwt.claim.sub', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', false);
  token := public.create_invite(eid, 'reader-practice@example.com', 'reader');
  perform set_config('request.jwt.claim.sub', 'cccccccc-cccc-cccc-cccc-cccccccccccc', false);
  perform public.accept_invite(token);
  begin
    perform public.apply_command(eid, null, 'reader-room', '{"type":"add_basic","unitId":"unit-party","roomId":"kitchen","space":"cramped","inherited":true}'::jsonb);
    perform public._cmd_fail('reader wrote');
  exception when insufficient_privilege then null;
  end;

  perform set_config('request.jwt.claim.sub', 'dddddddd-dddd-dddd-dddd-dddddddddddd', false);
  begin
    perform public.apply_command(eid, null, 'stranger', '{"type":"set_clock","ordinal":1}'::jsonb);
    perform public._cmd_fail('stranger wrote');
  exception when insufficient_privilege then null;
  end;

  perform set_config('request.jwt.claim.sub', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', false);
  drill := public.create_estate('Drill Yard');
  select revision into drill_rev from public.estates where id = drill;
  out := public.apply_command(drill, drill_rev, 'd-clock', '{"type":"set_clock","ordinal":1}'::jsonb);
  drill_rev := (out->>'revision')::bigint;
  out := public.apply_command(drill, drill_rev, 'd-cash', '{"type":"set_finance","cashGp":500}'::jsonb);
  drill_rev := (out->>'revision')::bigint;
  out := public.apply_command(drill, drill_rev, 'd-bar', '{"type":"add_special","unitId":"unit-party","catalogId":"barrack"}'::jsonb);
  drill_rev := (out->>'revision')::bigint;
  doc := out->'document';
  barrack_id := doc#>>'{facilities,0,id}';
  out := public.apply_command(drill, drill_rev, 'd-arm', '{"type":"add_special","unitId":"unit-party","catalogId":"armory"}'::jsonb);
  drill_rev := (out->>'revision')::bigint;
  doc := out->'document';
  select elem->>'id' into armory_id from jsonb_array_elements(doc->'facilities') elem where elem->>'catalogId' = 'armory' limit 1;
  out := public.apply_command(drill, drill_rev, 'd-rec', jsonb_build_object(
    'type', 'commit_turn', 'unitId', 'unit-party', 'presence', 'present', 'mode', 'orders',
    'orders', jsonb_build_array(jsonb_build_object('facilityId', barrack_id, 'suborder', 'recruit', 'count', 1))
  ));
  drill_rev := (out->>'revision')::bigint;
  out := public.apply_command(drill, drill_rev, 'd-stock', jsonb_build_object(
    'type', 'commit_turn', 'unitId', 'unit-party', 'presence', 'present', 'mode', 'orders',
    'orders', jsonb_build_array(jsonb_build_object('facilityId', armory_id, 'suborder', 'stock'))
  ));
  drill_rev := (out->>'revision')::bigint;
  out := public.apply_command(drill, drill_rev, 'd-wall', '{"type":"mark_enclosure","complete":true,"reason":"The drill wall was walked."}'::jsonb);
  drill_rev := (out->>'revision')::bigint;
  out := public.apply_command(drill, drill_rev, 'd-main', '{"type":"commit_turn","unitId":"unit-party","presence":"present","mode":"maintain"}'::jsonb);
  drill_rev := (out->>'revision')::bigint;
  doc := out->'document';
  select elem->>'id' into event_id from jsonb_array_elements(doc->'events') elem where elem->>'status' = 'pending' limit 1;
  out := public.apply_command(drill, drill_rev, 'd-attack', jsonb_build_object(
    'type', 'resolve_event', 'eventId', event_id, 'roll', 51,
    'detail', jsonb_build_object('rolls', jsonb_build_array(1, 1, 1, 1))
  ));
  doc := out->'document';
  if exists (select 1 from jsonb_array_elements(doc->'roster') elem where elem->>'category' = 'defender' and elem->>'status' = 'active') then
    perform public._cmd_fail('attack left a defender');
  end if;
  if exists (select 1 from jsonb_array_elements(doc->'facilities') elem where elem->>'catalogId' = 'armory' and coalesce((elem->>'stocked')::boolean, false)) then
    perform public._cmd_fail('armory stayed stocked');
  end if;
  if not exists (select 1 from jsonb_array_elements(doc->'facilities') elem where elem->>'status' = 'shutdown') then
    perform public._cmd_fail('attack did not shut a facility');
  end if;

  begin
    perform public.apply_command(eid, null, 'unknown-cmd', '{"type":"not_a_command"}'::jsonb);
    perform public._cmd_fail('unknown command was accepted');
  exception when feature_not_supported then
    if SQLERRM not like '%unsupported_on_server%' then raise; end if;
  end;
end;
$$;

set role authenticated;
select set_config('request.jwt.claim.sub', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', false);
select set_config('request.jwt.claim.role', 'authenticated', false);
select public._run_command_parity();

reset role;
do $$
declare
  eid uuid;
begin
  select id into eid from public.estates where document->>'name' = 'Hearthwatch Hold' limit 1;
  update public.estates
  set document = jsonb_set(document, '{clock,cadenceDays}', '7'::jsonb)
  where id = eid;
end $$;

set role authenticated;
select set_config('request.jwt.claim.sub', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', false);
select public.apply_command(
  (select id from public.estates where document->>'name' = 'Hearthwatch Hold' limit 1),
  null,
  'keep-cadence',
  '{"type":"set_clock","label":"Still the old turn length"}'::jsonb
)->>'revision' as kept_rev \gset

reset role;
do $$
declare
  cadence int;
begin
  select (document#>>'{clock,cadenceDays}')::int into cadence
  from public.estates where document->>'name' = 'Hearthwatch Hold';
  if cadence <> 7 then
    raise exception 'a later command rewrote an existing turn length';
  end if;
end $$;

reset role;
do $$
begin
  execute 'set local role anon';
  begin
    perform public.apply_command('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'::uuid, null, 'anon', '{"type":"set_clock","ordinal":1}'::jsonb);
    raise exception 'anon_could_write';
  exception
    when insufficient_privilege then
      null;
  end;
end $$;

reset role;
do $$
begin
  if (
    select count(*)
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname in ('empty_document', 'apply_command')
      and p.proconfig @> array['search_path=public']
  ) <> 2 then
    raise exception 'search_path is not pinned';
  end if;
end $$;
