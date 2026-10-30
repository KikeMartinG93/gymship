import Foundation

/// Supabase project credentials.
///
/// Fill these in with your project's values (Project Settings → API).
/// The anon key is safe to ship in-app as long as Row Level Security (RLS)
/// policies are enabled on every table — see `Docs/supabase_schema.sql`.
enum SupabaseConfig {
    static let url = URL(string: "https://vlhovmkkfeffadijjzjx.supabase.co")!
    static let anonKey = "sb_publishable_oFLfzbf5yCdu1auBqVJEJQ_c1DwuDmm"
}
