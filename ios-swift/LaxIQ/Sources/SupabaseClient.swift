import Foundation
import Supabase

let supabaseURL = URL(string: "https://gwknhjtjwdtvydbwrxfu.supabase.co")!
let supabaseAnonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imd3a25oanRqd2R0dnlkYndyeGZ1Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3Njk4ODY5NzQsImV4cCI6MjA4NTQ2Mjk3NH0.jDJCCVtw7jwye39g-DGoZuht-mDiQZGiVB4zhIN5WMw"

let supabase = SupabaseClient(supabaseURL: supabaseURL, supabaseKey: supabaseAnonKey)
