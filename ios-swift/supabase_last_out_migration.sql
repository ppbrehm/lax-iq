-- Tracks when a player was last subbed out, so the Stat Input screen can sort
-- bench players by "most recently came out" instead of roster order.

alter table game_players add column if not exists last_out_at timestamptz;
