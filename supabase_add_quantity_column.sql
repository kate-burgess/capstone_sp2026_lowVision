-- Run this in the Supabase SQL Editor (Dashboard → SQL) so the app can store
-- how many of each item you need (1–10).
--
-- Safe to run once; uses IF NOT EXISTS.

alter table public.grocery_items
  add column if not exists quantity integer not null default 1;

alter table public.grocery_items
  drop constraint if exists grocery_items_quantity_check;

alter table public.grocery_items
  add constraint grocery_items_quantity_check
  check (quantity >= 1 and quantity <= 10);
