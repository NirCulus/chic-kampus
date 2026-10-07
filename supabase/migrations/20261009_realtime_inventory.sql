-- Tahap 4.2: sinkronkan bahan dan ledger untuk Dashboard Owner.
do $$
begin
  if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'ingredients') then alter publication supabase_realtime add table public.ingredients; end if;
  if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'stock_ledger') then alter publication supabase_realtime add table public.stock_ledger; end if;
end;
$$;