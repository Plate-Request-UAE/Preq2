-- قاعدة بيانات النسخة الأونلاين (Supabase / PostgreSQL)
-- الجداول محمية بـ RLS، وكل الوصول يتم عبر دوال تتحقق من الصلاحيات.
create extension if not exists pgcrypto with schema extensions;

create table public.staff (user_id uuid primary key references auth.users(id) on delete cascade, username text unique not null);
create table public.requests (
  no text primary key, name text not null, code text not null, chassis text not null, model text not null,
  req_date date not null default current_date, docs jsonb not null default '{}'::jsonb,
  status text not null default 'new' check (status in ('new','ok','no')),
  vehicle text not null default '', notes text not null default '',
  created_at timestamptz not null default now(), decided_by text not null default '', decided_at timestamptz);
create table public.audit (id bigint generated always as identity primary key, at timestamptz not null default now(), actor text not null, action text not null, req_no text);
create table public.rate (id bigint generated always as identity primary key, ip text not null, kind text not null, at timestamptz not null default now());
create index on public.rate (ip, kind, at);

alter table public.staff enable row level security;
alter table public.requests enable row level security;
alter table public.audit enable row level security;
alter table public.rate enable row level security;
revoke all on public.staff, public.requests, public.audit, public.rate from anon, authenticated;

create or replace function public.is_staff() returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.staff where user_id = auth.uid()); $$;
create or replace function public.staff_name() returns text language sql stable security definer set search_path = '' as $$
  select username from public.staff where user_id = auth.uid(); $$;
create or replace function public.client_ip() returns text language sql stable set search_path = '' as $$
  select coalesce(split_part(coalesce(current_setting('request.headers', true)::json->>'x-forwarded-for',''), ',', 1), 'unknown'); $$;

-- حد للمحاولات لكل عنوان IP
create or replace function public.hit(p_kind text, p_max int, p_window interval) returns boolean
language plpgsql security definer set search_path = '' as $$
declare v_ip text := public.client_ip(); n int;
begin
  delete from public.rate where at < now() - interval '1 day';
  select count(*) into n from public.rate where ip = v_ip and kind = p_kind and at > now() - p_window;
  if n >= p_max then return false; end if;
  insert into public.rate(ip, kind) values (v_ip, p_kind); return true;
end $$;

-- المراجع: تقديم طلب
create or replace function public.submit_request(p_name text, p_code text, p_chassis text, p_model text, p_date date, p_docs jsonb)
returns text language plpgsql security definer set search_path = '' as $$
declare v_no text; k text; v jsonb; clean jsonb := '{}'::jsonb;
begin
  if not public.hit('sub', 10, interval '1 hour') then raise exception 'محاولات كثيرة، حاول لاحقاً'; end if;
  p_name := btrim(coalesce(p_name,'')); p_code := btrim(coalesce(p_code,''));
  p_chassis := btrim(coalesce(p_chassis,'')); p_model := btrim(coalesce(p_model,''));
  if length(p_name) not between 2 and 100 or length(p_code) not between 1 and 20
     or length(p_chassis) not between 5 and 30 or length(p_model) not between 2 and 60 then raise exception 'بيانات غير مكتملة'; end if;
  foreach k in array array['d1','d2','d3'] loop
    v := p_docs -> k;
    if v is not null and jsonb_typeof(v) = 'object' then
      if (v->>'path') !~ '^u/[0-9a-f-]{36}/d[1-3]\.(jpg|png|webp|pdf)$' then raise exception 'ملف غير صالح'; end if;
      clean := clean || jsonb_build_object(k, jsonb_build_object('path', v->>'path', 'name', left(coalesce(v->>'name','file'), 80)));
    end if;
  end loop;
  loop v_no := (10000000 + floor(random() * 90000000))::bigint::text; exit when not exists (select 1 from public.requests where no = v_no); end loop;
  insert into public.requests(no, name, code, chassis, model, req_date, docs) values (v_no, p_name, p_code, p_chassis, p_model, coalesce(p_date, current_date), clean);
  insert into public.audit(actor, action, req_no) values ('public', 'create', v_no);
  return v_no;
end $$;

-- المراجع: متابعة الطلب (رقم الطلب + رقم القاعدة)
create or replace function public.track_request(p_no text, p_chassis text)
returns table(no text, status text, vehicle text, notes text) language plpgsql security definer set search_path = '' as $$
begin
  if not public.hit('trk', 60, interval '10 minutes') then raise exception 'محاولات كثيرة'; end if;
  return query select r.no, r.status, r.vehicle, r.notes from public.requests r where r.no = p_no and lower(r.chassis) = lower(btrim(coalesce(p_chassis,'')));
end $$;

-- الموظفات
create or replace function public.staff_list()
returns table(no text, name text, code text, req_date date, status text, missing int, created_at timestamptz)
language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.is_staff() then raise exception 'يلزم تسجيل الدخول'; end if;
  return query select r.no, r.name, r.code, r.req_date, r.status, (3 - (select count(*) from jsonb_object_keys(r.docs)))::int, r.created_at
    from public.requests r order by r.created_at desc limit 500;
end $$;

create or replace function public.staff_get(p_no text) returns setof public.requests language plpgsql security definer set search_path = '' as $$
begin
  if not public.is_staff() then raise exception 'يلزم تسجيل الدخول'; end if;
  insert into public.audit(actor, action, req_no) values (public.staff_name(), 'view', p_no);
  return query select * from public.requests where no = p_no;
end $$;

create or replace function public.staff_decide(p_no text, p_status text, p_vehicle text, p_notes text) returns void
language plpgsql security definer set search_path = '' as $$
declare r public.requests; who text := public.staff_name();
begin
  if not public.is_staff() then raise exception 'يلزم تسجيل الدخول'; end if;
  select * into r from public.requests where no = p_no for update;
  if not found then raise exception 'غير موجود'; end if;
  if r.status <> 'new' then raise exception 'تم اتخاذ قرار على هذا الطلب مسبقاً'; end if;
  p_vehicle := btrim(coalesce(p_vehicle,'')); p_notes := left(btrim(coalesce(p_notes,'')), 500);
  if p_status = 'ok' then if length(p_vehicle) not between 1 and 20 then raise exception 'أدخل رقم المركبة'; end if;
  elsif p_status = 'no' then if p_notes = '' then raise exception 'الملاحظات إلزامية عند الرفض'; end if; p_vehicle := '';
  else raise exception 'قرار غير صالح'; end if;
  update public.requests set status = p_status, vehicle = p_vehicle, notes = p_notes, decided_by = who, decided_at = now() where no = p_no;
  insert into public.audit(actor, action, req_no) values (who, 'decision:' || p_status, p_no);
end $$;

create or replace function public.staff_log_file(p_no text, p_doc text) returns void language plpgsql security definer set search_path = '' as $$
begin
  if not public.is_staff() then raise exception 'يلزم تسجيل الدخول'; end if;
  insert into public.audit(actor, action, req_no) values (public.staff_name(), 'file:' || left(p_doc, 4), p_no);
end $$;

revoke execute on all functions in schema public from public, anon, authenticated;
grant execute on function public.submit_request(text,text,text,text,date,jsonb), public.track_request(text,text) to anon, authenticated;
grant execute on function public.staff_list(), public.staff_get(text), public.staff_decide(text,text,text,text), public.staff_log_file(text,text), public.is_staff() to authenticated;

-- التخزين: مجلد خاص، 3 ميغابايت، صور أو PDF فقط
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('docs', 'docs', false, 3145728, array['image/jpeg','image/png','image/webp','application/pdf']) on conflict (id) do nothing;
create policy "public upload new docs only" on storage.objects for insert to anon, authenticated
  with check (bucket_id = 'docs' and name ~ '^u/[0-9a-f-]{36}/d[1-3]\.(jpg|png|webp|pdf)$');
create policy "staff read docs" on storage.objects for select to authenticated using (bucket_id = 'docs' and public.is_staff());
