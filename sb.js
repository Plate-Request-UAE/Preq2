/* إعدادات الاتصال بـ Supabase — المفتاح هنا مفتاح عام (anon) مسموح ظهوره، والصلاحيات محمية في قاعدة البيانات */
var SB_URL = 'https://jhonftizocayfmswyvlq.supabase.co';
var SB_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Impob25mdGl6b2NheWZtc3d5dmxxIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTQ5NDYzNDEsImV4cCI6MjExMDUyMjM0MX0.V9hzmGg3eeO3eCb0cPnvqv_kxL8W33LknV9fG_ZpTug';
var STAFF_DOMAIN = '@plate-demo.local';
function $(i){return document.getElementById(i)}
function esc(s){return String(s==null?'':s).replace(/[&<>"']/g,function(c){return{'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]})}
function sbFetch(path,opt,token){
  opt=opt||{};var h=opt.headers||{};h.apikey=SB_KEY;h.Authorization='Bearer '+(token||SB_KEY);opt.headers=h;
  return fetch(SB_URL+path,opt).then(function(r){return r.text().then(function(t){var j=null;try{j=t?JSON.parse(t):null}catch(e){j=t}return{ok:r.ok,status:r.status,j:j}})});
}
function sbRpc(fn,args,token){return sbFetch('/rest/v1/rpc/'+fn,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(args||{})},token)}
function sbErr(x){var j=x&&x.j;return (j&&(j.message||j.error_description||j.msg||j.error))||'تعذر الاتصال'}
