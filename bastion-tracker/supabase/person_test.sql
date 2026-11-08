\set ON_ERROR_STOP on

insert into auth.users (id, email) values
  ('31313131-3131-3131-3131-313131313131', 'person-dm@example.com'),
  ('32323232-3232-3232-3232-323232323232', 'person-editor@example.com'),
  ('34343434-3434-3434-3434-343434343434', 'person-reader@example.com')
on conflict (id) do nothing;

create or replace function public._run_person_checks()
returns void
language plpgsql
as $$
declare
  eid uuid;
  rev bigint;
  out jsonb;
  doc jsonb;
  person_id text;
  facility_id text;
  cash jsonb;
  token text;
begin
  perform set_config('request.jwt.claim.sub', '31313131-3131-3131-3131-313131313131', false);
  perform set_config('request.jwt.claim.role', 'authenticated', false);
  eid := public.create_estate('Practice Hold');
  select revision into rev from public.estates where id = eid;
  out := public.apply_command(eid, rev, 'smithy', '{"type":"add_special","unitId":"unit-party","catalogId":"smithy"}'::jsonb);
  rev := (out->>'revision')::bigint;
  doc := out->'document';
  facility_id := doc#>>'{facilities,0,id}';
  out := public.apply_command(eid, rev, 'blank-hire', jsonb_build_object(
    'type', 'roster_save',
    'person', jsonb_build_object('name', '   ', 'category', 'hireling', 'role', 'Smith', 'facilityId', facility_id, 'unitId', 'unit-party')
  ));
  rev := (out->>'revision')::bigint;
  doc := out->'document';
  person_id := doc#>>'{roster,0,id}';
  if coalesce(doc#>>'{roster,0,name}', '') <> '' then
    raise exception 'unnamed placeholder was given a name';
  end if;
  cash := doc#>'{finance,cashGp}';

  token := public.create_invite(eid, 'person-editor@example.com', 'editor');
  perform set_config('request.jwt.claim.sub', '32323232-3232-3232-3232-323232323232', false);
  perform public.accept_invite(token);
  begin
    perform public.apply_command(eid, null, 'editor-remove', jsonb_build_object('type', 'remove_person', 'personId', person_id));
    raise exception 'editor removed a person';
  exception when insufficient_privilege then null;
  end;
  out := public.apply_command(eid, null, 'editor-edit', jsonb_build_object(
    'type', 'edit_person', 'personId', person_id, 'name', 'Ada Moss', 'role', 'Smith', 'category', 'hireling', 'summary', 'Works the forge', 'link', ''
  ));
  doc := out->'document';
  if doc#>>'{roster,0,id}' is distinct from person_id
     or doc#>>'{roster,0,name}' is distinct from 'Ada Moss'
     or doc#>>'{roster,0,facilityId}' is distinct from facility_id
     or doc#>'{finance,cashGp}' is distinct from cash then
    raise exception 'edit changed the id, assignment, or cash';
  end if;
  if not exists (
    select 1 from public.audit_log
    where estate_id = eid and command_type = 'edit_person' and summary like '%"" → "Ada Moss"%'
  ) then
    raise exception 'edit did not record the old and new name';
  end if;
  begin
    perform public.apply_command(eid, null, 'editor-category', jsonb_build_object(
      'type', 'edit_person', 'personId', person_id, 'name', 'Ada Moss', 'category', 'household', 'role', 'Smith'
    ));
    raise exception 'category change was allowed';
  exception when invalid_parameter_value then
    if SQLERRM not like 'That person''s category stays put%' then raise; end if;
  end;

  perform set_config('request.jwt.claim.sub', '31313131-3131-3131-3131-313131313131', false);
  token := public.create_invite(eid, 'person-reader@example.com', 'reader');
  perform set_config('request.jwt.claim.sub', '34343434-3434-3434-3434-343434343434', false);
  perform public.accept_invite(token);
  begin
    perform public.apply_command(eid, null, 'reader-edit', jsonb_build_object(
      'type', 'edit_person', 'personId', person_id, 'name', 'Someone else', 'role', 'Smith', 'category', 'hireling'
    ));
    raise exception 'reader edited a person';
  exception when insufficient_privilege then null;
  end;

  perform set_config('request.jwt.claim.sub', '31313131-3131-3131-3131-313131313131', false);
  select revision into rev from public.estates where id = eid;
  out := public.apply_command(eid, rev, 'guard', jsonb_build_object(
    'type', 'roster_save',
    'person', jsonb_build_object('name', 'Pell Ash', 'category', 'defender', 'role', 'Defender', 'unitId', 'unit-party')
  ));
  rev := (out->>'revision')::bigint;
  doc := out->'document';
  select elem->>'id' into person_id from jsonb_array_elements(doc->'roster') elem where elem->>'category' = 'defender' limit 1;
  begin
    perform public.apply_command(eid, rev, 'drop-guard', jsonb_build_object('type', 'remove_person', 'personId', person_id));
    raise exception 'defender was removed';
  exception when invalid_parameter_value then
    if SQLERRM not like 'That defender is still active%' then raise; end if;
  end;

  if exists (select 1 from pg_proc where proname = '_bastion_cmd_remove_person' and prosecdef) then
    raise exception 'remove person helper is security definer';
  end if;
  if exists (select 1 from pg_proc where proname = '_bastion_cmd_edit_person' and prosecdef) then
    raise exception 'edit person helper is security definer';
  end if;
end;
$$;

set role authenticated;
select set_config('request.jwt.claim.sub', '31313131-3131-3131-3131-313131313131', false);
select set_config('request.jwt.claim.role', 'authenticated', false);
select public._run_person_checks();
