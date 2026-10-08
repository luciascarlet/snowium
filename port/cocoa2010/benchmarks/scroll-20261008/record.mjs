// Browser diagnostics only. Real page input is sent through Screen Sharing.
import {mkdir,writeFile} from 'node:fs/promises';
import {createInterface} from 'node:readline';
const label=process.argv[2];
const seconds=Number(process.argv[3]||0);
if (!label) throw Error('Supply a run label');
const output=new URL('./'+label+'/',import.meta.url);
await mkdir(output,{recursive:true});
const endpoint='http://127.0.0.1:19227';
const info=await (await fetch(endpoint+'/json/version')).json();
const url=new URL(info.webSocketDebuggerUrl); url.host=new URL(endpoint).host;
const ws=new WebSocket(url);
await new Promise((resolve,reject)=>{ws.addEventListener('open',resolve,{once:true});ws.addEventListener('error',reject,{once:true})});
let nextId=0;
const pending=new Map(),events=[];
let completed;
const traceComplete=new Promise(resolve=>completed=resolve);
ws.addEventListener('message',event=>{
  const message=JSON.parse(event.data),p=pending.get(message.id);
  if(p){pending.delete(message.id);clearTimeout(p.timer);message.error?p.reject(message.error):p.resolve(message.result);}
  else if(message.method==='Tracing.dataCollected') events.push(...message.params.value);
  else if(message.method==='Tracing.tracingComplete') completed();
});
function call(method,params={}){
  return new Promise((resolve,reject)=>{const id=++nextId;pending.set(id,{resolve,reject,timer:setTimeout(()=>reject(Error(method+' timeout')),30000)});ws.send(JSON.stringify({id,method,params}));});
}
const input=createInterface({input:process.stdin});
function enter(){return new Promise(resolve=>{
  input.once('line',resolve);
  process.once('SIGINT',resolve);
});}
try {
  const before=(await call('SystemInfo.getProcessInfo')).processInfo;
  const histogramBefore=await call('Browser.getHistograms',{query:'Renderer4.'});
  await call('Tracing.start',{categories:process.env.SNOWIUM_TRACE_CATEGORIES || 'toplevel,cc,viz,benchmark,input,input.scrolling,devtools.timeline,blink.user_timing,loading',options:'record-as-much-as-possible',transferMode:'ReportEvents'});
  const start=performance.now();
  console.log('RECORDING '+label+(seconds?'; automatic stop after '+seconds+' seconds.':'; send Enter after the native scroll sequence.'));
  await (seconds?new Promise(resolve=>setTimeout(resolve,seconds*1000)):enter());
  const end=performance.now();
  const after=(await call('SystemInfo.getProcessInfo')).processInfo;
  await call('Tracing.end');
  await traceComplete;
  const histogramAfter=await call('Browser.getHistograms',{query:'Renderer4.'});
  const cpu=after.map(p=>({...p,seconds:p.cpuTime-(before.find(q=>q.id===p.id)?.cpuTime??p.cpuTime)}));
  await writeFile(new URL('trace.json',output),JSON.stringify(events));
  await writeFile(new URL('results.json',output),JSON.stringify({label,elapsedMs:end-start,cpu,histogramBefore,histogramAfter,browserVersion:info.Browser},null,2));
  console.log('Saved '+events.length+' events over '+((end-start)/1000).toFixed(2)+' seconds.');
} finally {input.close();ws.close();}
