\set ON_ERROR_STOP on

insert into auth.users (id, email) values
  ('35353535-3535-3535-3535-353535353535', 'manage-dm@example.com'),
  ('36363636-3636-3636-3636-363636363636', 'manage-editor@example.com')
on conflict (id) do nothing;

create or replace function public._run_manage_checks()
returns void
language plpgsql
as $$
declare
  eid uuid;
  rev bigint;
  out jsonb;
  doc jsonb;
  cash jsonb;
  facility_id text;
  person_id text;
  library_id text;
  token text;
  project_id text;
begin
  perform set_config('request.jwt.claim.sub', '35353535-3535-3535-3535-353535353535', false);
  perform set_config('request.jwt.claim.role', 'authenticated', false);
  eid := public.create_estate('Practice Hold');
  select revision into rev from public.estates where id = eid;
  out := public.apply_command(eid, rev, 'parlor', '{"type":"add_basic","unitId":"unit-party","roomId":"parlor","space":"cramped","inherited":true}'::jsonb);
  rev := (out->>'revision')::bigint;
  doc := out->'document';
  facility_id := doc#>>'{facilities,0,id}';
  cash := doc#>'{finance,cashGp}';
  if doc#>'{finance,cashKnown}' is distinct from 'false'::jsonb or cash is distinct from 'null'::jsonb then
    raise exception 'opening cash was invented';
  end if;
  out := public.apply_command(eid, rev, 'edit-room', jsonb_build_object(
    'type', 'edit_facility', 'facilityId', facility_id, 'roomId', 'storage', 'space', 'roomy', 'note', 'South wall', 'reason', 'The import named the wrong room.'
  ));
  rev := (out->>'revision')::bigint;
  doc := out->'document';
  if doc#>>'{facilities,0,id}' is distinct from facility_id
     or doc#>>'{facilities,0,catalogId}' is distinct from 'storage'
     or doc#>>'{facilities,0,space}' is distinct from 'roomy'
     or doc#>'{finance,cashGp}' is distinct from cash
     or doc#>'{finance,cashKnown}' is distinct from 'false'::jsonb then
    raise exception 'room edit changed the id or the cash';
  end if;
  if not exists (
    select 1 from public.audit_log
    where estate_id = eid and command_type = 'edit_facility' and summary like '%DM correction%' and summary like '%not a level-up replacement%'
  ) then
    raise exception 'room edit was described as a level-up';
  end if;

  out := public.apply_command(eid, rev, 'barrack', '{"type":"add_special","unitId":"unit-party","catalogId":"barrack"}'::jsonb);
  rev := (out->>'revision')::bigint;
  doc := out->'document';
  select elem->>'id' into facility_id from jsonb_array_elements(doc->'facilities') elem where elem->>'catalogId' = 'barrack' limit 1;
  if (doc#>>'{units,0,replacementBank}')::int <> 0 then
    raise exception 'a new estate had a replacement bank';
  end if;
  begin
    perform public.apply_command(eid, rev, 'official', jsonb_build_object(
      'type', 'replace_special', 'unitId', 'unit-party', 'facilityId', facility_id, 'catalogId', 'library'
    ));
    raise exception 'a level-up replacement was spent with an empty bank';
  exception when invalid_parameter_value then
    if SQLERRM not like '%no unused replacement%' then raise; end if;
  end;
  out := public.apply_command(eid, rev, 'correct', jsonb_build_object(
    'type', 'correct_special', 'unitId', 'unit-party', 'facilityId', facility_id, 'catalogId', 'library', 'reason', 'The barrack was the wrong choice.'
  ));
  rev := (out->>'revision')::bigint;
  doc := out->'document';
  if (doc#>>'{units,0,replacementBank}')::int <> 0
     or exists (select 1 from jsonb_array_elements(doc->'facilities') elem where elem->>'catalogId' = 'barrack' and elem->>'status' = 'active')
     or not exists (select 1 from jsonb_array_elements(doc->'facilities') elem where elem->>'catalogId' = 'library' and elem->>'acquired' = 'dm_correction')
     or not exists (select 1 from jsonb_array_elements(doc->'archive') elem where elem->>'catalogId' = 'barrack')
     or doc#>'{finance,cashGp}' is distinct from cash then
    raise exception 'mid-level swap did not archive the old facility';
  end if;
  if not exists (
    select 1 from public.audit_log
    where estate_id = eid and command_type = 'correct_special' and summary like '%not the published once-per-level swap%'
  ) then
    raise exception 'mid-level swap was labeled as the published replacement';
  end if;
  select elem->>'id' into library_id from jsonb_array_elements(doc->'facilities') elem where elem->>'catalogId' = 'library' limit 1;

  out := public.apply_command(eid, rev, 'blank', jsonb_build_object(
    'type', 'roster_save',
    'person', jsonb_build_object('name', '   ', 'category', 'hireling', 'role', 'Smith', 'facilityId', library_id, 'unitId', 'unit-party')
  ));
  rev := (out->>'revision')::bigint;
  doc := out->'document';
  person_id := doc#>>'{roster,0,id}';
  if coalesce(doc#>>'{roster,0,name}', '') <> '' then
    raise exception 'placeholder was named';
  end if;
  begin
    perform public.apply_command(eid, rev, 'drop-room', jsonb_build_object('type', 'remove_facility', 'facilityId', library_id, 'reason', 'Wrong shop.'));
    raise exception 'hirelings were ignored';
  exception when invalid_parameter_value then
    if SQLERRM not like '%hireling%' then raise; end if;
  end;
  out := public.apply_command(eid, rev, 'release', jsonb_build_object(
    'type', 'remove_facility', 'facilityId', library_id, 'reason', 'Wrong shop.', 'hirelings', 'release'
  ));
  rev := (out->>'revision')::bigint;
  doc := out->'document';
  if doc#>>'{roster,0,id}' is distinct from person_id
     or coalesce(doc#>>'{roster,0,name}', '') <> ''
     or doc#>>'{roster,0,status}' is distinct from 'active'
     or doc#>>'{roster,0,facilityId}' is not null
     or exists (select 1 from jsonb_array_elements(doc->'facilities') elem where elem->>'id' = library_id)
     or doc#>'{finance,cashGp}' is distinct from cash then
    raise exception 'released hireling was deleted or cash moved';
  end if;

  out := public.apply_command(eid, rev, 'smithy', '{"type":"add_special","unitId":"unit-party","catalogId":"smithy"}'::jsonb);
  rev := (out->>'revision')::bigint;
  doc := out->'document';
  select elem->>'id' into facility_id from jsonb_array_elements(doc->'facilities') elem where elem->>'catalogId' = 'smithy' limit 1;
  out := public.apply_command(eid, rev, 'clock', '{"type":"set_clock","ordinal":4}'::jsonb);
  rev := (out->>'revision')::bigint;
  out := public.apply_command(eid, rev, 'running', jsonb_build_object(
    'type', 'record_order', 'facilityId', facility_id, 'suborder', 'craft', 'startedDay', 4, 'note', 'Already at the forge'
  ));
  rev := (out->>'revision')::bigint;
  begin
    perform public.apply_command(eid, rev, 'drop-work', jsonb_build_object('type', 'remove_facility', 'facilityId', facility_id, 'reason', 'Stop the forge.'));
    raise exception 'unfinished work was dropped silently';
  exception when invalid_parameter_value then
    if SQLERRM not like '%unfinished work%' then raise; end if;
  end;
  out := public.apply_command(eid, rev, 'cancel-work', jsonb_build_object(
    'type', 'remove_facility', 'facilityId', facility_id, 'reason', 'Stop the forge.', 'cancelWork', true
  ));
  rev := (out->>'revision')::bigint;
  doc := out->'document';
  if not exists (
       select 1 from jsonb_array_elements(doc->'orders') elem
       where elem->>'facilityId' = facility_id and elem->>'status' = 'cancelled'
     )
     or doc#>'{finance,cashGp}' is distinct from cash
     or doc#>'{finance,cashKnown}' is distinct from 'false'::jsonb then
    raise exception 'cancelled work was paid or cash was invented';
  end if;

  out := public.apply_command(eid, rev, 'cash', '{"type":"set_finance","cashGp":8000}'::jsonb);
  rev := (out->>'revision')::bigint;
  out := public.apply_command(eid, rev, 'store', '{"type":"add_special","unitId":"unit-party","catalogId":"storehouse"}'::jsonb);
  rev := (out->>'revision')::bigint;
  doc := out->'document';
  select elem->>'id' into facility_id from jsonb_array_elements(doc->'facilities') elem where elem->>'catalogId' = 'storehouse' limit 1;
  out := public.apply_command(eid, rev, 'buy', jsonb_build_object(
    'type', 'commit_turn', 'unitId', 'unit-party', 'presence', 'present', 'mode', 'orders',
    'orders', jsonb_build_array(jsonb_build_object('facilityId', facility_id, 'suborder', 'buy', 'standardGp', 100, 'goodsName', 'Nails'))
  ));
  rev := (out->>'revision')::bigint;
  doc := out->'document';
  if (doc#>>'{finance,cashGp}')::int <> 7900 then
    raise exception 'purchase did not spend 100 GP';
  end if;
  out := public.apply_command(eid, rev, 'drop-buy', jsonb_build_object(
    'type', 'remove_facility', 'facilityId', facility_id, 'reason', 'The buy was the wrong order.', 'cancelWork', true
  ));
  rev := (out->>'revision')::bigint;
  doc := out->'document';
  if (doc#>>'{finance,cashGp}')::int <> 7900
     or exists (select 1 from jsonb_array_elements(doc->'goods') elem where elem->>'name' = 'Nails')
     or not exists (
       select 1 from public.audit_log
       where estate_id = eid and command_type = 'remove_facility' and summary like '%not refunded%'
     ) then
    raise exception 'cancelling a purchase refunded it or delivered the goods';
  end if;

  out := public.apply_command(eid, rev, 'kitchen', '{"type":"add_basic","unitId":"unit-party","roomId":"kitchen","space":"cramped","inherited":true}'::jsonb);
  rev := (out->>'revision')::bigint;
  doc := out->'document';
  select elem->>'id' into facility_id from jsonb_array_elements(doc->'facilities') elem where elem->>'catalogId' = 'kitchen' limit 1;
  out := public.apply_command(eid, rev, 'swap-basic', jsonb_build_object(
    'type', 'replace_basic', 'facilityId', facility_id, 'roomId', 'storage', 'space', 'roomy', 'reason', 'It was a storeroom.'
  ));
  rev := (out->>'revision')::bigint;
  doc := out->'document';
  if exists (select 1 from jsonb_array_elements(doc->'facilities') elem where elem->>'id' = facility_id)
     or not exists (select 1 from jsonb_array_elements(doc->'facilities') elem where elem->>'catalogId' = 'storage' and elem->>'acquired' = 'dm_correction')
     or (doc#>>'{finance,cashGp}')::int <> 7900 then
    raise exception 'basic replacement charged or kept the old id active';
  end if;

  out := public.apply_command(eid, rev, 'build', '{"type":"add_basic","unitId":"unit-party","roomId":"parlor","space":"cramped"}'::jsonb);
  rev := (out->>'revision')::bigint;
  doc := out->'document';
  project_id := doc#>>'{projects,0,id}';
  if (doc#>>'{finance,cashGp}')::int <> 7400 or project_id is null then
    raise exception 'paid build did not start';
  end if;
  out := public.apply_command(eid, rev, 'stop-build', jsonb_build_object('type', 'cancel_project', 'projectId', project_id, 'reason', 'That parlor was a misclick.'));
  doc := out->'document';
  if (doc#>>'{finance,cashGp}')::int <> 7400
     or not exists (select 1 from jsonb_array_elements(doc->'projects') elem where elem->>'id' = project_id and elem->>'status' = 'cancelled')
     or exists (select 1 from jsonb_array_elements(doc->'facilities') elem where elem->>'name' = 'Parlor' and elem->>'acquired' = 'built') then
    raise exception 'cancelled build refunded or finished the room';
  end if;

  out := public.apply_command(eid, null, 'garden', '{"type":"add_special","unitId":"unit-party","catalogId":"garden"}'::jsonb);
  doc := out->'document';
  select elem->>'id' into facility_id from jsonb_array_elements(doc->'facilities') elem where elem->>'catalogId' = 'garden' limit 1;
  out := public.apply_command(eid, null, 'yard', jsonb_build_object(
    'type', 'roster_save',
    'person', jsonb_build_object('name', 'Yard hand', 'category', 'hireling', 'role', 'Yard', 'facilityId', facility_id, 'unitId', 'unit-party')
  ));
  doc := out->'document';
  select elem->>'id' into person_id from jsonb_array_elements(doc->'roster') elem where elem->>'name' = 'Yard hand' limit 1;

  token := public.create_invite(eid, 'manage-editor@example.com', 'editor');
  perform set_config('request.jwt.claim.sub', '36363636-3636-3636-3636-363636363636', false);
  perform public.accept_invite(token);
  begin
    perform public.apply_command(eid, null, 'ed-remove', jsonb_build_object('type', 'remove_facility', 'facilityId', facility_id, 'reason', 'No.'));
    raise exception 'editor removed a room';
  exception when insufficient_privilege then null;
  end;
  begin
    perform public.apply_command(eid, null, 'ed-correct', jsonb_build_object('type', 'correct_special', 'unitId', 'unit-party', 'facilityId', facility_id, 'catalogId', 'library', 'reason', 'No.'));
    raise exception 'editor swapped a special';
  exception when insufficient_privilege then null;
  end;
  begin
    perform public.apply_command(eid, null, 'ed-person', jsonb_build_object('type', 'replace_person', 'personId', person_id, 'name', 'Nell', 'reason', 'No.'));
    raise exception 'editor replaced a person';
  exception when insufficient_privilege then null;
  end;
  begin
    perform public.apply_command(eid, null, 'ed-move', jsonb_build_object('type', 'assign_person', 'personId', person_id, 'facilityId', null, 'reason', 'No.'));
    raise exception 'editor moved a person';
  exception when insufficient_privilege then null;
  end;
  out := public.apply_command(eid, null, 'ed-name', jsonb_build_object(
    'type', 'edit_person', 'personId', person_id, 'name', 'Nell Cooper', 'role', 'Yard', 'category', 'hireling', 'summary', '', 'link', ''
  ));
  doc := out->'document';
  if not exists (
       select 1 from jsonb_array_elements(doc->'roster') elem
       where elem->>'id' = person_id and elem->>'name' = 'Nell Cooper' and elem->>'facilityId' = facility_id
     ) then
    raise exception 'naming a placeholder changed the assignment';
  end if;

  perform set_config('request.jwt.claim.sub', '35353535-3535-3535-3535-353535353535', false);
  out := public.apply_command(eid, null, 'dm-replace', jsonb_build_object(
    'type', 'replace_person', 'personId', person_id, 'name', '   ', 'category', 'hireling', 'role', 'Yard', 'reason', 'The name was early.'
  ));
  doc := out->'document';
  if not exists (select 1 from jsonb_array_elements(doc->'roster') elem where elem->>'id' = person_id and elem->>'status' = 'replaced' and elem->>'facilityId' is null)
     or not exists (
       select 1 from jsonb_array_elements(doc->'roster') elem
       where elem->>'status' = 'active' and coalesce(elem->>'name', '') = '' and elem->>'facilityId' = facility_id and elem->>'category' = 'hireling'
     ) then
    raise exception 'replacement did not keep the post for an unnamed person';
  end if;

  if exists (
    select 1 from pg_proc
    where proname in (
      '_bastion_close_facility', '_bastion_cmd_remove_facility', '_bastion_cmd_edit_facility',
      '_bastion_cmd_replace_basic', '_bastion_cmd_replace_person', '_bastion_cmd_assign_person',
      '_bastion_cmd_cancel_project', '_bastion_person_fields', '_bastion_reason'
    ) and prosecdef
  ) then
    raise exception 'room or roster helper is security definer';
  end if;
end;
$$;

set role authenticated;
select set_config('request.jwt.claim.sub', '35353535-3535-3535-3535-353535353535', false);
select set_config('request.jwt.claim.role', 'authenticated', false);
select public._run_manage_checks();
reset role;
