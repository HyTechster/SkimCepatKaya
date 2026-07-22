-- ============================================================================
-- 06_feedback.sql — player feedback & ideas
-- ----------------------------------------------------------------------------
-- A one-way inbox: signed-in players send a note (bug / idea / other) through
-- submit_feedback(), which validates it, caps its length, and rate-limits it on
-- the server. RLS denies ALL direct table access, so players can only INSERT via
-- the function and can never READ anyone's feedback. You (the owner) read it in
-- the Supabase dashboard (Table editor or SQL editor), which uses the service role.
--
-- Run order: 01..05 first, then this. Paste into Supabase -> SQL Editor -> Run.
-- ============================================================================

create table if not exists feedback (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid references auth.users (id) on delete set null,  -- who sent it
  sender_name  text not null check (char_length(sender_name) between 1 and 40),
  category     text not null check (category in ('bug', 'idea', 'other')),
  message      text not null check (char_length(message) between 1 and 1000),
  created_at   timestamptz not null default now()
);

-- newest-first reads for you; the second index also backs the rate-limit check
create index if not exists feedback_created_idx on feedback (created_at desc);
create index if not exists feedback_user_idx    on feedback (user_id, created_at desc);

-- RLS on, NO policies: anon/authenticated can neither read nor write directly.
-- Every write goes through submit_feedback() (SECURITY DEFINER, bypasses RLS).
alter table feedback enable row level security;

-- ---------------------------------------------------------------------------
-- submit_feedback(name, category, message): validate + rate-limit + insert.
--   * one submission per FEEDBACK_COOLDOWN (45s) per user, so it can't be spammed
--   * name capped 40 chars, message capped 1000, category constrained to 3 values
-- ---------------------------------------------------------------------------
create or replace function submit_feedback(p_name text, p_category text, p_message text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid  uuid := auth.uid();
  v_name text := btrim(coalesce(p_name, ''));
  v_msg  text := btrim(coalesce(p_message, ''));
  v_cat  text := lower(coalesce(p_category, 'other'));
begin
  if v_uid is null then raise exception 'not authenticated'; end if;
  if char_length(v_name) < 1 then raise exception 'name required'; end if;
  if char_length(v_msg)  < 1 then raise exception 'message required'; end if;
  if v_cat not in ('bug', 'idea', 'other') then v_cat := 'other'; end if;

  -- FEEDBACK_COOLDOWN = 45 seconds between submissions per user
  if exists (
       select 1 from feedback
        where user_id = v_uid and created_at > now() - interval '45 seconds'
     ) then
    raise exception 'feedback cooldown';
  end if;

  insert into feedback (user_id, sender_name, category, message)
    values (v_uid, left(v_name, 40), v_cat, left(v_msg, 1000));
end;
$$;

grant execute on function submit_feedback(text, text, text) to authenticated;

-- ---------------------------------------------------------------------------
-- HOW TO READ YOUR FEEDBACK — run this in the Supabase SQL editor any time:
--
--   select f.created_at, f.category, f.sender_name,
--          p.display_name as account_name, f.message
--     from feedback f
--     left join profiles p on p.user_id = f.user_id
--    order by f.created_at desc;
--
-- Or just open the `feedback` table in the Table editor (sort by created_at).
-- ---------------------------------------------------------------------------
