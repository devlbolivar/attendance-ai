import {test} from 'node:test';
import assert from 'node:assert/strict';
import {periodBounds,reportData,normalize} from '../lib/domain.ts';
import type {Meeting,Attendance,Member} from '../lib/domain.ts';
test('calendar periods respect week boundaries and fixed semesters',()=>{
 assert.deepEqual(periodBounds('2026-01-01','week'),['2025-12-29','2026-01-04']);
 assert.deepEqual(periodBounds('2026-10-13','semester'),['2026-07-01','2026-12-31']);
 assert.deepEqual(periodBounds('2024-02-10','month'),['2024-02-01','2024-02-29']);
 assert.deepEqual(periodBounds('2026-10-13','year'),['2026-01-01','2026-12-31']);
});
test('denominator excludes cancelled, unrecorded and people outside the historical roster',()=>{
 const meetings=[{id:'a',date:'2026-01-01',slot:1,status:'closed',visitors:null},{id:'b',date:'2026-01-02',slot:1,status:'closed',visitors:2},{id:'c',date:'2026-01-03',slot:1,status:'unrecorded'},{id:'d',date:'2026-01-04',slot:1,status:'cancelled'}] as Meeting[];
 const marks=[{meeting_id:'a',member_id:'one',status:'present'},{meeting_id:'b',member_id:'one',status:'absent'},{meeting_id:'b',member_id:'new',status:'present'},{meeting_id:'c',member_id:'one',status:null},{meeting_id:'d',member_id:'one',status:null}] as Attendance[];
 const result=reportData(meetings,marks,[{id:'one'},{id:'new'}] as Member[]);
 assert.equal(result.services,2);assert.equal(result.total,3);assert.equal(result.present,2);assert.equal(result.visitorsUnknown,1);
 assert.equal(result.individual[0].percentage,50);assert.equal(result.individual[0].streak,1);assert.equal(result.individual[1].percentage,100);
});
test('no records is not zero-percent attendance',()=>{assert.equal(reportData([],[],[{id:'a'}] as Member[]).individual[0].percentage,null)});
test('search matches accents and case',()=>assert.equal(normalize('  Maipú '),'maipu'));
