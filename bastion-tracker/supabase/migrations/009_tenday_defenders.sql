-- Tenday turns, defender counts, loan payments, and turn notes.
--
-- Run this once after 008_release_goods.sql. Do not run 001 through 008 again.
-- It does not change cash. It does not move a calendar anchor or the turn counter.
-- The first run sets a ten-day turn that skips festival days, and folds generic
-- "Defender N" roster entries into the Barrack count. Named defenders stay.
-- A document already marked defenderMigration 009 is left alone.


create or replace function public._bastion_shift_date(anchor jsonb, amount int, skip boolean)
returns text
language plpgsql
set search_path = public
as $$
declare
  months text[] := array['hammer','alturiak','ches','tarsakh','mirtul','kythorn','flamerule','eleasis','eleint','marpenoth','uktar','nightal'];
  names text[] := array['Hammer','Alturiak','Ches','Tarsakh','Mirtul','Kythorn','Flamerule','Eleasis','Eleint','Marpenoth','Uktar','Nightal'];
  month text;
  day_n int;
  festival text;
  year_n int;
  leap boolean;
  left_n int;
  direction int;
  guard int := 0;
  label text;
begin
  festival := nullif(anchor->>'festival', '');
  month := nullif(anchor->>'month', '');
  day_n := nullif(anchor->>'day', '')::int;
  if anchor->>'year' is null or anchor->>'year' = '' then
    year_n := null;
  else
    year_n := (anchor->>'year')::int;
  end if;
  if festival is not null then
    day_n := null;
  end if;
  left_n := amount;
  direction := case when amount < 0 then -1 else 1 end;
  while left_n <> 0 loop
    guard := guard + 1;
    if guard > 4000 then
      return null;
    end if;
    if festival is not null then
      if festival = 'midwinter' then month := case when direction > 0 then 'alturiak' else 'hammer' end; day_n := case when direction > 0 then 1 else 30 end;
      elsif festival = 'greengrass' then month := case when direction > 0 then 'mirtul' else 'tarsakh' end; day_n := case when direction > 0 then 1 else 30 end;
      elsif festival = 'midsummer' then
        if direction > 0 and year_n is not null and year_n % 4 = 0 then festival := 'shieldmeet'; continue; end if;
        month := case when direction > 0 then 'eleasis' else 'flamerule' end; day_n := case when direction > 0 then 1 else 30 end;
      elsif festival = 'shieldmeet' then month := case when direction > 0 then 'eleasis' else 'flamerule' end; day_n := case when direction > 0 then 1 else 30 end; festival := null;
      elsif festival = 'highharvestide' then month := case when direction > 0 then 'marpenoth' else 'eleint' end; day_n := case when direction > 0 then 1 else 30 end;
      elsif festival = 'feast_of_the_moon' then month := case when direction > 0 then 'nightal' else 'uktar' end; day_n := case when direction > 0 then 1 else 30 end;
      else return null;
      end if;
      if festival is distinct from 'shieldmeet' then festival := null; end if;
      if festival is null then
        left_n := left_n - direction;
      end if;
      continue;
    end if;
    day_n := day_n + direction;
    if day_n > 30 then
      if month = 'hammer' then festival := 'midwinter';
      elsif month = 'tarsakh' then festival := 'greengrass';
      elsif month = 'flamerule' then festival := 'midsummer';
      elsif month = 'eleint' then festival := 'highharvestide';
      elsif month = 'uktar' then festival := 'feast_of_the_moon';
      else
        month := months[(array_position(months, month) % 12) + 1];
        if month = 'hammer' and year_n is not null then year_n := year_n + 1; end if;
      end if;
      day_n := null;
      if festival is null then
        day_n := 1;
        left_n := left_n - direction;
      elsif not skip then
        left_n := left_n - direction;
      end if;
    elsif day_n < 1 then
      if month = 'alturiak' then festival := 'midwinter';
      elsif month = 'mirtul' then festival := 'greengrass';
      elsif month = 'eleasis' then
        if year_n is not null and year_n % 4 = 0 then festival := 'shieldmeet'; else festival := 'midsummer'; end if;
      elsif month = 'marpenoth' then festival := 'highharvestide';
      elsif month = 'nightal' then festival := 'feast_of_the_moon';
      else
        month := months[((array_position(months, month) + 10) % 12) + 1];
        if month = 'nightal' and year_n is not null then year_n := year_n - 1; end if;
      end if;
      day_n := null;
      if festival is null then
        day_n := 30;
        left_n := left_n - direction;
      elsif not skip then
        left_n := left_n - direction;
      end if;
    else
      left_n := left_n - direction;
    end if;
  end loop;
  if festival is not null then
    label := case festival
      when 'midwinter' then 'Midwinter'
      when 'greengrass' then 'Greengrass'
      when 'midsummer' then 'Midsummer'
      when 'shieldmeet' then 'Shieldmeet'
      when 'highharvestide' then 'Highharvestide'
      when 'feast_of_the_moon' then 'Feast of the Moon'
      else festival end;
  else
    label := day_n::text || ' ' || names[array_position(months, month)];
  end if;
  if year_n is not null then
    label := label || ', ' || year_n::text || ' DR';
  end if;
  return label;
end;
$$;

create or replace function public._bastion_sync_label(doc jsonb)
returns jsonb
language plpgsql
set search_path = public
as $$
declare
  anchor jsonb := doc#>'{clock,anchor}';
  turn_n int;
  origin int;
  span int;
  days int;
  label text;
begin
  if doc#>>'{clock,turn}' is null or anchor is null or anchor = 'null'::jsonb or anchor->>'turn' is null then
    return doc;
  end if;
  turn_n := (doc#>>'{clock,turn}')::int;
  origin := (anchor->>'turn')::int;
  days := case when coalesce((doc#>>'{clock,turnDays}')::int, 10) = 7 then 7 else 10 end;
  span := days * (turn_n - origin);
  label := public._bastion_shift_date(anchor, span, coalesce((doc#>>'{clock,skipFestivals}')::boolean, true));
  if label is not null then
    doc := jsonb_set(doc, '{clock,label}', to_jsonb(label));
  end if;
  return doc;
end;
$$;

create or replace function public._bastion_migrate_defenders(doc jsonb)
returns jsonb
language plpgsql
set search_path = public
as $$
declare
  person jsonb;
  facility jsonb;
  kept jsonb := '[]'::jsonb;
  generic int;
  named int;
begin
  if coalesce(doc->>'defenderMigration', '') = '009' then
    return doc;
  end if;
  for person in select value from jsonb_array_elements(coalesce(doc->'roster', '[]'::jsonb)) value loop
    if coalesce(nullif(person->>'status', ''), 'active') = 'active'
       and person->>'category' = 'defender'
       and coalesce(person->>'facilityId', '') <> ''
       and (btrim(coalesce(person->>'name', '')) = '' or btrim(person->>'name') ~* '^Defender [0-9]+$') then
      continue;
    end if;
    kept := kept || jsonb_build_array(person);
  end loop;
  for facility in select value from jsonb_array_elements(coalesce(doc->'facilities', '[]'::jsonb)) value loop
    if facility->>'catalogId' is distinct from 'barrack' or facility->>'status' = 'archived' then
      continue;
    end if;
    select count(*) into generic
    from jsonb_array_elements(coalesce(doc->'roster', '[]'::jsonb)) elem
    where coalesce(nullif(elem->>'status', ''), 'active') = 'active'
      and elem->>'category' = 'defender'
      and elem->>'facilityId' = facility->>'id'
      and (btrim(coalesce(elem->>'name', '')) = '' or btrim(elem->>'name') ~* '^Defender [0-9]+$');
    select count(*) into named
    from jsonb_array_elements(coalesce(doc->'roster', '[]'::jsonb)) elem
    where coalesce(nullif(elem->>'status', ''), 'active') = 'active'
      and elem->>'category' = 'defender'
      and elem->>'facilityId' = facility->>'id'
      and not (btrim(coalesce(elem->>'name', '')) = '' or btrim(elem->>'name') ~* '^Defender [0-9]+$');
    facility := facility || jsonb_build_object('defenderCount', generic + named);
    doc := jsonb_set(doc, '{facilities}', public._bastion_replace(doc->'facilities', facility->>'id', facility));
  end loop;
  doc := jsonb_set(doc, '{roster}', kept);
  if doc#>>'{clock,turnDays}' is null then
    doc := jsonb_set(doc, '{clock,turnDays}', '10'::jsonb);
  end if;
  if doc#>>'{clock,skipFestivals}' is null then
    doc := jsonb_set(doc, '{clock,skipFestivals}', 'true'::jsonb);
  end if;
  doc := doc || jsonb_build_object('defenderMigration', '009');
  return doc;
end;
$$;

update public.estates
set document = public._bastion_migrate_defenders(document)
where coalesce(document->>'defenderMigration', '') <> '009';

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
  doc := public._bastion_sync_label(doc);
  doc := public._bastion_settle(doc, command->>'idempotencyKey');
  return public._bastion_out(doc, jsonb_build_object('turn', turn_n, 'date', doc#>>'{clock,label}'), format('Advanced to Bastion turn %s. The in-game date is %s.', turn_n, coalesce(doc#>>'{clock,label}', 'not set')));
end;
$$;

create or replace function public._bastion_cmd_defenders(doc jsonb, command jsonb)
returns jsonb
language plpgsql
set search_path = public
as $$
declare
  facility jsonb;
  count_n int;
  cap int;
begin
  facility := public._bastion_facility(doc, command->>'facilityId');
  count_n := public._bastion_whole(command->>'count', 0, 25, 'Defender count is a whole number from 0 to 25.');
  cap := case when facility->>'space' = 'vast' then 25 else 12 end;
  if facility->>'catalogId' = 'barrack' and count_n > cap then
    raise exception 'This barrack houses %, not %.', cap, count_n using errcode = '22023';
  end if;
  facility := facility || jsonb_build_object('defenderCount', count_n);
  doc := public._bastion_put_facility(doc, facility);
  return public._bastion_out(doc, jsonb_build_object('facilityId', facility->>'id', 'count', count_n), format('Recorded %s defenders at %s. No Recruit turn was run.', count_n, facility->>'name'));
end;
$$;

create or replace function public._bastion_cmd_close_recorded(doc jsonb, command jsonb)
returns jsonb
language plpgsql
set search_path = public
as $$
declare
  order_row jsonb;
  task jsonb;
  lot jsonb;
  choice text;
  tasks jsonb := '[]'::jsonb;
begin
  order_row := public._bastion_find(doc->'orders', command->>'orderId');
  if order_row is null or coalesce((order_row->>'recorded')::boolean, false) is not true then
    raise exception 'That recorded order is not on the record.' using errcode = '22023';
  end if;
  if order_row->>'status' not in ('in_progress', 'committed') then
    raise exception 'That order is already finished.' using errcode = '22023';
  end if;
  choice := case when command->>'choice' = 'cancel' then 'cancel' else 'done' end;
  for task in select value from jsonb_array_elements(public._bastion_arr(doc, 'tasks')) value loop
    if task->>'orderId' is distinct from order_row->>'id' and task->>'id' is distinct from order_row->>'taskId' then
      tasks := tasks || jsonb_build_array(task);
      continue;
    end if;
    if task->>'status' = 'open' and coalesce((task->>'settled')::boolean, false) = false and task->>'auto' = 'storehouse_sell' and coalesce(task->>'lotId', '') <> '' then
      lot := public._bastion_find(doc->'goods', task->>'lotId');
      if lot is not null then
        lot := jsonb_set(lot, '{reservedGp}', to_jsonb(greatest(0, coalesce((lot->>'reservedGp')::int, 0) - coalesce((task->>'standardGp')::int, 0))));
        doc := jsonb_set(doc, '{goods}', public._bastion_replace(doc->'goods', lot->>'id', lot));
      end if;
    end if;
    if task->>'status' = 'open' and coalesce((task->>'settled')::boolean, false) = false then
      task := task || jsonb_build_object('status', 'cancelled', 'settled', true);
    end if;
    tasks := tasks || jsonb_build_array(task);
  end loop;
  doc := jsonb_set(doc, '{tasks}', tasks);
  order_row := order_row || jsonb_build_object('status', case when choice = 'cancel' then 'cancelled' else 'resolved' end);
  doc := jsonb_set(doc, '{orders}', public._bastion_replace(doc->'orders', order_row->>'id', order_row));
  return public._bastion_out(doc, jsonb_build_object('orderId', order_row->>'id', 'status', order_row->>'status'), format('%s the order already underway%s. Cash was not changed.', case when choice = 'cancel' then 'Cancelled' else 'Marked done' end, case when coalesce(order_row->>'label', '') = '' then '' else ': ' || (order_row->>'label') end));
end;
$$;

create or replace function public._bastion_cmd_repay(doc jsonb, command jsonb)
returns jsonb
language plpgsql
set search_path = public
as $$
declare
  payment jsonb;
  loan jsonb;
  loans jsonb := '[]'::jsonb;
  treasury int;
  personal int;
  treasury_total int := 0;
  parts text := '';
begin
  if jsonb_typeof(command->'payments') is distinct from 'array' or jsonb_array_length(command->'payments') < 1 then
    raise exception 'Enter a payment for at least one loan.' using errcode = '22023';
  end if;
  for payment in select value from jsonb_array_elements(command->'payments') value loop
    loan := public._bastion_find(doc->'finance'->'loans', payment->>'loanId');
    if loan is null then
      raise exception 'That loan is not on the record.' using errcode = '22023';
    end if;
    treasury := coalesce(nullif(payment->>'treasuryGp', '')::int, 0);
    personal := coalesce(nullif(payment->>'personalGp', '')::int, 0);
    if treasury < 0 or personal < 0 then
      raise exception 'A loan payment is a whole number of GP, or zero.' using errcode = '22023';
    end if;
    if treasury + personal > coalesce((loan->>'amountGp')::int, 0) then
      raise exception 'A loan cannot be paid below zero.' using errcode = '22023';
    end if;
    treasury_total := treasury_total + treasury;
    loan := jsonb_set(loan, '{amountGp}', to_jsonb(coalesce((loan->>'amountGp')::int, 0) - treasury - personal));
    doc := jsonb_set(doc, '{finance,loans}', public._bastion_replace(doc#>'{finance,loans}', loan->>'id', loan));
    parts := parts || case when parts = '' then '' else '; ' end || coalesce(loan->>'creditor', 'Lender') || ': ' || treasury || ' GP from the treasury and ' || personal || ' GP from personal treasure';
  end loop;
  if treasury_total > 0 then
    doc := public._bastion_spend(doc, treasury_total, 'Loan payment from the treasury', command->>'idempotencyKey');
  end if;
  return public._bastion_out(doc, jsonb_build_object('treasuryGp', treasury_total), format('Loan payments recorded. %s. Personal treasure is not tracked as cash.', parts));
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
    'notes', left(coalesce(command->>'notes', ''), 600)
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
create or replace function public._bastion_close_facility(doc jsonb, facility_id text, command jsonb, out next_doc jsonb, out note text)
language plpgsql
set search_path = public
as $$
declare
  facility jsonb;
  defenders int;
  lieutenants int;
  hireling_count int;
  other_count int;
  order_count int;
  task_count int;
  project_count int;
  event_count int;
  choice text;
  released int := 0;
  archived_people int := 0;
  cancelled int := 0;
  purchase_kept boolean := false;
  person jsonb;
  task jsonb;
  order_row jsonb;
  project jsonb;
  lot jsonb;
  bits text[] := array[]::text[];
begin
  facility := public._bastion_facility(doc, facility_id);
  select count(*) into defenders
  from jsonb_array_elements(coalesce(doc->'roster', '[]'::jsonb)) elem
  where elem->>'facilityId' = facility_id
    and coalesce(nullif(elem->>'status', ''), 'active') = 'active'
    and elem->>'category' = 'defender';
  defenders := greatest(defenders, coalesce((facility->>'defenderCount')::int, 0));
  if defenders > 0 then
    raise exception '% still houses % %. Change the defender count before removing or replacing this room. Nobody was deleted, and cash was not changed.',
      facility->>'name', defenders, case when defenders = 1 then 'defender' else 'defenders' end
      using errcode = '22023';
  end if;
  select count(*) into lieutenants
  from jsonb_array_elements(coalesce(doc->'roster', '[]'::jsonb)) elem
  where elem->>'facilityId' = facility_id
    and coalesce(nullif(elem->>'status', ''), 'active') = 'active'
    and elem->>'category' = 'lieutenant';
  if lieutenants > 0 then
    raise exception '% still has % % assigned. Replace or release them before removing or replacing this room. Nobody was deleted, and cash was not changed.',
      facility->>'name', lieutenants, case when lieutenants = 1 then 'lieutenant' else 'lieutenants' end
      using errcode = '22023';
  end if;
  select count(*) into event_count
  from jsonb_array_elements(coalesce(doc->'events', '[]'::jsonb)) ev
  where ev->>'status' = 'pending'
    and (ev->>'facilityId' = facility_id or ev#>>'{detail,facilityId}' = facility_id or ev#>>'{detail,shutdown}' = facility_id);
  if event_count > 0 then
    raise exception 'A record still waiting on a decision names %. Resolve that before removing or replacing the room. Cash was not changed.',
      facility->>'name'
      using errcode = '22023';
  end if;
  select count(*) into order_count
  from jsonb_array_elements(coalesce(doc->'orders', '[]'::jsonb)) elem
  where elem->>'facilityId' = facility_id and public._bastion_order_unfinished(doc, elem);
  select count(*) into task_count
  from jsonb_array_elements(coalesce(doc->'tasks', '[]'::jsonb)) elem
  where public._bastion_task_pending(elem)
    and (
      elem->>'orderId' in (
        select src->>'id'
        from jsonb_array_elements(coalesce(doc->'orders', '[]'::jsonb)) src
        where src->>'facilityId' = facility_id and public._bastion_order_unfinished(doc, src)
      )
      or elem->>'id' in (
        select src->>'taskId'
        from jsonb_array_elements(coalesce(doc->'orders', '[]'::jsonb)) src
        where src->>'facilityId' = facility_id
          and src->>'taskId' is not null
          and public._bastion_order_unfinished(doc, src)
      )
    );
  select count(*) into project_count
  from jsonb_array_elements(coalesce(doc->'projects', '[]'::jsonb)) elem
  where elem->>'status' = 'building' and elem->>'facilityId' = facility_id;
  if (order_count > 0 or task_count > 0 or project_count > 0) and not public._bastion_flag(command->'cancelWork') then
    raise exception '% has unfinished work. Confirm that you want it cancelled. Cancelling does not pay a sale, deliver a purchase, or refund money already spent.',
      facility->>'name'
      using errcode = '22023';
  end if;
  select count(*) into hireling_count
  from jsonb_array_elements(coalesce(doc->'roster', '[]'::jsonb)) elem
  where elem->>'facilityId' = facility_id
    and coalesce(nullif(elem->>'status', ''), 'active') = 'active'
    and elem->>'category' = 'hireling';
  choice := command->>'hirelings';
  if hireling_count > 0 and coalesce(choice, '') not in ('release', 'archive') then
    raise exception '% still has % %. Choose whether they stay on the roster unassigned, or are marked released. They are not deleted either way.',
      facility->>'name', hireling_count, case when hireling_count = 1 then 'hireling' else 'hirelings' end
      using errcode = '22023';
  end if;

  if public._bastion_flag(command->'cancelWork') then
    for task in
      select elem
      from jsonb_array_elements(coalesce(doc->'tasks', '[]'::jsonb)) elem
      where public._bastion_task_pending(elem)
        and (
          elem->>'orderId' in (
            select src->>'id'
            from jsonb_array_elements(coalesce(doc->'orders', '[]'::jsonb)) src
            where src->>'facilityId' = facility_id and public._bastion_order_unfinished(doc, src)
          )
          or elem->>'id' in (
            select src->>'taskId'
            from jsonb_array_elements(coalesce(doc->'orders', '[]'::jsonb)) src
            where src->>'facilityId' = facility_id
              and src->>'taskId' is not null
              and public._bastion_order_unfinished(doc, src)
          )
        )
    loop
      if task->>'auto' = 'storehouse_sell' and coalesce((task->>'settled')::boolean, false) = false then
        lot := public._bastion_find(doc->'goods', task->>'lotId');
        if lot is not null then
          lot := jsonb_set(lot, '{reservedGp}', to_jsonb(greatest(0, coalesce((lot->>'reservedGp')::int, 0) - coalesce((task->>'standardGp')::int, 0))));
          doc := jsonb_set(doc, '{goods}', public._bastion_replace(doc->'goods', lot->>'id', lot));
        end if;
      end if;
      if task->>'auto' = 'storehouse_buy' and coalesce((task->>'settled')::boolean, false) = false then
        purchase_kept := true;
      end if;
      task := task || jsonb_build_object('status', 'cancelled', 'settled', false);
      doc := jsonb_set(doc, '{tasks}', public._bastion_replace(doc->'tasks', task->>'id', task));
    end loop;
    for order_row in
      select elem
      from jsonb_array_elements(coalesce(doc->'orders', '[]'::jsonb)) elem
      where elem->>'facilityId' = facility_id and public._bastion_order_unfinished(doc, elem)
    loop
      order_row := order_row || jsonb_build_object(
        'status', 'cancelled',
        'cancelledReason', 'DM closed the facility before this work finished. It was not resolved and it was not paid.'
      );
      doc := jsonb_set(doc, '{orders}', public._bastion_replace(doc->'orders', order_row->>'id', order_row));
      cancelled := cancelled + 1;
    end loop;
    for project in
      select elem
      from jsonb_array_elements(coalesce(doc->'projects', '[]'::jsonb)) elem
      where elem->>'status' = 'building' and elem->>'facilityId' = facility_id
    loop
      project := project || jsonb_build_object('status', 'cancelled');
      doc := jsonb_set(doc, '{projects}', public._bastion_replace(doc->'projects', project->>'id', project));
    end loop;
  end if;

  for person in
    select elem
    from jsonb_array_elements(coalesce(doc->'roster', '[]'::jsonb)) elem
    where elem->>'facilityId' = facility_id
      and coalesce(nullif(elem->>'status', ''), 'active') = 'active'
      and elem->>'category' = 'hireling'
  loop
    if choice = 'archive' then
      person := person || jsonb_build_object(
        'facilityId', null,
        'status', 'released',
        'summary', left(btrim(concat_ws(' ', nullif(person->>'summary', ''), 'Released when ' || (facility->>'name') || ' was closed.')), 160)
      );
      archived_people := archived_people + 1;
    else
      person := person || jsonb_build_object('facilityId', null);
      released := released + 1;
    end if;
    doc := jsonb_set(doc, '{roster}', public._bastion_replace(doc->'roster', person->>'id', person));
  end loop;
  select count(*) into other_count
  from jsonb_array_elements(coalesce(doc->'roster', '[]'::jsonb)) elem
  where elem->>'facilityId' = facility_id
    and coalesce(nullif(elem->>'status', ''), 'active') = 'active'
    and coalesce(elem->>'category', '') not in ('defender', 'lieutenant', 'hireling');
  for person in
    select elem
    from jsonb_array_elements(coalesce(doc->'roster', '[]'::jsonb)) elem
    where elem->>'facilityId' = facility_id
      and coalesce(nullif(elem->>'status', ''), 'active') = 'active'
      and coalesce(elem->>'category', '') not in ('defender', 'lieutenant', 'hireling')
  loop
    person := person || jsonb_build_object('facilityId', null);
    doc := jsonb_set(doc, '{roster}', public._bastion_replace(doc->'roster', person->>'id', person));
  end loop;

  facility := public._bastion_find(doc->'facilities', facility_id) || jsonb_build_object('currentOrderId', null);
  doc := public._bastion_put_facility(doc, facility);

  if other_count > 0 then
    bits := bits || format('%s other assigned %s kept on the roster and unassigned.', other_count, case when other_count = 1 then 'person was' else 'people were' end);
  end if;
  if released > 0 then
    bits := bits || format('%s hireling%s stayed on the roster, unassigned.', released, case when released = 1 then '' else 's' end);
  end if;
  if archived_people > 0 then
    bits := bits || format('%s hireling%s %s marked released and %s not deleted.', archived_people, case when archived_people = 1 then '' else 's' end, case when archived_people = 1 then 'was' else 'were' end, case when archived_people = 1 then 'was' else 'were' end);
  end if;
  if cancelled > 0 then
    bits := bits || format('%s unfinished order%s %s cancelled, not paid.', cancelled, case when cancelled = 1 then '' else 's' end, case when cancelled = 1 then 'was' else 'were' end);
  end if;
  if purchase_kept then
    bits := array_append(bits, 'Money already spent on a purchase was not refunded, and the goods were not delivered.');
  end if;
  note := case when coalesce(array_length(bits, 1), 0) = 0 then '' else ' ' || array_to_string(bits, ' ') end;
  next_doc := doc;
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
  doc := public._bastion_sync_label(doc);
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
  doc := public._bastion_sync_label(doc);
  label := case
    when coalesce(doc#>>'{clock,anchor,festival}', '') <> '' then initcap(doc#>>'{clock,anchor,festival}')
    else (doc#>>'{clock,anchor,day}') || ' ' || initcap(doc#>>'{clock,anchor,month}')
  end;
  return public._bastion_out(doc, jsonb_build_object('anchor', doc->'clock'->'anchor', 'text', label), format('Re-anchored turn %s to %s. Later turns follow this date. %s', doc#>>'{clock,turn}', label, reason));
end;
$$;
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
    'clock', jsonb_build_object('label', '', 'turn', null, 'turnNeedsCheck', false, 'turnDays', 10, 'skipFestivals', true, 'anchor', null),
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
