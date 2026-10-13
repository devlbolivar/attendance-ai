-- Runs entirely in a transaction. No persistent test users or invitations.
begin;
insert into private.invitations(email,display_name,role,church_id) values
 ('test-recorder@congrega.example','Test Recorder','recorder','10000000-0000-0000-0000-000000000001'),
 ('test-coordinator@congrega.example','Test Coordinator','coordinator',null);
insert into auth.users(id,email) values ('99999999-0000-0000-0000-000000000001','test-recorder@congrega.example'),('99999999-0000-0000-0000-000000000002','test-coordinator@congrega.example');
select set_config('request.jwt.claims','{"sub":"99999999-0000-0000-0000-000000000001","role":"authenticated"}',true);
set local role authenticated;
do $$declare m jsonb; memberid uuid; failed boolean;
begin
 if (select count(*) from public.churches)<>1 then raise exception 'FAIL recorder churches';end if;
 if exists(select 1 from public.members where church_id='10000000-0000-0000-0000-000000000002') then raise exception 'FAIL cross church read';end if;
 failed:=false;
 begin perform public.command('create_meeting','{"church_id":"10000000-0000-0000-0000-000000000002","date":"2026-10-13","slot":20,"title":"Test"}');exception when others then failed:=true;end;
 if not failed then raise exception 'FAIL cross church write';end if;
 failed:=false;
 begin update public.profiles set role='coordinator' where id=auth.uid();exception when insufficient_privilege then failed:=true;end;
 if not failed then raise exception 'FAIL privilege escalation';end if;
 m:=public.command('create_meeting','{"church_id":"10000000-0000-0000-0000-000000000001","date":"2026-10-13","slot":20,"title":"Security test"}');
 select member_id into memberid from public.attendance where meeting_id=(m->>'id')::uuid limit 1;
 perform public.command('mark',jsonb_build_object('meeting_id',m->>'id','member_id',memberid,'status','present'));
 if (select status from public.attendance where meeting_id=(m->>'id')::uuid and member_id=memberid)<>'present' then raise exception 'FAIL mark';end if;
 perform public.command('close',jsonb_build_object('meeting_id',m->>'id'));
 if exists(select 1 from public.attendance where meeting_id=(m->>'id')::uuid and status is null) then raise exception 'FAIL finalize pending';end if;
 failed:=false;
 begin perform public.command('mark',jsonb_build_object('meeting_id',m->>'id','member_id',memberid,'status','absent'));exception when others then failed:=true;end;
 if not failed then raise exception 'FAIL edit closed';end if;
 failed:=false;
 begin perform public.command('reopen',jsonb_build_object('meeting_id',m->>'id'));exception when others then failed:=true;end;
 if not failed then raise exception 'FAIL recorder reopen';end if;
end$$;
reset role;
select set_config('request.jwt.claims','{"sub":"99999999-0000-0000-0000-000000000002","role":"authenticated"}',true);
set local role authenticated;
do $$declare mid uuid;
begin
 if (select count(*) from public.churches)<>2 then raise exception 'FAIL coordinator churches';end if;
 select id into mid from public.meetings where title='Security test' and slot=20;
 perform public.command('reopen',jsonb_build_object('meeting_id',mid));
 if (select status from public.meetings where id=mid)<>'open' then raise exception 'FAIL coordinator reopen';end if;
 perform public.command('toggle_user','{"id":"99999999-0000-0000-0000-000000000001","active":false}');
end$$;
reset role;
select set_config('request.jwt.claims','{"sub":"99999999-0000-0000-0000-000000000001","role":"authenticated"}',true);
set local role authenticated;
do $$begin if exists(select 1 from public.members) then raise exception 'FAIL deactivated access';end if;end$$;
reset role;
select 'PASS: church isolation, writes, escalation, closing, reopening and deactivation' as security_result;
rollback;
