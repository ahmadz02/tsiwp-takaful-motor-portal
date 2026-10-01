-- =====================================================================
-- Motor Takaful Value Proposal: REPAIR script
-- Fixes "Unable to save" when creating or editing a prospect.
-- Safe to run more than once. Does NOT delete any data.
-- =====================================================================

-- 1) Make sure every column the app uses exists (an older table may lack some)
alter table public.motor_proposals add column if not exists ifar_name         text;
alter table public.motor_proposals add column if not exists ifar_phone        text;
alter table public.motor_proposals add column if not exists owner_name        text;
alter table public.motor_proposals add column if not exists owner_id_no       text;
alter table public.motor_proposals add column if not exists vehicle_reg_no    text;
alter table public.motor_proposals add column if not exists vehicle_type      text;
alter table public.motor_proposals add column if not exists vehicle_model     text;
alter table public.motor_proposals add column if not exists engine_capacity   text;
alter table public.motor_proposals add column if not exists usage_type        text;
alter table public.motor_proposals add column if not exists vehicle_address   text;
alter table public.motor_proposals add column if not exists prospect_email    text;
alter table public.motor_proposals add column if not exists prospect_phone    text;
alter table public.motor_proposals add column if not exists ncd               text;
alter table public.motor_proposals add column if not exists coverage_term     text;
alter table public.motor_proposals add column if not exists quotes            jsonb not null default '[]'::jsonb;
alter table public.motor_proposals add column if not exists selected_quote    jsonb;
alter table public.motor_proposals add column if not exists payment_amount    numeric(12,2);
alter table public.motor_proposals add column if not exists payment_reference text;
alter table public.motor_proposals add column if not exists payment_slip_path text;
alter table public.motor_proposals add column if not exists payment_slip_name text;
alter table public.motor_proposals add column if not exists pdf_path          text;
alter table public.motor_proposals add column if not exists audit_log         jsonb not null default '[]'::jsonb;
alter table public.motor_proposals add column if not exists updated_at        timestamptz not null default now();
alter table public.motor_proposals add column if not exists submitted_at      timestamptz;
alter table public.motor_proposals add column if not exists closed_at         timestamptz;

-- 2) Remove the strict dropdown checks (the form already validates these)
alter table public.motor_proposals drop constraint if exists motor_proposals_vehicle_type_check;
alter table public.motor_proposals drop constraint if exists motor_proposals_usage_type_check;

-- 3) No-login app: created_by must not be required or tied to a user account
alter table public.motor_proposals alter column created_by drop not null;
alter table public.motor_proposals drop constraint if exists motor_proposals_created_by_fkey;

-- 4) Re-apply the open (no-login) access rules
alter table public.motor_proposals enable row level security;
do $$
declare r record;
begin
  for r in select policyname from pg_policies where schemaname = 'public' and tablename = 'motor_proposals' loop
    execute format('drop policy %I on public.motor_proposals', r.policyname);
  end loop;
end $$;

create policy motor_proposals_select on public.motor_proposals for select to anon, authenticated using (true);
create policy motor_proposals_insert on public.motor_proposals for insert to anon, authenticated with check (true);
create policy motor_proposals_update on public.motor_proposals for update to anon, authenticated using (true) with check (true);
create policy motor_proposals_delete on public.motor_proposals for delete to anon, authenticated using (status = 'OPEN');

grant usage on schema public to anon, authenticated;
grant select, insert, update, delete on public.motor_proposals to anon, authenticated;
grant usage, select on sequence public.motor_proposal_ref_seq to anon, authenticated;

-- 5) Tell the Supabase API to pick up the changes immediately
notify pgrst, 'reload schema';

-- 6) Check: this should list the 4 policies above, all for {anon,authenticated}
select policyname, cmd, roles from pg_policies
where schemaname = 'public' and tablename = 'motor_proposals' order by policyname;
