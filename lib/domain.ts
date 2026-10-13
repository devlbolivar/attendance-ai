export type Church = {id:string;name:string};
export type Profile = {id:string;display_name:string;email:string;role:'coordinator'|'recorder';church_id:string|null;active:boolean};
export type Member = {id:string;church_id:string;full_name:string;membership_status:string;age_group:string;country:string;phone:string;residence:string;active:boolean;joined_on:string;left_on:string|null;needs_review:boolean};
export type Meeting = {id:string;church_id:string;date:string;slot:number;title:string;status:'open'|'closed'|'cancelled'|'unrecorded';visitors:number|null;source:string;closed_at:string|null};
export type Attendance = {meeting_id:string;member_id:string;status:'present'|'absent'|null};
export const TODAY = () => new Intl.DateTimeFormat('en-CA',{timeZone:'America/Santiago',year:'numeric',month:'2-digit',day:'2-digit'}).format(new Date());
export const normalize = (s:string) => s.normalize('NFD').replace(/[\u0300-\u036f]/g,'').toLowerCase().trim();
export function dateLabel(date:string){const parsed=new Date(date+'T12:00:00Z');if(Number.isNaN(parsed.getTime()))return 'Selecciona una fecha';return new Intl.DateTimeFormat('es-CL',{day:'numeric',month:'long',year:'numeric',timeZone:'UTC'}).format(parsed)}
export function periodBounds(date:string,period:string):[string,string]{
 const d=new Date((/^\d{4}-\d{2}-\d{2}$/.test(date)?date:TODAY())+'T12:00:00Z'), y=d.getUTCFullYear(),m=d.getUTCMonth(); let a=new Date(d),b=new Date(d);
 if(period==='week'){a.setUTCDate(a.getUTCDate()-(a.getUTCDay()+6)%7);b=new Date(a);b.setUTCDate(b.getUTCDate()+6)}
 if(period==='month'){a=new Date(Date.UTC(y,m,1,12));b=new Date(Date.UTC(y,m+1,0,12))}
 if(period==='semester'){const s=m<6?0:6;a=new Date(Date.UTC(y,s,1,12));b=new Date(Date.UTC(y,s+6,0,12))}
 if(period==='year'){a=new Date(Date.UTC(y,0,1,12));b=new Date(Date.UTC(y,11,31,12))}
 return [a.toISOString().slice(0,10),b.toISOString().slice(0,10)];
}
export function reportData(meetings:Meeting[],attendance:Attendance[],members:Member[]){
 const closed=meetings.filter(m=>m.status==='closed');const ids=new Set(closed.map(m=>m.id));const marks=attendance.filter(a=>ids.has(a.meeting_id)&&a.status!==null);
 const individual=members.map(m=>{const rows=marks.filter(a=>a.member_id===m.id);const present=rows.filter(a=>a.status==='present').length;let streak=0;for(const meeting of [...closed].sort((a,b)=>b.date.localeCompare(a.date)||b.slot-a.slot)){const row=rows.find(r=>r.meeting_id===meeting.id);if(!row)continue;if(row.status==='present')break;streak++}return {member:m,present,total:rows.length,absent:rows.length-present,percentage:rows.length?Math.round(present/rows.length*100):null,streak}});
 const daily=closed.map(m=>{const rows=marks.filter(a=>a.meeting_id===m.id);return {...m,present:rows.filter(a=>a.status==='present').length,expected:rows.length}});
 return {individual,daily,present:marks.filter(a=>a.status==='present').length,total:marks.length,services:closed.length,visitors:closed.reduce((a,m)=>a+(m.visitors??0),0),visitorsUnknown:closed.filter(m=>m.visitors===null).length,excluded:meetings.length-closed.length};
}
