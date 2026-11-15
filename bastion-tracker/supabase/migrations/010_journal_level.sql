-- Journal ledger, recorded turn dates, honor-system level, and stable sale markup.
-- Does not change cash, the turn counter, the date anchor, loans, or goods.
-- Drops clock.label. Clears an audit turn number only when it is later than the
-- saved Bastion turn (the old ordinal 30 on a turn-4 estate). Stamps each committed
-- turn with the date derived from the current anchor. Safe to run once; a second run
-- does not touch a later real turn 30.

create or replace function public._bastion_turn_date(doc jsonb, turn_n int)
returns text
language plpgsql
stable
set search_path = public
as $$
declare
  origin int;
  step int;
begin
  if doc#>>'{clock,anchor,turn}' is null or turn_n is null then
    return 'date not set';
  end if;
  origin := (doc#>>'{clock,anchor,turn}')::int;
  step := case when coalesce((doc#>>'{clock,turnDays}')::int, 10) = 7 then 7 else 10 end;
  return coalesce(
    public._bastion_shift_date(doc->'clock'->'anchor', step * (turn_n - origin), coalesce((doc#>>'{clock,skipFestivals}')::boolean, true)),
    'date not set'
  );
end;
$$;

create or replace function public._bastion_sync_label(doc jsonb)
returns jsonb
language sql
set search_path = public
as $$
  select doc #- '{clock,label}';
$$;

create or replace function public._bastion_apply_level(doc jsonb, unit jsonb, next_level int, grant_flag boolean, out next_unit jsonb, out note text)
language plpgsql
set search_path = public
as $$
declare
  held int;
  cap int;
  fac jsonb;
  spec jsonb;
  order_row jsonb;
  task jsonb;
  warning text := '';
  room_name text;
begin
  if next_level < 5 or next_level > 20 then
    raise exception 'A bastion level is from 5 to 20.' using errcode = '22023';
  end if;
  select count(*) into held
  from jsonb_array_elements(coalesce(doc->'facilities', '[]'::jsonb)) as elem
  where elem->>'unitId' = unit->>'id'
    and elem->>'kind' = 'special'
    and elem->>'status' is distinct from 'archived';
  cap := public._bastion_cap(next_level);
  if held > cap then
    raise exception 'Level % allows % special facilities, and this unit already has %. Shut facilities still count.', next_level, cap, held
      using errcode = '22023';
  end if;
  for fac in
    select value from jsonb_array_elements(coalesce(doc->'facilities', '[]'::jsonb)) as value
    where value->>'unitId' = unit->>'id' and value->>'kind' = 'special' and value->>'status' is distinct from 'archived'
  loop
    spec := public._bastion_spec(fac->>'catalogId');
    if spec is not null and next_level < (spec->>'level')::int then
      raise exception '% requires level %. Level % is below what this unit''s facilities require.', spec->>'name', (spec->>'level')::int, next_level
        using errcode = '22023';
    end if;
  end loop;
  next_unit := jsonb_set(unit, '{level}', to_jsonb(next_level));
  note := format('Level set to %s.', next_level);
  for order_row in
    select value from jsonb_array_elements(coalesce(doc->'orders', '[]'::jsonb)) as value
    where value->>'unitId' = unit->>'id'
      and coalesce(value->>'status', '') not in ('resolved', 'cancelled')
      and value->>'suborder' = 'craft_magic'
  loop
    if next_level < 9 then
      select elem->>'name' into room_name
      from jsonb_array_elements(coalesce(doc->'facilities', '[]'::jsonb)) elem
      where elem->>'id' = order_row->>'facilityId';
      warning := warning || ' ' || coalesce(room_name, 'A workshop') || ': magic-item crafting needs level 9.';
    end if;
  end loop;
  for task in
    select value from jsonb_array_elements(coalesce(doc->'tasks', '[]'::jsonb)) as value
    where value->>'unitId' = unit->>'id'
      and value->>'status' = 'open'
      and coalesce((value->>'settled')::boolean, false) = false
      and value->>'auto' = 'storehouse_buy'
  loop
    if coalesce((task->>'standardGp')::int, 0) > public._bastion_buy_limit(next_level) then
      warning := warning || format(' A Storehouse purchase of %s GP is over the %s GP limit at level %s.', task->>'standardGp', public._bastion_buy_limit(next_level), next_level);
    end if;
  end loop;
  if warning <> '' then
    note := note || ' Still in progress:' || warning;
  end if;
end;
$$;

create or replace function public._bastion_cmd_clock(doc jsonb, command jsonb)
returns jsonb
language plpgsql
set search_path = public
as $$
begin
  doc := doc #- '{clock,label}';
  doc := public._bastion_set_turn(doc, command);
  return public._bastion_out(doc, jsonb_build_object('clock', doc->'clock'), 'Updated the Bastion turn.');
end;
$$;

create or replace function public._bastion_cmd_set_level(doc jsonb, command jsonb)
returns jsonb
language plpgsql
set search_path = public
as $$
declare
  unit jsonb;
  level int;
  note text;
begin
  unit := public._bastion_unit(doc, coalesce(command->>'unitId', doc#>>'{units,0,id}'));
  level := public._bastion_whole(command->>'level', 5, 20, 'A bastion level is from 5 to 20.');
  select applied.next_unit, applied.note into unit, note
  from public._bastion_apply_level(doc, unit, level, false) as applied;
  doc := public._bastion_put_unit(doc, unit);
  return public._bastion_out(doc, jsonb_build_object('level', (unit->>'level')::int, 'bank', (unit->>'replacementBank')::int), note);
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
  note text := 'Level unchanged.';
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
  doc := doc #- '{clock,label}';
  doc := public._bastion_set_turn(doc, command);
  if command ? 'turnDays' and coalesce(command->>'turnDays', '') <> '' then
    doc := jsonb_set(doc, '{clock,turnDays}', case when command->>'turnDays' = '7' then '7'::jsonb else '10'::jsonb end);
  end if;
  if command ? 'skipFestivals' then
    doc := jsonb_set(doc, '{clock,skipFestivals}', to_jsonb(coalesce((command->>'skipFestivals')::boolean, true)));
  end if;
  if command ? 'level' and coalesce(command->>'level', '') <> '' then
    level := public._bastion_whole(command->>'level', 5, 20, 'A bastion level is from 5 to 20.');
    select applied.next_unit, applied.note into unit, note
    from public._bastion_apply_level(doc, unit, level, false) as applied;
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

create or replace function public._bastion_cmd_take_turn(doc jsonb, command jsonb)
returns jsonb
language plpgsql
set search_path = public
as $$
declare
  turn_n int;
  shown text;
begin
  turn_n := public._bastion_clock(doc) + 1;
  doc := jsonb_set(doc, '{clock,turn}', to_jsonb(turn_n));
  doc := doc #- '{clock,label}';
  doc := public._bastion_settle(doc, command->>'idempotencyKey');
  shown := public._bastion_turn_date(doc, turn_n);
  return public._bastion_out(doc, jsonb_build_object('turn', turn_n, 'date', shown), format('Advanced to Bastion turn %s. The in-game date is %s.', turn_n, shown));
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
    if facility ? 'defenderCount' and coalesce(facility->>'defenderCount', '') <> '' then
      housed := coalesce((facility->>'defenderCount')::int, 0);
    else
      housed := (
        select count(*) from jsonb_array_elements(public._bastion_arr(next_doc, 'roster')) elem
        where elem->>'facilityId' = facility->>'id' and elem->>'category' = 'defender' and elem->>'status' = 'active'
      );
    end if;
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
    facility := facility || jsonb_build_object('defenderCount', housed + count_n);
    next_doc := public._bastion_put_facility(next_doc, facility);
    order_row := order_row || jsonb_build_object('status', 'resolved', 'result', jsonb_build_object('recruited', count_n, 'housed', housed + count_n));
  elsif sub->>'auto' = 'storehouse_buy' then
    if coalesce(btrim(request->>'goodsName'), '') = '' then
      raise exception 'Goods need a name.' using errcode = '22023';
    end if;
    limit_gp := public._bastion_buy_limit((unit->>'level')::int);
    standard_gp := public._bastion_whole(request->>'standardGp', 1, limit_gp, format('This level can buy up to %s GP of goods in one order.', limit_gp));
    next_doc := public._bastion_spend(next_doc, standard_gp, 'Storehouse purchase of ' || standard_gp || ' GP', command->>'idempotencyKey');
    due := public._bastion_clock(next_doc) + 1;
    select taken.next_doc, taken.next_id into next_doc, task_id from public._bastion_take(next_doc, 'task') as taken;
    next_doc := jsonb_set(next_doc, '{tasks}', public._bastion_arr(next_doc, 'tasks') || jsonb_build_array(jsonb_build_object(
      'id', task_id, 'status', 'open', 'settled', false, 'auto', 'storehouse_buy', 'unitId', unit->>'id',
      'orderId', order_id, 'goodsName', left(btrim(request->>'goodsName'), 80),
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
  elsif facility->>'catalogId' = 'stable' and sub->>'id' = 'trade' then
    gp := public._bastion_whole(coalesce(request->>'standardGp', request->>'gp'), 1, 2000000000, 'Enter the mount''s list price in whole GP.');
    due := public._bastion_clock(next_doc) + 1;
    if request->>'side' = 'sell' then
      select taken.next_doc, taken.next_id into next_doc, task_id from public._bastion_take(next_doc, 'task') as taken;
      next_doc := jsonb_set(next_doc, '{tasks}', public._bastion_arr(next_doc, 'tasks') || jsonb_build_array(jsonb_build_object(
        'id', task_id, 'status', 'open', 'settled', false, 'auto', 'stable_sell',
        'unitId', unit->>'id', 'orderId', order_id,
        'goodsName', left(coalesce(nullif(request->>'goodsName', ''), 'mount'), 80),
        'standardGp', gp, 'proceeds', round(gp * 1.2)::int, 'dueTurn', to_jsonb(due)
      )));
      order_row := order_row || jsonb_build_object(
        'taskId', task_id, 'dueTurn', due, 'auto', 'stable_sell',
        'preview', jsonb_build_object('standardGp', gp, 'proceeds', round(gp * 1.2)::int)
      );
    else
      next_doc := public._bastion_spend(next_doc, gp, 'Stable purchase of ' || left(coalesce(nullif(request->>'goodsName', ''), 'mount'), 80), command->>'idempotencyKey');
      due := public._bastion_clock(next_doc) + 1;
      select taken.next_doc, taken.next_id into next_doc, task_id from public._bastion_take(next_doc, 'task') as taken;
      next_doc := jsonb_set(next_doc, '{tasks}', public._bastion_arr(next_doc, 'tasks') || jsonb_build_array(jsonb_build_object(
        'id', task_id, 'status', 'open', 'settled', false, 'auto', 'stable_buy',
        'unitId', unit->>'id', 'orderId', order_id,
        'goodsName', left(coalesce(nullif(request->>'goodsName', ''), 'mount'), 80),
        'standardGp', gp, 'dueTurn', to_jsonb(due)
      )));
      order_row := order_row || jsonb_build_object('taskId', task_id, 'dueTurn', due, 'auto', 'stable_buy');
    end if;
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
    elsif task->>'auto' = 'stable_sell' then
      doc := public._bastion_receive(doc, (task->>'proceeds')::int, 'Sold a mount listed at ' || (task->>'standardGp') || ' GP', idem_key);
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
  order_names text;
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
    'orderIds', '[]'::jsonb,
    'notes', left(coalesce(command->>'notes', ''), 600),
    'date', to_jsonb(public._bastion_turn_date(doc, (doc#>>'{clock,turn}')::int))
  );
  if length(coalesce(command->>'notes', '')) > 600 then
    raise exception 'A turn note can be at most 600 characters.' using errcode = '22023';
  end if;
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
  select string_agg(elem->>'label', ', ' order by elem->>'label') into order_names
  from jsonb_array_elements(coalesce(doc->'orders', '[]'::jsonb)) elem
  where turn->'orderIds' ? (elem->>'id');
  return public._bastion_out(doc, jsonb_build_object('turnId', turn_id, 'orderIds', order_ids), case when coalesce(order_names, '') = '' then 'Orders committed.' else 'Orders committed: ' || order_names || '.' end);
end;
$$;


create or replace function public._bastion_migrate_journal(doc jsonb)
returns jsonb
language plpgsql
set search_path = public
as $$
declare
  turn_row jsonb;
  turns jsonb := '[]'::jsonb;
  entry jsonb;
  audit jsonb := '[]'::jsonb;
  clock_turn int;
begin
  if coalesce(doc->>'rulesMigration', '') = '010' then
    return doc;
  end if;
  doc := doc #- '{clock,label}';
  if doc#>>'{clock,turn}' ~ '^[0-9]+$' then
    clock_turn := (doc#>>'{clock,turn}')::int;
  end if;
  for turn_row in select value from jsonb_array_elements(coalesce(doc->'turns', '[]'::jsonb)) value loop
    if coalesce(turn_row->>'date', '') = '' and coalesce(turn_row->>'turn', '') ~ '^[0-9]+$' then
      turn_row := turn_row || jsonb_build_object('date', public._bastion_turn_date(doc, (turn_row->>'turn')::int));
    end if;
    turns := turns || jsonb_build_array(turn_row);
  end loop;
  doc := jsonb_set(doc, '{turns}', turns);
  for entry in select value from jsonb_array_elements(coalesce(doc->'audit', '[]'::jsonb)) value loop
    if clock_turn is not null and coalesce(entry->>'turn', '') ~ '^[0-9]+$' and (entry->>'turn')::int > clock_turn then
      entry := entry - 'turn';
    end if;
    audit := audit || jsonb_build_array(entry);
  end loop;
  doc := jsonb_set(doc, '{audit}', audit);
  doc := doc || jsonb_build_object('rulesMigration', '010');
  return doc;
end;
$$;

update public.estates
set document = public._bastion_migrate_journal(document)
where coalesce(document->>'rulesMigration', '') <> '010';

create or replace function public.handled_command_types()
returns text[]
language sql
immutable
set search_path = public
as $$
  select array[
    'set_settings','set_clock','set_finance','set_capabilities','raise_level','split_unit','add_special','replace_special','enlarge_special','add_basic','upgrade_basic','add_wall_squares','mark_enclosure','take_turn','roster_save','roster_remove','record_goods','commit_turn','resolve_event','dm_override','confirm_fall','import_accept','save_settings','set_level','record_defenders','set_loan','reserve_goods','release_goods','record_order','remove_goods','remove_person','edit_person','remove_facility','edit_facility','replace_basic','correct_special','replace_person','assign_person','cancel_project','set_order_start','close_recorded_order','repay_loans','set_calendar_anchor','reanchor_calendar','finish_project','set_due_turn'
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
  if cmd = 'close_recorded_order' then return public._bastion_cmd_close_recorded(doc, command); end if;
  if cmd = 'repay_loans' then return public._bastion_cmd_repay(doc, command); end if;
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
  if cmd = 'release_goods' then return public._bastion_cmd_release(doc, command); end if;
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
    'release_goods',
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
    'set_order_start',
    'close_recorded_order',
    'repay_loans'
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
    'clock', jsonb_build_object('turn', null, 'turnNeedsCheck', false, 'turnDays', 10, 'skipFestivals', true, 'anchor', null),
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
      and (p.proname like '\_bastion\_%' escape '\' or p.proname in ('handled_command_types', 'empty_document'))
  loop
    execute format('revoke all on function %s from public, anon, authenticated', fn);
  end loop;
end $$;
