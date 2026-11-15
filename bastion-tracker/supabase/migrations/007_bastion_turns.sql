-- Bastion turns are the only game-time unit.
--
-- Run this after 006_manage_rooms_people.sql. Do not run 001 through 006 again.
-- It does not change cash. It is safe to run once: a document already marked
-- turnsMigration 007 is left alone.
--
-- The old order field startedDay on ord-51 (and any similar order) kept the
-- number 30 from when the field was called startedTurn. That number is not the
-- Bastion turn. It is preserved as previousStartNumber and the start turn is
-- left unknown, with startNeedsCheck true, until someone sets it.
-- The old counter is copied onto clock.turn without dividing it. If that
-- number is not 3, clock.turnNeedsCheck is set and the number is not changed
-- to 3.

create or replace function public._bastion_migrate_turns(doc jsonb)
returns jsonb
language plpgsql
set search_path = public
as $$
declare
  clock jsonb;
  previous jsonb;
  orders jsonb := '[]'::jsonb;
  tasks jsonb := '[]'::jsonb;
  projects jsonb := '[]'::jsonb;
  squares jsonb := '[]'::jsonb;
  ledger jsonb := '[]'::jsonb;
  audit_rows jsonb := '[]'::jsonb;
  turn_rows jsonb := '[]'::jsonb;
  events jsonb := '[]'::jsonb;
  elem jsonb;
  detail jsonb;
  days_n int;
  needs_check boolean;
begin
  if coalesce(doc->>'turnsMigration', '') = '007' then
    return doc;
  end if;
  clock := coalesce(doc->'clock', '{}'::jsonb);
  if clock ? 'ordinal' then
    previous := clock->'ordinal';
  elsif clock ? 'turn' then
    previous := clock->'turn';
  else
    previous := 'null'::jsonb;
  end if;
  needs_check := previous = 'null'::jsonb or previous is null or coalesce(previous #>> '{}', '') is distinct from '3';
  clock := (clock - 'ordinal' - 'cadenceDays') || jsonb_build_object(
    'keptCounter', previous,
    'keptCadence', coalesce(clock->'cadenceDays', 'null'::jsonb),
    'turn', previous,
    'turnNeedsCheck', needs_check,
    'anchor', coalesce(clock->'anchor', 'null'::jsonb)
  );
  for elem in select value from jsonb_array_elements(coalesce(doc->'orders', '[]'::jsonb)) value loop
    if elem ? 'startedDay' then
      if coalesce(elem->>'startedDay', '') <> '' then
        elem := elem || jsonb_build_object('previousStartNumber', elem->'startedDay', 'startedTurn', null, 'startNeedsCheck', true);
      end if;
      elem := elem - 'startedDay';
    elsif coalesce(elem->>'startedTurn', '') <> '' and not (elem ? 'startNeedsCheck') then
      elem := elem || jsonb_build_object('previousStartNumber', elem->'startedTurn', 'startedTurn', null, 'startNeedsCheck', true);
    end if;
    orders := orders || jsonb_build_array(elem);
  end loop;
  for elem in select value from jsonb_array_elements(coalesce(doc->'tasks', '[]'::jsonb)) value loop
    if elem ? 'dueOrdinal' then
      elem := (elem - 'dueOrdinal' - 'startOrdinal' - 'days') || jsonb_build_object('previousDue', elem->'dueOrdinal', 'dueTurn', null, 'timerNeedsCheck', true);
    end if;
    tasks := tasks || jsonb_build_array(elem);
  end loop;
  for elem in select value from jsonb_array_elements(coalesce(doc->'projects', '[]'::jsonb)) value loop
    if elem ? 'dueOrdinal' or elem ? 'days' or elem ? 'startOrdinal' then
      elem := (elem - 'dueOrdinal' - 'startOrdinal' - 'days') || jsonb_build_object(
        'previousDue', elem->'dueOrdinal',
        'dueTurn', null,
        'timerNeedsCheck', true,
        'unscheduled', true
      );
    end if;
    projects := projects || jsonb_build_array(elem);
  end loop;
  for elem in select value from jsonb_array_elements(coalesce(doc#>'{walls,squares}', '[]'::jsonb)) value loop
    if elem ? 'dueOrdinal' then
      elem := (elem - 'dueOrdinal' - 'startOrdinal') || jsonb_build_object('previousDue', elem->'dueOrdinal', 'dueTurn', null, 'timerNeedsCheck', true, 'unscheduled', true);
    end if;
    squares := squares || jsonb_build_array(elem);
  end loop;
  for elem in select value from jsonb_array_elements(coalesce(doc->'ledger', '[]'::jsonb)) value loop
    if elem ? 'day' and not (elem ? 'turn') then
      elem := elem || jsonb_build_object('turn', elem->'day');
    end if;
    ledger := ledger || jsonb_build_array(elem - 'day');
  end loop;
  for elem in select value from jsonb_array_elements(coalesce(doc->'audit', '[]'::jsonb)) value loop
    if elem ? 'day' and not (elem ? 'turn') then
      elem := elem || jsonb_build_object('turn', elem->'day');
    end if;
    audit_rows := audit_rows || jsonb_build_array(elem - 'day');
  end loop;
  for elem in select value from jsonb_array_elements(coalesce(doc->'turns', '[]'::jsonb)) value loop
    if elem ? 'day' and not (elem ? 'turn') then
      elem := elem || jsonb_build_object('turn', elem->'day');
    end if;
    turn_rows := turn_rows || jsonb_build_array((elem - 'day') - 'cadenceDays');
  end loop;
  for elem in select value from jsonb_array_elements(coalesce(doc->'events', '[]'::jsonb)) value loop
    detail := coalesce(elem->'detail', '{}'::jsonb);
    if detail ? 'dueInDays' then
      if coalesce(detail->>'dueInDays', '') ~ '^-?[0-9]+$' and (detail->>'dueInDays')::int % 7 = 0 then
        days_n := (detail->>'dueInDays')::int / 7;
        detail := (detail - 'dueInDays') || jsonb_build_object('dueInTurns', days_n);
      else
        detail := (detail - 'dueInDays') || jsonb_build_object('previousDurationDays', detail->'dueInDays', 'dueInTurns', null, 'durationNeedsCheck', true);
      end if;
      elem := jsonb_set(elem, '{detail}', detail);
    end if;
    events := events || jsonb_build_array(elem);
  end loop;
  doc := jsonb_set(doc, '{clock}', clock);
  doc := jsonb_set(doc, '{orders}', orders);
  doc := jsonb_set(doc, '{tasks}', tasks);
  doc := jsonb_set(doc, '{projects}', projects);
  if doc #> '{walls,squares}' is not null then
    doc := jsonb_set(doc, '{walls,squares}', squares);
  end if;
  doc := jsonb_set(doc, '{ledger}', ledger);
  doc := jsonb_set(doc, '{audit}', audit_rows);
  doc := jsonb_set(doc, '{turns}', turn_rows);
  doc := jsonb_set(doc, '{events}', events);
  doc := doc || jsonb_build_object('turnsMigration', '007');
  return doc;
end;
$$;

update public.estates
set document = public._bastion_migrate_turns(document)
where coalesce(document->>'turnsMigration', '') <> '007';

create or replace function public._bastion_clock(doc jsonb)
returns int
language plpgsql
set search_path = public
as $$
begin
  if doc#>>'{clock,turn}' is null then
    raise exception 'Set the Bastion turn before starting something that takes turns. The session date can stay blank.'
      using errcode = '22023';
  end if;
  return (doc#>>'{clock,turn}')::int;
end;
$$;

create or replace function public._bastion_book_turns(book int)
returns int
language plpgsql
set search_path = public
as $$
begin
  if book is null then
    return null;
  end if;
  if book = 0 then
    return 0;
  end if;
  if book < 0 or book % 7 <> 0 then
    raise exception 'That duration is not a whole number of Bastion turns. It was not rounded.' using errcode = '22023';
  end if;
  return book / 7;
end;
$$;

create or replace function public._bastion_settle(doc jsonb, idem_key text)
returns jsonb
language plpgsql
set search_path = public
as $$
declare
  turn_n int;
  task jsonb;
  task_id text;
  lot jsonb;
  project jsonb;
  facility jsonb;
  square jsonb;
  facility_id text;
  good_id text;
begin
  turn_n := (doc#>>'{clock,turn}')::int;
  for task_id in
    select elem->>'id'
    from jsonb_array_elements(public._bastion_arr(doc, 'tasks')) elem
    where elem->>'status' = 'open'
      and elem->>'dueTurn' is not null
      and (elem->>'dueTurn')::int <= turn_n
  loop
    task := public._bastion_find(doc->'tasks', task_id);
    if task is null or task->>'status' is distinct from 'open' or coalesce((task->>'settled')::boolean, false) then
      continue;
    end if;
    if task->>'auto' = 'storehouse_sell' then
      doc := public._bastion_receive(doc, (task->>'proceeds')::int, 'Sold ' || (task->>'standardGp') || ' GP of goods', idem_key);
      task := task || jsonb_build_object('settled', true, 'status', 'resolved');
      doc := jsonb_set(doc, '{tasks}', public._bastion_replace(doc->'tasks', task->>'id', task));
      lot := public._bastion_find(doc->'goods', task->>'lotId');
      if lot is not null then
        lot := lot || jsonb_build_object(
          'standardGp', (lot->>'standardGp')::int - (task->>'standardGp')::int,
          'reservedGp', greatest(0, coalesce((lot->>'reservedGp')::int, 0) - (task->>'standardGp')::int)
        );
        if (lot->>'standardGp')::int <= 0 then
          lot := jsonb_set(lot, '{status}', '"sold"'::jsonb);
        end if;
        doc := jsonb_set(doc, '{goods}', public._bastion_replace(doc->'goods', lot->>'id', lot));
      end if;
    elsif task->>'auto' = 'storehouse_buy' then
      select taken.next_doc, taken.next_id into doc, good_id from public._bastion_take(doc, 'good') as taken;
      doc := jsonb_set(doc, '{goods}', public._bastion_arr(doc, 'goods') || jsonb_build_array(jsonb_build_object(
        'id', good_id,
        'name', coalesce(task->>'goodsName', 'Goods'),
        'standardGp', (task->>'standardGp')::int,
        'reservedGp', 0,
        'status', 'on_hand',
        'unitId', task->>'unitId'
      )));
      task := task || jsonb_build_object('settled', true, 'status', 'resolved');
      doc := jsonb_set(doc, '{tasks}', public._bastion_replace(doc->'tasks', task->>'id', task));
    else
      task := task || jsonb_build_object('status', 'ready');
      doc := jsonb_set(doc, '{tasks}', public._bastion_replace(doc->'tasks', task->>'id', task));
    end if;
  end loop;
  for project in
    select value from jsonb_array_elements(public._bastion_arr(doc, 'projects')) value
    where value->>'status' = 'building' and value->>'dueTurn' is not null and (value->>'dueTurn')::int <= turn_n
  loop
    project := public._bastion_find(doc->'projects', project->>'id');
    if project is null or project->>'status' is distinct from 'building' then
      continue;
    end if;
    project := jsonb_set(project, '{status}', '"done"'::jsonb);
    doc := jsonb_set(doc, '{projects}', public._bastion_replace(doc->'projects', project->>'id', project));
    if project->>'kind' = 'basic' then
      select taken.next_doc, taken.next_id into doc, facility_id from public._bastion_take(doc, 'fac') as taken;
      doc := jsonb_set(doc, '{facilities}', public._bastion_arr(doc, 'facilities') || jsonb_build_array(jsonb_build_object(
        'id', facility_id, 'unitId', project->>'unitId', 'kind', 'basic', 'catalogId', project->>'roomId',
        'name', project->>'name', 'space', project->>'space', 'status', 'active', 'acquired', 'built',
        'squares', public._bastion_squares(project->>'space')
      )));
    elsif project->>'kind' = 'upgrade' then
      facility := public._bastion_find(doc->'facilities', project->>'facilityId');
      if facility is not null then
        facility := facility || jsonb_build_object('space', project->>'space', 'status', 'active', 'squares', public._bastion_squares(project->>'space'));
        doc := public._bastion_put_facility(doc, facility);
      end if;
    end if;
  end loop;
  for square in
    select value from jsonb_array_elements(coalesce(doc#>'{walls,squares}', '[]'::jsonb)) value
    where value->>'status' = 'building' and value->>'dueTurn' is not null and (value->>'dueTurn')::int <= turn_n
  loop
    square := public._bastion_find(doc#>'{walls,squares}', square->>'id') || jsonb_build_object('status', 'built');
    doc := jsonb_set(doc, '{walls,squares}', public._bastion_replace(doc#>'{walls,squares}', square->>'id', square));
  end loop;
  return doc;
end;
$$;

create or replace function public._bastion_spend(doc jsonb, gp int, reason text, idem_key text)
returns jsonb
language plpgsql
set search_path = public
as $$
declare
  cash int;
  entry_id text;
begin
  if coalesce((doc#>>'{finance,cashKnown}')::boolean, false) is not true or doc#>>'{finance,cashGp}' is null then
    raise exception 'Cash is still unknown. Set an opening balance before any GP is spent or received. Unknown is not zero.'
      using errcode = '22023';
  end if;
  if gp < 0 then
    raise exception 'A payment cannot be negative.' using errcode = '22023';
  end if;
  cash := (doc#>>'{finance,cashGp}')::int;
  if cash < gp then
    raise exception 'That costs % GP and the recorded cash is % GP.', gp, cash using errcode = '22023';
  end if;
  doc := jsonb_set(doc, '{finance,cashGp}', to_jsonb(cash - gp));
  select taken.next_doc, taken.next_id into doc, entry_id from public._bastion_take(doc, 'led') as taken;
  doc := jsonb_set(doc, '{ledger}', public._bastion_arr(doc, 'ledger') || jsonb_build_array(jsonb_build_object(
    'id', entry_id, 'gp', -gp, 'reason', reason, 'turn', doc#>'{clock,turn}', 'key', to_jsonb(idem_key)
  )));
  return doc;
end;
$$;

create or replace function public._bastion_receive(doc jsonb, gp int, reason text, idem_key text)
returns jsonb
language plpgsql
set search_path = public
as $$
declare
  cash int;
  entry_id text;
begin
  if coalesce((doc#>>'{finance,cashKnown}')::boolean, false) is not true or doc#>>'{finance,cashGp}' is null then
    raise exception 'Cash is still unknown. Set an opening balance before any GP is spent or received. Unknown is not zero.'
      using errcode = '22023';
  end if;
  cash := coalesce((doc#>>'{finance,cashGp}')::int, 0) + gp;
  doc := jsonb_set(doc, '{finance,cashGp}', to_jsonb(cash));
  select taken.next_doc, taken.next_id into doc, entry_id from public._bastion_take(doc, 'led') as taken;
  doc := jsonb_set(doc, '{ledger}', public._bastion_arr(doc, 'ledger') || jsonb_build_array(jsonb_build_object(
    'id', entry_id, 'gp', gp, 'reason', reason, 'turn', doc#>'{clock,turn}', 'key', to_jsonb(idem_key)
  )));
  return doc;
end;
$$;

create or replace function public._bastion_cmd_settings(doc jsonb, command jsonb)
returns jsonb
language plpgsql
set search_path = public
as $$
declare
  unit jsonb;
begin
  if coalesce(command->>'name', '') <> '' then
    doc := jsonb_set(doc, '{name}', to_jsonb(left(command->>'name', 80)));
  end if;
  if coalesce(command->>'owner', '') <> '' or coalesce(command->>'unitName', '') <> '' then
    unit := public._bastion_unit(doc, coalesce(command->>'unitId', doc#>>'{units,0,id}'));
    if coalesce(command->>'unitName', '') <> '' then
      unit := jsonb_set(unit, '{name}', to_jsonb(left(command->>'unitName', 80)));
    end if;
    if coalesce(command->>'owner', '') <> '' then
      unit := jsonb_set(unit, '{owner}', to_jsonb(left(command->>'owner', 120)));
    end if;
    doc := public._bastion_put_unit(doc, unit);
  end if;
  return public._bastion_out(doc, jsonb_build_object('turn', doc#>'{clock,turn}'), 'Updated estate settings.');
end;
$$;

create or replace function public._bastion_set_turn(doc jsonb, command jsonb)
returns jsonb
language plpgsql
set search_path = public
as $$
declare
  turn_n int;
begin
  if command ? 'turn' then
    if command->'turn' = 'null'::jsonb or command->>'turn' is null or command->>'turn' = '' then
      doc := jsonb_set(doc, '{clock,turn}', 'null'::jsonb);
    else
      turn_n := public._bastion_whole(command->>'turn', 1, 2000000000, 'A Bastion turn is a whole number, starting at 1, or left unknown.');
      doc := jsonb_set(doc, '{clock,turn}', to_jsonb(turn_n));
    end if;
    doc := jsonb_set(doc, '{clock,turnNeedsCheck}', 'false'::jsonb);
  end if;
  return doc;
end;
$$;

create or replace function public._bastion_cmd_clock(doc jsonb, command jsonb)
returns jsonb
language plpgsql
set search_path = public
as $$
begin
  if command ? 'label' then
    doc := jsonb_set(doc, '{clock,label}', to_jsonb(left(coalesce(command->>'label', ''), 120)));
  end if;
  doc := public._bastion_set_turn(doc, command);
  return public._bastion_out(doc, jsonb_build_object('clock', doc->'clock'), 'Updated the Bastion turn and the session date.');
end;
$$;

create or replace function public._bastion_cmd_finance(doc jsonb, command jsonb)
returns jsonb
language plpgsql
set search_path = public
as $$
declare
  cash int;
  entry_id text;
begin
  if not command ? 'cashGp' or command->'cashGp' = 'null'::jsonb or command->>'cashGp' is null or command->>'cashGp' = '' then
    doc := jsonb_set(doc, '{finance,cashKnown}', 'false'::jsonb);
    doc := jsonb_set(doc, '{finance,cashGp}', 'null'::jsonb);
    return public._bastion_out(doc, jsonb_build_object('cashKnown', false), 'Cleared the cash balance back to unknown.');
  end if;
  cash := public._bastion_whole(command->>'cashGp', 0, 2000000000, 'Opening cash is a whole number of GP, or left unknown.');
  doc := jsonb_set(doc, '{finance,cashKnown}', 'true'::jsonb);
  doc := jsonb_set(doc, '{finance,cashGp}', to_jsonb(cash));
  select taken.next_doc, taken.next_id into doc, entry_id from public._bastion_take(doc, 'led') as taken;
  doc := jsonb_set(doc, '{ledger}', public._bastion_arr(doc, 'ledger') || jsonb_build_array(jsonb_build_object(
    'id', entry_id, 'gp', 0, 'reason', 'Opening cash set to ' || cash || ' GP', 'turn', doc#>'{clock,turn}', 'key', command->'idempotencyKey'
  )));
  return public._bastion_out(doc, jsonb_build_object('cashGp', cash), format('Set opening cash to %s GP.', cash));
end;
$$;

create or replace function public._bastion_cmd_save(doc jsonb, command jsonb)
returns jsonb
language plpgsql
set search_path = public
as $$
declare
  unit jsonb;
  level int;
  note text := 'Level unchanged. No replacement was added.';
  caps jsonb;
begin
  if coalesce(command->>'name', '') <> '' then
    doc := jsonb_set(doc, '{name}', to_jsonb(left(command->>'name', 80)));
  end if;
  unit := public._bastion_unit(doc, coalesce(command->>'unitId', doc#>>'{units,0,id}'));
  if coalesce(command->>'unitName', '') <> '' then
    unit := jsonb_set(unit, '{name}', to_jsonb(left(command->>'unitName', 80)));
  end if;
  if coalesce(command->>'owner', '') <> '' then
    unit := jsonb_set(unit, '{owner}', to_jsonb(left(command->>'owner', 120)));
  end if;
  if command ? 'label' then
    doc := jsonb_set(doc, '{clock,label}', to_jsonb(left(coalesce(command->>'label', ''), 120)));
  end if;
  doc := public._bastion_set_turn(doc, command);
  if command ? 'level' and coalesce(command->>'level', '') <> '' then
    level := public._bastion_whole(command->>'level', 1, 20, 'Choose a level from 1 to 20.');
    select applied.next_unit, applied.note into unit, note
    from public._bastion_apply_level(doc, unit, level, public._bastion_flag(command->'grantReplacements')) as applied;
  end if;
  if command ? 'capabilities' and jsonb_typeof(command->'capabilities') = 'array' then
    caps := public._bastion_filter_caps(command->'capabilities');
    unit := jsonb_set(unit, '{capabilities}', caps);
  end if;
  doc := public._bastion_put_unit(doc, unit);
  return public._bastion_out(
    doc,
    jsonb_build_object('turn', doc#>'{clock,turn}', 'level', (unit->>'level')::int, 'bank', (unit->>'replacementBank')::int),
    'Saved settings. ' || note
  );
end;
$$;

create or replace function public._bastion_cmd_add_basic(doc jsonb, command jsonb)
returns jsonb
language plpgsql
set search_path = public
as $$
declare
  unit jsonb;
  space text;
  build jsonb;
  room_name text;
  facility_id text;
  project_id text;
  free_one boolean;
begin
  unit := public._bastion_unit(doc, command->>'unitId');
  space := command->>'space';
  build := public._bastion_catalog()->'build'->space;
  if build is null then
    raise exception 'Choose cramped, roomy, or vast.' using errcode = '22023';
  end if;
  room_name := public._bastion_catalog()#>>array['rooms', command->>'roomId'];
  if room_name is null then
    raise exception 'Choose a basic room from the list.' using errcode = '22023';
  end if;
  free_one := public._bastion_flag(command->'inherited') or public._bastion_flag(command->'starter');
  if free_one then
    select taken.next_doc, taken.next_id into doc, facility_id from public._bastion_take(doc, 'fac') as taken;
    doc := jsonb_set(doc, '{facilities}', public._bastion_arr(doc, 'facilities') || jsonb_build_array(jsonb_build_object(
      'id', facility_id, 'unitId', unit->>'id', 'kind', 'basic', 'catalogId', command->>'roomId', 'name', room_name,
      'space', space, 'status', 'active',
      'acquired', case when public._bastion_flag(command->'inherited') then 'inherited' else 'starter' end,
      'squares', public._bastion_squares(space)
    )));
    return public._bastion_out(doc, jsonb_build_object('facilityId', facility_id, 'charged', 0), format('Added %s with no charge.', room_name));
  end if;
  doc := public._bastion_spend(doc, (build->>'gp')::int, 'Build ' || room_name, command->>'idempotencyKey');
  select taken.next_doc, taken.next_id into doc, project_id from public._bastion_take(doc, 'proj') as taken;
  doc := jsonb_set(doc, '{projects}', public._bastion_arr(doc, 'projects') || jsonb_build_array(jsonb_build_object(
    'id', project_id, 'unitId', unit->>'id', 'kind', 'basic', 'roomId', command->>'roomId', 'name', room_name,
    'space', space, 'gp', (build->>'gp')::int, 'unscheduled', true, 'dueTurn', null, 'startedTurn', doc#>'{clock,turn}', 'status', 'building'
  )));
  return public._bastion_out(
    doc,
    jsonb_build_object('projectId', project_id, 'dueTurn', null, 'charged', (build->>'gp')::int),
    format('%s costs %s GP. The published build time is not a whole number of Bastion turns, so no finish turn was scheduled.', room_name, (build->>'gp')::int)
  );
end;
$$;

create or replace function public._bastion_cmd_upgrade(doc jsonb, command jsonb)
returns jsonb
language plpgsql
set search_path = public
as $$
declare
  facility jsonb;
  step jsonb;
  project_id text;
begin
  facility := public._bastion_facility(doc, command->>'facilityId');
  if facility->>'kind' is distinct from 'basic' then
    raise exception 'Only basic rooms use this enlargement.' using errcode = '22023';
  end if;
  step := public._bastion_catalog()->'upgrade'->(facility->>'space');
  if step is null then
    raise exception 'This room is already vast.' using errcode = '22023';
  end if;
  doc := public._bastion_spend(doc, (step->>'gp')::int, 'Enlarge ' || (facility->>'name'), command->>'idempotencyKey');
  facility := facility || jsonb_build_object('status', 'building');
  doc := public._bastion_put_facility(doc, facility);
  select taken.next_doc, taken.next_id into doc, project_id from public._bastion_take(doc, 'proj') as taken;
  doc := jsonb_set(doc, '{projects}', public._bastion_arr(doc, 'projects') || jsonb_build_array(jsonb_build_object(
    'id', project_id, 'unitId', facility->>'unitId', 'kind', 'upgrade', 'facilityId', facility->>'id', 'name', facility->>'name',
    'from', facility->>'space', 'space', step->>'to', 'gp', (step->>'gp')::int, 'unscheduled', true, 'dueTurn', null,
    'startedTurn', doc#>'{clock,turn}', 'status', 'building'
  )));
  return public._bastion_out(doc, jsonb_build_object('projectId', project_id, 'dueTurn', null), format('%s is enlarging. The published time is not a whole number of Bastion turns, so no finish turn was scheduled.', facility->>'name'));
end;
$$;

create or replace function public._bastion_cmd_walls(doc jsonb, command jsonb)
returns jsonb
language plpgsql
set search_path = public
as $$
declare
  count_n int;
  gp int;
  i int;
  wall_id text;
  ids jsonb := '[]'::jsonb;
begin
  count_n := public._bastion_whole(command->>'squares', 1, 200, 'Enter how many 5-foot squares to start.');
  gp := (public._bastion_catalog()#>>'{wall,gp}')::int * count_n;
  doc := public._bastion_spend(doc, gp, 'Wall squares ×' || count_n, command->>'idempotencyKey');
  for i in 1..count_n loop
    select taken.next_doc, taken.next_id into doc, wall_id from public._bastion_take(doc, 'wall') as taken;
    doc := jsonb_set(doc, '{walls,squares}', coalesce(doc#>'{walls,squares}', '[]'::jsonb) || jsonb_build_array(jsonb_build_object(
      'id', wall_id, 'status', 'building', 'unscheduled', true, 'dueTurn', null, 'startedTurn', doc#>'{clock,turn}',
      'gp', (public._bastion_catalog()#>>'{wall,gp}')::int
    )));
    ids := ids || jsonb_build_array(wall_id);
  end loop;
  return public._bastion_out(
    doc,
    jsonb_build_object('ids', ids, 'dueTurn', null, 'charged', gp),
    format('%s wall squares are paid for. The published time is not a whole number of Bastion turns, so no finish turn was scheduled. The enclosure is still not marked complete.', count_n)
  );
end;
$$;

create or replace function public._bastion_cmd_take_turn(doc jsonb, command jsonb)
returns jsonb
language plpgsql
set search_path = public
as $$
declare
  turn_n int;
begin
  turn_n := public._bastion_clock(doc) + 1;
  doc := jsonb_set(doc, '{clock,turn}', to_jsonb(turn_n));
  doc := public._bastion_settle(doc, command->>'idempotencyKey');
  return public._bastion_out(doc, jsonb_build_object('turn', turn_n), format('Advanced to Bastion turn %s.', turn_n));
end;
$$;

create or replace function public._bastion_cmd_finish_project(doc jsonb, command jsonb)
returns jsonb
language plpgsql
set search_path = public
as $$
declare
  project jsonb;
  facility jsonb;
  facility_id text;
begin
  project := public._bastion_find(doc->'projects', command->>'projectId');
  if project is null or project->>'status' is distinct from 'building' then
    raise exception 'That build is not still in progress.' using errcode = '22023';
  end if;
  project := jsonb_set(project, '{status}', '"done"'::jsonb);
  doc := jsonb_set(doc, '{projects}', public._bastion_replace(doc->'projects', project->>'id', project));
  if project->>'kind' = 'basic' then
    select taken.next_doc, taken.next_id into doc, facility_id from public._bastion_take(doc, 'fac') as taken;
    doc := jsonb_set(doc, '{facilities}', public._bastion_arr(doc, 'facilities') || jsonb_build_array(jsonb_build_object(
      'id', facility_id, 'unitId', project->>'unitId', 'kind', 'basic', 'catalogId', project->>'roomId',
      'name', project->>'name', 'space', project->>'space', 'status', 'active', 'acquired', 'built',
      'squares', public._bastion_squares(project->>'space')
    )));
  elsif project->>'kind' = 'upgrade' then
    facility := public._bastion_find(doc->'facilities', project->>'facilityId');
    if facility is not null then
      facility := facility || jsonb_build_object('space', project->>'space', 'status', 'active', 'squares', public._bastion_squares(project->>'space'));
      doc := public._bastion_put_facility(doc, facility);
    end if;
  end if;
  return public._bastion_out(doc, jsonb_build_object('projectId', project->>'id', 'finished', true), format('Marked %s finished. No book duration was turned into a Bastion turn.', project->>'name'));
end;
$$;

create or replace function public._bastion_cmd_set_due_turn(doc jsonb, command jsonb)
returns jsonb
language plpgsql
set search_path = public
as $$
declare
  task jsonb;
  due int;
begin
  task := public._bastion_find(doc->'tasks', command->>'taskId');
  if task is null then
    raise exception 'That timer is not on the record.' using errcode = '22023';
  end if;
  due := public._bastion_whole(command->>'dueTurn', 1, 2000000000, 'A Bastion turn is a whole number, starting at 1, or left unknown.');
  task := task || jsonb_build_object('dueTurn', due, 'timerNeedsCheck', false);
  doc := jsonb_set(doc, '{tasks}', public._bastion_replace(doc->'tasks', task->>'id', task));
  return public._bastion_out(doc, jsonb_build_object('taskId', task->>'id', 'dueTurn', due), format('Set that work to finish on Bastion turn %s.', due));
end;
$$;

create or replace function public._bastion_cmd_set_order_start(doc jsonb, command jsonb)
returns jsonb
language plpgsql
set search_path = public
as $$
declare
  order_row jsonb;
  started int;
begin
  order_row := public._bastion_find(doc->'orders', command->>'orderId');
  if order_row is null then
    raise exception 'That order is not on the record.' using errcode = '22023';
  end if;
  if public._bastion_flag(command->'unknown') then
    order_row := order_row || jsonb_build_object('startedTurn', null, 'startNeedsCheck', false);
    doc := jsonb_set(doc, '{orders}', public._bastion_replace(doc->'orders', order_row->>'id', order_row));
    return public._bastion_out(doc, jsonb_build_object('orderId', order_row->>'id', 'startedTurn', null), format('Left the start of %s unknown. The old stored number was not used.', coalesce(order_row->>'label', order_row->>'id')));
  end if;
  started := public._bastion_whole(command->>'startedTurn', 1, 2000000000, 'A Bastion turn is a whole number, starting at 1, or left unknown.');
  if doc#>>'{clock,turn}' is not null and started > (doc#>>'{clock,turn}')::int then
    raise exception 'That Bastion turn is later than the current turn.' using errcode = '22023';
  end if;
  order_row := order_row || jsonb_build_object('startedTurn', started, 'startNeedsCheck', false);
  doc := jsonb_set(doc, '{orders}', public._bastion_replace(doc->'orders', order_row->>'id', order_row));
  return public._bastion_out(doc, jsonb_build_object('orderId', order_row->>'id', 'startedTurn', started), format('Set the start of %s to Bastion turn %s.', coalesce(order_row->>'label', order_row->>'id'), started));
end;
$$;

create or replace function public._bastion_cmd_record_order(doc jsonb, command jsonb)
returns jsonb
language plpgsql
set search_path = public
as $$
declare
  facility jsonb;
  spec jsonb;
  sub jsonb;
  started int;
  note text;
  existing jsonb;
  order_row jsonb;
  order_id text;
begin
  facility := public._bastion_facility(doc, command->>'facilityId');
  if facility->>'kind' is distinct from 'special' then
    raise exception 'Basic rooms do not take orders.' using errcode = '22023';
  end if;
  spec := public._bastion_spec(facility->>'catalogId');
  select elem into sub from jsonb_array_elements(coalesce(spec->'subs', '[]'::jsonb)) elem where elem->>'id' = command->>'suborder' limit 1;
  if sub is null then
    raise exception '% cannot take that order.', facility->>'name' using errcode = '22023';
  end if;
  if command ? 'startedTurn' and command->'startedTurn' is distinct from 'null'::jsonb and coalesce(command->>'startedTurn', '') <> '' then
    started := public._bastion_whole(command->>'startedTurn', 1, 2000000000, 'A Bastion turn is a whole number, starting at 1, or left unknown.');
    if doc#>>'{clock,turn}' is not null and started > (doc#>>'{clock,turn}')::int then
      raise exception 'That Bastion turn is later than the current turn.' using errcode = '22023';
    end if;
  else
    started := null;
  end if;
  note := left(coalesce(command->>'note', ''), 240);
  select elem into existing
  from jsonb_array_elements(public._bastion_arr(doc, 'orders')) elem
  where elem->>'facilityId' = facility->>'id' and elem->>'status' = 'in_progress' and coalesce((elem->>'recorded')::boolean, false)
  limit 1;
  if existing is null then
    select taken.next_doc, taken.next_id into doc, order_id from public._bastion_take(doc, 'ord') as taken;
    order_row := jsonb_build_object('id', order_id, 'facilityId', facility->>'id', 'unitId', facility->>'unitId', 'recorded', true);
  else
    order_row := existing;
    order_id := existing->>'id';
  end if;
  order_row := (order_row - 'startedDay') || jsonb_build_object(
    'suborder', sub->>'id', 'label', sub->>'label', 'status', 'in_progress',
    'startedTurn', to_jsonb(started), 'startNeedsCheck', false, 'note', note, 'auto', null, 'recorded', true
  );
  if existing is null then
    doc := jsonb_set(doc, '{orders}', public._bastion_arr(doc, 'orders') || jsonb_build_array(order_row));
  else
    doc := jsonb_set(doc, '{orders}', public._bastion_replace(doc->'orders', order_id, order_row));
  end if;
  facility := facility || jsonb_build_object('currentOrderId', order_id);
  doc := public._bastion_put_facility(doc, facility);
  return public._bastion_out(doc, jsonb_build_object('orderId', order_id, 'startedTurn', to_jsonb(started)), format('Marked %s as already running %s. No turn was resolved and no money moved.', facility->>'name', sub->>'label'));
end;
$$;

create or replace function public._bastion_store_anchor(doc jsonb, command jsonb)
returns jsonb
language plpgsql
set search_path = public
as $$
declare
  turn_n int;
  month text;
  festival text;
  day_n int;
  year_n int;
  anchor jsonb;
begin
  turn_n := public._bastion_whole(command->>'turn', 1, 2000000000, 'The anchor names a Bastion turn, starting at 1.');
  month := lower(btrim(coalesce(command->>'month', '')));
  if month = 'tarkesh' then month := 'tarsakh'; end if;
  festival := lower(btrim(coalesce(command->>'festival', '')));
  if festival <> '' and festival not in ('midwinter', 'greengrass', 'midsummer', 'shieldmeet', 'highharvestide') then
    raise exception 'Choose a Harptos month or festival.' using errcode = '22023';
  end if;
  if command ? 'year' and command->'year' is distinct from 'null'::jsonb and coalesce(command->>'year', '') <> '' then
    year_n := public._bastion_whole(command->>'year', 1, 100000, 'The year is a whole number, or left blank.');
  else
    year_n := null;
  end if;
  if festival <> '' then
    if festival = 'shieldmeet' and year_n is null then
      raise exception 'Shieldmeet needs a year, because it falls only when that year has one.' using errcode = '22023';
    end if;
    anchor := jsonb_build_object('turn', turn_n, 'festival', festival, 'month', null, 'day', null, 'year', to_jsonb(year_n));
  else
    if month not in ('hammer', 'alturiak', 'ches', 'tarsakh', 'mirtul', 'kythorn', 'flamerule', 'eleasis', 'eleint', 'marpenoth', 'uktar', 'nightal') then
      raise exception 'Choose a Harptos month or festival.' using errcode = '22023';
    end if;
    day_n := public._bastion_whole(command->>'day', 1, 30, 'A month date is a whole number from 1 to 30.');
    anchor := jsonb_build_object('turn', turn_n, 'festival', null, 'month', month, 'day', day_n, 'year', to_jsonb(year_n));
  end if;
  doc := jsonb_set(doc, '{clock,anchor}', anchor);
  return doc;
end;
$$;

create or replace function public._bastion_cmd_anchor(doc jsonb, command jsonb)
returns jsonb
language plpgsql
set search_path = public
as $$
declare
  label text;
begin
  doc := public._bastion_store_anchor(doc, command);
  label := case
    when coalesce(doc#>>'{clock,anchor,festival}', '') <> '' then initcap(doc#>>'{clock,anchor,festival}')
    else (doc#>>'{clock,anchor,day}') || ' ' || initcap(doc#>>'{clock,anchor,month}')
  end;
  if doc#>>'{clock,anchor,year}' is not null then
    label := label || ', ' || (doc#>>'{clock,anchor,year}') || ' DR';
  end if;
  return public._bastion_out(doc, jsonb_build_object('anchor', doc->'clock'->'anchor', 'text', label), format('Set the calendar anchor: turn %s is %s. Later turns follow it. The turn counter was not changed.', doc#>>'{clock,anchor,turn}', label));
end;
$$;

create or replace function public._bastion_cmd_reanchor(doc jsonb, command jsonb)
returns jsonb
language plpgsql
set search_path = public
as $$
declare
  label text;
  reason text;
begin
  if doc#>>'{clock,turn}' is null then
    raise exception 'Set the Bastion turn before starting something that takes turns. The session date can stay blank.' using errcode = '22023';
  end if;
  if command->>'turn' is distinct from doc#>>'{clock,turn}' then
    raise exception 'A date override re-anchors the current Bastion turn. It does not create a second counter.' using errcode = '22023';
  end if;
  reason := btrim(coalesce(command->>'reason', ''));
  if reason = '' then
    raise exception 'Say why this turn''s date differs from the one derived so far.' using errcode = '22023';
  end if;
  doc := public._bastion_store_anchor(doc, command);
  label := case
    when coalesce(doc#>>'{clock,anchor,festival}', '') <> '' then initcap(doc#>>'{clock,anchor,festival}')
    else (doc#>>'{clock,anchor,day}') || ' ' || initcap(doc#>>'{clock,anchor,month}')
  end;
  return public._bastion_out(doc, jsonb_build_object('anchor', doc->'clock'->'anchor', 'text', label), format('Re-anchored turn %s to %s. Later turns follow this date. %s', doc#>>'{clock,turn}', label, reason));
end;
$$;

create or replace function public._bastion_place(doc jsonb, command jsonb, unit jsonb, turn_id text, request jsonb, out next_doc jsonb, out order_row jsonb)
language plpgsql
set search_path = public
as $$
declare
  facility jsonb;
  spec jsonb;
  sub jsonb;
  order_id text;
  count_n int;
  housed int;
  room int;
  i int;
  person_id text;
  person jsonb;
  standard_gp int;
  available int;
  proceeds int;
  limit_gp int;
  lot jsonb;
  task_id text;
  due int;
  defenders int;
  cost int;
  has_smithy boolean;
  lieutenants int;
  days_known boolean := false;
  days int;
  gp int;
  ordinal int;
begin
  next_doc := doc;
  facility := public._bastion_facility(next_doc, request->>'facilityId');
  if facility->>'unitId' is distinct from unit->>'id' then
    raise exception 'An order can only go to this owner''s facility.' using errcode = '22023';
  end if;
  if facility->>'kind' is distinct from 'special' then
    raise exception 'Basic rooms do not take orders.' using errcode = '22023';
  end if;
  if facility->>'blockedOnTurnId' = turn_id or facility->>'status' = 'shutdown' then
    raise exception '% is shut for this turn.', facility->>'name' using errcode = '22023';
  end if;
  spec := public._bastion_spec(facility->>'catalogId');
  if spec is null then
    raise exception '% cannot take that order.', facility->>'name' using errcode = '22023';
  end if;
  select elem into sub from jsonb_array_elements(spec->'subs') elem where elem->>'id' = request->>'suborder' limit 1;
  if sub is null then
    raise exception '% cannot take that order.', facility->>'name' using errcode = '22023';
  end if;
  if sub->>'id' = 'craft_magic' and (unit->>'level')::int < 9 then
    raise exception 'Magic-item crafting from this facility waits until level 9.' using errcode = '22023';
  end if;
  select taken.next_doc, taken.next_id into next_doc, order_id from public._bastion_take(next_doc, 'ord') as taken;
  order_row := jsonb_build_object(
    'id', order_id,
    'turnId', turn_id,
    'unitId', unit->>'id',
    'facilityId', facility->>'id',
    'suborder', sub->>'id',
    'label', sub->>'label',
    'status', 'committed',
    'auto', sub->>'auto'
  );
  if sub->>'auto' = 'barrack_recruit' then
    housed := (
      select count(*) from jsonb_array_elements(public._bastion_arr(next_doc, 'roster')) elem
      where elem->>'facilityId' = facility->>'id' and elem->>'category' = 'defender' and elem->>'status' = 'active'
    );
    room := (case when facility->>'space' = 'vast' then 25 else 12 end) - housed;
    if room <= 0 then
      raise exception 'This barrack is full, so it cannot recruit.' using errcode = '22023';
    end if;
    if request->>'count' is null or request->>'count' !~ '^[0-9]+$' then
      raise exception 'Recruit 1 to 4 defenders.' using errcode = '22023';
    end if;
    count_n := (request->>'count')::int;
    if count_n < 1 or count_n > 4 then
      raise exception 'Recruit 1 to 4 defenders.' using errcode = '22023';
    end if;
    if count_n > room then
      raise exception 'This barrack has room for % more, not %.', room, count_n using errcode = '22023';
    end if;
    for i in 1..count_n loop
      select taken.next_doc, taken.next_id into next_doc, person_id from public._bastion_take(next_doc, 'npc') as taken;
      person := jsonb_build_object(
        'id', person_id,
        'name', 'Defender ' || (jsonb_array_length(public._bastion_arr(next_doc, 'roster')) + 1),
        'category', 'defender',
        'summary', '',
        'role', 'Defender',
        'link', '',
        'unitId', unit->>'id',
        'facilityId', facility->>'id',
        'status', 'active',
        'housed', true,
        'protectsOnce', false
      );
      next_doc := jsonb_set(next_doc, '{roster}', public._bastion_arr(next_doc, 'roster') || jsonb_build_array(person));
    end loop;
    order_row := order_row || jsonb_build_object('status', 'resolved', 'result', jsonb_build_object('recruited', count_n, 'housed', housed + count_n));
  elsif sub->>'auto' = 'storehouse_buy' then
    limit_gp := public._bastion_buy_limit((unit->>'level')::int);
    standard_gp := public._bastion_whole(request->>'standardGp', 1, limit_gp, format('This level can buy up to %s GP of goods in one order.', limit_gp));
    next_doc := public._bastion_spend(next_doc, standard_gp, 'Storehouse purchase of ' || standard_gp || ' GP', command->>'idempotencyKey');
    due := public._bastion_clock(next_doc) + 1;
    select taken.next_doc, taken.next_id into next_doc, task_id from public._bastion_take(next_doc, 'task') as taken;
    next_doc := jsonb_set(next_doc, '{tasks}', public._bastion_arr(next_doc, 'tasks') || jsonb_build_array(jsonb_build_object(
      'id', task_id, 'status', 'open', 'settled', false, 'auto', 'storehouse_buy', 'unitId', unit->>'id',
      'orderId', order_id, 'goodsName', left(coalesce(nullif(request->>'goodsName', ''), 'Goods'), 80),
      'standardGp', standard_gp, 'dueTurn', due
    )));
    order_row := order_row || jsonb_build_object('taskId', task_id, 'dueTurn', due);
  elsif sub->>'auto' = 'storehouse_sell' then
    lot := public._bastion_find(next_doc->'goods', request->>'lotId');
    if lot is null or lot->>'status' is distinct from 'on_hand' then
      raise exception 'Choose goods that are still on hand.' using errcode = '22023';
    end if;
    available := (lot->>'standardGp')::int - coalesce((lot->>'reservedGp')::int, 0);
    if request ? 'standardGp' and coalesce(request->>'standardGp', '') <> '' then
      standard_gp := public._bastion_whole(request->>'standardGp', 1, 2000000000, 'Sell a list-price amount that is still free.');
    else
      standard_gp := available;
    end if;
    if standard_gp < 1 or standard_gp > available then
      raise exception 'Sell a list-price amount that is still free.' using errcode = '22023';
    end if;
    proceeds := public._bastion_proceeds(standard_gp, (unit->>'level')::int);
    lot := jsonb_set(lot, '{reservedGp}', to_jsonb(coalesce((lot->>'reservedGp')::int, 0) + standard_gp));
    next_doc := jsonb_set(next_doc, '{goods}', public._bastion_replace(next_doc->'goods', lot->>'id', lot));
    due := public._bastion_clock(next_doc) + 1;
    select taken.next_doc, taken.next_id into next_doc, task_id from public._bastion_take(next_doc, 'task') as taken;
    next_doc := jsonb_set(next_doc, '{tasks}', public._bastion_arr(next_doc, 'tasks') || jsonb_build_array(jsonb_build_object(
      'id', task_id, 'status', 'open', 'settled', false, 'auto', 'storehouse_sell', 'unitId', unit->>'id',
      'orderId', order_id, 'lotId', lot->>'id', 'standardGp', standard_gp, 'proceeds', proceeds, 'dueTurn', due
    )));
    order_row := order_row || jsonb_build_object('taskId', task_id, 'dueTurn', due, 'preview', jsonb_build_object('standardGp', standard_gp, 'proceeds', proceeds, 'turns', 1));
  elsif sub->>'auto' = 'armory_stock' then
    select count(*) into defenders from jsonb_array_elements(public._bastion_arr(next_doc, 'roster')) elem
      where elem->>'unitId' = unit->>'id' and elem->>'category' = 'defender' and elem->>'status' = 'active';
    select exists (
      select 1 from jsonb_array_elements(next_doc->'facilities') elem
      where elem->>'unitId' = unit->>'id' and elem->>'catalogId' = 'smithy' and elem->>'status' = 'active'
    ) into has_smithy;
    cost := 100 + 100 * defenders;
    if has_smithy then cost := cost / 2; end if;
    next_doc := public._bastion_spend(next_doc, cost, 'Stocked the armory', command->>'idempotencyKey');
    facility := public._bastion_facility(next_doc, facility->>'id') || jsonb_build_object('stocked', true);
    next_doc := public._bastion_put_facility(next_doc, facility);
    order_row := order_row || jsonb_build_object('status', 'resolved', 'result', jsonb_build_object('cost', cost, 'defenders', defenders, 'halved', has_smithy));
  elsif sub->>'auto' = 'war_lieutenant' then
    select count(*) into lieutenants from jsonb_array_elements(public._bastion_arr(next_doc, 'roster')) elem
      where elem->>'unitId' = unit->>'id' and elem->>'category' = 'lieutenant' and elem->>'status' = 'active';
    if lieutenants >= 10 then
      raise exception 'This war room already has 10 lieutenants.' using errcode = '22023';
    end if;
    select taken.next_doc, taken.next_id into next_doc, person_id from public._bastion_take(next_doc, 'npc') as taken;
    next_doc := jsonb_set(next_doc, '{roster}', public._bastion_arr(next_doc, 'roster') || jsonb_build_array(jsonb_build_object(
      'id', person_id,
      'name', left(coalesce(nullif(request->>'name', ''), 'Lieutenant ' || (lieutenants + 1)), 80),
      'category', 'lieutenant', 'summary', '', 'role', 'Lieutenant', 'link', '',
      'unitId', unit->>'id', 'facilityId', facility->>'id', 'status', 'active', 'housed', true, 'protectsOnce', false
    )));
    order_row := order_row || jsonb_build_object('status', 'resolved');
  else
    if request ? 'gp' and request->'gp' is distinct from 'null'::jsonb and coalesce(request->>'gp', '') <> '' then
      gp := public._bastion_whole(request->>'gp', 0, 2000000000, 'Enter a whole GP cost, or leave the order unpriced.');
      if gp > 0 then
        next_doc := public._bastion_spend(next_doc, gp, sub->>'label', command->>'idempotencyKey');
      end if;
    end if;
    if request ? 'turns' and request->'turns' is distinct from 'null'::jsonb and coalesce(request->>'turns', '') <> '' then
      days := public._bastion_whole(request->>'turns', 0, 520, 'Duration has to be a whole number of Bastion turns.');
      days_known := true;
    elsif sub->'days' is null or sub->'days' = 'null'::jsonb then
      days_known := false;
    else
      days := public._bastion_book_turns((sub->>'days')::int);
      days_known := true;
    end if;
    if not days_known then
      order_row := order_row || jsonb_build_object('status', 'awaiting_dm', 'note', left(coalesce(nullif(sub->>'note', ''), 'Enter a duration and any price from the rules outside this chapter.'), 240));
    else
      ordinal := case when days = 0 then public._bastion_clock(next_doc) else public._bastion_clock(next_doc) + days end;
      select taken.next_doc, taken.next_id into next_doc, task_id from public._bastion_take(next_doc, 'task') as taken;
      next_doc := jsonb_set(next_doc, '{tasks}', public._bastion_arr(next_doc, 'tasks') || jsonb_build_array(jsonb_build_object(
        'id', task_id, 'status', 'open', 'settled', false, 'auto', 'manual', 'unitId', unit->>'id', 'orderId', order_id,
        'note', left(coalesce(request->>'note', sub->>'note', ''), 240),
        'dueTurn', to_jsonb(ordinal)
      )));
      order_row := order_row || jsonb_build_object('taskId', task_id, 'dueTurn', to_jsonb(ordinal));
    end if;
  end if;
  next_doc := jsonb_set(next_doc, '{orders}', public._bastion_arr(next_doc, 'orders') || jsonb_build_array(order_row));
end;
$$;
create or replace function public._bastion_cmd_commit(doc jsonb, command jsonb)
returns jsonb
language plpgsql
set search_path = public
as $$
declare
  unit jsonb;
  presence text;
  mode text;
  turn_id text;
  turn jsonb;
  facility jsonb;
  event_id text;
  orders jsonb;
  request jsonb;
  i int;
  placed jsonb;
  order_ids jsonb := '[]'::jsonb;
  warning text := '';
begin
  unit := public._bastion_unit(doc, command->>'unitId');
  if coalesce((unit->>'fallen')::boolean, false) then
    raise exception 'This bastion has fallen. Start a new one instead of issuing orders.' using errcode = '22023';
  end if;
  if exists (
    select 1 from jsonb_array_elements(public._bastion_arr(doc, 'events')) elem
    where elem->>'unitId' = unit->>'id' and elem->>'status' = 'pending'
  ) then
    raise exception 'Resolve the pending Maintain event before the next turn.' using errcode = '22023';
  end if;
  presence := command->>'presence';
  if presence not in ('present', 'absent', 'absent_with_contact') then
    raise exception 'Say whether the owner is here, away, or away but able to send word.' using errcode = '22023';
  end if;
  mode := command->>'mode';
  if presence = 'absent' and mode is distinct from 'no_orders' then
    mode := 'maintain';
  end if;
  if mode not in ('maintain', 'orders', 'no_orders') then
    raise exception 'Choose Maintain, orders, or no orders.' using errcode = '22023';
  end if;
  select taken.next_doc, taken.next_id into doc, turn_id from public._bastion_take(doc, 'turn') as taken;
  for facility in
    select value from jsonb_array_elements(public._bastion_arr(doc, 'facilities')) value
    where value->>'unitId' = unit->>'id'
  loop
    if facility->>'shutdownUntilTurnId' = 'next' then
      facility := facility || jsonb_build_object('blockedOnTurnId', turn_id, 'shutdownUntilTurnId', null, 'status', 'shutdown');
      doc := public._bastion_put_facility(doc, facility);
    elsif facility->>'blockedOnTurnId' is not null and facility->>'blockedOnTurnId' is distinct from turn_id then
      facility := facility || jsonb_build_object('blockedOnTurnId', null);
      if facility->>'status' = 'shutdown' then
        facility := jsonb_set(facility, '{status}', '"active"'::jsonb);
      end if;
      doc := public._bastion_put_facility(doc, facility);
    end if;
  end loop;
  orders := coalesce(command->'orders', '[]'::jsonb);
  if jsonb_typeof(orders) is distinct from 'array' then
    orders := '[]'::jsonb;
  end if;
  turn := jsonb_build_object(
    'id', turn_id,
    'unitId', unit->>'id',
    'presence', presence,
    'contact', left(coalesce(command->>'contact', ''), 160),
    'mode', mode,
    'status', 'committed',
    'turn', doc#>'{clock,turn}',
    'orderIds', '[]'::jsonb
  );
  if mode = 'maintain' then
    if jsonb_array_length(orders) > 0 then
      raise exception 'Maintain covers the whole ownership unit. It cannot share a turn with other orders.' using errcode = '22023';
    end if;
    unit := jsonb_set(unit, '{neglectStreak}', '0'::jsonb);
    doc := public._bastion_put_unit(doc, unit);
    select taken.next_doc, taken.next_id into doc, event_id from public._bastion_take(doc, 'event') as taken;
    doc := jsonb_set(doc, '{events}', public._bastion_arr(doc, 'events') || jsonb_build_array(jsonb_build_object(
      'id', event_id, 'unitId', unit->>'id', 'turnId', turn_id, 'status', 'pending', 'roll', null, 'type', null, 'detail', '{}'::jsonb
    )));
    turn := turn || jsonb_build_object('eventId', event_id);
    doc := jsonb_set(doc, '{turns}', public._bastion_arr(doc, 'turns') || jsonb_build_array(turn));
    return public._bastion_out(doc, jsonb_build_object('turnId', turn_id, 'eventId', event_id), 'Maintain is in effect for this whole unit. Roll or choose the event before the next turn.');
  end if;
  if mode = 'no_orders' then
    unit := jsonb_set(unit, '{neglectStreak}', to_jsonb(coalesce((unit->>'neglectStreak')::int, 0) + 1));
    doc := public._bastion_put_unit(doc, unit);
    if (unit->>'neglectStreak')::int >= (unit->>'level')::int then
      warning := format('No orders have been issued for %s turns, which matches this owner''s level. The DM can confirm a fall. It is not automatic.', unit->>'neglectStreak');
    end if;
    doc := jsonb_set(doc, '{turns}', public._bastion_arr(doc, 'turns') || jsonb_build_array(turn));
    return public._bastion_out(doc, jsonb_build_object('turnId', turn_id, 'neglectStreak', (unit->>'neglectStreak')::int, 'warning', warning), coalesce(nullif(warning, ''), 'Recorded a turn with no orders. This is not the same as Maintain.'));
  end if;
  if jsonb_array_length(orders) = 0 then
    raise exception 'Choose at least one order, or switch this turn to Maintain or no orders.' using errcode = '22023';
  end if;
  unit := jsonb_set(unit, '{neglectStreak}', '0'::jsonb);
  doc := public._bastion_put_unit(doc, unit);
  for i in 0 .. jsonb_array_length(orders) - 1 loop
    request := orders->i;
    select placed_row.next_doc, placed_row.order_row into doc, placed
    from public._bastion_place(doc, command, unit, turn_id, request) as placed_row;
    order_ids := order_ids || jsonb_build_array(placed->>'id');
  end loop;
  turn := jsonb_set(turn, '{orderIds}', order_ids);
  doc := jsonb_set(doc, '{turns}', public._bastion_arr(doc, 'turns') || jsonb_build_array(turn));
  return public._bastion_out(doc, jsonb_build_object('turnId', turn_id, 'orderIds', order_ids), 'Orders committed.');
end;
$$;
create or replace function public._bastion_cmd_enlarge(doc jsonb, command jsonb)
returns jsonb
language plpgsql
set search_path = public
as $$
declare
  facility jsonb;
  spec jsonb;
  gp int;
  hirelings int;
begin
  facility := public._bastion_facility(doc, command->>'facilityId');
  spec := public._bastion_spec(facility->>'catalogId');
  if spec is null or spec->'enlargeGp' is null or spec->>'enlargeGp' = '' or spec->'enlargeGp' = 'null'::jsonb then
    raise exception 'This facility has no enlargement price in the bastion rules.' using errcode = '22023';
  end if;
  if facility->>'space' = 'vast' then
    raise exception 'This facility is already vast.' using errcode = '22023';
  end if;
  gp := (spec->>'enlargeGp')::int;
  doc := public._bastion_spend(doc, gp, 'Enlarged ' || (facility->>'name'), command->>'idempotencyKey');
  hirelings := coalesce((facility->>'hirelings')::int, 1) + coalesce((spec->>'enlargeHirelings')::int, 0);
  facility := facility || jsonb_build_object('space', 'vast', 'hirelings', hirelings);
  if spec->>'id' = 'garden' then
    facility := jsonb_set(facility, '{plots}', '2'::jsonb);
  end if;
  if spec->>'id' = 'stable' then
    facility := jsonb_set(facility, '{vastCapacityLarge}', '6'::jsonb);
  end if;
  doc := public._bastion_put_facility(doc, facility);
  return public._bastion_out(doc, jsonb_build_object('facilityId', facility->>'id'), format('Enlarged %s for %s GP. No extra turns were added, because the chapter does not give a build time.', facility->>'name', gp));
end;
$$;


create or replace function public.handled_command_types()
returns text[]
language sql
immutable
set search_path = public
as $$
  select array[
    'set_settings','set_clock','set_finance','set_capabilities','raise_level','split_unit','add_special','replace_special','enlarge_special','add_basic','upgrade_basic','add_wall_squares','mark_enclosure','take_turn','roster_save','roster_remove','record_goods','commit_turn','resolve_event','dm_override','confirm_fall','import_accept','save_settings','set_level','record_defenders','set_loan','reserve_goods','record_order','remove_goods','remove_person','edit_person','remove_facility','edit_facility','replace_basic','correct_special','replace_person','assign_person','cancel_project','set_order_start','set_calendar_anchor','reanchor_calendar','finish_project','set_due_turn'
  ]::text[];
$$;

create or replace function public._bastion_apply(doc jsonb, command jsonb)
returns jsonb
language plpgsql
set search_path = public
as $$
declare
  cmd text := command->>'type';
begin
  if cmd = 'set_settings' then return public._bastion_cmd_settings(doc, command); end if;
  if cmd = 'set_clock' then return public._bastion_cmd_clock(doc, command); end if;
  if cmd = 'set_finance' then return public._bastion_cmd_finance(doc, command); end if;
  if cmd = 'set_capabilities' then return public._bastion_cmd_capabilities(doc, command); end if;
  if cmd = 'raise_level' then return public._bastion_cmd_raise(doc, command); end if;
  if cmd = 'split_unit' then return public._bastion_cmd_split(doc, command); end if;
  if cmd = 'add_special' then return public._bastion_cmd_add_special(doc, command); end if;
  if cmd = 'replace_special' or cmd = 'correct_special' then return public._bastion_cmd_replace(doc, command); end if;
  if cmd = 'enlarge_special' then return public._bastion_cmd_enlarge(doc, command); end if;
  if cmd = 'add_basic' then return public._bastion_cmd_add_basic(doc, command); end if;
  if cmd = 'upgrade_basic' then return public._bastion_cmd_upgrade(doc, command); end if;
  if cmd = 'add_wall_squares' then return public._bastion_cmd_walls(doc, command); end if;
  if cmd = 'mark_enclosure' then return public._bastion_cmd_enclosure(doc, command); end if;
  if cmd = 'take_turn' then return public._bastion_cmd_take_turn(doc, command); end if;
  if cmd = 'set_calendar_anchor' then return public._bastion_cmd_anchor(doc, command); end if;
  if cmd = 'reanchor_calendar' then return public._bastion_cmd_reanchor(doc, command); end if;
  if cmd = 'set_order_start' then return public._bastion_cmd_set_order_start(doc, command); end if;
  if cmd = 'finish_project' then return public._bastion_cmd_finish_project(doc, command); end if;
  if cmd = 'set_due_turn' then return public._bastion_cmd_set_due_turn(doc, command); end if;
  if cmd = 'roster_save' then return public._bastion_cmd_roster(doc, command); end if;
  if cmd = 'roster_remove' then return public._bastion_cmd_roster_remove(doc, command); end if;
  if cmd = 'record_goods' then return public._bastion_cmd_goods(doc, command); end if;
  if cmd = 'commit_turn' then return public._bastion_cmd_commit(doc, command); end if;
  if cmd = 'resolve_event' then return public._bastion_cmd_resolve(doc, command); end if;
  if cmd = 'dm_override' then return public._bastion_cmd_override(doc, command); end if;
  if cmd = 'confirm_fall' then return public._bastion_cmd_fall(doc, command); end if;
  if cmd = 'import_accept' then return public._bastion_cmd_import(doc, command); end if;
  if cmd = 'save_settings' then return public._bastion_cmd_save(doc, command); end if;
  if cmd = 'set_level' then return public._bastion_cmd_set_level(doc, command); end if;
  if cmd = 'record_defenders' then return public._bastion_cmd_defenders(doc, command); end if;
  if cmd = 'set_loan' then return public._bastion_cmd_loan(doc, command); end if;
  if cmd = 'reserve_goods' then return public._bastion_cmd_reserve(doc, command); end if;
  if cmd = 'record_order' then return public._bastion_cmd_record_order(doc, command); end if;
  if cmd = 'remove_goods' then return public._bastion_cmd_remove_goods(doc, command); end if;
  if cmd = 'remove_person' then return public._bastion_cmd_remove_person(doc, command); end if;
  if cmd = 'edit_person' then return public._bastion_cmd_edit_person(doc, command); end if;
  if cmd = 'remove_facility' then return public._bastion_cmd_remove_facility(doc, command); end if;
  if cmd = 'edit_facility' then return public._bastion_cmd_edit_facility(doc, command); end if;
  if cmd = 'replace_basic' then return public._bastion_cmd_replace_basic(doc, command); end if;
  if cmd = 'replace_person' then return public._bastion_cmd_replace_person(doc, command); end if;
  if cmd = 'assign_person' then return public._bastion_cmd_assign_person(doc, command); end if;
  if cmd = 'cancel_project' then return public._bastion_cmd_cancel_project(doc, command); end if;
  raise exception 'unsupported_on_server' using errcode = '0A000';
end;
$$;
create or replace function public.apply_command(eid uuid, expected_revision bigint, idempotency_key text, command jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  role text;
  doc jsonb;
  rev bigint;
  prior jsonb;
  cmd text;
  dm_only text[] := array[
    'set_settings',
    'set_clock',
    'set_finance',
    'raise_level',
    'split_unit',
    'replace_special',
    'dm_override',
    'confirm_fall',
    'import_accept',
    'set_capabilities',
    'mark_enclosure',
    'save_settings',
    'set_level',
    'record_defenders',
    'set_loan',
    'reserve_goods',
    'record_order',
    'remove_goods',
    'remove_person',
    'remove_facility',
    'edit_facility',
    'replace_basic',
    'correct_special',
    'replace_person',
    'assign_person',
    'cancel_project',
    'set_order_start'
  ];
  applied jsonb;
  result jsonb;
  summary text;
  audit_id text;
begin
  if auth.uid() is null then
    raise exception 'sign_in_required' using errcode = '42501';
  end if;
  role := public.member_role(eid);
  if role is null then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  if idempotency_key is not null and idempotency_key <> '' then
    select command_log.result into prior from public.command_log where estate_id = eid and command_log.idempotency_key = apply_command.idempotency_key;
    if prior is not null then
      return prior || jsonb_build_object('replay', true);
    end if;
  end if;

  select document, revision into doc, rev from public.estates where id = eid for update;
  if rev is null then
    raise exception 'missing_estate' using errcode = 'P0002';
  end if;
  if expected_revision is not null and expected_revision <> rev then
    raise exception 'revision_conflict' using errcode = '40001';
  end if;

  cmd := command->>'type';
  if role = 'reader' and cmd not in ('set_calendar_anchor', 'reanchor_calendar') then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  if role <> 'dm' and cmd = any(dm_only) then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  if not cmd = any(public.handled_command_types()) then
    raise exception 'unsupported_on_server' using errcode = '0A000';
  end if;
  if idempotency_key is not null and not command ? 'idempotencyKey' then
    command := command || jsonb_build_object('idempotencyKey', idempotency_key);
  end if;

  applied := public._bastion_apply(doc, command);
  doc := applied->'doc';
  result := coalesce(applied->'result', '{}'::jsonb);
  summary := coalesce(applied->>'summary', cmd);

  select taken.next_doc, taken.next_id into doc, audit_id from public._bastion_take(doc, 'aud') as taken;
  doc := jsonb_set(doc, '{audit}', public._bastion_arr(doc, 'audit') || jsonb_build_array(jsonb_build_object(
    'id', audit_id,
    'revision', rev + 1,
    'type', cmd,
    'summary', summary,
    'reason', left(coalesce(command->>'reason', ''), 400),
    'actorRole', role,
    'actorEmail', to_jsonb(coalesce(public.current_email(), '')),
    'turn', doc#>'{clock,turn}'
  )));

  rev := rev + 1;
  doc := jsonb_set(doc, '{revision}', to_jsonb(rev));
  update public.estates set document = doc, revision = rev where id = eid;
  insert into public.audit_log (estate_id, revision, actor, command_type, summary, reason)
  values (eid, rev, auth.uid(), cmd, summary, coalesce(command->>'reason', ''));
  result := result || jsonb_build_object('revision', rev, 'document', doc, 'replay', false);
  if idempotency_key is not null and idempotency_key <> '' then
    insert into public.command_log (estate_id, idempotency_key, result) values (eid, idempotency_key, result);
  end if;
  return result;
end;
$$;

create or replace function public.empty_document(estate_name text)
returns jsonb
language sql
immutable
set search_path = public
as $$
  select jsonb_build_object(
    'revision', 1,
    'seq', 0,
    'practice', false,
    'name', left(coalesce(nullif(btrim(estate_name), ''), 'Unnamed bastion'), 80),
    'clock', jsonb_build_object('label', '', 'turn', null, 'turnNeedsCheck', false, 'anchor', null),
    'finance', jsonb_build_object('cashKnown', false, 'cashGp', null, 'loans', '[]'::jsonb),
    'units', jsonb_build_array(jsonb_build_object(
      'id', 'unit-party', 'name', 'Party', 'level', 5,
      'owner', 'Shared, or assign later', 'replacementBank', 0,
      'capabilities', '[]'::jsonb, 'neglectStreak', 0, 'fallen', false
    )),
    'facilities', '[]'::jsonb,
    'archive', '[]'::jsonb,
    'projects', '[]'::jsonb,
    'walls', jsonb_build_object('enclosureComplete', false, 'squares', '[]'::jsonb),
    'roster', '[]'::jsonb,
    'goods', '[]'::jsonb,
    'tasks', '[]'::jsonb,
    'turns', '[]'::jsonb,
    'events', '[]'::jsonb,
    'orders', '[]'::jsonb,
    'ledger', '[]'::jsonb,
    'audit', '[]'::jsonb,
    'warnings', '[]'::jsonb
  );
$$;

create or replace function public._bastion_event_body(doc jsonb, command jsonb, unit jsonb, event jsonb, out next_doc jsonb, out next_event jsonb, out result jsonb)
language plpgsql
set search_path = public
as $$
declare
  detail jsonb := coalesce(command->'detail', '{}'::jsonb);
  dice int;
  sides int;
  rolls jsonb;
  roll_n int;
  i int;
  kills int := 0;
  monster jsonb;
  person jsonb;
  defenders jsonb := '[]'::jsonb;
  lost jsonb := '[]'::jsonb;
  stocked boolean;
  remaining int;
  specials jsonb := '[]'::jsonb;
  facility jsonb;
  shutdown_id text := null;
  index_n int;
  bribe int;
  gp int;
  staff_left int;
  next_roll int;
  mapped text;
  follow jsonb;
  kind int;
  die_n int;
  sent int;
  total int;
  reward int;
  band int;
begin
  next_doc := doc;
  next_event := event;
  if event->>'type' = 'all_is_well' then
    next_event := next_event || jsonb_build_object('detail', jsonb_build_object('note', left(coalesce(detail->>'note', ''), 240)));
    result := jsonb_build_object('type', 'all_is_well', 'deltas', '[]'::jsonb);
    return;
  end if;
  if event->>'type' = 'attack' then
    dice := 6;
    if coalesce((next_doc#>>'{walls,enclosureComplete}')::boolean, false) then dice := dice - 2; end if;
    dice := dice - coalesce((
      select count(*) from jsonb_array_elements(public._bastion_arr(next_doc, 'roster')) elem
      where elem->>'category' = 'lieutenant' and elem->>'status' = 'active' and elem->>'unitId' = unit->>'id' and coalesce((elem->>'housed')::boolean, false)
    ), 0);
    if dice < 0 then
      dice := 0;
      if not public._bastion_flag(detail->'confirmZeroDice') then
        raise exception 'Reductions would drop the attack below zero dice. The DM should confirm zero before continuing.' using errcode = '22023';
      end if;
    end if;
    select exists (
      select 1 from jsonb_array_elements(next_doc->'facilities') elem
      where elem->>'unitId' = unit->>'id' and elem->>'catalogId' = 'armory' and coalesce((elem->>'stocked')::boolean, false) and elem->>'status' = 'active'
    ) into stocked;
    sides := case when stocked then 8 else 6 end;
    rolls := coalesce(detail->'rolls', '[]'::jsonb);
    if jsonb_typeof(rolls) is distinct from 'array' or jsonb_array_length(rolls) is distinct from dice then
      raise exception 'Enter % dice with % sides. They stay saved with the event.', dice, sides using errcode = '22023';
    end if;
    for i in 0 .. dice - 1 loop
      if (rolls->>i) !~ '^[0-9]+$' or (rolls->>i)::int < 1 or (rolls->>i)::int > sides then
        raise exception 'Enter % dice with % sides. They stay saved with the event.', dice, sides using errcode = '22023';
      end if;
      if (rolls->>i)::int = 1 then kills := kills + 1; end if;
    end loop;
    select elem into monster from jsonb_array_elements(public._bastion_arr(next_doc, 'roster')) elem
      where elem->>'unitId' = unit->>'id' and coalesce((elem->>'protectsOnce')::boolean, false) and elem->>'status' = 'active' limit 1;
    if monster is not null then
      kills := 0;
      monster := monster || jsonb_build_object('status', 'gone', 'protectsOnce', false);
      next_doc := jsonb_set(next_doc, '{roster}', public._bastion_replace(next_doc->'roster', monster->>'id', monster));
    end if;
    for person in
      select value from jsonb_array_elements(public._bastion_arr(next_doc, 'roster')) value
      where value->>'unitId' = coalesce(nullif(detail->>'lossUnitId', ''), unit->>'id')
        and value->>'category' = 'defender' and value->>'status' = 'active'
    loop
      defenders := defenders || jsonb_build_array(person);
    end loop;
    for i in 0 .. kills - 1 loop
      if detail->'lossIds' is not null and jsonb_typeof(detail->'lossIds') = 'array' then
        person := public._bastion_find(defenders, detail#>>array['lossIds', i::text]);
      else
        person := defenders->i;
      end if;
      if person is null then continue; end if;
      person := jsonb_set(person, '{status}', '"dead"'::jsonb);
      next_doc := jsonb_set(next_doc, '{roster}', public._bastion_replace(next_doc->'roster', person->>'id', person));
      lost := lost || jsonb_build_array(person->>'id');
    end loop;
    if stocked then
      for facility in
        select value from jsonb_array_elements(next_doc->'facilities') value
        where value->>'unitId' = unit->>'id' and value->>'catalogId' = 'armory' and coalesce((value->>'stocked')::boolean, false)
      loop
        facility := jsonb_set(facility, '{stocked}', 'false'::jsonb);
        next_doc := public._bastion_put_facility(next_doc, facility);
      end loop;
    end if;
    select count(*) into remaining from jsonb_array_elements(public._bastion_arr(next_doc, 'roster')) elem
      where elem->>'unitId' = unit->>'id' and elem->>'category' = 'defender' and elem->>'status' = 'active';
    if remaining = 0 then
      for facility in
        select value from jsonb_array_elements(next_doc->'facilities') value
        where value->>'unitId' = unit->>'id' and value->>'kind' = 'special' and value->>'status' = 'active'
      loop
        specials := specials || jsonb_build_array(facility);
      end loop;
      if jsonb_array_length(specials) > 0 then
        index_n := coalesce(nullif(detail->>'shutdownIndex', '')::int, 0);
        facility := specials->index_n;
        if facility is null then facility := specials->0; end if;
        facility := facility || jsonb_build_object('status', 'shutdown', 'shutdownUntilTurnId', 'next');
        next_doc := public._bastion_put_facility(next_doc, facility);
        shutdown_id := facility->>'id';
      end if;
    end if;
    next_event := next_event || jsonb_build_object('detail', jsonb_build_object(
      'dice', dice, 'sides', sides, 'rolls', rolls, 'lost', lost, 'shutdown', to_jsonb(shutdown_id), 'monster', to_jsonb(monster->>'name')
    ));
    result := jsonb_build_object('type', 'attack', 'dice', dice, 'sides', sides, 'lost', jsonb_array_length(lost), 'shutdown', to_jsonb(shutdown_id), 'armorySpent', stocked);
    return;
  end if;
  if event->>'type' = 'criminal' then
    if detail->>'bribeRoll' is null or detail->>'bribeRoll' !~ '^[0-9]+$' or (detail->>'bribeRoll')::int < 1 or (detail->>'bribeRoll')::int > 6 then
      raise exception 'Enter the bribe die, from 1 to 6.' using errcode = '22023';
    end if;
    bribe := (detail->>'bribeRoll')::int;
    gp := bribe * 100;
    if detail->>'choice' = 'pay' then
      next_doc := public._bastion_spend(next_doc, gp, 'Bribe to keep a hireling', command->>'idempotencyKey');
      next_event := next_event || jsonb_build_object('detail', jsonb_build_object('choice', 'pay', 'gp', gp));
      result := jsonb_build_object('type', 'criminal', 'gp', gp);
      return;
    end if;
    if detail->>'choice' is distinct from 'arrest' then
      raise exception 'Pay the bribe or let the hireling be arrested.' using errcode = '22023';
    end if;
    person := public._bastion_find(next_doc->'roster', detail->>'personId');
    if person is null or person->>'status' is distinct from 'active' then
      raise exception 'Name the hireling who is arrested.' using errcode = '22023';
    end if;
    person := jsonb_set(person, '{status}', '"arrested"'::jsonb);
    next_doc := jsonb_set(next_doc, '{roster}', public._bastion_replace(next_doc->'roster', person->>'id', person));
    facility := case when coalesce(person->>'facilityId', '') <> '' then public._bastion_find(next_doc->'facilities', person->>'facilityId') else null end;
    select count(*) into staff_left from jsonb_array_elements(public._bastion_arr(next_doc, 'roster')) elem
      where elem->>'facilityId' = person->>'facilityId' and elem->>'status' = 'active' and elem->>'category' = 'hireling';
    if facility is not null and staff_left < 1 and person->>'category' = 'hireling' then
      facility := facility || jsonb_build_object('status', 'shutdown', 'shutdownUntilTurnId', 'next');
      next_doc := public._bastion_put_facility(next_doc, facility);
    end if;
    next_event := next_event || jsonb_build_object('detail', jsonb_build_object('choice', 'arrest', 'personId', person->>'id'));
    result := jsonb_build_object('type', 'criminal', 'arrested', person->>'name');
    return;
  end if;
  if event->>'type' = 'opportunity' then
    if detail->>'choice' = 'decline' then
      next_event := next_event || jsonb_build_object('detail', jsonb_build_object('choice', 'decline'));
      result := jsonb_build_object('type', 'opportunity', 'choice', 'decline');
      return;
    end if;
    if detail->>'choice' is distinct from 'pay' then
      raise exception 'Pay 500 GP for another event, or decline.' using errcode = '22023';
    end if;
    next_doc := public._bastion_spend(next_doc, 500, 'Extraordinary opportunity', command->>'idempotencyKey');
    if detail->>'nextRoll' is null or detail->>'nextRoll' !~ '^[0-9]+$' or (detail->>'nextRoll')::int < 1 or (detail->>'nextRoll')::int > 100 then
      raise exception 'Enter the new d100. If it is 59–63, roll again and enter the later result.' using errcode = '22023';
    end if;
    next_roll := (detail->>'nextRoll')::int;
    mapped := public._bastion_event_type(next_roll);
    if mapped = 'opportunity' then
      raise exception 'That result is the opportunity again. Roll once more and enter the new result.' using errcode = '22023';
    end if;
    next_event := next_event || jsonb_build_object('type', mapped, 'detail', jsonb_build_object('paid', 500, 'replacedRoll', next_roll));
    follow := coalesce(detail->'follow', '{}'::jsonb);
    select body.next_doc, body.next_event, body.result into next_doc, next_event, result
    from public._bastion_event_body(next_doc, command || jsonb_build_object('detail', follow), unit, next_event) as body;
    return;
  end if;
  if event->>'type' = 'visitors' then
    if detail->>'die' is null or detail->>'die' !~ '^[0-9]+$' or (detail->>'die')::int < 1 or (detail->>'die')::int > 6 then
      raise exception 'Enter 1d6 for the visitors'' payment.' using errcode = '22023';
    end if;
    die_n := (detail->>'die')::int;
    next_doc := public._bastion_receive(next_doc, die_n * 100, 'Friendly visitors', command->>'idempotencyKey');
    next_event := next_event || jsonb_build_object('detail', jsonb_build_object('gp', die_n * 100));
    result := jsonb_build_object('type', 'visitors', 'gp', die_n * 100);
    return;
  end if;
  if event->>'type' = 'guest' then
    if detail->>'kind' is null or detail->>'kind' !~ '^[0-9]+$' or (detail->>'kind')::int not in (1, 2, 3, 4) then
      raise exception 'Choose the guest result from 1 to 4.' using errcode = '22023';
    end if;
    kind := (detail->>'kind')::int;
    next_event := next_event || jsonb_build_object('detail', jsonb_build_object('kind', kind));
    if kind = 2 then
      if detail->>'die' is null or detail->>'die' !~ '^[0-9]+$' or (detail->>'die')::int < 1 or (detail->>'die')::int > 6 then
        raise exception 'Enter 1d6 for the gift.' using errcode = '22023';
      end if;
      next_event := jsonb_set(next_event, '{detail,gp}', to_jsonb((detail->>'die')::int * 100));
      next_event := jsonb_set(next_event, '{detail,dueInTurns}', '1'::jsonb);
      result := jsonb_build_object('type', 'guest', 'kind', 2, 'gpLater', (detail->>'die')::int * 100, 'note', 'The gift is due after 1 Bastion turn. Record it then; it is not cash today.');
      return;
    end if;
    if kind = 3 or kind = 4 then
      select taken.next_doc, taken.next_id into next_doc, shutdown_id from public._bastion_take(next_doc, 'npc') as taken;
      next_doc := jsonb_set(next_doc, '{roster}', public._bastion_arr(next_doc, 'roster') || jsonb_build_array(jsonb_build_object(
        'id', shutdown_id,
        'name', left(coalesce(nullif(detail->>'name', ''), case when kind = 3 then 'Mercenary guest' else 'Friendly monster' end), 80),
        'category', case when kind = 3 then 'defender' else 'guest' end,
        'summary', case when kind = 3 then 'Staying guest. Does not need a barrack bed.' else 'Will protect the bastion once, then leave.' end,
        'role', case when kind = 3 then 'Guest defender' else 'Guest' end,
        'link', '', 'unitId', unit->>'id', 'facilityId', null, 'status', 'active', 'housed', false,
        'protectsOnce', kind = 4
      )));
      result := jsonb_build_object('type', 'guest', 'kind', kind, 'defender', kind = 3);
      return;
    end if;
    result := jsonb_build_object('type', 'guest', 'kind', 1, 'note', 'Renowned guest stays 1 Bastion turn. Record the letter yourself.');
    return;
  end if;
  if event->>'type' = 'lost_hirelings' then
    facility := public._bastion_facility(next_doc, detail->>'facilityId');
    if facility->>'unitId' is distinct from unit->>'id' or facility->>'kind' is distinct from 'special' then
      raise exception 'Choose one of this owner''s special facilities.' using errcode = '22023';
    end if;
    for person in
      select value from jsonb_array_elements(public._bastion_arr(next_doc, 'roster')) value
      where value->>'facilityId' = facility->>'id' and value->>'category' = 'hireling' and value->>'status' = 'active'
    loop
      person := jsonb_set(person, '{status}', '"gone"'::jsonb);
      next_doc := jsonb_set(next_doc, '{roster}', public._bastion_replace(next_doc->'roster', person->>'id', person));
    end loop;
    facility := facility || jsonb_build_object('status', 'shutdown', 'shutdownUntilTurnId', 'next');
    next_doc := public._bastion_put_facility(next_doc, facility);
    next_event := next_event || jsonb_build_object('detail', jsonb_build_object('facilityId', facility->>'id'));
    result := jsonb_build_object('type', 'lost_hirelings', 'facility', facility->>'name');
    return;
  end if;
  if event->>'type' = 'magic' then
    if btrim(coalesce(detail->>'item', '')) = '' then
      raise exception 'Name the uncommon potion or scroll. The item tables are not in the bastion chapter.' using errcode = '22023';
    end if;
    next_event := next_event || jsonb_build_object('detail', jsonb_build_object('item', left(btrim(detail->>'item'), 120)));
    result := jsonb_build_object('type', 'magic', 'item', left(btrim(detail->>'item'), 120));
    return;
  end if;
  if event->>'type' = 'refugees' then
    if detail->>'count' is null or detail->>'count' !~ '^[0-9]+$' or (detail->>'count')::int < 2 or (detail->>'count')::int > 8 then
      raise exception 'Enter the 2d4 result, from 2 to 8.' using errcode = '22023';
    end if;
    if detail->>'die' is null or detail->>'die' !~ '^[0-9]+$' or (detail->>'die')::int < 1 or (detail->>'die')::int > 6 then
      raise exception 'Enter 1d6 for the refugees'' payment.' using errcode = '22023';
    end if;
    if detail->'housed' is null or jsonb_typeof(detail->'housed') is distinct from 'boolean' then
      raise exception 'Say whether a basic room can house them. There is no squares-per-person formula.' using errcode = '22023';
    end if;
    next_doc := public._bastion_receive(next_doc, (detail->>'die')::int * 100, 'Refugee payment', command->>'idempotencyKey');
    next_event := next_event || jsonb_build_object('detail', jsonb_build_object('count', (detail->>'count')::int, 'housed', detail->'housed', 'gp', (detail->>'die')::int * 100));
    result := jsonb_build_object('type', 'refugees', 'count', (detail->>'count')::int, 'gp', (detail->>'die')::int * 100, 'housed', detail->'housed');
    return;
  end if;
  if event->>'type' = 'aid' then
    if detail->>'sent' is null or detail->>'sent' !~ '^[0-9]+$' or (detail->>'sent')::int < 1 then
      raise exception 'Send at least one defender, or do not take the request.' using errcode = '22023';
    end if;
    sent := (detail->>'sent')::int;
    rolls := coalesce(detail->'rolls', '[]'::jsonb);
    if jsonb_typeof(rolls) is distinct from 'array' or jsonb_array_length(rolls) is distinct from sent then
      raise exception 'Enter one d6 for each defender sent. Armory stock is not applied to this total.' using errcode = '22023';
    end if;
    total := 0;
    for i in 0 .. sent - 1 loop
      if (rolls->>i) !~ '^[0-9]+$' or (rolls->>i)::int < 1 or (rolls->>i)::int > 6 then
        raise exception 'Enter one d6 for each defender sent. Armory stock is not applied to this total.' using errcode = '22023';
      end if;
      total := total + (rolls->>i)::int;
    end loop;
    if detail->>'rewardRoll' is null or detail->>'rewardRoll' !~ '^[0-9]+$' or (detail->>'rewardRoll')::int < 1 or (detail->>'rewardRoll')::int > 6 then
      raise exception 'Enter the reward d6.' using errcode = '22023';
    end if;
    reward := (detail->>'rewardRoll')::int;
    gp := reward * 100;
    if total < 10 then
      gp := gp / 2;
      person := public._bastion_find(next_doc->'roster', detail->>'casualtyId');
      if person is null or person->>'category' is distinct from 'defender' or person->>'status' is distinct from 'active' then
        raise exception 'Name the defender who is lost when the total is under 10.' using errcode = '22023';
      end if;
      person := jsonb_set(person, '{status}', '"dead"'::jsonb);
      next_doc := jsonb_set(next_doc, '{roster}', public._bastion_replace(next_doc->'roster', person->>'id', person));
    end if;
    next_doc := public._bastion_receive(next_doc, gp, 'Request for aid', command->>'idempotencyKey');
    next_event := next_event || jsonb_build_object('detail', jsonb_build_object('sent', sent, 'total', total, 'gp', gp, 'casualty', to_jsonb(person->>'name')));
    result := jsonb_build_object('type', 'aid', 'total', total, 'gp', gp, 'casualty', to_jsonb(person->>'name'));
    return;
  end if;
  if event->>'type' = 'treasure' then
    if detail->>'band' is null or detail->>'band' !~ '^[0-9]+$' or (detail->>'band')::int < 1 or (detail->>'band')::int > 100 then
      raise exception 'Enter the treasure d100.' using errcode = '22023';
    end if;
    if btrim(coalesce(detail->>'item', '')) = '' then
      raise exception 'The treasure tables are in another chapter. Enter the object you rolled there.' using errcode = '22023';
    end if;
    band := (detail->>'band')::int;
    next_event := next_event || jsonb_build_object('detail', jsonb_build_object('band', band, 'item', left(btrim(detail->>'item'), 160), 'claimed', public._bastion_flag(detail->'ownerPresent')));
    result := jsonb_build_object('type', 'treasure', 'item', left(btrim(detail->>'item'), 160), 'claimed', public._bastion_flag(detail->'ownerPresent'), 'note', case when public._bastion_flag(detail->'ownerPresent') then 'Claimed now.' else 'Stored until the owner can claim it. Not converted to cash.' end);
    return;
  end if;
  raise exception 'That event still needs a choice.' using errcode = '22023';
end;
$$;

revoke all on function public.apply_command(uuid, bigint, text, jsonb) from public, anon;
grant execute on function public.apply_command(uuid, bigint, text, jsonb) to authenticated;

do $$
declare
  fn regprocedure;
begin
  for fn in
    select p.oid::regprocedure
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and (p.proname like '\_bastion\_%' escape '\' or p.proname = 'handled_command_types')
  loop
    execute format('revoke all on function %s from public, anon, authenticated', fn);
  end loop;
end $$;
