"""Read-only XLSX extraction. Outputs private JSON, never commit personal data.
Usage: python scripts/import_workbooks.py /path/to/uploads private/import.json
Exact normalized names only; uncertain aliases are deliberately not merged.
"""
import sys, json, re, unicodedata, uuid, datetime, calendar
from pathlib import Path
from collections import defaultdict, Counter
import openpyxl

MONTHS = ['ENERO','FEBRERO','MARZO','ABRIL','MAYO','JUNIO','JULIO','AGOSTO','SEPTIEMBRE','OCTUBRE','NOVIEMBRE','DICIEMBRE']
def norm(x):
    return ' '.join(''.join(c for c in unicodedata.normalize('NFD',str(x or '')) if unicodedata.category(c)!='Mn').lower().split())
def clean(x):
    if x is None: return ''
    if isinstance(x,float) and x.is_integer(): return str(int(x))
    return ' '.join(str(x).split())
def uid(key): return str(uuid.uuid5(uuid.NAMESPACE_URL, 'congrega/2026/'+key))

def extract(folder, cutoff):
    people={}; events={}; notes=[]
    for file in sorted(Path(folder).glob('*.xlsx')):
        church='Maipú' if 'maipu' in norm(file.name) else 'Cerrillos'
        cid='10000000-0000-0000-0000-00000000000'+('1' if church=='Maipú' else '2')
        wb=openpyxl.load_workbook(file,data_only=True)
        sheets=[s for s in wb if s.title.upper() in MONTHS]
        latest=max(sheets,key=lambda s:MONTHS.index(s.title.upper()))
        current={norm(r[2]) for r in latest.values if isinstance(r[0],(int,float)) and r[2]}
        for s in sheets:
            month=MONTHS.index(s.title.upper())+1; rows=list(s.values); headers={norm(v):i for i,v in enumerate(rows[1]) if v}
            if 'septiembre' in norm(rows[0]) and s.title=='OCTUBRE':notes.append({'church_id':cid,'kind':'Fuente','detail':'OCTUBRE conserva encabezado Septiembre; se usó el nombre de la hoja.'})
            roster=[]
            for rownum,row in enumerate(rows[3:],4):
                if not isinstance(row[0],(int,float)) or not row[2]:continue
                name=clean(row[2]); key=church+'/'+norm(name); pid=uid(key)
                status=clean(row[1]).upper().replace('PLENA COMINION','PLENA COMUNIÓN')
                age='Adolescente' if status=='ADOLESCENTE' else 'Niño/a' if status in ('NIÑO','NIÑA') else 'Bebé' if status=='BEBÉ' else 'Adulto'
                country=clean(row[headers['pais']]) if 'pais' in headers else ''
                phone=clean(row[headers['contacto']]) if 'contacto' in headers else ''
                residence=next((clean(row[i]) for i,v in enumerate(rows[0]) if norm(v)=='residencia'),'')
                previous=people.get(pid,{})
                people[pid]={'id':pid,'church_id':cid,'full_name':name,'membership_status':status,'age_group':age,'country':country or previous.get('country',''),'phone':phone or previous.get('phone',''),'residence':residence or previous.get('residence',''),'active':norm(name) in current,'joined_on':previous.get('joined_on',f'2026-{month:02d}-01'),'left_on':None if norm(name) in current else f'2026-{month:02d}-{calendar.monthrange(2026,month)[1]}','needs_review':False,'source_key':key}
                roster.append((pid,row,rownum))
            curr=month;last=0;occ=Counter()
            for col in range(len(rows[2])):
                day=rows[2][col]
                if not isinstance(day,(int,float)) or not 1<=day<=31:continue
                day=int(day)
                if day<last:curr+=1
                last=day
                if curr>12:continue
                try: date=datetime.date(2026,curr,day).isoformat()
                except ValueError:
                    notes.append({'church_id':cid,'kind':'Fecha inválida','detail':f'{s.title}, columna {col+1}: {day}/{curr}/2026'});continue
                occ[date]+=1;slot=occ[date];eid=uid(church+'/'+date+'/'+str(slot))
                values={pid:norm(row[col]) for pid,row,_ in roster}
                symbols=set(values.values())-{''}
                state='closed' if 'x' in symbols else 'cancelled' if '-' in symbols else 'unrecorded'
                if date>cutoff:state='unrecorded'
                unknown=symbols-{'x','-'}
                if unknown:notes.append({'church_id':cid,'kind':'Marca pendiente','detail':f'{s.title}, {date}, servicio {slot}: marcas desconocidas {sorted(unknown)}. Se conserva la reunión sin registrar.'});state='unrecorded'
                if 'x' in symbols and '-' in symbols:notes.append({'church_id':cid,'kind':'Marcas mixtas','detail':f'{date}, servicio {slot}: hay X y guiones. Solo se importaron presentes; los guiones quedan pendientes de revisión.'});state='open'
                sunday=datetime.date.fromisoformat(date).weekday()==6
                title=('Escuela dominical' if slot==1 else 'Culto general') if sunday else 'Culto general'
                visitors=next((int(r[col]) for r in rows if any(norm(v)=='nuevos' for v in r[:6]) and isinstance(r[col],(int,float))),None)
                record={'id':eid,'church_id':cid,'date':date,'slot':slot,'title':title,'status':state,'visitors':visitors,'source':s.title,'closed_at':date+'T23:59:00-03:00' if state=='closed' else None}
                marks=[{'meeting_id':eid,'member_id':pid,'status':('present' if value=='x' else 'absent' if not value and state=='closed' else None)} for pid,value in values.items()]
                if eid in events:
                    old,oldmarks=events[eid]
                    priority={'unrecorded':0,'cancelled':1,'open':2,'closed':3}
                    if priority[old['status']]>priority[state]:continue
                    if old['status']=='closed' and state=='closed' and oldmarks!=marks:
                        notes.append({'church_id':cid,'kind':'Solapamiento','detail':f'{date}, servicio {slot}: dos hojas registran asistencia; prevalece {s.title}.'})
                events[eid]=(record,marks)
    # Flag plausible aliases for a human decision; never merge different names automatically.
    from difflib import SequenceMatcher
    p=list(people.values())
    for i,a in enumerate(p):
        for b in p[i+1:]:
            if a['church_id']!=b['church_id']:continue
            x,y=norm(a['full_name']),norm(b['full_name'])
            if x.split()[0]==y.split()[0] or SequenceMatcher(None,x,y).ratio()>.82:
                a['needs_review']=b['needs_review']=True
                notes.append({'church_id':a['church_id'],'kind':'Posible nombre variante','detail':f"Revisar si {a['full_name']} y {b['full_name']} son la misma persona. Se conservaron fichas separadas."})
    return {'members':p,'meetings':[x[0] for x in events.values()],'attendance':[r for e in events.values() for r in e[1]],'notes':notes}

if __name__=='__main__':
    data=extract(sys.argv[1],sys.argv[3] if len(sys.argv)>3 else '2026-10-13')
    Path(sys.argv[2]).write_text(json.dumps(data,ensure_ascii=False))
    print(json.dumps({'members':len(data['members']),'active':sum(m['active'] for m in data['members']),'meetings':dict(Counter(m['status'] for m in data['meetings'])),'marks':dict(Counter(m['status'] for m in data['attendance'])),'notes':len(data['notes'])},ensure_ascii=False))
