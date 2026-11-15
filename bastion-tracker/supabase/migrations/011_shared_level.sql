-- One level path. Raising the level uses the same checks as saving it, and does not add replacements.
-- Does not change cash, the turn, the anchor, loans, goods, orders, or an open sale.
-- Safe to run again: it only replaces functions.

create or replace function public._bastion_cmd_raise(doc jsonb, command jsonb)
returns jsonb
language plpgsql
set search_path = public
as $$
begin
  return public._bastion_cmd_set_level(doc, command);
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
    raise exception 'This level has no unused replacement. Changing the level does not add one. Add the facility from the level cap, or correct the room.'
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

revoke all on function public._bastion_cmd_raise(jsonb, jsonb) from public, anon, authenticated;
revoke all on function public._bastion_cmd_replace(jsonb, jsonb) from public, anon, authenticated;
