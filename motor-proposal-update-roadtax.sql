-- Update: 'Exclude Road Tax' tick box. Run once in Supabase SQL Editor.

-- ---------- Public link: submit selection + payment to Sales Dept ----------
-- Prices are taken from the stored proposal, never from the browser.
drop function if exists public.submit_motor_proposal(uuid, text, text, numeric, text, text, text, text);
drop function if exists public.submit_motor_proposal(uuid, text, text, numeric, text, text, text, text, boolean);
create or replace function public.submit_motor_proposal(
  p_token uuid, p_operator text, p_option_code text,
  p_payment_amount numeric, p_payment_reference text,
  p_slip_path text, p_slip_name text, p_pdf_path text,
  p_exclude_road_tax boolean default false)
returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  v_row   public.motor_proposals;
  v_quote jsonb;
  v_opt   jsonb;
  v_sel   jsonb;
  v_tp numeric; v_rt numeric; v_af numeric;
begin
  select * into v_row from public.motor_proposals where public_token = p_token for update;
  if not found then raise exception 'Proposal not found.'; end if;
  if v_row.status <> 'OPEN' then return null; end if;

  select q into v_quote from jsonb_array_elements(v_row.quotes) q where q->>'operator' = p_operator limit 1;
  if v_quote is null then raise exception 'Selected Takaful operator is not part of this proposal.'; end if;

  select o into v_opt from jsonb_array_elements(v_quote->'options') o where o->>'code' = p_option_code limit 1;
  if v_opt is null then raise exception 'Selected option is not part of this proposal.'; end if;

  if coalesce(p_payment_amount, 0) <= 0 then raise exception 'Payment amount is required.'; end if;
  if coalesce(trim(p_payment_reference), '') = '' then raise exception 'Payment reference number is required.'; end if;
  if p_slip_path is null or split_part(p_slip_path, '/', 1) <> p_token::text then raise exception 'Payment slip is required.'; end if;
  if p_pdf_path  is null or split_part(p_pdf_path,  '/', 1) <> p_token::text then raise exception 'Proposal PDF is missing.'; end if;

  v_tp := coalesce((v_opt->>'takaful_price')::numeric, 0);
  v_rt := coalesce((v_opt->>'road_tax')::numeric, (v_quote->>'road_tax')::numeric, 0);
  v_af := coalesce((v_opt->>'admin_fee')::numeric, (v_quote->>'admin_fee')::numeric, 20);

  v_sel := jsonb_build_object(
    'operator', p_operator,
    'sum_covered', v_quote->'sum_covered',
    'note', v_quote->'note',
    'option_code', p_option_code,
    'option_name', v_opt->>'name',
    'takaful_price', v_tp, 'road_tax', v_rt, 'admin_fee', v_af,
    'exclude_road_tax', coalesce(p_exclude_road_tax, false),
    'full_total', v_tp + v_rt + v_af,
    -- Road Tax excluded → payable is the Takaful Price only
    'total', case when coalesce(p_exclude_road_tax, false) then v_tp else v_tp + v_rt + v_af end);

  update public.motor_proposals set
    selected_quote    = v_sel,
    payment_amount    = round(p_payment_amount, 2),
    payment_reference = trim(p_payment_reference),
    payment_slip_path = p_slip_path,
    payment_slip_name = p_slip_name,
    pdf_path          = p_pdf_path,
    status            = 'SUBMITTED',
    submitted_at      = now(),
    updated_at        = now(),
    audit_log         = audit_log || jsonb_build_array(jsonb_build_object(
                          'action', 'Option selected & payment sent to Sales Dept',
                          'timestamp', now()))
  where id = v_row.id;

  return v_sel;
end;
$$;
grant execute on function public.submit_motor_proposal(uuid, text, text, numeric, text, text, text, text, boolean) to anon, authenticated;

