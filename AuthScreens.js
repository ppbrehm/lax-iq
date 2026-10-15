import React from "react";
import {
  View,
  Text,
  TextInput,
  Pressable,
  StyleSheet,
  ActivityIndicator,
  ScrollView,
  Alert,
  Platform,
} from "react-native";
import { supabase } from "./supabaseClient";

// ============================================================================
// UTILITY
// ============================================================================

const showAlert = (title, message) => {
  if (Platform.OS === "web") {
    window.alert(`${title}\n\n${message}`);
  } else {
    Alert.alert(title, message);
  }
};

// ============================================================================
// LOGIN SCREEN
// ============================================================================

export const LoginScreen = ({ onSwitchToSignup }) => {
  const [email, setEmail] = React.useState("");
  const [password, setPassword] = React.useState("");
  const [loading, setLoading] = React.useState(false);
  const [error, setError] = React.useState("");

  const handleLogin = async () => {
    if (!email.trim() || !password.trim()) {
      setError("Please enter your email and password.");
      return;
    }

    setLoading(true);
    setError("");

    try {
      const { error } = await supabase.auth.signInWithPassword({
        email: email.trim().toLowerCase(),
        password,
      });

      if (error) throw error;
      // Auth state change in App.js will handle navigation
    } catch (err) {
      setError(err.message || "Login failed. Please try again.");
    } finally {
      setLoading(false);
    }
  };

  return (
    <View style={styles.authContainer}>
      <View style={styles.authCard}>
        <Text style={styles.logoMark}>🥍</Text>
        <Text style={styles.authTitle}>LaxIQ</Text>
        <Text style={styles.authSubtitle}>Sign in to your team</Text>

        {error ? <Text style={styles.errorText}>{error}</Text> : null}

        <TextInput
          style={styles.authInput}
          placeholder="Email"
          placeholderTextColor="#9CA3AF"
          autoCapitalize="none"
          keyboardType="email-address"
          value={email}
          onChangeText={setEmail}
        />

        <TextInput
          style={styles.authInput}
          placeholder="Password"
          placeholderTextColor="#9CA3AF"
          secureTextEntry
          value={password}
          onChangeText={setPassword}
          onSubmitEditing={handleLogin}
        />

        <Pressable
          style={[styles.authButton, loading && styles.authButtonDisabled]}
          onPress={handleLogin}
          disabled={loading}
        >
          {loading ? (
            <ActivityIndicator color="#FFFFFF" />
          ) : (
            <Text style={styles.authButtonText}>Sign In</Text>
          )}
        </Pressable>

        <Pressable style={styles.switchLink} onPress={onSwitchToSignup}>
          <Text style={styles.switchLinkText}>
            No account?{" "}
            <Text style={styles.switchLinkAccent}>Create your team →</Text>
          </Text>
        </Pressable>
      </View>
    </View>
  );
};

// ============================================================================
// SIGNUP SCREEN
// ============================================================================

export const SignupScreen = ({ onSwitchToLogin }) => {
  const [teamName, setTeamName] = React.useState("");
  const [email, setEmail] = React.useState("");
  const [password, setPassword] = React.useState("");
  const [confirmPassword, setConfirmPassword] = React.useState("");
  const [loading, setLoading] = React.useState(false);
  const [error, setError] = React.useState("");

  const handleSignup = async () => {
    setError("");

    if (!teamName.trim()) return setError("Please enter a team name.");
    if (!email.trim()) return setError("Please enter an email.");
    if (password.length < 6) return setError("Password must be at least 6 characters.");
    if (password !== confirmPassword) return setError("Passwords don't match.");

    setLoading(true);

    try {
      // 1. Create the Supabase auth user
      const { data: authData, error: authError } = await supabase.auth.signUp({
        email: email.trim().toLowerCase(),
        password,
      });

      if (authError) throw authError;

      const userId = authData.user?.id;
      if (!userId) throw new Error("Signup succeeded but no user ID returned.");

      // 2. Create the team
      const { data: teamData, error: teamError } = await supabase
        .from("teams")
        .insert([{ name: teamName.trim() }])
        .select()
        .single();

      if (teamError) throw teamError;

      // 3. Add this user as head coach
      const { error: memberError } = await supabase
        .from("team_members")
        .insert([{
          team_id: teamData.id,
          user_id: userId,
          role: "head_coach",
        }]);

      if (memberError) throw memberError;

      // Auth state change in App.js will handle navigation
    } catch (err) {
      setError(err.message || "Signup failed. Please try again.");
    } finally {
      setLoading(false);
    }
  };

  return (
    <ScrollView contentContainerStyle={styles.authScrollContainer}>
      <View style={styles.authCard}>
        <Text style={styles.logoMark}>🥍</Text>
        <Text style={styles.authTitle}>Create Your Team</Text>
        <Text style={styles.authSubtitle}>You'll be the Head Coach</Text>

        {error ? <Text style={styles.errorText}>{error}</Text> : null}

        <Text style={styles.inputLabel}>Team Name</Text>
        <TextInput
          style={styles.authInput}
          placeholder="e.g. Westfield Varsity Boys"
          placeholderTextColor="#9CA3AF"
          value={teamName}
          onChangeText={setTeamName}
        />

        <Text style={styles.inputLabel}>Your Email</Text>
        <TextInput
          style={styles.authInput}
          placeholder="coach@example.com"
          placeholderTextColor="#9CA3AF"
          autoCapitalize="none"
          keyboardType="email-address"
          value={email}
          onChangeText={setEmail}
        />

        <Text style={styles.inputLabel}>Password</Text>
        <TextInput
          style={styles.authInput}
          placeholder="At least 6 characters"
          placeholderTextColor="#9CA3AF"
          secureTextEntry
          value={password}
          onChangeText={setPassword}
        />

        <Text style={styles.inputLabel}>Confirm Password</Text>
        <TextInput
          style={styles.authInput}
          placeholder="Repeat your password"
          placeholderTextColor="#9CA3AF"
          secureTextEntry
          value={confirmPassword}
          onChangeText={setConfirmPassword}
        />

        <Pressable
          style={[styles.authButton, loading && styles.authButtonDisabled]}
          onPress={handleSignup}
          disabled={loading}
        >
          {loading ? (
            <ActivityIndicator color="#FFFFFF" />
          ) : (
            <Text style={styles.authButtonText}>Create Team & Sign Up</Text>
          )}
        </Pressable>

        <Pressable style={styles.switchLink} onPress={onSwitchToLogin}>
          <Text style={styles.switchLinkText}>
            Already have an account?{" "}
            <Text style={styles.switchLinkAccent}>Sign in →</Text>
          </Text>
        </Pressable>
      </View>
    </ScrollView>
  );
};

// ============================================================================
// TEAM MANAGEMENT SCREEN
// ============================================================================

export const TeamManagementScreen = ({ onBack, currentUser, currentTeam, currentRole }) => {
  const [members, setMembers] = React.useState([]);
  const [inviteEmail, setInviteEmail] = React.useState("");
  const [loading, setLoading] = React.useState(true);
  const [inviting, setInviting] = React.useState(false);
  const [showInviteForm, setShowInviteForm] = React.useState(false);

  const isHeadCoach = currentRole === "head_coach";

  const loadMembers = React.useCallback(async () => {
    try {
      const { data, error } = await supabase
        .from("team_members")
        .select("id, role, user_id, created_at")
        .eq("team_id", currentTeam.id)
        .order("created_at", { ascending: true });

      if (error) throw error;
      setMembers(data || []);
    } catch (err) {
      console.error("Error loading team members:", err);
    } finally {
      setLoading(false);
    }
  }, [currentTeam]);

  React.useEffect(() => {
    loadMembers();
  }, [loadMembers]);

  const handleInvite = async () => {
    if (!inviteEmail.trim()) return;
    if (!isHeadCoach) {
      showAlert("Permission Denied", "Only Head Coaches can invite members.");
      return;
    }

    setInviting(true);
    try {
      // Look up the user by email via a Supabase function or auth admin
      // For now we use a client-side workaround: invite via magic link
      // The invited user will sign up themselves with the team join code
      // Simple approach: find user_id from a profiles/auth lookup isn't possible
      // client-side without a service role key. Instead, we'll use a "pending invite"
      // pattern or just show instructions.

      // Practical approach for React Native: send a Supabase magic link
      // and have the user's sign-up flow detect an invite.
      // For now, show the head coach the team ID to share.
      showAlert(
        "Invite Sent",
        `Ask ${inviteEmail.trim()} to download the app and sign up using:\n\nTeam Code: ${currentTeam.id.slice(0, 8).toUpperCase()}\n\nThey'll be added as an Assistant Coach.`
      );
      setInviteEmail("");
      setShowInviteForm(false);
    } catch (err) {
      showAlert("Error", err.message);
    } finally {
      setInviting(false);
    }
  };

  const handleRemoveMember = async (memberId, memberUserId) => {
    if (!isHeadCoach) {
      showAlert("Permission Denied", "Only Head Coaches can remove members.");
      return;
    }
    if (memberUserId === currentUser.id) {
      showAlert("Error", "You can't remove yourself.");
      return;
    }

    const confirm = Platform.OS === "web"
      ? window.confirm("Remove this coach from your team?")
      : await new Promise(resolve =>
          Alert.alert("Remove Coach", "Remove this coach from your team?", [
            { text: "Cancel", onPress: () => resolve(false) },
            { text: "Remove", style: "destructive", onPress: () => resolve(true) },
          ])
        );

    if (!confirm) return;

    try {
      const { error } = await supabase
        .from("team_members")
        .delete()
        .eq("id", memberId);

      if (error) throw error;
      setMembers(prev => prev.filter(m => m.id !== memberId));
    } catch (err) {
      showAlert("Error", err.message);
    }
  };

  const handleChangeRole = async (memberId, currentMemberRole) => {
    if (!isHeadCoach) {
      showAlert("Permission Denied", "Only Head Coaches can change roles.");
      return;
    }

    const newRole = currentMemberRole === "head_coach" ? "assistant_coach" : "head_coach";

    try {
      const { error } = await supabase
        .from("team_members")
        .update({ role: newRole })
        .eq("id", memberId);

      if (error) throw error;
      setMembers(prev =>
        prev.map(m => m.id === memberId ? { ...m, role: newRole } : m)
      );
    } catch (err) {
      showAlert("Error", err.message);
    }
  };

  const handleSignOut = async () => {
    const confirm = Platform.OS === "web"
      ? window.confirm("Sign out of LaxIQ?")
      : await new Promise(resolve =>
          Alert.alert("Sign Out", "Sign out of LaxIQ?", [
            { text: "Cancel", onPress: () => resolve(false) },
            { text: "Sign Out", style: "destructive", onPress: () => resolve(true) },
          ])
        );

    if (confirm) await supabase.auth.signOut();
  };

  return (
    <View style={styles.tmContainer}>
      <Pressable onPress={onBack}>
        <Text style={styles.backLink}>← Back to Home</Text>
      </Pressable>

      <Text style={styles.tmTitle}>{currentTeam?.name}</Text>

      {/* Current user badge */}
      <View style={styles.myBadge}>
        <View style={styles.myBadgeLeft}>
          <Text style={styles.myBadgeEmail}>{currentUser?.email}</Text>
          <View style={[styles.rolePill, currentRole === "head_coach" && styles.rolePillHead]}>
            <Text style={[styles.rolePillText, currentRole === "head_coach" && styles.rolePillTextHead]}>
              {currentRole === "head_coach" ? "👑 Head Coach" : "🏃 Assistant Coach"}
            </Text>
          </View>
        </View>
        <Pressable style={styles.signOutButton} onPress={handleSignOut}>
          <Text style={styles.signOutButtonText}>Sign Out</Text>
        </Pressable>
      </View>

      {/* Team Code */}
      <View style={styles.teamCodeBox}>
        <Text style={styles.teamCodeLabel}>Team Join Code</Text>
        <Text style={styles.teamCodeValue}>{currentTeam?.id?.slice(0, 8).toUpperCase()}</Text>
        <Text style={styles.teamCodeHint}>Share this code with assistant coaches when they sign up</Text>
      </View>

      {/* Members list */}
      <Text style={styles.sectionTitle}>Team Members</Text>

      {loading ? (
        <ActivityIndicator color="#007AFF" style={{ marginTop: 16 }} />
      ) : (
        <ScrollView style={styles.membersList}>
          {members.map(member => {
            const isMe = member.user_id === currentUser?.id;
            return (
              <View key={member.id} style={styles.memberRow}>
                <View style={styles.memberInfo}>
                  <Text style={styles.memberUserId}>
                    {isMe ? "You" : `Coach (${member.user_id.slice(0, 6)}...)`}
                  </Text>
                  <View style={[styles.rolePill, member.role === "head_coach" && styles.rolePillHead]}>
                    <Text style={[styles.rolePillText, member.role === "head_coach" && styles.rolePillTextHead]}>
                      {member.role === "head_coach" ? "👑 Head Coach" : "🏃 Assistant"}
                    </Text>
                  </View>
                </View>

                {isHeadCoach && !isMe && (
                  <View style={styles.memberActions}>
                    <Pressable
                      style={styles.memberActionButton}
                      onPress={() => handleChangeRole(member.id, member.role)}
                    >
                      <Text style={styles.memberActionText}>
                        {member.role === "head_coach" ? "Demote" : "Promote"}
                      </Text>
                    </Pressable>
                    <Pressable
                      style={[styles.memberActionButton, styles.memberActionDanger]}
                      onPress={() => handleRemoveMember(member.id, member.user_id)}
                    >
                      <Text style={[styles.memberActionText, styles.memberActionTextDanger]}>
                        Remove
                      </Text>
                    </Pressable>
                  </View>
                )}
              </View>
            );
          })}
        </ScrollView>
      )}

      {/* Invite (head coach only) */}
      {isHeadCoach && (
        <View style={styles.inviteSection}>
          {!showInviteForm ? (
            <Pressable
              style={styles.inviteButton}
              onPress={() => setShowInviteForm(true)}
            >
              <Text style={styles.inviteButtonText}>+ Invite Assistant Coach</Text>
            </Pressable>
          ) : (
            <View style={styles.inviteForm}>
              <TextInput
                style={styles.authInput}
                placeholder="Assistant coach's email"
                placeholderTextColor="#9CA3AF"
                autoCapitalize="none"
                keyboardType="email-address"
                value={inviteEmail}
                onChangeText={setInviteEmail}
              />
              <View style={{ flexDirection: "row", gap: 8 }}>
                <Pressable
                  style={[styles.authButton, { flex: 1 }, inviting && styles.authButtonDisabled]}
                  onPress={handleInvite}
                  disabled={inviting}
                >
                  <Text style={styles.authButtonText}>
                    {inviting ? "Sending..." : "Send Invite"}
                  </Text>
                </Pressable>
                <Pressable
                  style={styles.cancelInviteButton}
                  onPress={() => { setShowInviteForm(false); setInviteEmail(""); }}
                >
                  <Text style={styles.cancelInviteButtonText}>Cancel</Text>
                </Pressable>
              </View>
            </View>
          )}
        </View>
      )}
    </View>
  );
};

// ============================================================================
// JOIN TEAM SCREEN (for assistant coaches signing up with a team code)
// ============================================================================

export const JoinTeamScreen = ({ userId, onJoined }) => {
  const [teamCode, setTeamCode] = React.useState("");
  const [loading, setLoading] = React.useState(false);
  const [error, setError] = React.useState("");

  const handleJoin = async () => {
    if (teamCode.trim().length < 8) {
      setError("Please enter a valid 8-character team code.");
      return;
    }

    setLoading(true);
    setError("");

    try {
      // Find team where id starts with the code (case-insensitive prefix match)
      const { data: teams, error: teamError } = await supabase
        .from("teams")
        .select("id, name");

      if (teamError) throw teamError;

      const matchedTeam = teams?.find(t =>
        t.id.replace(/-/g, "").toUpperCase().startsWith(teamCode.trim().toUpperCase())
      );

      if (!matchedTeam) {
        setError("Team code not found. Double-check with your Head Coach.");
        setLoading(false);
        return;
      }

      // Add this user as assistant coach
      const { error: memberError } = await supabase
        .from("team_members")
        .insert([{
          team_id: matchedTeam.id,
          user_id: userId,
          role: "assistant_coach",
        }]);

      if (memberError) {
        if (memberError.code === "23505") {
          setError("You're already a member of this team.");
        } else {
          throw memberError;
        }
        setLoading(false);
        return;
      }

      onJoined();
    } catch (err) {
      setError(err.message || "Failed to join team.");
    } finally {
      setLoading(false);
    }
  };

  return (
    <View style={styles.authContainer}>
      <View style={styles.authCard}>
        <Text style={styles.logoMark}>🥍</Text>
        <Text style={styles.authTitle}>Join Your Team</Text>
        <Text style={styles.authSubtitle}>
          Enter the 8-character code from your Head Coach
        </Text>

        {error ? <Text style={styles.errorText}>{error}</Text> : null}

        <TextInput
          style={[styles.authInput, styles.codeInput]}
          placeholder="e.g. A1B2C3D4"
          placeholderTextColor="#9CA3AF"
          autoCapitalize="characters"
          maxLength={8}
          value={teamCode}
          onChangeText={setTeamCode}
        />

        <Pressable
          style={[styles.authButton, loading && styles.authButtonDisabled]}
          onPress={handleJoin}
          disabled={loading}
        >
          {loading ? (
            <ActivityIndicator color="#FFFFFF" />
          ) : (
            <Text style={styles.authButtonText}>Join Team</Text>
          )}
        </Pressable>

        <Pressable
          style={styles.switchLink}
          onPress={() => supabase.auth.signOut()}
        >
          <Text style={styles.switchLinkText}>
            Wrong account?{" "}
            <Text style={styles.switchLinkAccent}>Sign out →</Text>
          </Text>
        </Pressable>
      </View>
    </View>
  );
};

// ============================================================================
// STYLES
// ============================================================================

const styles = StyleSheet.create({
  authContainer: {
    flex: 1,
    backgroundColor: "#F2F2F7",
    justifyContent: "center",
    alignItems: "center",
    paddingHorizontal: 24,
  },

  authScrollContainer: {
    flexGrow: 1,
    backgroundColor: "#F2F2F7",
    justifyContent: "center",
    alignItems: "center",
    paddingHorizontal: 24,
    paddingVertical: 40,
  },

  authCard: {
    width: "100%",
    maxWidth: 400,
    backgroundColor: "#FFFFFF",
    borderRadius: 24,
    padding: 28,
    shadowColor: "#000",
    shadowOpacity: 0.1,
    shadowOffset: { width: 0, height: 8 },
    shadowRadius: 24,
    elevation: 8,
    alignItems: "center",
  },

  logoMark: {
    fontSize: 48,
    marginBottom: 8,
  },

  authTitle: {
    fontSize: 28,
    fontWeight: "800",
    color: "#111827",
    marginBottom: 4,
    textAlign: "center",
  },

  authSubtitle: {
    fontSize: 15,
    color: "#6B7280",
    marginBottom: 24,
    textAlign: "center",
  },

  inputLabel: {
    alignSelf: "flex-start",
    fontSize: 13,
    fontWeight: "600",
    color: "#374151",
    marginBottom: 4,
    marginTop: 4,
  },

  authInput: {
    width: "100%",
    borderWidth: 1.5,
    borderColor: "#D1D5DB",
    borderRadius: 14,
    fontSize: 16,
    color: "#111827",
    paddingHorizontal: 14,
    paddingVertical: 12,
    marginBottom: 12,
    backgroundColor: "#F9FAFB",
  },

  codeInput: {
    fontSize: 24,
    fontWeight: "700",
    letterSpacing: 6,
    textAlign: "center",
  },

  authButton: {
    width: "100%",
    paddingVertical: 14,
    borderRadius: 14,
    backgroundColor: "#007AFF",
    alignItems: "center",
    marginTop: 4,
    marginBottom: 16,
    shadowColor: "#007AFF",
    shadowOpacity: 0.3,
    shadowOffset: { width: 0, height: 4 },
    shadowRadius: 8,
    elevation: 4,
  },

  authButtonDisabled: {
    opacity: 0.6,
  },

  authButtonText: {
    color: "#FFFFFF",
    fontSize: 16,
    fontWeight: "700",
  },

  switchLink: {
    marginTop: 4,
  },

  switchLinkText: {
    fontSize: 14,
    color: "#6B7280",
    textAlign: "center",
  },

  switchLinkAccent: {
    color: "#007AFF",
    fontWeight: "600",
  },

  errorText: {
    color: "#EF4444",
    fontSize: 14,
    fontWeight: "500",
    textAlign: "center",
    marginBottom: 12,
    backgroundColor: "#FEF2F2",
    paddingHorizontal: 12,
    paddingVertical: 8,
    borderRadius: 10,
    width: "100%",
  },

  // Team Management
  tmContainer: {
    flex: 1,
    paddingTop: 50,
    paddingHorizontal: 16,
    backgroundColor: "#F2F2F7",
  },

  tmTitle: {
    fontSize: 26,
    fontWeight: "800",
    color: "#111827",
    marginBottom: 16,
    marginTop: 8,
  },

  backLink: {
    color: "#007AFF",
    fontSize: 16,
    marginTop: 16,
    marginBottom: 8,
  },

  myBadge: {
    flexDirection: "row",
    alignItems: "center",
    justifyContent: "space-between",
    backgroundColor: "#111827",
    borderRadius: 16,
    padding: 16,
    marginBottom: 16,
  },

  myBadgeLeft: {
    flex: 1,
  },

  myBadgeEmail: {
    color: "#F9FAFB",
    fontSize: 14,
    fontWeight: "600",
    marginBottom: 6,
  },

  rolePill: {
    alignSelf: "flex-start",
    paddingHorizontal: 10,
    paddingVertical: 4,
    borderRadius: 999,
    backgroundColor: "#374151",
  },

  rolePillHead: {
    backgroundColor: "#F59E0B",
  },

  rolePillText: {
    fontSize: 12,
    fontWeight: "700",
    color: "#D1D5DB",
  },

  rolePillTextHead: {
    color: "#111827",
  },

  signOutButton: {
    paddingHorizontal: 14,
    paddingVertical: 8,
    borderRadius: 10,
    borderWidth: 1.5,
    borderColor: "#4B5563",
  },

  signOutButtonText: {
    color: "#D1D5DB",
    fontSize: 13,
    fontWeight: "600",
  },

  teamCodeBox: {
    backgroundColor: "#EFF6FF",
    borderRadius: 14,
    padding: 16,
    marginBottom: 20,
    borderWidth: 1.5,
    borderColor: "#BFDBFE",
    alignItems: "center",
  },

  teamCodeLabel: {
    fontSize: 12,
    fontWeight: "700",
    color: "#3B82F6",
    textTransform: "uppercase",
    letterSpacing: 1,
    marginBottom: 4,
  },

  teamCodeValue: {
    fontSize: 28,
    fontWeight: "800",
    color: "#1D4ED8",
    letterSpacing: 4,
    marginBottom: 4,
  },

  teamCodeHint: {
    fontSize: 12,
    color: "#6B7280",
    textAlign: "center",
  },

  sectionTitle: {
    fontSize: 16,
    fontWeight: "700",
    color: "#374151",
    marginBottom: 8,
  },

  membersList: {
    flex: 1,
    marginBottom: 16,
  },

  memberRow: {
    flexDirection: "row",
    alignItems: "center",
    justifyContent: "space-between",
    backgroundColor: "#FFFFFF",
    borderRadius: 14,
    padding: 14,
    marginBottom: 8,
    borderWidth: 1,
    borderColor: "#E5E5EA",
    shadowColor: "#000",
    shadowOpacity: 0.04,
    shadowOffset: { width: 0, height: 1 },
    shadowRadius: 2,
    elevation: 1,
  },

  memberInfo: {
    flex: 1,
    gap: 6,
  },

  memberUserId: {
    fontSize: 14,
    fontWeight: "600",
    color: "#111827",
  },

  memberActions: {
    flexDirection: "row",
    gap: 8,
  },

  memberActionButton: {
    paddingHorizontal: 12,
    paddingVertical: 6,
    borderRadius: 8,
    borderWidth: 1.5,
    borderColor: "#D1D5DB",
    backgroundColor: "#F9FAFB",
  },

  memberActionDanger: {
    borderColor: "#FECACA",
    backgroundColor: "#FEF2F2",
  },

  memberActionText: {
    fontSize: 13,
    fontWeight: "600",
    color: "#374151",
  },

  memberActionTextDanger: {
    color: "#EF4444",
  },

  inviteSection: {
    paddingBottom: 24,
  },

  inviteButton: {
    width: "100%",
    paddingVertical: 14,
    borderRadius: 14,
    backgroundColor: "#007AFF",
    alignItems: "center",
    shadowColor: "#007AFF",
    shadowOpacity: 0.25,
    shadowOffset: { width: 0, height: 4 },
    shadowRadius: 8,
    elevation: 4,
  },

  inviteButtonText: {
    color: "#FFFFFF",
    fontSize: 16,
    fontWeight: "700",
  },

  inviteForm: {
    gap: 8,
  },

  cancelInviteButton: {
    paddingHorizontal: 16,
    paddingVertical: 14,
    borderRadius: 14,
    borderWidth: 1.5,
    borderColor: "#D1D5DB",
    backgroundColor: "#FFFFFF",
    alignItems: "center",
  },

  cancelInviteButtonText: {
    color: "#6B7280",
    fontSize: 15,
    fontWeight: "600",
  },
});
