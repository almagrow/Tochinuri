/* Modo sin conexión: guarda la app para abrirla aunque no haya internet.
   Las páginas se piden primero a la red (para tener siempre la última versión); los datos de Supabase nunca se guardan aquí. */
const CACHE="tochinuri-v16";
const SHELL=["./","index.html","legal.html","config.js","manifest.webmanifest","icons/icon-192.png","icons/icon-512.png","icons/apple-touch-icon.png"];
self.addEventListener("install",e=>{e.waitUntil(caches.open(CACHE).then(c=>c.addAll(SHELL)).then(()=>self.skipWaiting()))});
self.addEventListener("activate",e=>{e.waitUntil(caches.keys().then(ks=>Promise.all(ks.filter(k=>k!==CACHE).map(k=>caches.delete(k)))).then(()=>self.clients.claim()))});
self.addEventListener("fetch",e=>{
  const u=new URL(e.request.url);
  if(e.request.method!=="GET")return;
  if(u.hostname.endsWith("supabase.co"))return;
  const same=u.origin===location.origin;
  if(e.request.mode==="navigate"||(same&&/\.(html|js|webmanifest)$/.test(u.pathname))){
    e.respondWith(fetch(e.request).then(r=>{const c=r.clone();caches.open(CACHE).then(x=>x.put(e.request,c));return r}).catch(()=>caches.match(e.request).then(r=>r||caches.match("index.html"))));
    return;
  }
  if(same||u.hostname==="cdn.jsdelivr.net"||u.hostname.endsWith("gstatic.com")||u.hostname==="fonts.googleapis.com"){
    e.respondWith(caches.match(e.request).then(r=>r||fetch(e.request).then(res=>{const c=res.clone();caches.open(CACHE).then(x=>x.put(e.request,c));return res})));
  }
});
