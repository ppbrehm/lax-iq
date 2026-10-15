-- Tracks whether a game is scheduled, in progress, or completed, so the Game
-- Hub can prompt "Start Game?" and the Schedule can show live/final status.

alter table games add column if not exists status text not null default 'scheduled';

alter table games drop constraint if exists games_status_check;
alter table games add constraint games_status_check
  check (status in ('scheduled', 'in_progress', 'completed'));
