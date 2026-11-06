import { createClient } from '@supabase/supabase-js'

export const supabaseUrl = import.meta.env.VITE_SUPABASE_URL as string | undefined
export const supabasePublishableKey = import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY as string | undefined

// In the browser, Supabase keeps the lecturer/admin signed in using localStorage by default.
export const supabase = createClient(supabaseUrl ?? '', supabasePublishableKey ?? '')
