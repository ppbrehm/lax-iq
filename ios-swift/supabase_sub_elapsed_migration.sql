-- Replaces the wall-clock last_in_at/last_out_at timestamps with a single
-- game-clock-driven "current stint" counter, so "time since sub in/out" on the
-- Game Hub tracks actual GAME time: it resets to 0 on every sub, ticks up only
-- while the game clock is running (freezing when paused), and isn't disrupted by
-- quarter changes the way a counter derived from timer_elapsed_sec would be.

alter table game_players drop column if exists last_in_at;
alter table game_players drop column if exists last_out_at;
alter table game_players drop column if exists sub_in_elapsed_sec;
alter table game_players drop column if exists sub_out_elapsed_sec;

alter table game_players add column if not exists current_stint_sec integer not null default 0;
