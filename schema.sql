-- schema.sql
-- Run this once against your Postgres database before deploying.
-- Works on Vercel Postgres, Neon, Supabase, or any standard Postgres instance.
--
-- Usage (example with psql):
--   psql "$DATABASE_URL" -f schema.sql

CREATE TABLE IF NOT EXISTS bookings (
  id                      SERIAL PRIMARY KEY,
  booking_id              VARCHAR(32) UNIQUE NOT NULL,      -- e.g. SMK-2026-AB12CD
  full_name               VARCHAR(120) NOT NULL,
  email                   VARCHAR(254) NOT NULL,
  phone                   VARCHAR(20) NOT NULL,
  appointment_date        DATE NOT NULL,
  appointment_time        VARCHAR(20) NOT NULL,
  consultation_type       VARCHAR(60) NOT NULL,
  description              TEXT DEFAULT '',
  amount                  INTEGER NOT NULL,                 -- always 1500, enforced server-side
  currency                VARCHAR(3) NOT NULL DEFAULT 'PKR',
  payment_status          VARCHAR(20) NOT NULL DEFAULT 'PENDING', -- PENDING | PAID | FAILED
  booking_status           VARCHAR(20) NOT NULL DEFAULT 'PENDING_PAYMENT',
                            -- PENDING_PAYMENT | CONFIRMED | CANCELLED | FAILED | COMPLETED
  payfast_transaction_id  VARCHAR(80),
  confirmation_email_sent  BOOLEAN NOT NULL DEFAULT FALSE,
  admin_email_sent        BOOLEAN NOT NULL DEFAULT FALSE,
  created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at              TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_bookings_email ON bookings (email);
CREATE INDEX IF NOT EXISTS idx_bookings_payment_status ON bookings (payment_status);
CREATE INDEX IF NOT EXISTS idx_bookings_transaction_id ON bookings (payfast_transaction_id);

-- Sanity constraint: amount must always equal the fixed consultation fee.
-- This is a belt-and-suspenders DB-level guard on top of the server-side
-- enforcement in api/create-payment.js — the amount can never silently drift.
ALTER TABLE bookings DROP CONSTRAINT IF EXISTS bookings_amount_fixed;
ALTER TABLE bookings ADD CONSTRAINT bookings_amount_fixed CHECK (amount = 1500);
