-- Separate "where I am today" from assigned terminal (mockup terminal select).
alter table public.drivers
  add column if not exists current_terminal_id uuid references public.terminals (terminal_id);
