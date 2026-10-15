import { createClient } from '@supabase/supabase-js';
import 'react-native-url-polyfill/auto';

// TODO: Replace these with your actual Supabase credentials
// You can find these in your Supabase project settings -> API
const supabaseUrl = 'https://gwknhjtjwdtvydbwrxfu.supabase.co'; // e.g., 'https://xxxxx.supabase.co'
const supabaseAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imd3a25oanRqd2R0dnlkYndyeGZ1Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3Njk4ODY5NzQsImV4cCI6MjA4NTQ2Mjk3NH0.jDJCCVtw7jwye39g-DGoZuht-mDiQZGiVB4zhIN5WMw'; // Long string starting with 'eyJ...'

export const supabase = createClient(supabaseUrl, supabaseAnonKey);
