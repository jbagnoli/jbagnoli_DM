-- Let the DM remove a mistaken roster name, and let an editor or the DM
-- fill in a name later. Existing people are not deleted. Cash is not changed.

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
    'edit_person'
  ]::text[];
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
  name := left(btrim(coalesce(person->>'name', '')), 80);
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
  return public._bastion_out(doc, jsonb_build_object('personId', record->>'id'), format('Saved %s.', coalesce(nullif(record->>'name', ''), 'an unnamed person')));
end;
$$;

create or replace function public._bastion_cmd_remove_person(doc jsonb, command jsonb)
returns jsonb
language plpgsql
set search_path = public
as $$
declare
  person jsonb;
  person_id text;
  facility_id text;
  cash_gp jsonb;
  cash_known jsonb;
begin
  person := public._bastion_find(doc->'roster', coalesce(command->>'personId', command->>'id'));
  if person is null then
    raise exception 'That person is not on the roster.' using errcode = '22023';
  end if;
  person_id := person->>'id';
  if coalesce(nullif(person->>'status', ''), 'active') = 'active' and person->>'category' = 'defender' then
    raise exception 'That defender is still active and counted. Change the defender count instead of deleting the name. Cash was not changed.'
      using errcode = '22023';
  end if;
  facility_id := person->>'facilityId';
  if coalesce(nullif(person->>'status', ''), 'active') = 'active'
     and facility_id is not null and facility_id <> ''
     and exists (
       select 1 from jsonb_array_elements(coalesce(doc->'facilities', '[]'::jsonb)) elem
       where elem->>'id' = facility_id and elem->>'status' is distinct from 'archived'
     ) then
    raise exception 'That person is still assigned to a facility. Clear that assignment before removing them. Cash was not changed.'
      using errcode = '22023';
  end if;
  if coalesce(nullif(person->>'status', ''), 'active') = 'active' and coalesce((person->>'protectsOnce')::boolean, false) then
    raise exception 'That person is still set to protect the bastion once. Cash was not changed.'
      using errcode = '22023';
  end if;
  if exists (
       select 1 from jsonb_array_elements(coalesce(doc->'orders', '[]'::jsonb)) elem
       where coalesce(elem->>'status', '') not in ('resolved', 'cancelled')
         and position('"' || person_id || '"' in elem::text) > 0
     )
     or exists (
       select 1 from jsonb_array_elements(coalesce(doc->'tasks', '[]'::jsonb)) elem
       where elem->>'status' = 'open' and position('"' || person_id || '"' in elem::text) > 0
     )
     or exists (
       select 1 from jsonb_array_elements(coalesce(doc->'events', '[]'::jsonb)) elem
       where elem->>'status' = 'pending' and position('"' || person_id || '"' in elem::text) > 0
     ) then
    raise exception 'That person is tied to an order that has not finished. Release that link before removing them. Cash was not changed.'
      using errcode = '22023';
  end if;
  cash_gp := doc#>'{finance,cashGp}';
  cash_known := doc#>'{finance,cashKnown}';
  doc := jsonb_set(doc, '{roster}', public._bastion_remove(doc->'roster', person_id));
  doc := jsonb_set(doc, '{finance,cashGp}', cash_gp);
  doc := jsonb_set(doc, '{finance,cashKnown}', cash_known);
  return public._bastion_out(
    doc,
    jsonb_build_object('personId', person_id, 'removed', true),
    format('Removed %s. Cash was not changed.', coalesce(nullif(person->>'name', ''), 'unnamed person'))
  );
end;
$$;

create or replace function public._bastion_cmd_edit_person(doc jsonb, command jsonb)
returns jsonb
language plpgsql
set search_path = public
as $$
declare
  person jsonb;
  old_name text;
  old_role text;
  old_summary text;
  old_link text;
  old_category text;
  new_name text;
  new_role text;
  new_summary text;
  new_link text;
  new_category text;
  locked boolean;
  facility_id text;
  summary text;
begin
  person := public._bastion_find(doc->'roster', coalesce(command->>'personId', command->>'id'));
  if person is null then
    raise exception 'That person is not on the roster.' using errcode = '22023';
  end if;
  old_name := coalesce(person->>'name', '');
  old_role := coalesce(person->>'role', '');
  old_summary := coalesce(person->>'summary', '');
  old_link := coalesce(person->>'link', '');
  old_category := coalesce(person->>'category', '');
  new_name := left(btrim(coalesce(command->>'name', old_name)), 80);
  new_role := left(coalesce(command->>'role', old_role), 80);
  new_summary := left(coalesce(command->>'summary', old_summary), 160);
  new_link := left(coalesce(command->>'link', old_link), 300);
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
  summary := format(
    'Edited roster %s. Name: "%s" → "%s". Role: "%s" → "%s". Category: "%s" → "%s". Summary: "%s" → "%s". Link: "%s" → "%s".',
    person->>'id', old_name, new_name, old_role, new_role, old_category, new_category, old_summary, new_summary, old_link, new_link
  );
  person := person || jsonb_build_object(
    'name', new_name,
    'role', new_role,
    'summary', new_summary,
    'link', new_link,
    'category', new_category
  );
  doc := jsonb_set(doc, '{roster}', public._bastion_replace(doc->'roster', person->>'id', person));
  return public._bastion_out(doc, jsonb_build_object(
    'personId', person->>'id',
    'old', jsonb_build_object('name', old_name, 'role', old_role, 'category', old_category, 'summary', old_summary, 'link', old_link),
    'new', jsonb_build_object('name', new_name, 'role', new_role, 'category', new_category, 'summary', new_summary, 'link', new_link)
  ), summary);
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
  if cmd = 'remove_goods' then return public._bastion_cmd_remove_goods(doc, command); end if;
  if cmd = 'remove_person' then return public._bastion_cmd_remove_person(doc, command); end if;
  if cmd = 'edit_person' then return public._bastion_cmd_edit_person(doc, command); end if;
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
    'remove_person'
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
