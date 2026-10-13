-- Congrega: repeatable bootstrap for an EMPTY database. Apply once.
create schema if not exists private;
revoke all on schema private from public, anon;
grant usage on schema private to authenticated;
create table public.churches(id uuid primary key default gen_random_uuid(),name text not null unique);
insert into public.churches(id,name) values ('10000000-0000-0000-0000-000000000001','Maipú'),('10000000-0000-0000-0000-000000000002','Cerrillos');
create table public.profiles(id uuid primary key references auth.users(id),email text not null unique,display_name text not null,role text not null check(role in ('coordinator','recorder')),church_id uuid references public.churches(id),active boolean not null default true,check(role='coordinator' or church_id is not null));
create table private.invitations(email text primary key,display_name text not null,role text not null check(role in ('coordinator','recorder')),church_id uuid references public.churches(id),created_at timestamptz not null default now(),created_by uuid references auth.users(id),check(role='coordinator' or church_id is not null));
create table public.members(id uuid primary key default gen_random_uuid(),church_id uuid not null references public.churches(id),full_name text not null check(length(trim(full_name)) between 1 and 150),membership_status text not null default 'SIMPATIZANTE',age_group text not null default 'Adulto' check(age_group in ('Adulto','Adolescente','Niño/a','Bebé')),country text not null default '',phone text not null default '',residence text not null default '',active boolean not null default true,joined_on date not null default (now() at time zone 'America/Santiago')::date,left_on date,needs_review boolean not null default false,source_key text unique,check(left_on is null or left_on>=joined_on));
create index members_church on public.members(church_id,active);
create table public.meetings(id uuid primary key default gen_random_uuid(),church_id uuid not null references public.churches(id),date date not null,slot int not null check(slot between 1 and 20),title text not null check(length(trim(title)) between 1 and 120),status text not null default 'open' check(status in ('open','closed','cancelled','unrecorded')),visitors int default 0 check(visitors between 0 and 100000),source text not null default 'app',closed_at timestamptz,created_by uuid references auth.users(id),unique(church_id,date,slot));
create index meetings_date on public.meetings(church_id,date);
create table public.attendance(meeting_id uuid references public.meetings(id),member_id uuid references public.members(id),status text check(status in ('present','absent')),updated_by uuid references auth.users(id),updated_at timestamptz not null default now(),primary key(meeting_id,member_id));
create index attendance_member on public.attendance(member_id);
create table public.audit_log(id bigint generated always as identity primary key,church_id uuid references public.churches(id),actor_id uuid,entity text not null,entity_id text not null,action text not null,before_data jsonb,after_data jsonb,created_at timestamptz not null default now());
create index audit_church on public.audit_log(church_id,created_at desc);
create table public.import_notes(id bigint generated always as identity primary key,church_id uuid references public.churches(id),kind text not null,detail text not null,created_at timestamptz not null default now());

create function private.is_coordinator() returns boolean language sql stable security definer set search_path='' as $$select auth.uid() is not null and exists(select 1 from public.profiles where id=auth.uid() and active and role='coordinator')$$;
create function private.can_access(c uuid) returns boolean language sql stable security definer set search_path='' as $$select auth.uid() is not null and exists(select 1 from public.profiles where id=auth.uid() and active and (role='coordinator' or church_id=c))$$;
revoke all on function private.is_coordinator(),private.can_access(uuid) from public,anon;
grant execute on function private.is_coordinator(),private.can_access(uuid) to authenticated;

alter table public.churches enable row level security;
alter table public.profiles enable row level security;
alter table public.members enable row level security;
alter table public.meetings enable row level security;
alter table public.attendance enable row level security;
alter table public.audit_log enable row level security;
alter table public.import_notes enable row level security;
alter table private.invitations enable row level security;
create policy church_read on public.churches for select to authenticated using(private.can_access(id));
create policy profile_read on public.profiles for select to authenticated using(id=(select auth.uid()) or private.is_coordinator());
create policy member_read on public.members for select to authenticated using(private.can_access(church_id));
create policy meeting_read on public.meetings for select to authenticated using(private.can_access(church_id));
create policy attendance_read on public.attendance for select to authenticated using(exists(select 1 from public.meetings m where m.id=meeting_id and private.can_access(m.church_id)));
create policy audit_read on public.audit_log for select to authenticated using(private.is_coordinator());
create policy notes_read on public.import_notes for select to authenticated using(private.is_coordinator());
revoke all on public.churches,public.profiles,public.members,public.meetings,public.attendance,public.audit_log,public.import_notes from anon,authenticated;
grant select on public.churches,public.profiles,public.members,public.meetings,public.attendance,public.audit_log,public.import_notes to authenticated;

create function private.new_user() returns trigger language plpgsql security definer set search_path='' as $$
declare inv private.invitations;
begin
 select * into inv from private.invitations where email=lower(new.email) for update;
 if not found then raise exception 'Solo se permiten cuentas invitadas'; end if;
 insert into public.profiles(id,email,display_name,role,church_id) values(new.id,lower(new.email),inv.display_name,inv.role,inv.church_id);
 delete from private.invitations where email=lower(new.email);
 return new;
end$$;
revoke all on function private.new_user() from public,anon,authenticated;
create trigger invited_users_only after insert on auth.users for each row execute function private.new_user();

create function private.audit_change() returns trigger language plpgsql security definer set search_path='' as $$
declare j jsonb; oldj jsonb; c uuid; eid text;
begin
 j:=to_jsonb(new);oldj:=case when tg_op='UPDATE' then to_jsonb(old) else null end;
 if oldj is not null and j=oldj then return new;end if;
 c:=(j->>'church_id')::uuid;eid:=j->>'id';
 if tg_table_name='attendance' then select church_id into c from public.meetings where id=(j->>'meeting_id')::uuid;eid:=(j->>'meeting_id')||'/'||(j->>'member_id');end if;
 insert into public.audit_log(church_id,actor_id,entity,entity_id,action,before_data,after_data) values(c,auth.uid(),tg_table_name,coalesce(eid,''),tg_op,oldj,j);
 return new;
end$$;
revoke all on function private.audit_change() from public,anon,authenticated;
create trigger audit_members after insert or update on public.members for each row execute function private.audit_change();
create trigger audit_meetings after insert or update on public.meetings for each row execute function private.audit_change();
create trigger audit_attendance after insert or update on public.attendance for each row execute function private.audit_change();
create trigger audit_profiles after insert or update on public.profiles for each row execute function private.audit_change();

create function private.command(action text,payload jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare who public.profiles; c uuid; mid uuid; memberid uuid; meet public.meetings; target public.profiles; result jsonb; existing public.members; e text;
begin
 select * into who from public.profiles where id=auth.uid() and active;
 if auth.uid() is null or who.id is null then raise exception 'Acceso no autorizado';end if;
 if action='save_member' then
  c:=(payload->>'church_id')::uuid;
  if not private.can_access(c) then raise exception 'Iglesia no autorizada';end if;
  if nullif(payload->>'id','') is not null then
   memberid:=(payload->>'id')::uuid;select * into existing from public.members where id=memberid for update;
   if existing.id is null or existing.church_id<>c then raise exception 'Miembro no autorizado';end if;
   if who.role<>'coordinator' and (coalesce((payload->>'active')::boolean,true)<>existing.active or (payload->>'joined_on')::date<>existing.joined_on) then raise exception 'Solo Coordinación puede cambiar vigencia';end if;
   update public.members set full_name=trim(payload->>'full_name'),membership_status=payload->>'membership_status',age_group=payload->>'age_group',country=coalesce(payload->>'country',''),phone=coalesce(payload->>'phone',''),residence=coalesce(payload->>'residence',''),active=coalesce((payload->>'active')::boolean,true),joined_on=(payload->>'joined_on')::date,left_on=case when (payload->>'active')::boolean=false then coalesce(existing.left_on,(now() at time zone 'America/Santiago')::date) else null end,needs_review=false where id=memberid returning to_jsonb(members.*) into result;
  else
   insert into public.members(church_id,full_name,membership_status,age_group,country,phone,residence,joined_on) values(c,trim(payload->>'full_name'),payload->>'membership_status',payload->>'age_group',coalesce(payload->>'country',''),coalesce(payload->>'phone',''),coalesce(payload->>'residence',''),coalesce((payload->>'joined_on')::date,(now() at time zone 'America/Santiago')::date)) returning id,to_jsonb(members.*) into memberid,result;
   insert into public.attendance(meeting_id,member_id) select id,memberid from public.meetings where church_id=c and status='open' and date>=(result->>'joined_on')::date;
  end if;
  return result;
 elsif action='create_meeting' then
  c:=(payload->>'church_id')::uuid;
  if not private.can_access(c) then raise exception 'Iglesia no autorizada';end if;
  if (payload->>'date')::date>(now() at time zone 'America/Santiago')::date then raise exception 'No se puede registrar asistencia futura';end if;
  insert into public.meetings(church_id,date,slot,title,created_by) values(c,(payload->>'date')::date,(payload->>'slot')::int,payload->>'title',who.id) returning id,to_jsonb(meetings.*) into mid,result;
  insert into public.attendance(meeting_id,member_id) select mid,id from public.members where church_id=c and joined_on<=(payload->>'date')::date and (left_on is null or left_on>=(payload->>'date')::date);
  return result;
 elsif action in ('mark','close','reopen','cancel','visitors') then
  mid:=(payload->>'meeting_id')::uuid;select * into meet from public.meetings where id=mid for update;
  if meet.id is null or not private.can_access(meet.church_id) then raise exception 'Reunión no autorizada';end if;
  if meet.date>(now() at time zone 'America/Santiago')::date then raise exception 'La reunión tiene fecha futura';end if;
  if action='reopen' then
   if who.role<>'coordinator' and meet.status<>'unrecorded' then raise exception 'Solo Coordinación puede reabrir';end if;
   update public.meetings set status='open',closed_at=null where id=mid;
   insert into public.attendance(meeting_id,member_id) select mid,id from public.members where church_id=meet.church_id and joined_on<=meet.date and (left_on is null or left_on>=meet.date) on conflict do nothing;
  elsif action='cancel' then
   if who.role<>'coordinator' then raise exception 'Solo Coordinación puede cancelar';end if;
   update public.meetings set status='cancelled',closed_at=null where id=mid;
  else
   if meet.status<>'open' then raise exception 'Reunión cerrada. Solicita a Coordinación que la reabra';end if;
   if action='mark' then
    if payload->>'status' not in ('present','absent') and payload->>'status' is not null then raise exception 'Estado inválido';end if;
    update public.attendance set status=payload->>'status',updated_by=who.id,updated_at=now() where meeting_id=mid and member_id=(payload->>'member_id')::uuid;
    if not found then raise exception 'La persona no pertenece a la lista de esta reunión';end if;
   elsif action='close' then
    update public.attendance set status='absent',updated_by=who.id,updated_at=now() where meeting_id=mid and status is null;
    update public.meetings set status='closed',closed_at=now() where id=mid;
   elsif action='visitors' then update public.meetings set visitors=(payload->>'visitors')::int where id=mid;
   end if;
  end if;
  return jsonb_build_object('ok',true);
 elsif action='prepare_invitation' then
  if who.role<>'coordinator' then raise exception 'Solo Coordinación puede invitar';end if;
  e:=lower(trim(payload->>'email'));
  if e !~ '^[^ @]+@[^ @]+\.[^ @]+$' then raise exception 'Correo inválido';end if;
  if exists(select 1 from public.profiles where email=e) then raise exception 'Ya existe una cuenta con ese correo';end if;
  insert into private.invitations(email,display_name,role,church_id,created_by) values(e,trim(payload->>'display_name'),payload->>'role',nullif(payload->>'church_id','')::uuid,who.id) on conflict(email) do update set display_name=excluded.display_name,role=excluded.role,church_id=excluded.church_id,created_by=excluded.created_by,created_at=now();
  return jsonb_build_object('ok',true);
 elsif action='toggle_user' then
  if who.role<>'coordinator' then raise exception 'Solo Coordinación puede gestionar usuarios';end if;
  if (payload->>'id')::uuid=who.id then raise exception 'No puedes desactivar tu propia cuenta';end if;
  update public.profiles set active=(payload->>'active')::boolean where id=(payload->>'id')::uuid;
  return jsonb_build_object('ok',true);
 elsif action='merge_members' then
  if who.role<>'coordinator' then raise exception 'Solo Coordinación puede unir fichas';end if;
  memberid:=(payload->>'from_id')::uuid;mid:=(payload->>'to_id')::uuid;
  if memberid=mid then raise exception 'Selecciona dos personas diferentes';end if;
  select * into existing from public.members where id=memberid for update;
  if existing.id is null or not exists(select 1 from public.members where id=mid and church_id=existing.church_id) then raise exception 'Ambas fichas deben ser de la misma iglesia';end if;
  insert into public.attendance(meeting_id,member_id,status,updated_by) select meeting_id,mid,status,who.id from public.attendance where member_id=memberid on conflict(meeting_id,member_id) do update set status=case when attendance.status='present' or excluded.status='present' then 'present' when attendance.status='absent' or excluded.status='absent' then 'absent' else null end,updated_by=who.id,updated_at=now();
  insert into public.audit_log(church_id,actor_id,entity,entity_id,action,before_data,after_data) values(existing.church_id,who.id,'members',memberid::text,'MERGE',to_jsonb(existing),jsonb_build_object('target_id',mid,'attendance',(select jsonb_agg(to_jsonb(a)) from public.attendance a where member_id=memberid)));
  delete from public.attendance where member_id=memberid;
  update public.members set joined_on=least(joined_on,existing.joined_on) where id=mid;
  update public.members set active=false,needs_review=false,left_on=greatest(joined_on,(now() at time zone 'America/Santiago')::date) where id=memberid;
  return jsonb_build_object('ok',true);
 end if;
 raise exception 'Operación desconocida';
end$$;
revoke all on function private.command(text,jsonb) from public,anon;
grant execute on function private.command(text,jsonb) to authenticated;
create function public.command(action text,payload jsonb) returns jsonb language sql security invoker set search_path='' as $$select private.command(action,payload)$$;
revoke all on function public.command(text,jsonb) from public,anon;
grant execute on function public.command(text,jsonb) to authenticated;
