"""Render one SQL batch from reviewed extraction. Run only against the selected project."""
import json,sys
data=json.load(open(sys.argv[1])); table=sys.argv[2];start=int(sys.argv[3]);size=int(sys.argv[4]);rows=data[table][start:start+size]
if not rows:sys.exit(0)
target='import_notes' if table=='notes' else table
cols=list(rows[0]); encoded=json.dumps(rows,ensure_ascii=False,separators=(',',':')).replace("'","''")
print('insert into public.'+target+' ('+','.join(cols)+') select '+','.join(cols)+' from jsonb_populate_recordset(null::public.'+target+", '"+encoded+"'::jsonb)"+(' on conflict do nothing' if table!='notes' else '')+';')
