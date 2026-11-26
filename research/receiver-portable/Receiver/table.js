export const columns = "at_unix,at_utc,outcome,failure,uptime_secs,temperature_c,thermal,service,network_service,data_service,band,ca_secondary_count,lte_rsrp_dbm,lte_rsrq_db,lte_sinr_db,lte_rssi_dbm,nr_rsrp_dbm,nr_rsrq_db,nr_sinr_db,plmn,session_secs".split(",");
export const signals = columns.slice(12, 19);
export const signalLabels = ["LTE RSRP · dBm", "LTE RSRQ · dB", "LTE SINR · dB", "LTE RSSI · dBm", "NR RSRP · dBm", "NR RSRQ · dB", "NR SINR · dB"];

export function localOrigin(raw) {
  if (!raw) return null;
  let url;
  try { url = new URL(raw); } catch { return null; }
  if (!["http:", "https:"].includes(url.protocol) || url.username || url.password) return null;
  if (url.hostname === "localhost") return url.origin;
  const parts = url.hostname.split(".");
  if (parts.length !== 4 || !parts.every(v => /^\d{1,3}$/.test(v) && Number(v) <= 255)) return null;
  const [a,b] = parts.map(Number);
  return a === 10 || a === 127 || (a === 192 && b === 168) || (a === 172 && b >= 16 && b <= 31) || (a === 169 && b === 254) ? url.origin : null;
}

// Read tables written by the pinned Mooring exporter. Values are numeric or closed-vocabulary cells.
export function readRows(text) {
  const lines = text.replace(/^\uFEFF/, "").replaceAll("\r\n", "\n").split("\n");
  if (lines.pop() !== "" || lines.shift() !== columns.join(",")) throw Error("文件结尾或 Mooring 表头不完整");
  if (!lines.length) throw Error("表中没有观测行");
  return lines.map((line, i) => {
    const fields = line.split(",");
    const row = Object.fromEntries(columns.map((key, j) => [key, fields[j]]));
    const seconds = Number(row.at_unix);
    if (fields.length !== columns.length || !/^\d+$/.test(row.at_unix) || !Number.isSafeInteger(seconds) ||
        !Number.isFinite(Date.parse(row.at_utc)) || new Date(seconds * 1000).toISOString().replace(".000Z","Z") !== row.at_utc)
      throw Error(`第 ${i+2} 行的列或 UTC 时间无效`);
    const failCodes = ["not_configured","unreachable","auth_failed","identity_mismatch","unsupported","malformed","local_failure"];
    const read = row.outcome === "read";
    if (!read && (row.outcome !== "failed" || !failCodes.includes(row.failure) || fields.slice(4).some(Boolean)) ||
        read && (row.failure || !["attached","no_service"].includes(row.service))) throw Error(`第 ${i+2} 行的测量状态无效`);
    if (read && row.service === "no_service" && fields.slice(8).some(Boolean)) throw Error(`第 ${i+2} 行的无服务记录含有附着指标`);
    const unsigned = s => /^(0|[1-9]\d*)$/.test(s) && BigInt(s) <= 18446744073709551615n;
    if (read && (!unsigned(row.uptime_secs) || !/^-?\d{1,3}$/.test(row.temperature_c) || Number(row.temperature_c)<-40 || Number(row.temperature_c)>125 || row.thermal !== "normal")) throw Error(`第 ${i+2} 行的设备读数无效`);
    if (read && row.service === "attached" && (!['nr5g','lte'].includes(row.network_service) || !['nr_sub6','lte','lte_plus'].includes(row.data_service) || !/^[Bn][1-9]\d{0,2}$/.test(row.band) || !/^\d{3}-\d{2,3}$/.test(row.plmn) || !unsigned(row.ca_secondary_count) || Number(row.ca_secondary_count)>255 || !unsigned(row.session_secs) || BigInt(row.session_secs)>BigInt(row.uptime_secs))) throw Error(`第 ${i+2} 行的附着读数无效`);
    const ranges = [[-156,-31],[-43,20],[-23,40],[-150,0],[-156,-31],[-43,20],[-23,40]];
    for (let j=0; j<signals.length; j++) {
      const raw = row[signals[j]], [min,max] = ranges[j];
      if (raw && (!/^-?\d+\.\d$/.test(raw) || Number(raw)<min || Number(raw)>max)) throw Error(`第 ${i+2} 行的射频数值无效`);
    }
    return {line, row};
  });
}

export function stats(rows, key) {
  const vals = rows.map(x => x.row[key]).filter(x => x !== "").map(Number).sort((a,b) => a-b);
  if (!vals.length) return {count:0, median:null};
  const middle = Math.floor(vals.length/2);
  return {count:vals.length, median: vals.length%2 ? vals[middle] : (vals[middle-1]+vals[middle])/2};
}
