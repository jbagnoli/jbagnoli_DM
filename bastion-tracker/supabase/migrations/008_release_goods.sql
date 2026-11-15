-- Release reserved goods, and link a recorded Storehouse sale to a lot.
--
-- Run this once after 007_bastion_turns.sql. Do not run 001 through 007 again.
-- It does not change cash and it does not rewrite saved documents.
--
-- release_goods is DM-only, like reserve_goods. It clears all or part of a
-- lot's reserved amount and, when nothing remains reserved, the commitment
-- note. It does not move cash. It is refused while that amount is covered by
-- an open Storehouse sale. The sale is not cancelled.
--
-- Recording a Storehouse sell that is already underway now requires a lot and
-- a list price. It reuses a reservation that is not already tied to an open
-- sale, reserves any extra free amount, and creates one storehouse_sell task
-- due on the next Bastion turn. It does not pay the sale. The next take_turn
-- pays it once.


create or replace function public._bastion_cmd_release(doc jsonb, command jsonb)
returns jsonb
language plpgsql
set search_path = public
as $$
declare
  lot jsonb;
  task jsonb;
  reserved int;
  covered int := 0;
  releasable int;
  amount int;
begin
  lot := public._bastion_find(doc->'goods', command->>'lotId');
  if lot is null or lot->>'status' is distinct from 'on_hand' then
    raise exception 'Those goods are not on hand.' using errcode = '22023';
  end if;
  reserved := coalesce((lot->>'reservedGp')::int, 0);
  for task in
    select value from jsonb_array_elements(public._bastion_arr(doc, 'tasks')) value
    where value->>'lotId' = lot->>'id'
      and value->>'auto' = 'storehouse_sell'
      and value->>'status' = 'open'
      and coalesce((value->>'settled')::boolean, false) = false
  loop
    covered := covered + coalesce((task->>'standardGp')::int, 0);
  end loop;
  releasable := reserved - covered;
  if releasable <= 0 then
    raise exception 'Those goods are tied to an open Storehouse sale. That sale was not cancelled, and cash was not changed.' using errcode = '22023';
  end if;
  if command ? 'standardGp' and command->'standardGp' is distinct from 'null'::jsonb and coalesce(command->>'standardGp', '') <> '' then
    amount := public._bastion_whole(command->>'standardGp', 1, 2000000000, 'Release a whole number of GP above zero.');
  else
    amount := releasable;
  end if;
  if amount > releasable then
    raise exception 'That would release goods tied to an open Storehouse sale. Cash was not changed.' using errcode = '22023';
  end if;
  lot := lot || jsonb_build_object('reservedGp', reserved - amount);
  if coalesce((lot->>'reservedGp')::int, 0) <= 0 then
    lot := lot || jsonb_build_object('reservedGp', 0, 'commitment', '');
  end if;
  doc := jsonb_set(doc, '{goods}', public._bastion_replace(doc->'goods', lot->>'id', lot));
  return public._bastion_out(doc, jsonb_build_object('lotId', lot->>'id', 'reservedGp', (lot->>'reservedGp')::int, 'releasedGp', amount), format('Released %s GP of %s. Cash was not changed.', amount, coalesce(nullif(lot->>'name', ''), 'unnamed goods')));
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
  unit jsonb;
  started int;
  note text;
  existing jsonb;
  order_row jsonb;
  order_id text;
  lot jsonb;
  task jsonb;
  amount int;
  reserved int;
  covered int := 0;
  free_gp int;
  uncovered int;
  extra int;
  proceeds int;
  due int;
  task_id text;
  summary text;
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
  if existing is not null and sub->>'auto' = 'storehouse_sell' and coalesce(existing->>'taskId', '') <> '' then
    if exists (
      select 1 from jsonb_array_elements(public._bastion_arr(doc, 'tasks')) elem
      where elem->>'id' = existing->>'taskId' and elem->>'status' = 'open' and coalesce((elem->>'settled')::boolean, false) = false
    ) then
      raise exception 'That sale is already recorded. Cash was not changed.' using errcode = '22023';
    end if;
  end if;
  if existing is null then
    select taken.next_doc, taken.next_id into doc, order_id from public._bastion_take(doc, 'ord') as taken;
    order_row := jsonb_build_object('id', order_id, 'facilityId', facility->>'id', 'unitId', facility->>'unitId', 'recorded', true);
  else
    order_row := existing;
    order_id := existing->>'id';
  end if;
  order_row := (order_row - 'startedDay') || jsonb_build_object(
    'suborder', sub->>'id', 'label', sub->>'label', 'status', 'in_progress',
    'startedTurn', to_jsonb(started), 'startNeedsCheck', false, 'note', note,
    'auto', case when sub->>'auto' = 'storehouse_sell' then 'storehouse_sell' else null end,
    'recorded', true
  );
  summary := format('Marked %s as already running %s. No turn was resolved and no money moved.', facility->>'name', sub->>'label');
  if sub->>'auto' = 'storehouse_sell' then
    if doc#>>'{clock,turn}' is null then
      raise exception 'Set the Bastion turn before recording a sale that pays on the next turn.' using errcode = '22023';
    end if;
    lot := public._bastion_find(doc->'goods', command->>'lotId');
    if lot is null or lot->>'status' is distinct from 'on_hand' then
      raise exception 'Choose goods that are still on hand.' using errcode = '22023';
    end if;
    amount := public._bastion_whole(command->>'standardGp', 1, 2000000000, 'Sell a list-price amount that is still free.');
    for task in
      select value from jsonb_array_elements(public._bastion_arr(doc, 'tasks')) value
      where value->>'lotId' = lot->>'id' and value->>'auto' = 'storehouse_sell' and value->>'status' = 'open' and coalesce((value->>'settled')::boolean, false) = false
    loop
      covered := covered + coalesce((task->>'standardGp')::int, 0);
    end loop;
    reserved := coalesce((lot->>'reservedGp')::int, 0);
    free_gp := (lot->>'standardGp')::int - reserved;
    uncovered := greatest(0, reserved - covered);
    if amount > uncovered + free_gp then
      raise exception 'Sell a list-price amount that is still free.' using errcode = '22023';
    end if;
    extra := greatest(0, amount - uncovered);
    if extra > 0 then
      lot := jsonb_set(lot, '{reservedGp}', to_jsonb(reserved + extra));
      doc := jsonb_set(doc, '{goods}', public._bastion_replace(doc->'goods', lot->>'id', lot));
    end if;
    unit := public._bastion_unit(doc, facility->>'unitId');
    proceeds := public._bastion_proceeds(amount, (unit->>'level')::int);
    due := (doc#>>'{clock,turn}')::int + 1;
    select taken.next_doc, taken.next_id into doc, task_id from public._bastion_take(doc, 'task') as taken;
    doc := jsonb_set(doc, '{tasks}', public._bastion_arr(doc, 'tasks') || jsonb_build_array(jsonb_build_object(
      'id', task_id, 'status', 'open', 'settled', false, 'auto', 'storehouse_sell', 'unitId', facility->>'unitId',
      'orderId', order_id, 'lotId', lot->>'id', 'standardGp', amount, 'proceeds', proceeds, 'dueTurn', due, 'note', note, 'recorded', true
    )));
    order_row := order_row || jsonb_build_object('taskId', task_id, 'lotId', lot->>'id', 'dueTurn', due, 'auto', 'storehouse_sell');
    summary := format('Recorded a Storehouse sale of %s GP of %s already underway. Cash was not changed. It pays on the next Bastion turn.', amount, coalesce(nullif(lot->>'name', ''), 'goods'));
  end if;
  if existing is null then
    doc := jsonb_set(doc, '{orders}', public._bastion_arr(doc, 'orders') || jsonb_build_array(order_row));
  else
    doc := jsonb_set(doc, '{orders}', public._bastion_replace(doc->'orders', order_id, order_row));
  end if;
  facility := facility || jsonb_build_object('currentOrderId', order_id);
  doc := public._bastion_put_facility(doc, facility);
  return public._bastion_out(doc, jsonb_build_object('orderId', order_id, 'startedTurn', to_jsonb(started)), summary);
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
create or replace function public.handled_command_types()
returns text[]
language sql
immutable
set search_path = public
as $$
  select array[
    'set_settings','set_clock','set_finance','set_capabilities','raise_level','split_unit','add_special','replace_special','enlarge_special','add_basic','upgrade_basic','add_wall_squares','mark_enclosure','take_turn','roster_save','roster_remove','record_goods','commit_turn','resolve_event','dm_override','confirm_fall','import_accept','save_settings','set_level','record_defenders','set_loan','reserve_goods','release_goods','record_order','remove_goods','remove_person','edit_person','remove_facility','edit_facility','replace_basic','correct_special','replace_person','assign_person','cancel_project','set_order_start','set_calendar_anchor','reanchor_calendar','finish_project','set_due_turn'
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
