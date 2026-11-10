-- DM corrections for rooms and people.
--
-- Run this after 005_remove_person.sql. Do not run 001, 002, 003, or 004 again.
-- This file does not rewrite existing estates, does not change cash, and does
-- not delete anyone by itself. A signed-in DM can later edit, remove, or
-- replace a room, swap a special facility without spending a level-up
-- replacement, and replace or reassign a person. An editor can still name an
-- unnamed person. Removal archives the room and keeps people unless the DM
-- marks hirelings released. Unfinished work is cancelled only when the DM
-- confirms that, and cancelling it does not pay a sale or refund a purchase.

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
    'record_order',
    'remove_goods',
    'remove_person',
    'edit_person',
    'remove_facility',
    'edit_facility',
    'replace_basic',
    'correct_special',
    'replace_person',
    'assign_person',
    'cancel_project'
  ]::text[];
$$;

create or replace function public._bastion_reason(command jsonb)
returns text
language plpgsql
set search_path = public
as $$
declare
  reason text := left(btrim(coalesce(command->>'reason', '')), 400);
begin
  if reason = '' then
    raise exception 'Write why this correction is being made. Cash was not changed.' using errcode = '22023';
  end if;
  return reason;
end;
$$;

create or replace function public._bastion_task_pending(task jsonb)
returns boolean
language sql
immutable
set search_path = public
as $$
  select task is not null
    and coalesce((task->>'settled')::boolean, false) = false
    and coalesce(task->>'status', '') not in ('resolved', 'cancelled');
$$;

create or replace function public._bastion_order_unfinished(doc jsonb, ord jsonb)
returns boolean
language sql
stable
set search_path = public
as $$
  select case
    when ord is null or coalesce(ord->>'status', '') in ('resolved', 'cancelled') then false
    when not exists (
      select 1
      from jsonb_array_elements(coalesce(doc->'tasks', '[]'::jsonb)) task
      where task->>'orderId' = ord->>'id' or (ord->>'taskId' is not null and task->>'id' = ord->>'taskId')
    ) then true
    else exists (
      select 1
      from jsonb_array_elements(coalesce(doc->'tasks', '[]'::jsonb)) task
      where (task->>'orderId' = ord->>'id' or (ord->>'taskId' is not null and task->>'id' = ord->>'taskId'))
        and public._bastion_task_pending(task)
    )
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

create or replace function public._bastion_archive_facility(doc jsonb, facility_id text, archived_reason text)
returns jsonb
language plpgsql
set search_path = public
as $$
declare
  facility jsonb;
begin
  facility := public._bastion_find(doc->'facilities', facility_id);
  if facility is null then
    raise exception 'That facility is not active.' using errcode = '22023';
  end if;
  facility := facility || jsonb_build_object('status', 'archived', 'archivedReason', left(coalesce(archived_reason, ''), 400));
  doc := jsonb_set(doc, '{archive}', public._bastion_arr(doc, 'archive') || jsonb_build_array(facility));
  doc := jsonb_set(doc, '{facilities}', public._bastion_remove(doc->'facilities', facility_id));
  return doc;
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
  correction boolean;
  extra text;
  acquired text;
  old_name text;
  summary text;
begin
  unit := public._bastion_unit(doc, command->>'unitId');
  current := public._bastion_facility(doc, command->>'facilityId');
  if current->>'kind' is distinct from 'special' then
    raise exception 'That room is not a special facility.' using errcode = '22023';
  end if;
  if current->>'unitId' is distinct from unit->>'id' then
    raise exception 'That facility belongs to another owner.' using errcode = '22023';
  end if;
  spec := public._bastion_spec(command->>'catalogId');
  if spec is null then
    raise exception 'That replacement is not in the bastion list.' using errcode = '22023';
  end if;
  if spec->>'id' = current->>'catalogId' then
    raise exception 'Choose a different facility. Edit the note if this room is already the right one.' using errcode = '22023';
  end if;
  if (unit->>'level')::int < (spec->>'level')::int then
    raise exception '% requires level %.', spec->>'name', (spec->>'level')::int using errcode = '22023';
  end if;
  if coalesce(spec->>'prereq', '') <> '' and not (coalesce(unit->'capabilities', '[]'::jsonb) ? (spec->>'prereq')) then
    raise exception '% needs a capability this unit does not have.', spec->>'name' using errcode = '22023';
  end if;
  if coalesce((spec->>'unique')::boolean, false) and exists (
    select 1 from jsonb_array_elements(coalesce(doc->'facilities', '[]'::jsonb)) elem
    where elem->>'unitId' = unit->>'id'
      and elem->>'catalogId' = spec->>'id'
      and elem->>'status' = 'active'
      and elem->>'id' is distinct from current->>'id'
  ) then
    raise exception '% is already kept.', spec->>'name' using errcode = '22023';
  end if;
  correction := command->>'type' = 'correct_special' or public._bastion_flag(command->'dmOverride');
  if correction then
    perform public._bastion_reason(command);
  elsif coalesce((unit->>'replacementBank')::int, 0) < 1 then
    raise exception 'This level has no unused replacement. Gaining a level grants one. The current level by itself does not grant a stack of swaps.'
      using errcode = '22023';
  end if;
  select closed.next_doc, closed.note into doc, extra
  from public._bastion_close_facility(doc, current->>'id', command) as closed;
  old_name := current->>'name';
  doc := public._bastion_archive_facility(
    doc,
    current->>'id',
    case
      when command->>'type' = 'correct_special' then 'DM correction: ' || public._bastion_reason(command)
      when public._bastion_flag(command->'dmOverride') then 'DM override: ' || public._bastion_reason(command)
      else 'Replaced'
    end
  );
  if not correction then
    unit := jsonb_set(unit, '{replacementBank}', to_jsonb((unit->>'replacementBank')::int - 1));
    doc := public._bastion_put_unit(doc, unit);
  end if;
  acquired := case
    when command->>'type' = 'correct_special' then 'dm_correction'
    when public._bastion_flag(command->'dmOverride') then 'dm_override'
    else 'replacement'
  end;
  select made.next_doc, made.facility into doc, facility
  from public._bastion_make_special(doc, unit, spec, acquired) as made;
  summary := case
    when command->>'type' = 'correct_special' then format('DM correction: swapped %s for %s. This did not spend a level-up replacement, and it is not the published once-per-level swap. The old room is archived. Cash was not changed.', old_name, spec->>'name')
    when public._bastion_flag(command->'dmOverride') then format('DM override: replaced %s with %s without using a level-up replacement. The old one stays in the archive. Cash was not changed.', old_name, spec->>'name')
    else format('Replaced %s with %s. The old one stays in the archive.', old_name, spec->>'name')
  end;
  return public._bastion_out(
    doc,
    jsonb_build_object('facilityId', facility->>'id', 'bank', (public._bastion_unit(doc, unit->>'id')->>'replacementBank')::int, 'acquired', acquired),
    summary || coalesce(extra, '')
  );
end;
$$;

create or replace function public._bastion_cmd_remove_facility(doc jsonb, command jsonb)
returns jsonb
language plpgsql
set search_path = public
as $$
declare
  current jsonb;
  extra text;
  reason text;
  summary text;
begin
  reason := public._bastion_reason(command);
  current := public._bastion_facility(doc, command->>'facilityId');
  select closed.next_doc, closed.note into doc, extra
  from public._bastion_close_facility(doc, current->>'id', command) as closed;
  doc := public._bastion_archive_facility(doc, current->>'id', 'DM correction: ' || reason);
  summary := case
    when current->>'kind' = 'basic' then format('DM correction: archived %s. This is not a sale. The bastion chapter does not give a price for removing a basic room, so cash was not changed.', current->>'name')
    else format('DM correction: archived %s. Special facilities are not sold. Cash was not changed. The old room is in the archive.', current->>'name')
  end;
  return public._bastion_out(doc, jsonb_build_object('facilityId', current->>'id', 'removed', true), summary || coalesce(extra, ''));
end;
$$;

create or replace function public._bastion_cmd_edit_facility(doc jsonb, command jsonb)
returns jsonb
language plpgsql
set search_path = public
as $$
declare
  facility jsonb;
  spec jsonb;
  before_name text;
  before_space text;
  before_note text;
  before_catalog text;
  room_name text;
  next_space text;
  housed int;
  cap int;
  hirelings int;
begin
  perform public._bastion_reason(command);
  facility := public._bastion_facility(doc, command->>'facilityId');
  if facility->>'status' = 'building' or exists (
    select 1 from jsonb_array_elements(coalesce(doc->'projects', '[]'::jsonb)) project
    where project->>'status' = 'building' and project->>'facilityId' = facility->>'id'
  ) then
    raise exception '% is in the middle of an enlargement. Cancel that project or let it finish before editing the room. Cash was not changed.',
      facility->>'name' using errcode = '22023';
  end if;
  before_name := facility->>'name';
  before_space := facility->>'space';
  before_note := coalesce(facility->>'note', '');
  before_catalog := facility->>'catalogId';
  if command ? 'note' then
    facility := facility || jsonb_build_object('note', left(coalesce(command->>'note', ''), 160));
  end if;
  if facility->>'kind' = 'basic' then
    if coalesce(command->>'roomId', '') <> '' and command->>'roomId' is distinct from facility->>'catalogId' then
      room_name := public._bastion_catalog()#>>array['rooms', command->>'roomId'];
      if room_name is null then
        raise exception 'Choose a basic room from the list.' using errcode = '22023';
      end if;
      facility := facility || jsonb_build_object('catalogId', command->>'roomId', 'name', room_name);
    end if;
    if coalesce(command->>'space', '') <> '' and command->>'space' is distinct from facility->>'space' then
      if public._bastion_squares(command->>'space') = 0 then
        raise exception 'Choose cramped, roomy, or vast.' using errcode = '22023';
      end if;
      facility := facility || jsonb_build_object('space', command->>'space', 'squares', public._bastion_squares(command->>'space'));
    end if;
  elsif facility->>'kind' = 'special' then
    if coalesce(command->>'roomId', '') <> '' and command->>'roomId' is distinct from facility->>'catalogId' then
      raise exception 'A special facility is swapped from its own action. Edit can change the note or a wrongly recorded size.' using errcode = '22023';
    end if;
    if coalesce(command->>'space', '') <> '' and command->>'space' is distinct from facility->>'space' then
      spec := public._bastion_spec(facility->>'catalogId');
      next_space := command->>'space';
      if next_space not in ('cramped', 'roomy', 'vast')
         or (
           spec->'enlargeGp' is not null and spec->>'enlargeGp' ~ '^[0-9]+$'
           and next_space not in (spec->>'space', 'vast')
         )
         or (
           (spec->'enlargeGp' is null or spec->>'enlargeGp' !~ '^[0-9]+$')
           and next_space is distinct from spec->>'space'
         ) then
        raise exception '% is not recorded at that size. Enlargement, when the chapter has a price, stays on its own action.', facility->>'name'
          using errcode = '22023';
      end if;
      if facility->>'catalogId' = 'barrack' then
        cap := case when next_space = 'vast' then 25 else 12 end;
        select count(*) into housed
        from jsonb_array_elements(coalesce(doc->'roster', '[]'::jsonb)) person
        where person->>'facilityId' = facility->>'id'
          and person->>'category' = 'defender'
          and coalesce(nullif(person->>'status', ''), 'active') = 'active';
        if housed > cap then
          raise exception 'This barrack houses %, and the % size holds %. The defender count was not changed.', housed, next_space, cap
            using errcode = '22023';
        end if;
      end if;
      hirelings := coalesce((spec->>'hirelings')::int, 1) + case when next_space = 'vast' then coalesce((spec->>'enlargeHirelings')::int, 0) else 0 end;
      facility := facility || jsonb_build_object('space', next_space, 'hirelings', hirelings);
      if spec->>'id' = 'garden' then
        facility := facility || jsonb_build_object('plots', case when next_space = 'vast' then 2 else 1 end);
      end if;
      if spec->>'id' = 'stable' then
        facility := facility || jsonb_build_object('vastCapacityLarge', case when next_space = 'vast' then 6 else 3 end);
      end if;
    end if;
  else
    raise exception 'That room cannot be edited.' using errcode = '22023';
  end if;
  if before_name = facility->>'name'
     and before_space = facility->>'space'
     and before_note = coalesce(facility->>'note', '')
     and before_catalog = facility->>'catalogId' then
    raise exception 'Nothing on that room changed.' using errcode = '22023';
  end if;
  doc := public._bastion_put_facility(doc, facility);
  return public._bastion_out(
    doc,
    jsonb_build_object('facilityId', facility->>'id'),
    format('DM correction: edited %s. Room: "%s" → "%s". Size: "%s" → "%s". Note: "%s" → "%s". Cash was not changed. This did not start a build and it is not a level-up replacement.',
      before_name, before_name, facility->>'name', before_space, facility->>'space', before_note, coalesce(facility->>'note', ''))
  );
end;
$$;

create or replace function public._bastion_cmd_replace_basic(doc jsonb, command jsonb)
returns jsonb
language plpgsql
set search_path = public
as $$
declare
  current jsonb;
  room_name text;
  facility_id text;
  extra text;
  reason text;
begin
  reason := public._bastion_reason(command);
  current := public._bastion_facility(doc, command->>'facilityId');
  if current->>'kind' is distinct from 'basic' then
    raise exception 'Use the special-facility swap for a special facility.' using errcode = '22023';
  end if;
  room_name := public._bastion_catalog()#>>array['rooms', command->>'roomId'];
  if room_name is null then
    raise exception 'Choose a basic room from the list.' using errcode = '22023';
  end if;
  if public._bastion_catalog()->'build'->(command->>'space') is null then
    raise exception 'Choose cramped, roomy, or vast.' using errcode = '22023';
  end if;
  if current->>'catalogId' = command->>'roomId' and current->>'space' = command->>'space' then
    raise exception 'That is already the recorded room. Edit the note, or choose a different room.' using errcode = '22023';
  end if;
  select closed.next_doc, closed.note into doc, extra
  from public._bastion_close_facility(doc, current->>'id', command) as closed;
  doc := public._bastion_archive_facility(doc, current->>'id', 'DM correction: ' || reason);
  select taken.next_doc, taken.next_id into doc, facility_id from public._bastion_take(doc, 'fac') as taken;
  doc := jsonb_set(doc, '{facilities}', public._bastion_arr(doc, 'facilities') || jsonb_build_array(jsonb_build_object(
    'id', facility_id,
    'unitId', current->>'unitId',
    'kind', 'basic',
    'catalogId', command->>'roomId',
    'name', room_name,
    'space', command->>'space',
    'status', 'active',
    'acquired', 'dm_correction',
    'squares', public._bastion_squares(command->>'space'),
    'note', ''
  )));
  return public._bastion_out(
    doc,
    jsonb_build_object('facilityId', facility_id, 'replacedId', current->>'id'),
    format('DM correction: replaced %s with %s. The old room is archived. No build was started and no money moved. This is not the published way to add a basic room.', current->>'name', room_name) || coalesce(extra, '')
  );
end;
$$;

create or replace function public._bastion_cmd_cancel_project(doc jsonb, command jsonb)
returns jsonb
language plpgsql
set search_path = public
as $$
declare
  project jsonb;
  facility jsonb;
  reason text;
begin
  reason := public._bastion_reason(command);
  project := public._bastion_find(doc->'projects', command->>'projectId');
  if project is null or project->>'status' is distinct from 'building' then
    raise exception 'That build is not still in progress.' using errcode = '22023';
  end if;
  project := project || jsonb_build_object('status', 'cancelled', 'cancelledReason', reason);
  doc := jsonb_set(doc, '{projects}', public._bastion_replace(doc->'projects', project->>'id', project));
  if project->>'kind' = 'upgrade' and coalesce(project->>'facilityId', '') <> '' then
    facility := public._bastion_find(doc->'facilities', project->>'facilityId');
    if facility is not null and facility->>'status' = 'building' then
      facility := facility || jsonb_build_object('status', 'active');
      doc := public._bastion_put_facility(doc, facility);
    end if;
  end if;
  return public._bastion_out(
    doc,
    jsonb_build_object('projectId', project->>'id', 'cancelled', true),
    format('DM correction: cancelled the unfinished work on %s. The build will not finish. Money already spent was not refunded.', project->>'name')
  );
end;
$$;

create or replace function public._bastion_person_fields(doc jsonb, person jsonb, command jsonb)
returns jsonb
language plpgsql
set search_path = public
as $$
declare
  new_name text;
  new_role text;
  new_summary text;
  new_link text;
  new_category text;
  old_category text := coalesce(person->>'category', '');
  facility_id text;
  locked boolean;
begin
  if command ? 'name' then
    new_name := left(btrim(coalesce(command->>'name', '')), 80);
  else
    new_name := coalesce(person->>'name', '');
  end if;
  new_role := left(case when command ? 'role' then coalesce(command->>'role', '') else coalesce(person->>'role', '') end, 80);
  new_summary := left(case when command ? 'summary' then coalesce(command->>'summary', '') else coalesce(person->>'summary', '') end, 160);
  new_link := left(case when command ? 'link' then coalesce(command->>'link', '') else coalesce(person->>'link', '') end, 300);
  if new_link <> '' and new_link !~ '^https?://' then
    raise exception 'A link should start with http:// or https://, or be left blank.' using errcode = '22023';
  end if;
  new_category := coalesce(nullif(command->>'category', ''), old_category);
  if new_category not in ('household', 'hireling', 'defender', 'guest', 'lieutenant', 'creature') then
    raise exception 'Choose a roster category.' using errcode = '22023';
  end if;
  facility_id := person->>'facilityId';
  locked := coalesce(nullif(person->>'status', ''), 'active') = 'active'
    and (
      old_category = 'defender'
      or coalesce((person->>'protectsOnce')::boolean, false)
      or (
        facility_id is not null and facility_id <> ''
        and exists (
          select 1 from jsonb_array_elements(coalesce(doc->'facilities', '[]'::jsonb)) elem
          where elem->>'id' = facility_id and elem->>'status' is distinct from 'archived'
        )
      )
    );
  if new_category is distinct from old_category and locked then
    raise exception 'That person''s category stays put while they are a defender, assigned to a facility, or set to protect the bastion.'
      using errcode = '22023';
  end if;
  return jsonb_build_object('name', new_name, 'role', new_role, 'summary', new_summary, 'link', new_link, 'category', new_category);
end;
$$;

create or replace function public._bastion_cmd_replace_person(doc jsonb, command jsonb)
returns jsonb
language plpgsql
set search_path = public
as $$
declare
  person jsonb;
  fields jsonb;
  person_id text;
  new_id text;
  facility_id text;
  old_name text;
  label text;
  kept_housed boolean;
  kept_protects boolean;
  kept_unit text;
begin
  perform public._bastion_reason(command);
  person := public._bastion_find(doc->'roster', coalesce(command->>'personId', command->>'id'));
  if person is null then
    raise exception 'That person is not on the roster.' using errcode = '22023';
  end if;
  fields := public._bastion_person_fields(doc, person, command);
  person_id := person->>'id';
  if exists (
       select 1 from jsonb_array_elements(coalesce(doc->'orders', '[]'::jsonb)) elem
       where public._bastion_order_unfinished(doc, elem) and position('"' || person_id || '"' in elem::text) > 0
     )
     or exists (
       select 1 from jsonb_array_elements(coalesce(doc->'tasks', '[]'::jsonb)) elem
       where public._bastion_task_pending(elem) and position('"' || person_id || '"' in elem::text) > 0
     )
     or exists (
       select 1 from jsonb_array_elements(coalesce(doc->'events', '[]'::jsonb)) elem
       where elem->>'status' = 'pending' and position('"' || person_id || '"' in elem::text) > 0
     ) then
    raise exception 'That person is tied to work that has not finished. Release that link before replacing them. Cash was not changed.'
      using errcode = '22023';
  end if;
  facility_id := person->>'facilityId';
  old_name := coalesce(person->>'name', '');
  kept_housed := coalesce((person->>'housed')::boolean, false);
  kept_protects := coalesce((person->>'protectsOnce')::boolean, false);
  kept_unit := person->>'unitId';
  select taken.next_doc, taken.next_id into doc, new_id from public._bastion_take(doc, 'npc') as taken;
  person := person || jsonb_build_object('status', 'replaced', 'facilityId', null, 'housed', false, 'protectsOnce', false);
  doc := jsonb_set(doc, '{roster}', public._bastion_replace(doc->'roster', person_id, person));
  label := coalesce(nullif(fields->>'name', ''), 'an unnamed person');
  doc := jsonb_set(doc, '{roster}', public._bastion_arr(doc, 'roster') || jsonb_build_array(jsonb_build_object(
    'id', new_id,
    'name', fields->>'name',
    'category', fields->>'category',
    'summary', fields->>'summary',
    'role', fields->>'role',
    'link', fields->>'link',
    'unitId', kept_unit,
    'facilityId', case when facility_id is null or facility_id = '' then 'null'::jsonb else to_jsonb(facility_id) end,
    'status', 'active',
    'housed', kept_housed,
    'protectsOnce', kept_protects
  )));
  return public._bastion_out(
    doc,
    jsonb_build_object('personId', new_id, 'replacedId', person_id),
    format('Replaced roster %s ("%s") with %s ("%s"). The old name stays on the roster as replaced. Cash was not changed.', person_id, old_name, new_id, label)
  );
end;
$$;

create or replace function public._bastion_cmd_assign_person(doc jsonb, command jsonb)
returns jsonb
language plpgsql
set search_path = public
as $$
declare
  person jsonb;
  fields jsonb;
  facility jsonb;
  facility_id text;
  old_facility text;
  housed int;
  cap int;
  label text;
begin
  perform public._bastion_reason(command);
  person := public._bastion_find(doc->'roster', coalesce(command->>'personId', command->>'id'));
  if person is null then
    raise exception 'That person is not on the roster.' using errcode = '22023';
  end if;
  fields := public._bastion_person_fields(doc, person, command);
  if command ? 'facilityId' and command->'facilityId' is not null and command->'facilityId' <> 'null'::jsonb and coalesce(command->>'facilityId', '') <> '' then
    facility_id := command->>'facilityId';
  else
    facility_id := null;
  end if;
  if facility_id is not null then
    facility := public._bastion_facility(doc, facility_id);
    if fields->>'category' = 'defender' and facility->>'catalogId' = 'barrack' then
      cap := case when facility->>'space' = 'vast' then 25 else 12 end;
      select count(*) into housed
      from jsonb_array_elements(coalesce(doc->'roster', '[]'::jsonb)) elem
      where elem->>'facilityId' = facility->>'id'
        and elem->>'category' = 'defender'
        and coalesce(nullif(elem->>'status', ''), 'active') = 'active'
        and elem->>'id' is distinct from person->>'id';
      if housed + 1 > cap then
        raise exception 'This barrack houses %, not %.', cap, housed + 1 using errcode = '22023';
      end if;
    end if;
  elsif fields->>'category' = 'defender' and coalesce(nullif(person->>'status', ''), 'active') = 'active' then
    raise exception 'A defender stays housed until you change the defender count. The assignment was not cleared.' using errcode = '22023';
  end if;
  old_facility := coalesce(person->>'facilityId', '');
  label := coalesce(nullif(fields->>'name', ''), 'an unnamed person');
  person := person || jsonb_build_object(
    'name', fields->>'name',
    'role', fields->>'role',
    'summary', fields->>'summary',
    'link', fields->>'link',
    'category', fields->>'category',
    'facilityId', case when facility_id is null then 'null'::jsonb else to_jsonb(facility_id) end
  );
  doc := jsonb_set(doc, '{roster}', public._bastion_replace(doc->'roster', person->>'id', person));
  return public._bastion_out(
    doc,
    jsonb_build_object('personId', person->>'id', 'facilityId', case when facility_id is null then 'null'::jsonb else to_jsonb(facility_id) end),
    format('DM correction: assigned roster %s ("%s") from "%s" to "%s". Cash was not changed.', person->>'id', label, old_facility, coalesce(facility_id, ''))
  );
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
  if cmd = 'replace_special' or cmd = 'correct_special' then return public._bastion_cmd_replace(doc, command); end if;
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
    'cancel_project'
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
