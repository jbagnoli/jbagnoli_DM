-- Teach apply_command every order the tracker can send, and start new
-- estates on a 10-day turn. Existing estate rows are not rewritten.
-- A bastion that is already saved keeps its turn length until Settings changes it.

create or replace function public.handled_command_types()
returns text[]
language sql
immutable
set search_path = public
as $$
  select array[
    'set_settings',
    'set_clock',
    'set_finance',
    'set_capabilities',
    'raise_level',
    'split_unit',
    'add_special',
    'replace_special',
    'enlarge_special',
    'add_basic',
    'upgrade_basic',
    'add_wall_squares',
    'mark_enclosure',
    'advance_days',
    'roster_save',
    'roster_remove',
    'record_goods',
    'commit_turn',
    'resolve_event',
    'dm_override',
    'confirm_fall',
    'import_accept',
    'save_settings',
    'set_level',
    'record_defenders',
    'set_loan',
    'reserve_goods',
    'record_order'
  ]::text[];
$$;

create or replace function public._bastion_catalog()
returns jsonb
language sql
immutable
set search_path = public
as $fn$
  select $catalog${"rooms":{"bedroom":"Bedroom","dining":"Dining room","parlor":"Parlor","courtyard":"Courtyard","kitchen":"Kitchen","storage":"Storage"},"squares":{"cramped":4,"roomy":16,"vast":36},"build":{"cramped":{"gp":500,"days":20},"roomy":{"gp":1000,"days":45},"vast":{"gp":3000,"days":125}},"upgrade":{"cramped":{"to":"roomy","gp":500,"days":25},"roomy":{"to":"vast","gp":2000,"days":80}},"wall":{"gp":250,"days":10},"events":[{"id":"all_is_well","min":1,"max":50,"name":"All is well"},{"id":"attack","min":51,"max":55,"name":"Attack"},{"id":"criminal","min":56,"max":58,"name":"Criminal hireling"},{"id":"opportunity","min":59,"max":63,"name":"Extraordinary opportunity"},{"id":"visitors","min":64,"max":72,"name":"Friendly visitors"},{"id":"guest","min":73,"max":76,"name":"Guest"},{"id":"lost_hirelings","min":77,"max":79,"name":"Lost hirelings"},{"id":"magic","min":80,"max":83,"name":"Magical discovery"},{"id":"refugees","min":84,"max":91,"name":"Refugees"},{"id":"aid","min":92,"max":98,"name":"Request for aid"},{"id":"treasure","min":99,"max":100,"name":"Treasure"}],"specials":[{"id":"arcane_study","name":"Arcane Study","level":5,"prereq":"arcane_or_tool","unique":true,"space":"roomy","hirelings":1,"enlargeGp":null,"enlargeHirelings":0,"subs":[{"id":"craft","label":"Craft an ordinary item","days":null,"auto":"manual","note":"Enter the time and price from the crafting rules you use."},{"id":"craft_magic","label":"Craft a magic implement","days":null,"auto":"manual","note":"Level 9 or higher. Enter chapter-approved time and price. Do not guess them."}]},{"id":"armory","name":"Armory","level":5,"prereq":null,"unique":true,"space":"roomy","hirelings":1,"enlargeGp":null,"enlargeHirelings":0,"subs":[{"id":"stock","label":"Stock the armory","days":0,"auto":"armory_stock","note":""}]},{"id":"barrack","name":"Barrack","level":5,"prereq":null,"unique":false,"space":"roomy","hirelings":1,"enlargeGp":2000,"enlargeHirelings":0,"subs":[{"id":"recruit","label":"Recruit defenders","days":0,"auto":"barrack_recruit","note":""}]},{"id":"garden","name":"Garden","level":5,"prereq":null,"unique":false,"space":"roomy","hirelings":1,"enlargeGp":2000,"enlargeHirelings":1,"subs":[{"id":"harvest","label":"Harvest","days":7,"auto":"manual","note":"Record what was gathered. The chapter does not set a GP yield."},{"id":"convert","label":"Change the crop","days":21,"auto":"manual","note":"The garden is busy for 21 days."}]},{"id":"library","name":"Library","level":5,"prereq":null,"unique":true,"space":"roomy","hirelings":1,"enlargeGp":null,"enlargeHirelings":0,"subs":[{"id":"research","label":"Research","days":7,"auto":"manual","note":"Deliver the facts at the next contact. Three is the usual maximum."}]},{"id":"sanctuary","name":"Sanctuary","level":5,"prereq":"holy_or_druid","unique":true,"space":"roomy","hirelings":1,"enlargeGp":null,"enlargeHirelings":0,"subs":[{"id":"charm","label":"Prepare a charm","days":7,"auto":"manual","note":""}]},{"id":"smithy","name":"Smithy","level":5,"prereq":null,"unique":true,"space":"roomy","hirelings":2,"enlargeGp":null,"enlargeHirelings":0,"subs":[{"id":"craft","label":"Smith ordinary gear","days":null,"auto":"manual","note":""},{"id":"craft_magic","label":"Craft a magic armament","days":null,"auto":"manual","note":"Level 9 or higher. Enter approved time and price."}]},{"id":"storehouse","name":"Storehouse","level":5,"prereq":null,"unique":true,"space":"roomy","hirelings":1,"enlargeGp":null,"enlargeHirelings":0,"subs":[{"id":"buy","label":"Buy goods","days":7,"auto":"storehouse_buy","note":""},{"id":"sell","label":"Sell goods","days":7,"auto":"storehouse_sell","note":""}]},{"id":"workshop","name":"Workshop","level":5,"prereq":null,"unique":true,"space":"roomy","hirelings":3,"enlargeGp":2000,"enlargeHirelings":2,"subs":[{"id":"craft","label":"Craft ordinary gear","days":null,"auto":"manual","note":""},{"id":"craft_magic","label":"Craft a magic implement","days":null,"auto":"manual","note":"Level 9 or higher. Enter approved time and price."}]},{"id":"gaming_hall","name":"Gaming Hall","level":9,"prereq":null,"unique":true,"space":"vast","hirelings":4,"enlargeGp":null,"enlargeHirelings":0,"subs":[{"id":"gamble","label":"Run the tables","days":7,"auto":"manual","note":"Enter the roll and the resulting GP when you have them."}]},{"id":"greenhouse","name":"Greenhouse","level":9,"prereq":null,"unique":true,"space":"roomy","hirelings":1,"enlargeGp":null,"enlargeHirelings":0,"subs":[{"id":"harvest","label":"Harvest","days":7,"auto":"manual","note":""}]},{"id":"laboratory","name":"Laboratory","level":9,"prereq":null,"unique":true,"space":"roomy","hirelings":1,"enlargeGp":null,"enlargeHirelings":0,"subs":[{"id":"poison","label":"Brew a poison","days":7,"auto":"manual","note":"Enter the listed price. The tracker will halve that number and will not invent one."}]},{"id":"sacristy","name":"Sacristy","level":9,"prereq":"holy_or_druid","unique":true,"space":"roomy","hirelings":1,"enlargeGp":null,"enlargeHirelings":0,"subs":[{"id":"holy_water","label":"Prepare holy water","days":7,"auto":"manual","note":"Optional extra GP in 100 GP steps, maximum 500."}]},{"id":"scriptorium","name":"Scriptorium","level":9,"prereq":null,"unique":true,"space":"roomy","hirelings":1,"enlargeGp":null,"enlargeHirelings":0,"subs":[{"id":"copy","label":"Copy a book","days":7,"auto":"manual","note":"Requires a blank book."},{"id":"paperwork","label":"Copy paperwork","days":7,"auto":"manual","note":"Up to 50 copies, 1 GP each, delivered within 50 miles."},{"id":"scroll","label":"Copy a spell scroll","days":null,"auto":"manual","note":"Enter Player's Handbook time and price."}]},{"id":"stable","name":"Stable","level":9,"prereq":null,"unique":false,"space":"roomy","hirelings":1,"enlargeGp":2000,"enlargeHirelings":0,"subs":[{"id":"trade","label":"Buy or sell mounts","days":7,"auto":"manual","note":"Enter the list price. The sale bonus is applied to the price you enter."}]},{"id":"teleportation_circle","name":"Teleportation Circle","level":9,"prereq":null,"unique":true,"space":"roomy","hirelings":1,"enlargeGp":null,"enlargeHirelings":0,"subs":[{"id":"invite","label":"Invite a spellcaster","days":0,"auto":"manual","note":"Roll any die. Odd declines. Even accepts. Record the spell limit yourself."}]},{"id":"theater","name":"Theater","level":9,"prereq":null,"unique":true,"space":"vast","hirelings":4,"enlargeGp":null,"enlargeHirelings":0,"subs":[{"id":"rehearse","label":"Rehearse","days":14,"auto":"manual","note":""},{"id":"show","label":"Stage a show","days":7,"auto":"manual","note":""}]},{"id":"training_area","name":"Training Area","level":9,"prereq":null,"unique":false,"space":"vast","hirelings":4,"enlargeGp":null,"enlargeHirelings":0,"subs":[{"id":"train","label":"Train","days":7,"auto":"manual","note":""}]},{"id":"trophy_room","name":"Trophy Room","level":9,"prereq":null,"unique":true,"space":"roomy","hirelings":1,"enlargeGp":null,"enlargeHirelings":0,"subs":[{"id":"research","label":"Research a trophy","days":7,"auto":"manual","note":""}]},{"id":"archive","name":"Archive","level":13,"prereq":null,"unique":true,"space":"roomy","hirelings":1,"enlargeGp":2000,"enlargeHirelings":0,"subs":[{"id":"research","label":"Consult the archive","days":7,"auto":"manual","note":""}]},{"id":"meditation_chamber","name":"Meditation Chamber","level":13,"prereq":null,"unique":true,"space":"cramped","hirelings":1,"enlargeGp":null,"enlargeHirelings":0,"subs":[{"id":"focus","label":"Meditate","days":7,"auto":"manual","note":""}]},{"id":"menagerie","name":"Menagerie","level":13,"prereq":null,"unique":true,"space":"vast","hirelings":2,"enlargeGp":null,"enlargeHirelings":0,"subs":[{"id":"recruit","label":"Recruit a creature","days":7,"auto":"manual","note":"Enter the price and whether it counts as a defender."}]},{"id":"observatory","name":"Observatory","level":13,"prereq":"spellcasting_focus","unique":true,"space":"roomy","hirelings":1,"enlargeGp":null,"enlargeHirelings":0,"subs":[{"id":"charm","label":"Read the sky","days":7,"auto":"manual","note":""}]},{"id":"pub","name":"Pub","level":13,"prereq":null,"unique":true,"space":"roomy","hirelings":1,"enlargeGp":2000,"enlargeHirelings":3,"subs":[{"id":"rumor","label":"Listen for rumors","days":7,"auto":"manual","note":""}]},{"id":"reliquary","name":"Reliquary","level":13,"prereq":"holy_or_druid","unique":true,"space":"cramped","hirelings":1,"enlargeGp":null,"enlargeHirelings":0,"subs":[{"id":"talisman","label":"Prepare a talisman","days":7,"auto":"manual","note":""}]},{"id":"demiplane","name":"Demiplane","level":17,"prereq":"arcane_or_tool","unique":true,"space":"vast","hirelings":1,"enlargeGp":null,"enlargeHirelings":0,"subs":[{"id":"attune","label":"Use the demiplane","days":0,"auto":"manual","note":""}]},{"id":"guildhall","name":"Guildhall","level":17,"prereq":"expertise","unique":true,"space":"vast","hirelings":1,"enlargeGp":null,"enlargeHirelings":0,"subs":[{"id":"assign","label":"Give a guild assignment","days":null,"auto":"manual","note":"Enter the rolled or stated duration and any GP."}]},{"id":"sanctum","name":"Sanctum","level":17,"prereq":"holy_or_druid","unique":true,"space":"roomy","hirelings":4,"enlargeGp":null,"enlargeHirelings":0,"subs":[{"id":"empower","label":"Empower","days":7,"auto":"manual","note":""}]},{"id":"war_room","name":"War Room","level":17,"prereq":"fighting_or_unarmored","unique":true,"space":"vast","hirelings":2,"enlargeGp":null,"enlargeHirelings":0,"subs":[{"id":"lieutenant","label":"Recruit a lieutenant","days":0,"auto":"war_lieutenant","note":""},{"id":"army","label":"Muster soldiers","days":7,"auto":"manual","note":"100 guards or 20 mounted per lieutenant. Enter feed costs. The army is not tracked as free defenders."}]}]}$catalog$::jsonb;
$fn$;

create or replace function public._bastion_out(doc jsonb, result jsonb, summary text)
returns jsonb
language sql
immutable
set search_path = public
as $$
  select jsonb_build_object('doc', doc, 'result', coalesce(result, '{}'::jsonb), 'summary', summary);
$$;

create or replace function public._bastion_flag(value jsonb)
returns boolean
language sql
immutable
set search_path = public
as $$
  select coalesce(value, 'false'::jsonb) = 'true'::jsonb;
$$;

create or replace function public._bastion_cap(level int)
returns int
language sql
immutable
set search_path = public
as $$
  select case
    when level < 5 then 0
    when level < 9 then 2
    when level < 13 then 4
    when level < 17 then 5
    else 6
  end;
$$;

create or replace function public._bastion_proceeds(standard_gp int, level int)
returns int
language sql
immutable
set search_path = public
as $$
  select round(standard_gp * (10000 + case
    when level >= 17 then 10000
    when level >= 13 then 5000
    when level >= 9 then 2000
    else 1000
  end) / 10000.0)::int;
$$;

create or replace function public._bastion_buy_limit(level int)
returns int
language sql
immutable
set search_path = public
as $$
  select case when level >= 13 then 5000 when level >= 9 then 2000 else 500 end;
$$;

create or replace function public._bastion_take(doc jsonb, prefix text, out next_doc jsonb, out next_id text)
language plpgsql
set search_path = public
as $$
declare
  n int;
begin
  n := coalesce((doc->>'seq')::int, 0) + 1;
  next_doc := jsonb_set(doc, '{seq}', to_jsonb(n));
  next_id := prefix || '-' || n::text;
end;
$$;

create or replace function public._bastion_arr(doc jsonb, key text)
returns jsonb
language sql
immutable
set search_path = public
as $$
  select coalesce(doc->key, '[]'::jsonb);
$$;

create or replace function public._bastion_find(arr jsonb, item_id text)
returns jsonb
language sql
stable
set search_path = public
as $$
  select elem
  from jsonb_array_elements(coalesce(arr, '[]'::jsonb)) elem
  where elem->>'id' = item_id
  limit 1;
$$;

create or replace function public._bastion_replace(arr jsonb, item_id text, item jsonb)
returns jsonb
language sql
immutable
set search_path = public
as $$
  select coalesce(
    jsonb_agg(case when elem->>'id' = item_id then item else elem end order by ord),
    '[]'::jsonb
  )
  from jsonb_array_elements(coalesce(arr, '[]'::jsonb)) with ordinality as t(elem, ord);
$$;

create or replace function public._bastion_remove(arr jsonb, item_id text)
returns jsonb
language sql
immutable
set search_path = public
as $$
  select coalesce(jsonb_agg(elem order by ord), '[]'::jsonb)
  from jsonb_array_elements(coalesce(arr, '[]'::jsonb)) with ordinality as t(elem, ord)
  where elem->>'id' is distinct from item_id;
$$;

create or replace function public._bastion_spec(spec_id text)
returns jsonb
language sql
stable
set search_path = public
as $$
  select elem
  from jsonb_array_elements(public._bastion_catalog()->'specials') elem
  where elem->>'id' = spec_id
  limit 1;
$$;

create or replace function public._bastion_event_name(event_id text)
returns text
language sql
stable
set search_path = public
as $$
  select elem->>'name'
  from jsonb_array_elements(public._bastion_catalog()->'events') elem
  where elem->>'id' = event_id
  limit 1;
$$;

create or replace function public._bastion_event_type(roll int)
returns text
language sql
stable
set search_path = public
as $$
  select elem->>'id'
  from jsonb_array_elements(public._bastion_catalog()->'events') elem
  where roll >= (elem->>'min')::int and roll <= (elem->>'max')::int
  limit 1;
$$;

create or replace function public._bastion_clock(doc jsonb)
returns int
language plpgsql
set search_path = public
as $$
begin
  if doc#>>'{clock,ordinal}' is null then
    raise exception 'Set an in-game day before starting something that takes days. The date can stay blank until you know it.'
      using errcode = '22023';
  end if;
  return (doc#>>'{clock,ordinal}')::int;
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
    'id', entry_id,
    'gp', -gp,
    'reason', reason,
    'day', doc#>'{clock,ordinal}',
    'key', to_jsonb(idem_key)
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
    'id', entry_id,
    'gp', gp,
    'reason', reason,
    'day', doc#>'{clock,ordinal}',
    'key', to_jsonb(idem_key)
  )));
  return doc;
end;
$$;

create or replace function public._bastion_unit(doc jsonb, unit_id text)
returns jsonb
language plpgsql
set search_path = public
as $$
declare
  unit jsonb;
begin
  if unit_id is null or unit_id = '' then
    unit := doc#>'{units,0}';
  else
    unit := public._bastion_find(doc->'units', unit_id);
  end if;
  if unit is null then
    raise exception 'That ownership unit is not on this estate.' using errcode = '22023';
  end if;
  return unit;
end;
$$;

create or replace function public._bastion_put_unit(doc jsonb, unit jsonb)
returns jsonb
language sql
immutable
set search_path = public
as $$
  select jsonb_set(doc, '{units}', public._bastion_replace(doc->'units', unit->>'id', unit));
$$;

create or replace function public._bastion_facility(doc jsonb, facility_id text)
returns jsonb
language plpgsql
set search_path = public
as $$
declare
  facility jsonb;
begin
  facility := public._bastion_find(doc->'facilities', facility_id);
  if facility is null or facility->>'status' = 'archived' then
    raise exception 'That facility is not active.' using errcode = '22023';
  end if;
  return facility;
end;
$$;

create or replace function public._bastion_put_facility(doc jsonb, facility jsonb)
returns jsonb
language sql
immutable
set search_path = public
as $$
  select jsonb_set(doc, '{facilities}', public._bastion_replace(doc->'facilities', facility->>'id', facility));
$$;

create or replace function public._bastion_whole(raw text, lo int, hi int, message text)
returns int
language plpgsql
set search_path = public
as $$
declare
  n int;
begin
  if raw is null or raw !~ '^-?[0-9]+$' then
    raise exception '%', message using errcode = '22023';
  end if;
  n := raw::int;
  if n < lo or n > hi then
    raise exception '%', message using errcode = '22023';
  end if;
  return n;
end;
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
  gained int;
  granted int;
begin
  if next_level < 1 or next_level > 20 then
    raise exception 'Choose a level from 1 to 20.' using errcode = '22023';
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
  gained := next_level - (unit->>'level')::int;
  granted := case when grant_flag and gained > 0 then gained else 0 end;
  next_unit := jsonb_set(unit, '{level}', to_jsonb(next_level));
  next_unit := jsonb_set(next_unit, '{replacementBank}', to_jsonb(coalesce((unit->>'replacementBank')::int, 0) + granted));
  if granted > 0 then
    note := format('Level %s. One replacement was added for each level gained (%s).', next_level, granted);
  else
    note := format('Level set to %s. No replacement was added.', next_level);
  end if;
end;
$$;

create or replace function public._bastion_filter_caps(items jsonb)
returns jsonb
language sql
immutable
set search_path = public
as $$
  select coalesce(jsonb_agg(item), '[]'::jsonb)
  from jsonb_array_elements_text(coalesce(items, '[]'::jsonb)) item
  where item in ('arcane_or_tool', 'holy_or_druid', 'spellcasting_focus', 'expertise', 'fighting_or_unarmored');
$$;

create or replace function public._bastion_cmd_settings(doc jsonb, command jsonb)
returns jsonb
language plpgsql
set search_path = public
as $$
declare
  days int;
  unit jsonb;
begin
  if coalesce(command->>'name', '') <> '' then
    doc := jsonb_set(doc, '{name}', to_jsonb(left(command->>'name', 80)));
  end if;
  if command ? 'cadenceDays' and command->>'cadenceDays' is not null and command->>'cadenceDays' <> '' then
    days := public._bastion_whole(command->>'cadenceDays', 1, 365, 'Cadence is a whole number of in-game days, at least 1.');
    doc := jsonb_set(doc, '{clock,cadenceDays}', to_jsonb(days));
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
  return public._bastion_out(doc, jsonb_build_object('cadenceDays', doc#>'{clock,cadenceDays}'), 'Updated estate settings.');
end;
$$;

create or replace function public._bastion_cmd_clock(doc jsonb, command jsonb)
returns jsonb
language plpgsql
set search_path = public
as $$
declare
  ordinal int;
begin
  if command ? 'label' then
    doc := jsonb_set(doc, '{clock,label}', to_jsonb(left(coalesce(command->>'label', ''), 120)));
  end if;
  if command ? 'ordinal' then
    if command->'ordinal' = 'null'::jsonb or command->>'ordinal' is null or command->>'ordinal' = '' then
      doc := jsonb_set(doc, '{clock,ordinal}', 'null'::jsonb);
    else
      ordinal := public._bastion_whole(command->>'ordinal', 0, 2000000000, 'The day count has to be a whole number, or stay unknown.');
      doc := jsonb_set(doc, '{clock,ordinal}', to_jsonb(ordinal));
    end if;
  end if;
  return public._bastion_out(doc, jsonb_build_object('clock', doc->'clock'), 'Updated the in-game clock.');
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
    'id', entry_id, 'gp', 0, 'reason', 'Opening cash set to ' || cash || ' GP', 'day', doc#>'{clock,ordinal}', 'key', command->'idempotencyKey'
  )));
  return public._bastion_out(doc, jsonb_build_object('cashGp', cash), format('Set opening cash to %s GP.', cash));
end;
$$;

create or replace function public._bastion_cmd_capabilities(doc jsonb, command jsonb)
returns jsonb
language plpgsql
set search_path = public
as $$
declare
  unit jsonb;
  caps jsonb;
begin
  unit := public._bastion_unit(doc, command->>'unitId');
  caps := public._bastion_filter_caps(command->'capabilities');
  unit := jsonb_set(unit, '{capabilities}', caps);
  doc := public._bastion_put_unit(doc, unit);
  return public._bastion_out(doc, jsonb_build_object('capabilities', caps), 'Updated facility prerequisites for this owner.');
end;
$$;

create or replace function public._bastion_cmd_raise(doc jsonb, command jsonb)
returns jsonb
language plpgsql
set search_path = public
as $$
declare
  unit jsonb;
  level int;
  gained int;
begin
  unit := public._bastion_unit(doc, command->>'unitId');
  if command->>'level' is null or command->>'level' !~ '^[0-9]+$' then
    raise exception 'The new level has to be the same or higher, up to 20.' using errcode = '22023';
  end if;
  level := (command->>'level')::int;
  if level < (unit->>'level')::int or level > 20 then
    raise exception 'The new level has to be the same or higher, up to 20.' using errcode = '22023';
  end if;
  gained := level - (unit->>'level')::int;
  unit := jsonb_set(unit, '{level}', to_jsonb(level));
  unit := jsonb_set(unit, '{replacementBank}', to_jsonb(coalesce((unit->>'replacementBank')::int, 0) + gained));
  doc := public._bastion_put_unit(doc, unit);
  return public._bastion_out(
    doc,
    jsonb_build_object('level', level, 'gainedReplacements', gained, 'bank', (unit->>'replacementBank')::int),
    case when gained > 0 then format('Level %s. One replacement was added for each level gained (%s).', level, gained) else 'Level unchanged.' end
  );
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
  level := public._bastion_whole(command->>'level', 1, 20, 'Choose a level from 1 to 20.');
  select applied.next_unit, applied.note into unit, note
  from public._bastion_apply_level(doc, unit, level, public._bastion_flag(command->'grantReplacements')) as applied;
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
  days int;
  unit jsonb;
  ordinal int;
  level int;
  note text := 'Level unchanged. No replacement was added.';
  caps jsonb;
begin
  if coalesce(command->>'name', '') <> '' then
    doc := jsonb_set(doc, '{name}', to_jsonb(left(command->>'name', 80)));
  end if;
  if command ? 'cadenceDays' and coalesce(command->>'cadenceDays', '') <> '' then
    days := public._bastion_whole(command->>'cadenceDays', 1, 365, 'Cadence is a whole number of in-game days, at least 1.');
    doc := jsonb_set(doc, '{clock,cadenceDays}', to_jsonb(days));
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
  if command ? 'ordinal' then
    if command->'ordinal' = 'null'::jsonb or command->>'ordinal' is null or command->>'ordinal' = '' then
      doc := jsonb_set(doc, '{clock,ordinal}', 'null'::jsonb);
    else
      ordinal := public._bastion_whole(command->>'ordinal', 0, 2000000000, 'The day count has to be a whole number, or stay unknown.');
      doc := jsonb_set(doc, '{clock,ordinal}', to_jsonb(ordinal));
    end if;
  end if;
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
    jsonb_build_object('cadenceDays', doc#>'{clock,cadenceDays}', 'level', (unit->>'level')::int, 'bank', (unit->>'replacementBank')::int),
    'Saved settings. ' || note
  );
end;
$$;

create or replace function public._bastion_active_count(doc jsonb, unit_id text)
returns int
language sql
stable
set search_path = public
as $$
  select count(*)::int
  from jsonb_array_elements(coalesce(doc->'facilities', '[]'::jsonb)) elem
  where elem->>'unitId' = unit_id and elem->>'kind' = 'special' and elem->>'status' = 'active';
$$;

create or replace function public._bastion_make_special(doc jsonb, unit jsonb, spec jsonb, acquired text, out next_doc jsonb, out facility jsonb)
language plpgsql
set search_path = public
as $$
declare
  facility_id text;
begin
  select taken.next_doc, taken.next_id into next_doc, facility_id from public._bastion_take(doc, 'fac') as taken;
  facility := jsonb_build_object(
    'id', facility_id,
    'unitId', unit->>'id',
    'kind', 'special',
    'catalogId', spec->>'id',
    'name', spec->>'name',
    'space', spec->>'space',
    'hirelings', (spec->>'hirelings')::int,
    'status', 'active',
    'acquired', acquired,
    'stocked', false,
    'shutdownUntilTurnId', null,
    'blockedOnTurnId', null,
    'plots', 1,
    'vastCapacityLarge', case when spec->>'id' = 'stable' then to_jsonb(3) else 'null'::jsonb end
  );
  next_doc := jsonb_set(next_doc, '{facilities}', public._bastion_arr(next_doc, 'facilities') || jsonb_build_array(facility));
end;
$$;

create or replace function public._bastion_require_eligible(doc jsonb, unit jsonb, spec jsonb, ignore_id text)
returns void
language plpgsql
set search_path = public
as $$
declare
  cap int;
begin
  if spec is null then
    raise exception 'That facility is not in the bastion list.' using errcode = '22023';
  end if;
  if (unit->>'level')::int < (spec->>'level')::int then
    raise exception '% requires level %. This unit is level %.', spec->>'name', (spec->>'level')::int, (unit->>'level')::int
      using errcode = '22023';
  end if;
  if coalesce(spec->>'prereq', '') <> '' and not (coalesce(unit->'capabilities', '[]'::jsonb) ? (spec->>'prereq')) then
    raise exception '% needs a capability this unit does not have yet. Add it in settings if the character qualifies.', spec->>'name'
      using errcode = '22023';
  end if;
  if coalesce((spec->>'unique')::boolean, false) and exists (
    select 1 from jsonb_array_elements(coalesce(doc->'facilities', '[]'::jsonb)) elem
    where elem->>'unitId' = unit->>'id'
      and elem->>'catalogId' = spec->>'id'
      and elem->>'status' = 'active'
      and elem->>'id' is distinct from ignore_id
  ) then
    raise exception '% can be kept only once. Barrack, Garden, Stable, and Training Area are the repeats.', spec->>'name'
      using errcode = '22023';
  end if;
  cap := public._bastion_cap((unit->>'level')::int);
  if ignore_id is null and public._bastion_active_count(doc, unit->>'id') >= cap then
    raise exception 'Level % allows % special facilities. Replace one, or raise the level, before adding another.', (unit->>'level')::int, cap
      using errcode = '22023';
  end if;
end;
$$;

create or replace function public._bastion_cmd_add_special(doc jsonb, command jsonb)
returns jsonb
language plpgsql
set search_path = public
as $$
declare
  unit jsonb;
  spec jsonb;
  facility jsonb;
begin
  unit := public._bastion_unit(doc, command->>'unitId');
  spec := public._bastion_spec(command->>'catalogId');
  perform public._bastion_require_eligible(doc, unit, spec, null);
  select made.next_doc, made.facility into doc, facility
  from public._bastion_make_special(doc, unit, spec, coalesce(nullif(command->>'acquired', ''), 'level')) as made;
  return public._bastion_out(doc, jsonb_build_object('facilityId', facility->>'id'), format('Added %s. No build cost, because specials come from level.', facility->>'name'));
end;
$$;

create or replace function public._bastion_cmd_replace(doc jsonb, command jsonb)
returns jsonb
language plpgsql
set search_path = public
as $$
declare
  unit jsonb;
  current jsonb;
  spec jsonb;
  facility jsonb;
  override boolean;
  archive_reason text;
begin
  unit := public._bastion_unit(doc, command->>'unitId');
  current := public._bastion_facility(doc, command->>'facilityId');
  if current->>'unitId' is distinct from unit->>'id' then
    raise exception 'That facility belongs to another owner.' using errcode = '22023';
  end if;
  if current->>'kind' is distinct from 'special' then
    raise exception 'That facility is not active.' using errcode = '22023';
  end if;
  spec := public._bastion_spec(command->>'catalogId');
  if spec is null then
    raise exception 'That replacement is not in the bastion list.' using errcode = '22023';
  end if;
  if (unit->>'level')::int < (spec->>'level')::int then
    raise exception '% requires level %.', spec->>'name', (spec->>'level')::int using errcode = '22023';
  end if;
  if coalesce(spec->>'prereq', '') <> '' and not (coalesce(unit->'capabilities', '[]'::jsonb) ? (spec->>'prereq')) then
    raise exception '% needs a capability this unit does not have.', spec->>'name' using errcode = '22023';
  end if;
  if coalesce((spec->>'unique')::boolean, false) and exists (
    select 1 from jsonb_array_elements(doc->'facilities') elem
    where elem->>'unitId' = unit->>'id' and elem->>'catalogId' = spec->>'id' and elem->>'status' = 'active' and elem->>'id' is distinct from current->>'id'
  ) then
    raise exception '% is already kept.', spec->>'name' using errcode = '22023';
  end if;
  override := public._bastion_flag(command->'dmOverride');
  if override and btrim(coalesce(command->>'reason', '')) = '' then
    raise exception 'Write why this replacement skips the normal limit.' using errcode = '22023';
  end if;
  if not override and coalesce((unit->>'replacementBank')::int, 0) < 1 then
    raise exception 'This level has no unused replacement. Gaining a level grants one. The current level by itself does not grant a stack of swaps.'
      using errcode = '22023';
  end if;
  current := jsonb_set(current, '{status}', '"archived"'::jsonb);
  archive_reason := case when override then concat('DM override: ', coalesce(command->>'reason', '')) else 'Replaced' end;
  doc := jsonb_set(doc, '{archive}', public._bastion_arr(doc, 'archive') || jsonb_build_array(current || jsonb_build_object('archivedReason', archive_reason)));
  doc := jsonb_set(doc, '{facilities}', public._bastion_remove(doc->'facilities', current->>'id'));
  if not override then
    unit := jsonb_set(unit, '{replacementBank}', to_jsonb((unit->>'replacementBank')::int - 1));
    doc := public._bastion_put_unit(doc, unit);
  end if;
  select made.next_doc, made.facility into doc, facility
  from public._bastion_make_special(doc, unit, spec, 'replacement') as made;
  return public._bastion_out(
    doc,
    jsonb_build_object('facilityId', facility->>'id', 'bank', (public._bastion_unit(doc, unit->>'id')->>'replacementBank')::int),
    format('Replaced %s with %s. The old one stays in the archive.', current->>'name', spec->>'name')
  );
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
  return public._bastion_out(doc, jsonb_build_object('facilityId', facility->>'id'), format('Enlarged %s for %s GP. No extra days were added, because the chapter does not give a build time.', facility->>'name', gp));
end;
$$;

create or replace function public._bastion_squares(space text)
returns int
language sql
immutable
set search_path = public
as $$
  select coalesce((public._bastion_catalog()#>>array['squares', space])::int, 0);
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
  ordinal int;
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
      'id', facility_id,
      'unitId', unit->>'id',
      'kind', 'basic',
      'catalogId', command->>'roomId',
      'name', room_name,
      'space', space,
      'status', 'active',
      'acquired', case when public._bastion_flag(command->'inherited') then 'inherited' else 'starter' end,
      'squares', public._bastion_squares(space)
    )));
    return public._bastion_out(doc, jsonb_build_object('facilityId', facility_id, 'charged', 0), format('Added %s with no charge.', room_name));
  end if;
  doc := public._bastion_spend(doc, (build->>'gp')::int, 'Build ' || room_name, command->>'idempotencyKey');
  ordinal := public._bastion_clock(doc);
  select taken.next_doc, taken.next_id into doc, project_id from public._bastion_take(doc, 'proj') as taken;
  doc := jsonb_set(doc, '{projects}', public._bastion_arr(doc, 'projects') || jsonb_build_array(jsonb_build_object(
    'id', project_id,
    'unitId', unit->>'id',
    'kind', 'basic',
    'roomId', command->>'roomId',
    'name', room_name,
    'space', space,
    'gp', (build->>'gp')::int,
    'days', (build->>'days')::int,
    'startOrdinal', ordinal,
    'dueOrdinal', ordinal + (build->>'days')::int,
    'status', 'building'
  )));
  return public._bastion_out(
    doc,
    jsonb_build_object('projectId', project_id, 'dueOrdinal', ordinal + (build->>'days')::int, 'charged', (build->>'gp')::int),
    format('%s costs %s GP and is ready on day %s.', room_name, (build->>'gp')::int, ordinal + (build->>'days')::int)
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
  ordinal int;
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
  ordinal := public._bastion_clock(doc);
  select taken.next_doc, taken.next_id into doc, project_id from public._bastion_take(doc, 'proj') as taken;
  facility := facility || jsonb_build_object('status', 'building');
  doc := public._bastion_put_facility(doc, facility);
  doc := jsonb_set(doc, '{projects}', public._bastion_arr(doc, 'projects') || jsonb_build_array(jsonb_build_object(
    'id', project_id,
    'unitId', facility->>'unitId',
    'kind', 'upgrade',
    'facilityId', facility->>'id',
    'name', facility->>'name',
    'from', facility->>'space',
    'space', step->>'to',
    'gp', (step->>'gp')::int,
    'days', (step->>'days')::int,
    'startOrdinal', ordinal,
    'dueOrdinal', ordinal + (step->>'days')::int,
    'status', 'building'
  )));
  return public._bastion_out(doc, jsonb_build_object('projectId', project_id, 'dueOrdinal', ordinal + (step->>'days')::int), format('%s enlarges on day %s.', facility->>'name', ordinal + (step->>'days')::int));
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
  days int;
  start_day int;
  i int;
  wall_id text;
  ids jsonb := '[]'::jsonb;
begin
  count_n := public._bastion_whole(command->>'squares', 1, 200, 'Enter how many 5-foot squares to start.');
  gp := (public._bastion_catalog()#>>'{wall,gp}')::int * count_n;
  days := (public._bastion_catalog()#>>'{wall,days}')::int;
  doc := public._bastion_spend(doc, gp, 'Wall squares ×' || count_n, command->>'idempotencyKey');
  start_day := public._bastion_clock(doc);
  for i in 1..count_n loop
    select taken.next_doc, taken.next_id into doc, wall_id from public._bastion_take(doc, 'wall') as taken;
    doc := jsonb_set(doc, '{walls,squares}', coalesce(doc#>'{walls,squares}', '[]'::jsonb) || jsonb_build_array(jsonb_build_object(
      'id', wall_id,
      'status', 'building',
      'startOrdinal', start_day,
      'dueOrdinal', start_day + days,
      'gp', (public._bastion_catalog()#>>'{wall,gp}')::int
    )));
    ids := ids || jsonb_build_array(wall_id);
  end loop;
  return public._bastion_out(
    doc,
    jsonb_build_object('ids', ids, 'dueOrdinal', start_day + days, 'charged', gp),
    format('%s wall squares finish on day %s. They run together, so the days are not stacked. The enclosure is still not marked complete.', count_n, start_day + days)
  );
end;
$$;

create or replace function public._bastion_cmd_enclosure(doc jsonb, command jsonb)
returns jsonb
language plpgsql
set search_path = public
as $$
declare
  complete boolean;
begin
  if btrim(coalesce(command->>'reason', '')) = '' then
    raise exception 'Say why the walls now form a complete enclosure. Square count does not decide it.' using errcode = '22023';
  end if;
  complete := public._bastion_flag(command->'complete');
  doc := jsonb_set(doc, '{walls,enclosureComplete}', to_jsonb(complete));
  return public._bastion_out(
    doc,
    jsonb_build_object('complete', complete),
    case when complete then 'Marked the walls as a complete enclosure.' else 'Cleared the complete-enclosure mark.' end
  );
end;
$$;

create or replace function public._bastion_cmd_roster(doc jsonb, command jsonb)
returns jsonb
language plpgsql
set search_path = public
as $$
declare
  person jsonb := coalesce(command->'person', '{}'::jsonb);
  name text;
  link text;
  record jsonb;
  existing jsonb;
begin
  name := btrim(coalesce(person->>'name', ''));
  if name = '' then
    raise exception 'A person needs a name.' using errcode = '22023';
  end if;
  if coalesce(person->>'category', '') not in ('household', 'hireling', 'defender', 'guest', 'lieutenant', 'creature') then
    raise exception 'Choose a roster category.' using errcode = '22023';
  end if;
  link := left(coalesce(person->>'link', ''), 300);
  if link <> '' and link !~ '^https?://' then
    raise exception 'A link should start with http:// or https://, or be left blank.' using errcode = '22023';
  end if;
  existing := case when coalesce(person->>'id', '') <> '' then public._bastion_find(doc->'roster', person->>'id') else null end;
  if existing is null then
    select taken.next_doc, taken.next_id into doc, name from public._bastion_take(doc, 'npc') as taken;
    record := jsonb_build_object('id', name);
    name := left(btrim(person->>'name'), 80);
  else
    record := existing;
    name := left(btrim(person->>'name'), 80);
  end if;
  record := record || jsonb_build_object(
    'name', name,
    'category', person->>'category',
    'summary', left(coalesce(person->>'summary', ''), 160),
    'role', left(coalesce(person->>'role', ''), 80),
    'link', link,
    'unitId', coalesce(person->>'unitId', doc#>>'{units,0,id}'),
    'facilityId', case when person->'facilityId' is null or person->'facilityId' = 'null'::jsonb or coalesce(person->>'facilityId', '') = '' then 'null'::jsonb else to_jsonb(person->>'facilityId') end,
    'status', coalesce(nullif(person->>'status', ''), 'active'),
    'housed', public._bastion_flag(person->'housed'),
    'protectsOnce', public._bastion_flag(person->'protectsOnce')
  );
  if existing is null then
    doc := jsonb_set(doc, '{roster}', public._bastion_arr(doc, 'roster') || jsonb_build_array(record));
  else
    doc := jsonb_set(doc, '{roster}', public._bastion_replace(doc->'roster', record->>'id', record));
  end if;
  return public._bastion_out(doc, jsonb_build_object('personId', record->>'id'), format('Saved %s.', record->>'name'));
end;
$$;

create or replace function public._bastion_cmd_roster_remove(doc jsonb, command jsonb)
returns jsonb
language plpgsql
set search_path = public
as $$
declare
  person jsonb;
begin
  person := public._bastion_find(doc->'roster', command->>'personId');
  if person is null then
    raise exception 'That person is not on the roster.' using errcode = '22023';
  end if;
  person := jsonb_set(person, '{status}', '"gone"'::jsonb);
  doc := jsonb_set(doc, '{roster}', public._bastion_replace(doc->'roster', person->>'id', person));
  return public._bastion_out(doc, jsonb_build_object('personId', person->>'id'), format('Marked %s as gone. The name stays in the log.', person->>'name'));
end;
$$;

create or replace function public._bastion_cmd_goods(doc jsonb, command jsonb)
returns jsonb
language plpgsql
set search_path = public
as $$
declare
  standard_gp int;
  lot_id text;
begin
  standard_gp := public._bastion_whole(command->>'standardGp', 0, 2000000000, 'Goods need a list price in whole GP.');
  select taken.next_doc, taken.next_id into doc, lot_id from public._bastion_take(doc, 'good') as taken;
  doc := jsonb_set(doc, '{goods}', public._bastion_arr(doc, 'goods') || jsonb_build_array(jsonb_build_object(
    'id', lot_id,
    'name', left(coalesce(nullif(command->>'name', ''), 'Goods'), 80),
    'standardGp', standard_gp,
    'reservedGp', 0,
    'status', 'on_hand',
    'unitId', coalesce(nullif(command->>'unitId', ''), doc#>>'{units,0,id}'),
    'note', 'Recorded as already on hand. This did not charge or pay anyone.'
  )));
  return public._bastion_out(doc, jsonb_build_object('lotId', lot_id), format('Recorded %s GP of goods without a sale or purchase.', standard_gp));
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
  names jsonb := '[]'::jsonb;
  name text;
  existing jsonb := '[]'::jsonb;
  person jsonb;
  kept jsonb := '[]'::jsonb;
  i int;
  person_id text;
  cap int;
begin
  facility := public._bastion_facility(doc, command->>'facilityId');
  count_n := public._bastion_whole(command->>'count', 0, 25, 'Defender count is a whole number from 0 to 25.');
  cap := case when facility->>'space' = 'vast' then 25 else 12 end;
  if facility->>'catalogId' = 'barrack' and count_n > cap then
    raise exception 'This barrack houses %, not %.', cap, count_n using errcode = '22023';
  end if;
  if jsonb_typeof(command->'names') = 'array' then
    for name in select jsonb_array_elements_text(command->'names') loop
      if btrim(name) <> '' then
        names := names || jsonb_build_array(left(btrim(name), 80));
      end if;
    end loop;
  end if;
  if jsonb_array_length(names) > count_n then
    raise exception 'There are more names than the defender count.' using errcode = '22023';
  end if;
  for person in
    select value from jsonb_array_elements(public._bastion_arr(doc, 'roster')) value
    where value->>'category' = 'defender' and value->>'status' = 'active' and value->>'facilityId' = facility->>'id'
  loop
    existing := existing || jsonb_build_array(person);
  end loop;
  for i in count_n .. jsonb_array_length(existing) - 1 loop
    person := existing->i;
    person := jsonb_set(person, '{status}', '"gone"'::jsonb);
    doc := jsonb_set(doc, '{roster}', public._bastion_replace(doc->'roster', person->>'id', person));
  end loop;
  for i in 0 .. least(count_n, jsonb_array_length(existing)) - 1 loop
    kept := kept || jsonb_build_array(existing->i);
  end loop;
  while jsonb_array_length(kept) < count_n loop
    select taken.next_doc, taken.next_id into doc, person_id from public._bastion_take(doc, 'npc') as taken;
    person := jsonb_build_object(
      'id', person_id,
      'name', 'Defender ' || (jsonb_array_length(public._bastion_arr(doc, 'roster')) + 1),
      'category', 'defender',
      'summary', 'Recorded as already housed. This was not a Recruit order.',
      'role', 'Defender',
      'link', '',
      'unitId', facility->>'unitId',
      'facilityId', facility->>'id',
      'status', 'active',
      'housed', true,
      'protectsOnce', false
    );
    doc := jsonb_set(doc, '{roster}', public._bastion_arr(doc, 'roster') || jsonb_build_array(person));
    kept := kept || jsonb_build_array(person);
  end loop;
  for i in 0 .. jsonb_array_length(names) - 1 loop
    person := kept->i;
    person := jsonb_set(person, '{name}', to_jsonb(names->>i));
    doc := jsonb_set(doc, '{roster}', public._bastion_replace(doc->'roster', person->>'id', person));
  end loop;
  return public._bastion_out(doc, jsonb_build_object('facilityId', facility->>'id', 'count', count_n), format('Recorded %s defenders at %s. No Recruit turn was run.', count_n, facility->>'name'));
end;
$$;

create or replace function public._bastion_cmd_loan(doc jsonb, command jsonb)
returns jsonb
language plpgsql
set search_path = public
as $$
declare
  loans jsonb;
  loan jsonb;
  creditor text;
  amount int;
  note text;
begin
  loans := public._bastion_arr(doc, 'finance') -> 'loans';
  if loans is null or jsonb_typeof(doc#>'{finance,loans}') is distinct from 'array' then
    loans := '[]'::jsonb;
  else
    loans := doc#>'{finance,loans}';
  end if;
  if public._bastion_flag(command->'remove') then
    loan := public._bastion_find(loans, command->>'loanId');
    if loan is null then
      raise exception 'That loan is not on the record.' using errcode = '22023';
    end if;
    loans := public._bastion_remove(loans, loan->>'id');
    doc := jsonb_set(doc, '{finance,loans}', loans);
    return public._bastion_out(doc, jsonb_build_object('loanId', loan->>'id', 'removed', true), format('Removed the loan from %s. Cash was not changed.', loan->>'creditor'));
  end if;
  creditor := left(btrim(coalesce(command->>'creditor', '')), 80);
  if creditor = '' then
    raise exception 'A loan needs a creditor label.' using errcode = '22023';
  end if;
  amount := public._bastion_whole(command->>'amountGp', 0, 2000000000, 'Loan amount is a whole number of GP, or zero.');
  note := left(coalesce(command->>'note', ''), 240);
  if coalesce(command->>'loanId', '') <> '' then
    loan := public._bastion_find(loans, command->>'loanId');
    if loan is null then
      raise exception 'That loan is not on the record.' using errcode = '22023';
    end if;
    loan := loan || jsonb_build_object('creditor', creditor, 'amountGp', amount, 'note', note);
    loans := public._bastion_replace(loans, loan->>'id', loan);
  else
    select taken.next_doc, taken.next_id into doc, creditor from public._bastion_take(doc, 'loan') as taken;
    loan := jsonb_build_object('id', creditor, 'creditor', left(btrim(command->>'creditor'), 80), 'amountGp', amount, 'note', note);
    loans := coalesce(doc#>'{finance,loans}', '[]'::jsonb) || jsonb_build_array(loan);
  end if;
  doc := jsonb_set(doc, '{finance,loans}', loans);
  if coalesce(command->>'loanId', '') <> '' then
    return public._bastion_out(doc, jsonb_build_object('loanId', loan->>'id'), format('Updated the loan from %s. Cash was not changed.', loan->>'creditor'));
  end if;
  return public._bastion_out(doc, jsonb_build_object('loanId', loan->>'id'), format('Recorded a loan of %s GP from %s. Cash was not changed.', amount, loan->>'creditor'));
end;
$$;

create or replace function public._bastion_cmd_reserve(doc jsonb, command jsonb)
returns jsonb
language plpgsql
set search_path = public
as $$
declare
  amount int;
  note text;
  lot jsonb;
  lot_id text;
  available int;
begin
  amount := public._bastion_whole(command->>'standardGp', 1, 2000000000, 'Committed goods need a list price in whole GP.');
  note := left(coalesce(nullif(command->>'note', ''), 'Committed to an order already underway. This did not charge or pay anyone.'), 240);
  if coalesce(command->>'lotId', '') <> '' then
    lot := public._bastion_find(doc->'goods', command->>'lotId');
    if lot is null or lot->>'status' is distinct from 'on_hand' then
      raise exception 'Those goods are not on hand.' using errcode = '22023';
    end if;
    available := (lot->>'standardGp')::int - coalesce((lot->>'reservedGp')::int, 0);
    if amount > available then
      raise exception 'That commits more than the goods still free.' using errcode = '22023';
    end if;
    lot := lot || jsonb_build_object('reservedGp', coalesce((lot->>'reservedGp')::int, 0) + amount, 'commitment', note);
    doc := jsonb_set(doc, '{goods}', public._bastion_replace(doc->'goods', lot->>'id', lot));
    return public._bastion_out(doc, jsonb_build_object('lotId', lot->>'id', 'reservedGp', (lot->>'reservedGp')::int), format('Marked %s GP of %s as already committed. Cash was not changed.', amount, lot->>'name'));
  end if;
  select taken.next_doc, taken.next_id into doc, lot_id from public._bastion_take(doc, 'good') as taken;
  lot := jsonb_build_object(
    'id', lot_id,
    'name', left(coalesce(nullif(command->>'name', ''), 'Goods'), 80),
    'standardGp', amount,
    'reservedGp', amount,
    'status', 'on_hand',
    'unitId', coalesce(nullif(command->>'unitId', ''), doc#>>'{units,0,id}'),
    'note', note,
    'commitment', note
  );
  doc := jsonb_set(doc, '{goods}', public._bastion_arr(doc, 'goods') || jsonb_build_array(lot));
  return public._bastion_out(doc, jsonb_build_object('lotId', lot_id, 'reservedGp', amount), format('Recorded %s GP of %s as already committed. Cash was not changed.', amount, lot->>'name'));
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
    started := public._bastion_whole(command->>'startedTurn', 0, 2000000000, 'The turn it started has to be a whole number, or left blank.');
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
  order_row := order_row || jsonb_build_object(
    'suborder', sub->>'id',
    'label', sub->>'label',
    'status', 'in_progress',
    'startedTurn', to_jsonb(started),
    'note', note,
    'auto', null,
    'recorded', true
  );
  if existing is null then
    doc := jsonb_set(doc, '{orders}', public._bastion_arr(doc, 'orders') || jsonb_build_array(order_row));
  else
    doc := jsonb_set(doc, '{orders}', public._bastion_replace(doc->'orders', order_id, order_row));
  end if;
  facility := facility || jsonb_build_object('currentOrderId', order_id);
  doc := public._bastion_put_facility(doc, facility);
  return public._bastion_out(doc, jsonb_build_object('orderId', order_id), format('Marked %s as already running %s. No turn was resolved and no money moved.', facility->>'name', sub->>'label'));
end;
$$;

create or replace function public._bastion_cmd_split(doc jsonb, command jsonb)
returns jsonb
language plpgsql
set search_path = public
as $$
declare
  level int;
  unit_id text;
  cap int;
begin
  if not public._bastion_flag(command->'acknowledgeNewCap') then
    raise exception 'Splitting adds a new owner''s own facility cap. Confirm that you mean to do that. Rooms are not copied.'
      using errcode = '22023';
  end if;
  level := public._bastion_whole(command->>'level', 5, 20, 'A new owner unit needs a level from 5 to 20.');
  cap := public._bastion_cap(level);
  select taken.next_doc, taken.next_id into doc, unit_id from public._bastion_take(doc, 'unit') as taken;
  doc := jsonb_set(doc, '{units}', public._bastion_arr(doc, 'units') || jsonb_build_array(jsonb_build_object(
    'id', unit_id,
    'name', left(coalesce(nullif(command->>'name', ''), 'Character bastion'), 80),
    'level', level,
    'owner', left(coalesce(nullif(command->>'owner', ''), 'Unassigned'), 120),
    'replacementBank', 0,
    'capabilities', '[]'::jsonb,
    'neglectStreak', 0,
    'fallen', false
  )));
  return public._bastion_out(doc, jsonb_build_object('unitId', unit_id, 'cap', cap), format('Opened a separate unit at level %s with its own cap of %s. No rooms were copied.', level, cap));
end;
$$;

create or replace function public._bastion_cmd_override(doc jsonb, command jsonb)
returns jsonb
language plpgsql
set search_path = public
as $$
declare
  facility jsonb;
begin
  if btrim(coalesce(command->>'reason', '')) = '' then
    raise exception 'A DM override needs a written reason.' using errcode = '22023';
  end if;
  if coalesce(command#>>'{patch,facilityId}', '') <> '' then
    facility := public._bastion_find(doc->'facilities', command#>>'{patch,facilityId}');
    if facility is null then
      facility := public._bastion_find(doc->'archive', command#>>'{patch,facilityId}');
    end if;
    if facility is null then
      raise exception 'That facility is not in the record.' using errcode = '22023';
    end if;
    if coalesce(command#>>'{patch,status}', '') <> '' and facility is not null and public._bastion_find(doc->'facilities', facility->>'id') is not null then
      facility := jsonb_set(facility, '{status}', to_jsonb(command#>>'{patch,status}'));
      doc := public._bastion_put_facility(doc, facility);
    elsif coalesce(command#>>'{patch,status}', '') <> '' then
      facility := jsonb_set(facility, '{status}', to_jsonb(command#>>'{patch,status}'));
      doc := jsonb_set(doc, '{archive}', public._bastion_replace(doc->'archive', facility->>'id', facility));
    end if;
  end if;
  return public._bastion_out(doc, jsonb_build_object('ok', true), left(coalesce(nullif(command->>'summary', ''), 'DM override'), 200));
end;
$$;

create or replace function public._bastion_cmd_fall(doc jsonb, command jsonb)
returns jsonb
language plpgsql
set search_path = public
as $$
declare
  unit jsonb;
  facility jsonb;
begin
  unit := public._bastion_unit(doc, command->>'unitId');
  if btrim(coalesce(command->>'reason', '')) = '' then
    raise exception 'Say whether this is neglect, giving the bastion up, or ruin.' using errcode = '22023';
  end if;
  unit := jsonb_set(unit, '{fallen}', 'true'::jsonb);
  doc := public._bastion_put_unit(doc, unit);
  for facility in
    select value from jsonb_array_elements(public._bastion_arr(doc, 'facilities')) value
    where value->>'unitId' = unit->>'id'
  loop
    facility := jsonb_set(facility, '{status}', '"archived"'::jsonb);
    doc := jsonb_set(doc, '{archive}', public._bastion_arr(doc, 'archive') || jsonb_build_array(facility));
    doc := jsonb_set(doc, '{facilities}', public._bastion_remove(doc->'facilities', facility->>'id'));
  end loop;
  return public._bastion_out(doc, jsonb_build_object('fallen', true), format('Marked %s as fallen. A new bastion is a separate step and is not created automatically.', unit->>'name'));
end;
$$;

create or replace function public._bastion_settle(doc jsonb, idem_key text)
returns jsonb
language plpgsql
set search_path = public
as $$
declare
  ordinal int;
  task jsonb;
  task_id text;
  lot jsonb;
  project jsonb;
  facility jsonb;
  square jsonb;
  facility_id text;
  good_id text;
begin
  ordinal := (doc#>>'{clock,ordinal}')::int;
  for task_id in
    select elem->>'id'
    from jsonb_array_elements(public._bastion_arr(doc, 'tasks')) elem
    where elem->>'status' = 'open'
      and elem->>'dueOrdinal' is not null
      and (elem->>'dueOrdinal')::int <= ordinal
  loop
    task := public._bastion_find(doc->'tasks', task_id);
    if task is null or task->>'status' is distinct from 'open' then
      continue;
    end if;
    if coalesce((task->>'settled')::boolean, false) then
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
    where value->>'status' = 'building' and value->>'dueOrdinal' is not null and (value->>'dueOrdinal')::int <= ordinal
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
        'id', facility_id,
        'unitId', project->>'unitId',
        'kind', 'basic',
        'catalogId', project->>'roomId',
        'name', project->>'name',
        'space', project->>'space',
        'status', 'active',
        'acquired', 'built',
        'squares', public._bastion_squares(project->>'space')
      )));
    elsif project->>'kind' = 'upgrade' then
      facility := public._bastion_find(doc->'facilities', project->>'facilityId');
      if facility is not null then
        facility := facility || jsonb_build_object(
          'space', project->>'space',
          'status', 'active',
          'squares', public._bastion_squares(project->>'space')
        );
        doc := public._bastion_put_facility(doc, facility);
      end if;
    end if;
  end loop;
  for square in
    select value from jsonb_array_elements(coalesce(doc#>'{walls,squares}', '[]'::jsonb)) value
    where value->>'status' = 'building' and (value->>'dueOrdinal')::int <= ordinal
  loop
    square := public._bastion_find(doc#>'{walls,squares}', square->>'id') || jsonb_build_object('status', 'built');
    doc := jsonb_set(doc, '{walls,squares}', public._bastion_replace(doc#>'{walls,squares}', square->>'id', square));
  end loop;
  return doc;
end;
$$;

create or replace function public._bastion_cmd_advance(doc jsonb, command jsonb)
returns jsonb
language plpgsql
set search_path = public
as $$
declare
  days int;
  ordinal int;
begin
  days := public._bastion_whole(command->>'days', 1, 3650, 'Advance a whole number of in-game days.');
  ordinal := public._bastion_clock(doc) + days;
  doc := jsonb_set(doc, '{clock,ordinal}', to_jsonb(ordinal));
  if coalesce(command->>'label', '') <> '' then
    doc := jsonb_set(doc, '{clock,label}', to_jsonb(left(command->>'label', 120)));
  end if;
  doc := public._bastion_settle(doc, command->>'idempotencyKey');
  return public._bastion_out(doc, jsonb_build_object('ordinal', ordinal), format('Advanced to day %s.', ordinal));
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
    due := public._bastion_clock(next_doc) + 7;
    select taken.next_doc, taken.next_id into next_doc, task_id from public._bastion_take(next_doc, 'task') as taken;
    next_doc := jsonb_set(next_doc, '{tasks}', public._bastion_arr(next_doc, 'tasks') || jsonb_build_array(jsonb_build_object(
      'id', task_id, 'status', 'open', 'settled', false, 'auto', 'storehouse_buy', 'unitId', unit->>'id',
      'orderId', order_id, 'goodsName', left(coalesce(nullif(request->>'goodsName', ''), 'Goods'), 80),
      'standardGp', standard_gp, 'dueOrdinal', due
    )));
    order_row := order_row || jsonb_build_object('taskId', task_id, 'dueOrdinal', due);
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
    due := public._bastion_clock(next_doc) + 7;
    select taken.next_doc, taken.next_id into next_doc, task_id from public._bastion_take(next_doc, 'task') as taken;
    next_doc := jsonb_set(next_doc, '{tasks}', public._bastion_arr(next_doc, 'tasks') || jsonb_build_array(jsonb_build_object(
      'id', task_id, 'status', 'open', 'settled', false, 'auto', 'storehouse_sell', 'unitId', unit->>'id',
      'orderId', order_id, 'lotId', lot->>'id', 'standardGp', standard_gp, 'proceeds', proceeds, 'dueOrdinal', due
    )));
    order_row := order_row || jsonb_build_object('taskId', task_id, 'dueOrdinal', due, 'preview', jsonb_build_object('standardGp', standard_gp, 'proceeds', proceeds, 'days', 7));
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
    if request ? 'days' and request->'days' is distinct from 'null'::jsonb and coalesce(request->>'days', '') <> '' then
      days := public._bastion_whole(request->>'days', 0, 3650, 'Duration has to be a whole number of days from the facility, not from the turn length.');
      days_known := true;
    elsif sub->'days' is null or sub->'days' = 'null'::jsonb then
      days_known := false;
    else
      days := public._bastion_whole(sub->>'days', 0, 3650, 'Duration has to be a whole number of days from the facility, not from the turn length.');
      days_known := true;
    end if;
    if not days_known then
      order_row := order_row || jsonb_build_object('status', 'awaiting_dm', 'note', left(coalesce(nullif(sub->>'note', ''), 'Enter a duration and any price from the rules outside this chapter.'), 240));
    else
      ordinal := case when days = 0 then nullif(next_doc#>>'{clock,ordinal}', '')::int else public._bastion_clock(next_doc) + days end;
      select taken.next_doc, taken.next_id into next_doc, task_id from public._bastion_take(next_doc, 'task') as taken;
      next_doc := jsonb_set(next_doc, '{tasks}', public._bastion_arr(next_doc, 'tasks') || jsonb_build_array(jsonb_build_object(
        'id', task_id, 'status', 'open', 'settled', false, 'auto', 'manual', 'unitId', unit->>'id', 'orderId', order_id,
        'note', left(coalesce(request->>'note', sub->>'note', ''), 240),
        'dueOrdinal', to_jsonb(ordinal)
      )));
      order_row := order_row || jsonb_build_object('taskId', task_id, 'dueOrdinal', to_jsonb(ordinal));
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
    'day', doc#>'{clock,ordinal}',
    'cadenceDays', doc#>'{clock,cadenceDays}',
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
      next_event := jsonb_set(next_event, '{detail,dueInDays}', '7'::jsonb);
      result := jsonb_build_object('type', 'guest', 'kind', 2, 'gpLater', (detail->>'die')::int * 100, 'note', 'The gift is due after 7 days. Record it then; it is not cash today.');
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
    result := jsonb_build_object('type', 'guest', 'kind', 1, 'note', 'Renowned guest stays 7 days. Record the letter yourself.');
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

create or replace function public._bastion_cmd_resolve(doc jsonb, command jsonb)
returns jsonb
language plpgsql
set search_path = public
as $$
declare
  event jsonb;
  unit jsonb;
  roll_n int;
  event_type text;
  known text;
  body_doc jsonb;
  body_event jsonb;
  body_result jsonb;
begin
  event := public._bastion_find(doc->'events', command->>'eventId');
  if event is null then
    raise exception 'That event is not open.' using errcode = '22023';
  end if;
  if event->>'status' = 'resolved' then
    raise exception 'This event is already in the log. It will not be rolled again.' using errcode = '22023';
  end if;
  unit := public._bastion_unit(doc, event->>'unitId');
  event_type := nullif(command->>'eventIdChoice', '');
  if command ? 'roll' and command->'roll' is distinct from 'null'::jsonb and coalesce(command->>'roll', '') <> '' then
    roll_n := public._bastion_whole(command->>'roll', 1, 100, 'Enter a d100 result from 1 to 100, or choose the event yourself.');
    event_type := public._bastion_event_type(roll_n);
    if event_type = 'opportunity' and public._bastion_flag(command->'opportunityReroll') then
      raise exception 'Resolve the opportunity choice before rolling a replacement event.' using errcode = '22023';
    end if;
  else
    roll_n := null;
  end if;
  if event_type is null then
    raise exception 'Roll a d100 or choose the event. Refreshing the page will not roll again.' using errcode = '22023';
  end if;
  known := public._bastion_event_name(event_type);
  if known is null then
    raise exception 'That is not a bastion event.' using errcode = '22023';
  end if;
  event := event || jsonb_build_object('roll', to_jsonb(roll_n), 'type', event_type, 'status', 'resolved', 'detail', '{}'::jsonb);
  select body.next_doc, body.next_event, body.result into body_doc, body_event, body_result
  from public._bastion_event_body(doc, command, unit, event) as body;
  body_event := body_event || jsonb_build_object('result', body_result, 'status', 'resolved');
  doc := jsonb_set(body_doc, '{events}', public._bastion_replace(body_doc->'events', body_event->>'id', body_event));
  return public._bastion_out(doc, body_result, known || ' resolved.');
end;
$$;

create or replace function public._bastion_cmd_import(doc jsonb, command jsonb)
returns jsonb
language plpgsql
set search_path = public
as $$
declare
  item jsonb := coalesce(command->'item', '{}'::jsonb);
  status text := coalesce(item->>'status', '');
  forwarded jsonb;
begin
  if coalesce(item->>'kind', '') in ('turn', 'finance', 'date', 'goods', 'loan', 'defender', 'defenders') then
    raise exception 'Turns, dates, loans, goods, and defenders from a review file are not applied. Enter those yourself.'
      using errcode = '22023';
  end if;
  if position('pending' in lower(status)) > 0 and coalesce(item->>'kind', '') not in ('facility', 'roster') then
    raise exception 'This note is still awaiting a decision. It was not written into the record.'
      using errcode = '22023';
  end if;
  if item->>'kind' = 'facility' then
    if item->>'facilityKind' = 'basic' then
      forwarded := jsonb_build_object(
        'unitId', coalesce(item->>'unitId', doc#>>'{units,0,id}'),
        'roomId', item->>'roomId',
        'space', item->>'space',
        'inherited', true,
        'idempotencyKey', command->'idempotencyKey'
      );
      return public._bastion_cmd_add_basic(doc, forwarded);
    end if;
    forwarded := jsonb_build_object(
      'unitId', coalesce(item->>'unitId', doc#>>'{units,0,id}'),
      'catalogId', item->>'catalogId',
      'acquired', 'inherited',
      'idempotencyKey', command->'idempotencyKey'
    );
    return public._bastion_cmd_add_special(doc, forwarded);
  end if;
  if item->>'kind' = 'roster' then
    return public._bastion_cmd_roster(doc, jsonb_build_object('person', coalesce(item->'person', '{}'::jsonb), 'idempotencyKey', command->'idempotencyKey'));
  end if;
  raise exception 'That review item cannot be applied automatically.' using errcode = '22023';
end;
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
  if cmd = 'replace_special' then return public._bastion_cmd_replace(doc, command); end if;
  if cmd = 'enlarge_special' then return public._bastion_cmd_enlarge(doc, command); end if;
  if cmd = 'add_basic' then return public._bastion_cmd_add_basic(doc, command); end if;
  if cmd = 'upgrade_basic' then return public._bastion_cmd_upgrade(doc, command); end if;
  if cmd = 'add_wall_squares' then return public._bastion_cmd_walls(doc, command); end if;
  if cmd = 'mark_enclosure' then return public._bastion_cmd_enclosure(doc, command); end if;
  if cmd = 'advance_days' then return public._bastion_cmd_advance(doc, command); end if;
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
  raise exception 'unsupported_on_server' using errcode = '0A000';
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
    'clock', jsonb_build_object('label', '', 'ordinal', null, 'cadenceDays', 10),
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
    'record_order'
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
  if role = 'reader' or (role <> 'dm' and cmd = any(dm_only)) then
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
    'day', doc#>'{clock,ordinal}'
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
revoke all on function public.empty_document(text) from public, anon, authenticated;

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
