// Publishable key only. This is intentionally safe for the browser bundle.
// Override these values through .env.local to use a separate development project.
export const supabaseUrl=process.env.NEXT_PUBLIC_SUPABASE_URL||"https://opzuiwgquwtsvgxarhsr.supabase.co";
export const supabasePublishableKey=process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY||"sb_publishable_qj0snhl9_n7kA2akQ1wwWQ_2z8KnGhR";
