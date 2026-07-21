// auth.js — thin wrappers over Supabase email/password auth.
// The display_name travels in user metadata; the signup trigger in
// db/04_functions.sql reads it to seed the player's profile.
import { supabase } from "./supabase.js";

export async function signUp(email, password, displayName) {
  return supabase.auth.signUp({
    email,
    password,
    options: { data: { display_name: displayName } },
  });
}

export async function signIn(email, password) {
  return supabase.auth.signInWithPassword({ email, password });
}

export async function signOut() {
  return supabase.auth.signOut();
}

export async function getSession() {
  const { data } = await supabase.auth.getSession();
  return data.session;
}

// Fires whenever the user signs in or out. Returns an unsubscribe handle.
export function onAuthChange(cb) {
  const { data } = supabase.auth.onAuthStateChange((_event, session) => cb(session));
  return () => data.subscription.unsubscribe();
}
