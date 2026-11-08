-- Shared bastion record. Direct table writes are closed.
-- The hosted project already has auth.users and auth.uid().

create extension if not exists pgcrypto;

do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then
    create role anon nologin;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then
    create role authenticated nologin;
  end if;
end $$;

create table if not exists public.estates (
  id uuid primary key default gen_random_uuid(),
  document jsonb not null,
  revision bigint not null default 1,
  created_at timestamptz not null default now(),
  constraint estates_revision_positive check (revision > 0)
);

create table if not exists public.estate_members (
  estate_id uuid not null references public.estates(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null check (role in ('dm', 'editor', 'reader')),
  primary key (estate_id, user_id)
);

create table if not exists public.invitations (
  id uuid primary key default gen_random_uuid(),
  estate_id uuid not null references public.estates(id) on delete cascade,
  email text not null,
  role text not null check (role in ('dm', 'editor', 'reader')),
  token_hash text not null unique,
  created_by uuid not null,
  accepted_at timestamptz,
  expires_at timestamptz not null default (now() + interval '14 days')
);

create table if not exists public.command_log (
  estate_id uuid not null references public.estates(id) on delete cascade,
  idempotency_key text not null,
  result jsonb not null,
  created_at timestamptz not null default now(),
  primary key (estate_id, idempotency_key)
);

create table if not exists public.audit_log (
  id bigint generated always as identity primary key,
  estate_id uuid not null references public.estates(id) on delete cascade,
  revision bigint not null,
  actor uuid,
  command_type text not null,
  summary text not null,
  reason text not null default '',
  created_at timestamptz not null default now()
);

alter table public.estates enable row level security;
alter table public.estate_members enable row level security;
alter table public.invitations enable row level security;
alter table public.command_log enable row level security;
alter table public.audit_log enable row level security;

alter table public.estates force row level security;
alter table public.estate_members force row level security;
alter table public.invitations force row level security;
alter table public.command_log force row level security;
alter table public.audit_log force row level security;

revoke all on public.estates, public.estate_members, public.invitations, public.command_log, public.audit_log from public, anon, authenticated;
grant select on public.estates, public.estate_members, public.invitations, public.command_log, public.audit_log to authenticated;

create or replace function public.member_role(eid uuid)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select role from public.estate_members where estate_id = eid and user_id = auth.uid();
$$;

create or replace function public.current_email()
returns text
language sql
stable
security definer
set search_path = public, auth
as $$
  select email from auth.users where id = auth.uid();
$$;

create policy estates_member_read on public.estates
for select to authenticated
using (public.member_role(id) is not null);

create policy members_read on public.estate_members
for select to authenticated
using (public.member_role(estate_id) is not null);

create policy invites_dm_read on public.invitations
for select to authenticated
using (public.member_role(estate_id) = 'dm');

create policy command_log_read on public.command_log
for select to authenticated
using (public.member_role(estate_id) is not null);

create policy audit_read on public.audit_log
for select to authenticated
using (public.member_role(estate_id) is not null);

create or replace function public.empty_document(estate_name text)
returns jsonb
language sql
immutable
as $$
  select jsonb_build_object(
    'revision', 1,
    'seq', 0,
    'practice', false,
    'name', left(coalesce(nullif(btrim(estate_name), ''), 'Unnamed bastion'), 80),
    'clock', jsonb_build_object('label', '', 'ordinal', null, 'cadenceDays', 7),
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

create or replace function public.create_estate(estate_name text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  eid uuid;
begin
  if auth.uid() is null then
    raise exception 'sign_in_required' using errcode = '42501';
  end if;
  insert into public.estates (document)
  values (public.empty_document(estate_name))
  returning id into eid;
  insert into public.estate_members (estate_id, user_id, role)
  values (eid, auth.uid(), 'dm');
  return eid;
end;
$$;

create or replace function public.create_invite(eid uuid, invite_email text, invite_role text)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  raw_token text;
begin
  if public.member_role(eid) <> 'dm' then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  if invite_role not in ('dm', 'editor', 'reader') then
    raise exception 'bad_role' using errcode = '22023';
  end if;
  raw_token := encode(gen_random_bytes(18), 'hex');
  insert into public.invitations (estate_id, email, role, token_hash, created_by)
  values (eid, lower(btrim(invite_email)), invite_role, encode(digest(raw_token, 'sha256'), 'hex'), auth.uid());
  return raw_token;
end;
$$;

create or replace function public.accept_invite(raw_token text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  row public.invitations%rowtype;
begin
  if auth.uid() is null or public.current_email() is null then
    raise exception 'sign_in_required' using errcode = '42501';
  end if;
  select * into row
  from public.invitations
  where token_hash = encode(digest(raw_token, 'sha256'), 'hex')
    and accepted_at is null
    and expires_at > now();
  if row.id is null then
    raise exception 'invite_not_found' using errcode = 'P0002';
  end if;
  if lower(row.email) <> lower(public.current_email()) then
    raise exception 'invite_email_mismatch' using errcode = '42501';
  end if;
  insert into public.estate_members (estate_id, user_id, role)
  values (row.estate_id, auth.uid(), row.role)
  on conflict (estate_id, user_id) do update set role = excluded.role;
  update public.invitations set accepted_at = now() where id = row.id;
  return row.estate_id;
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
  unit jsonb;
  facility jsonb;
  spec_level int;
  spec_unique boolean;
  active_count int;
  cap int;
  level int;
  gained int;
  cash int;
  standard_gp int;
  proceeds int;
  limit_gp int;
  due_day int;
  ordinal int;
  housed int;
  recruit_count int;
  i int;
  result jsonb;
  task jsonb;
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
  if role = 'reader' or (role <> 'dm' and cmd = any(array['set_settings','set_clock','set_finance','set_capabilities','raise_level','split_unit','replace_special','dm_override','confirm_fall','import_accept','mark_enclosure'])) then
    raise exception 'forbidden' using errcode = '42501';
  end if;

  if cmd = 'set_finance' then
    if command->>'cashGp' is null or command->>'cashGp' = '' then
      doc := jsonb_set(doc, '{finance,cashKnown}', 'false'::jsonb);
      doc := jsonb_set(doc, '{finance,cashGp}', 'null'::jsonb);
      result := jsonb_build_object('cashKnown', false);
    else
      cash := (command->>'cashGp')::int;
      if cash < 0 then raise exception 'bad_amount' using errcode = '22023'; end if;
      doc := jsonb_set(doc, '{finance,cashKnown}', 'true'::jsonb);
      doc := jsonb_set(doc, '{finance,cashGp}', to_jsonb(cash));
      result := jsonb_build_object('cashGp', cash);
    end if;
  elsif cmd = 'set_clock' then
    if command ? 'ordinal' then
      if command->>'ordinal' is null or command->'ordinal' = 'null'::jsonb then
        doc := jsonb_set(doc, '{clock,ordinal}', 'null'::jsonb);
      else
        doc := jsonb_set(doc, '{clock,ordinal}', to_jsonb((command->>'ordinal')::int));
      end if;
    end if;
    if command ? 'label' then
      doc := jsonb_set(doc, '{clock,label}', to_jsonb(left(command->>'label', 120)));
    end if;
    result := jsonb_build_object('clock', doc->'clock');
  elsif cmd = 'set_settings' then
    if command ? 'cadenceDays' then
      if (command->>'cadenceDays')::int < 1 then raise exception 'bad_cadence' using errcode = '22023'; end if;
      doc := jsonb_set(doc, '{clock,cadenceDays}', to_jsonb((command->>'cadenceDays')::int));
    end if;
    if coalesce(command->>'name', '') <> '' then
      doc := jsonb_set(doc, '{name}', to_jsonb(left(command->>'name', 80)));
    end if;
    result := jsonb_build_object('cadenceDays', doc#>'{clock,cadenceDays}');
  elsif cmd = 'raise_level' then
    select value into unit from jsonb_array_elements(doc->'units') value where value->>'id' = command->>'unitId';
    if unit is null then raise exception 'missing_unit' using errcode = 'P0002'; end if;
    level := (command->>'level')::int;
    gained := level - (unit->>'level')::int;
    if gained < 0 or level > 20 then raise exception 'bad_level' using errcode = '22023'; end if;
    unit := jsonb_set(unit, '{level}', to_jsonb(level));
    unit := jsonb_set(unit, '{replacementBank}', to_jsonb((unit->>'replacementBank')::int + gained));
    doc := jsonb_set(doc, '{units}', (
      select coalesce(jsonb_agg(case when value->>'id' = unit->>'id' then unit else value end), '[]'::jsonb)
      from jsonb_array_elements(doc->'units')
    ));
    result := jsonb_build_object('level', level, 'gainedReplacements', gained, 'bank', (unit->>'replacementBank')::int);
  elsif cmd = 'add_special' then
    select value into unit from jsonb_array_elements(doc->'units') value where value->>'id' = command->>'unitId';
    if unit is null then raise exception 'missing_unit' using errcode = 'P0002'; end if;
    select min_level, unique_facility into spec_level, spec_unique
    from (values
      ('arcane_study', 5, true), ('armory', 5, true), ('barrack', 5, false), ('garden', 5, false),
      ('library', 5, true), ('sanctuary', 5, true), ('smithy', 5, true), ('storehouse', 5, true),
      ('workshop', 5, true), ('gaming_hall', 9, true), ('greenhouse', 9, true), ('laboratory', 9, true),
      ('sacristy', 9, true), ('scriptorium', 9, true), ('stable', 9, false), ('teleportation_circle', 9, true),
      ('theater', 9, true), ('training_area', 9, false), ('trophy_room', 9, true), ('archive', 13, true),
      ('meditation_chamber', 13, true), ('menagerie', 13, true), ('observatory', 13, true), ('pub', 13, true),
      ('reliquary', 13, true), ('demiplane', 17, true), ('guildhall', 17, true), ('sanctum', 17, true),
      ('war_room', 17, true)
    ) as catalog(id, min_level, unique_facility)
    where id = command->>'catalogId';
    if spec_level is null then raise exception 'unknown_facility' using errcode = '22023'; end if;
    if (unit->>'level')::int < spec_level then raise exception 'level_gate' using errcode = '22023'; end if;
    select count(*) into active_count from jsonb_array_elements(doc->'facilities') value
      where value->>'unitId' = unit->>'id' and value->>'kind' = 'special' and value->>'status' = 'active';
    cap := case
      when (unit->>'level')::int < 5 then 0
      when (unit->>'level')::int < 9 then 2
      when (unit->>'level')::int < 13 then 4
      when (unit->>'level')::int < 17 then 5
      else 6
    end;
    if active_count >= cap then raise exception 'cap' using errcode = '22023'; end if;
    if spec_unique and exists (
      select 1 from jsonb_array_elements(doc->'facilities') value
      where value->>'unitId' = unit->>'id' and value->>'catalogId' = command->>'catalogId' and value->>'status' = 'active'
    ) then
      raise exception 'duplicate' using errcode = '22023';
    end if;
    doc := jsonb_set(doc, '{seq}', to_jsonb((doc->>'seq')::int + 1));
    facility := jsonb_build_object(
      'id', 'fac-' || (doc->>'seq'),
      'unitId', unit->>'id',
      'kind', 'special',
      'catalogId', command->>'catalogId',
      'name', command->>'catalogId',
      'space', 'roomy',
      'hirelings', 1,
      'status', 'active',
      'acquired', coalesce(command->>'acquired', 'level'),
      'stocked', false,
      'shutdownUntilTurnId', null,
      'blockedOnTurnId', null
    );
    doc := jsonb_set(doc, '{facilities}', (doc->'facilities') || jsonb_build_array(facility));
    result := jsonb_build_object('facilityId', facility->>'id');
  elsif cmd = 'record_goods' then
    standard_gp := (command->>'standardGp')::int;
    if standard_gp < 0 then raise exception 'bad_amount' using errcode = '22023'; end if;
    doc := jsonb_set(doc, '{seq}', to_jsonb((doc->>'seq')::int + 1));
    doc := jsonb_set(doc, '{goods}', (doc->'goods') || jsonb_build_array(jsonb_build_object(
      'id', 'good-' || (doc->>'seq'),
      'name', left(coalesce(command->>'name', 'Goods'), 80),
      'standardGp', standard_gp,
      'reservedGp', 0,
      'status', 'on_hand',
      'unitId', coalesce(command->>'unitId', 'unit-party'),
      'note', 'Recorded as already on hand. This did not charge or pay anyone.'
    )));
    result := jsonb_build_object('standardGp', standard_gp);
  elsif cmd = 'commit_turn' then
    if command->>'mode' = 'orders' and command#>>'{orders,0,suborder}' = 'sell' then
      if coalesce((doc#>>'{finance,cashKnown}')::boolean, false) is not true then
        raise exception 'finance_unknown' using errcode = '22023';
      end if;
      if doc#>>'{clock,ordinal}' is null then
        raise exception 'calendar_unknown' using errcode = '22023';
      end if;
      select value into unit from jsonb_array_elements(doc->'units') value where value->>'id' = command->>'unitId';
      standard_gp := (command#>>'{orders,0,standardGp}')::int;
      level := (unit->>'level')::int;
      proceeds := round(standard_gp * case when level >= 17 then 2 when level >= 13 then 1.5 when level >= 9 then 1.2 else 1.1 end);
      ordinal := (doc#>>'{clock,ordinal}')::int;
      due_day := ordinal + 7;
      doc := jsonb_set(doc, '{seq}', to_jsonb((doc->>'seq')::int + 1));
      task := jsonb_build_object(
        'id', 'task-' || (doc->>'seq'),
        'status', 'open',
        'settled', false,
        'auto', 'storehouse_sell',
        'standardGp', standard_gp,
        'proceeds', proceeds,
        'dueOrdinal', due_day,
        'lotId', command#>>'{orders,0,lotId}'
      );
      doc := jsonb_set(doc, '{tasks}', (doc->'tasks') || jsonb_build_array(task));
      result := jsonb_build_object('dueOrdinal', due_day, 'proceeds', proceeds);
    elsif command->>'mode' = 'orders' and command#>>'{orders,0,suborder}' = 'recruit' then
      recruit_count := (command#>>'{orders,0,count}')::int;
      if recruit_count < 1 or recruit_count > 4 then
        raise exception 'bad_amount' using errcode = '22023';
      end if;
      select count(*) into housed from jsonb_array_elements(doc->'roster') value
        where value->>'facilityId' = command#>>'{orders,0,facilityId}'
          and value->>'category' = 'defender' and value->>'status' = 'active';
      if housed >= 12 then raise exception 'barrack_full' using errcode = '22023'; end if;
      if housed + recruit_count > 12 then raise exception 'barrack_cap' using errcode = '22023'; end if;
      for i in 1..recruit_count loop
        doc := jsonb_set(doc, '{seq}', to_jsonb((doc->>'seq')::int + 1));
        doc := jsonb_set(doc, '{roster}', (doc->'roster') || jsonb_build_array(jsonb_build_object(
          'id', 'npc-' || (doc->>'seq'),
          'name', 'Defender ' || ((doc->>'seq')::int),
          'category', 'defender',
          'summary', '',
          'role', 'Defender',
          'link', '',
          'unitId', command->>'unitId',
          'facilityId', command#>>'{orders,0,facilityId}',
          'status', 'active',
          'housed', true,
          'protectsOnce', false
        )));
      end loop;
      result := jsonb_build_object('recruited', recruit_count);
    else
      raise exception 'unsupported_on_server' using errcode = '0A000';
    end if;
  elsif cmd = 'advance_days' then
    if doc#>>'{clock,ordinal}' is null then
      raise exception 'calendar_unknown' using errcode = '22023';
    end if;
    ordinal := (doc#>>'{clock,ordinal}')::int + (command->>'days')::int;
    doc := jsonb_set(doc, '{clock,ordinal}', to_jsonb(ordinal));
    proceeds := 0;
    for task in select value from jsonb_array_elements(doc->'tasks') value
      where value->>'status' = 'open' and value->>'auto' = 'storehouse_sell' and (value->>'dueOrdinal')::int <= ordinal and coalesce((value->>'settled')::boolean, false) = false
    loop
      if coalesce((doc#>>'{finance,cashKnown}')::boolean, false) is not true then
        raise exception 'finance_unknown' using errcode = '22023';
      end if;
      cash := coalesce((doc#>>'{finance,cashGp}')::int, 0) + (task->>'proceeds')::int;
      doc := jsonb_set(doc, '{finance,cashGp}', to_jsonb(cash));
      proceeds := proceeds + (task->>'proceeds')::int;
      doc := jsonb_set(doc, '{ledger}', (doc->'ledger') || jsonb_build_array(jsonb_build_object(
        'gp', (task->>'proceeds')::int,
        'reason', 'Sold goods',
        'day', ordinal,
        'key', idempotency_key
      )));
      doc := (
        select jsonb_set(doc, '{tasks}', coalesce(jsonb_agg(
          case when value->>'id' = task->>'id' then value || jsonb_build_object('status', 'resolved', 'settled', true) else value end
        ), '[]'::jsonb))
        from jsonb_array_elements(doc->'tasks')
      );
    end loop;
    result := jsonb_build_object('ordinal', ordinal, 'proceeds', proceeds);
  else
    raise exception 'unsupported_on_server' using errcode = '0A000';
  end if;

  rev := rev + 1;
  doc := jsonb_set(doc, '{revision}', to_jsonb(rev));
  update public.estates set document = doc, revision = rev where id = eid;
  insert into public.audit_log (estate_id, revision, actor, command_type, summary, reason)
  values (eid, rev, auth.uid(), cmd, cmd, coalesce(command->>'reason', ''));
  result := result || jsonb_build_object('revision', rev, 'document', doc, 'replay', false);
  if idempotency_key is not null and idempotency_key <> '' then
    insert into public.command_log (estate_id, idempotency_key, result) values (eid, idempotency_key, result);
  end if;
  return result;
end;
$$;

revoke all on function public.create_estate(text) from public, anon;
revoke all on function public.create_invite(uuid, text, text) from public, anon;
revoke all on function public.accept_invite(text) from public, anon;
revoke all on function public.apply_command(uuid, bigint, text, jsonb) from public, anon;
revoke all on function public.member_role(uuid) from public, anon;
revoke all on function public.current_email() from public, anon;
revoke all on function public.empty_document(text) from public, anon;

grant execute on function public.create_estate(text) to authenticated;
grant execute on function public.create_invite(uuid, text, text) to authenticated;
grant execute on function public.accept_invite(text) to authenticated;
grant execute on function public.apply_command(uuid, bigint, text, jsonb) to authenticated;
grant execute on function public.member_role(uuid) to authenticated;
grant execute on function public.current_email() to authenticated;
