// Runs in the extension's isolated world, on the operator-selected management tab.
export async function readDevice(origin, moduleBase64, seconds) {
  if (location.origin !== origin) return {state:"origin_changed"};
  const module = Uint8Array.from(atob(moduleBase64), c => c.charCodeAt(0));
  const {instance} = await WebAssembly.instantiate(module);
  const wasm = instance.exports;
  const limit = wasm.input_capacity();
  const offset = wasm.input_address();
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 6000);
  let size = 0, kind = 0, note = "";
  try {
    const response = await fetch("/api/model.json?internalapi=1", {
      method:"GET", mode:"same-origin", credentials:"same-origin", redirect:"manual",
      cache:"no-store", referrerPolicy:"no-referrer", signal:controller.signal
    });
    if (response.type === "opaqueredirect" || [401,403].includes(response.status)) {
      kind=2; note="请在接收机原标签页登录，然后重新开始。";
    } else if (!response.ok) {
      kind=1; note="接收机管理页返回 HTTP " + response.status;
    } else if (!response.body || Number(response.headers.get("content-length"))>limit) {
      kind=3; note="响应为空或超过接收机解析上限。";
    } else {
      const reader=response.body.getReader();
      try {
        while (true) {
          const {value,done}=await reader.read();
          if (done) break;
          if (size+value.length>limit) { kind=3; note="接收机响应过大。"; await reader.cancel(); break; }
          new Uint8Array(wasm.memory.buffer, offset+size, value.length).set(value);
          size+=value.length;
        }
      } finally { reader.releaseLock(); }
    }
  } catch { kind=1; note="接收机未应答或请求超时。"; }
  finally { clearTimeout(timer); controller.abort(); }
  if (kind && size) new Uint8Array(wasm.memory.buffer,offset,size).fill(0);
  if (wasm.sample(kind ? 0 : size,kind,BigInt(seconds))!==0) throw Error("设备响应转换失败");
  const csv=new TextDecoder().decode(new Uint8Array(wasm.memory.buffer,wasm.output_address(),wasm.output_length()));
  return {state:"sample",csv,note};
}
