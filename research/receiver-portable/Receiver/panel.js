import { columns, signals, signalLabels, localOrigin, readRows, stats } from "./table.js";
import { readDevice } from "./read-device.js";

const el = id => document.getElementById(id);
const q = new URLSearchParams(location.search);
const origin = localOrigin(q.get("origin"));
const tabId = /^\d+$/.test(q.get("tab") ?? "") ? Number(q.get("tab")) : null;
const connected = origin && Number.isSafeInteger(tabId) && typeof chrome !== "undefined" && chrome.scripting;
let rows = [], running = false, stopping = false, wake = null, moduleBytes, failureWasm, imported = false;
const statusNames={unreachable:"接收机未应答",auth_failed:"需在原标签页重新登录",unsupported:"型号或 API 版本不匹配",malformed:"管理响应未通过格式检查",local_failure:"原管理页已关闭或读取权限失效"};

el("target").textContent = connected ? "接收机管理页 " + origin : "可打开 Mooring 导出的 CSV。在已登录的接收机管理页点扩展图标可采样。";
el("start").disabled = !connected;

function render() {
  const last = rows.at(-1)?.row;
  const failures=rows.filter(v=>v.row.outcome==="failed").length;
  const attached=rows.filter(v=>v.row.service==="attached").length;
  el("counts").textContent = rows.length ? `共 ${rows.length} 次 · 已附着 ${attached} · 无服务 ${rows.length-failures-attached} · 读取失败 ${failures}` : "尚无观测";
  el("metrics").replaceChildren(...signals.map((key,i)=>{
    const tr=document.createElement("tr"), metric=stats(rows,key);
    const values=[signalLabels[i],last?.[key] || "—",metric.median===null ? "—" : String(Number(metric.median.toFixed(2))),String(metric.count)];
    for (const v of values) {const td=document.createElement("td"); td.textContent=v; tr.append(td);}
    return tr;
  }));
  el("when").textContent=last ? `最近记录 ${last.at_utc} · ${last.band || "—"} · ${last.data_service || (last.failure ? statusNames[last.failure] || last.failure : "无服务")}` : "";
  el("save").disabled=rows.length===0;
}

async function prepare() {
  if (moduleBytes) return;
  const r=await fetch(chrome.runtime.getURL("radio.wasm"));
  if(!r.ok) throw Error("解析器文件不可读");
  const bytes=new Uint8Array(await r.arrayBuffer());
  const {instance}=await WebAssembly.instantiate(bytes);
  failureWasm=instance.exports;
  const pieces=[];
  for(let i=0;i<bytes.length;i+=16000) pieces.push(String.fromCharCode(...bytes.subarray(i,i+16000)));
  moduleBytes=btoa(pieces.join(""));
}
function localFailure(seconds) {
  if(failureWasm.sample(0,4,BigInt(seconds))!==0) throw Error("本地错误行转换失败");
  return new TextDecoder().decode(new Uint8Array(failureWasm.memory.buffer,failureWasm.output_address(),failureWasm.output_length()));
}
async function poll(seconds) {
  let answers;
  try {
    answers=await chrome.scripting.executeScript({target:{tabId,frameIds:[0]},world:"ISOLATED",func:readDevice,args:[origin,moduleBytes,seconds]});
  } catch {
    return {csv:localFailure(seconds),note:"管理页不可读。请返回原管理页确认连接，再点扩展图标。",terminal:true};
  }
  const data=answers[0]?.result;
  if(data?.state!=="sample") return {csv:localFailure(seconds),note:"原管理页已离开该接收机，或解析器无法启动。",terminal:true};
  return data;
}
function wait(ms) {return new Promise(done=>{const id=setTimeout(done,ms);wake=()=>{clearTimeout(id);done();};});}
function enableRun(active) {
  running=active; el("start").disabled=active || !connected || imported;
  el("stop").disabled=!active; el("input").disabled=active;
  el("count").disabled=active; el("interval").disabled=active;
}
el("start").addEventListener("click",async()=>{
  if(running || imported || !connected || !el("count").reportValidity() || !el("interval").reportValidity()) return;
  const count=el("count").valueAsNumber, interval=el("interval").valueAsNumber;
  if(!Number.isInteger(count)||count<1||count>1440||!Number.isInteger(interval)||interval<1||interval>3600) return;
  if(rows.length+count>1440){el("notice").textContent="本窗口最多保留 1440 行。导出后在接收机管理页重新打开采集窗口。";return;}
  enableRun(true); stopping=false; let detail="";
  try {
    await prepare();
    for(let i=0;i<count && !stopping;i++) {
      el("notice").textContent=`正在读取第 ${i+1} / ${count} 次…`;
      const begun=Date.now(), result=await poll(Math.floor(begun/1000));
      const batch=readRows(result.csv);
      if(batch.length!==1) throw Error("一次请求返回了多条记录");
      rows.push(batch[0]);render();
      const reason=batch[0].row.failure;
      detail=result.note || statusNames[reason] || "";
      if(result.terminal || ["auth_failed","unsupported","malformed"].includes(reason)) break;
      if(i+1<count && !stopping) {
        el("notice").textContent=detail || "等待下次采样。请保持接收机管理标签页和采集窗口打开。";
        await wait(Math.max(0,interval*1000-(Date.now()-begun)));wake=null;
      }
    }
    el("notice").textContent=detail || (stopping?"已停止。":"采样完成。");
  } catch(e) { el("notice").textContent="采样中断：" + e.message; }
  finally {wake=null;enableRun(false);}
});
el("stop").addEventListener("click",()=>{stopping=true;wake?.();el("stop").disabled=true;el("notice").textContent="正在结束本次读取。";});
el("save").addEventListener("click",()=>{
  const blob=new Blob([columns.join(",")+"\n"+rows.map(v=>v.line).join("\n")+"\n"],{type:"text/csv;charset=utf-8"});
  const url=URL.createObjectURL(blob), a=document.createElement("a");
  a.href=url;a.download="m7-radio-"+new Date().toISOString().replaceAll(":","-")+".csv";a.click();
  setTimeout(()=>URL.revokeObjectURL(url),30000);
});
el("input").addEventListener("change",async e=>{
  const f=e.target.files[0]; if(!f || running) return;
  if(rows.length && !imported) {el("notice").textContent="本窗口已有现场采样。请另开窗口查看文件，避免覆盖观测。";e.target.value="";return;}
  try {
    if(f.size>32*1024*1024) throw Error("文件超过 32 MiB，请按日期拆分");
    const next=readRows(await f.text());
    rows=next;imported=true;enableRun(false);render();
    el("notice").textContent="已载入 "+f.name;
  } catch(err) { el("notice").textContent="导入失败：" + err.message; }
  e.target.value="";
});
render();
