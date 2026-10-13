import {createClient} from 'npm:@supabase/supabase-js@2.117.3';
const headers={'Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'authorization, x-client-info, apikey, content-type','Content-Type':'application/json'};
const reply=(status:number,data:unknown)=>new Response(JSON.stringify(data),{status,headers});
Deno.serve(async(req:Request)=>{
 if(req.method==='OPTIONS')return new Response('ok',{headers});
 if(req.method!=='POST')return reply(405,{error:'Método no permitido'});
 try{
  const admin=createClient(Deno.env.get('SUPABASE_URL')!,Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,{auth:{persistSession:false,autoRefreshToken:false}});
  const token=(req.headers.get('Authorization')||'').replace(/^Bearer /,'');
  if(!token)return reply(401,{error:'Sesión requerida'});
  const {data:{user},error}=await admin.auth.getUser(token);
  if(error||!user)return reply(401,{error:'Sesión inválida'});
  const {data:profile}=await admin.from('profiles').select('role,active').eq('id',user.id).single();
  if(!profile?.active||profile.role!=='coordinator')return reply(403,{error:'Solo Coordinación puede gestionar accesos'});
  const body=await req.json();const email=String(body.email||'').trim().toLowerCase();
  if(!/^[^ @]+@[^ @]+\.[^ @]+$/.test(email))return reply(400,{error:'Correo inválido'});
  if(body.action!=='invite'&&body.action!=='recover')return reply(400,{error:'Operación inválida'});
  if(body.action==='recover'){
   const {data:target}=await admin.from('profiles').select('id,active').eq('email',email).single();
   if(!target?.active)return reply(400,{error:'La cuenta no existe o está desactivada'});
  }
  // Invitation creation is enforced by the database trigger and prepared via authenticated RPC.
  const {data,error:linkError}=await admin.auth.admin.generateLink({type:body.action==='invite'?'invite':'recovery',email});
  if(linkError)return reply(400,{error:linkError.message});
  return reply(200,{token_hash:data.properties.hashed_token});
 }catch{return reply(500,{error:'No se pudo generar el enlace. Intenta nuevamente.'})}
});
