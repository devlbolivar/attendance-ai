import { createClient } from '@supabase/supabase-js';
export const configured = Boolean(process.env.NEXT_PUBLIC_SUPABASE_URL && process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY);
export const db = createClient(process.env.NEXT_PUBLIC_SUPABASE_URL || 'https://placeholder.supabase.co', process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY || 'not-configured');
