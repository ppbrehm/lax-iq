import * as DocumentPicker from 'expo-document-picker';
import React from "react";
import {
  ActivityIndicator,
  Platform,
  Pressable,
  ScrollView,
  StyleSheet,
  Text,
  TextInput,
  View,
} from "react-native";
import { TeamManagementScreen } from "./AuthScreens";
import { supabase } from './supabaseClient';


// Stat categories and headers
const STAT_COL_WIDTH = 90;
const OFFENSIVE_STATS = ["Shots", "SOG", "Goals", "Shot%", "Assists", "TO"];
const FACEOFF_STATS = ["FO Att", "FO Win", "FO%"];
const DEFENSIVE_STATS = ["GB", "CT"];
const GOALIE_STATS = ["SA", "SAOG", "GA", "Saves", "Save%"];

const STAT_HEADERS = [
  ...OFFENSIVE_STATS,
  ...FACEOFF_STATS,
  ...DEFENSIVE_STATS,
  ...GOALIE_STATS
];

// Indices for each stat (for easier reference)
const STAT_INDEX = {
  SHOTS: 0,
  SOG: 1,
  GOALS: 2,
  SHOT_PCT: 3,
  ASSISTS: 4,
  TURNOVERS: 5,
  FO_ATT: 6,
  FO_WIN: 7,
  FO_PCT: 8,
  GB: 9,
  CT: 10,
  SA: 11,
  SAOG: 12,
  GA: 13,
  SAVES: 14,
  SAVE_PCT: 15
};

// ============================================================================
// UTILITY FUNCTIONS
// ============================================================================

const formatSeconds = (totalSeconds) => {
  const s = Math.max(0, Math.floor(totalSeconds || 0));
  const minutes = Math.floor(s / 60);
  const seconds = s % 60;
  return `${minutes}:${seconds.toString().padStart(2, "0")}`;
};

// NEW: Calculate total stats
const calculateTotalStats = (stats) => {
  if (!stats || stats.length === 0) {
    return Array(STAT_HEADERS.length).fill(0);
  }

  const totals = Array(STAT_HEADERS.length).fill(0);
  
  // Sum up all raw stats (skip calculated percentages)
  stats.forEach(playerStats => {
    STAT_HEADERS.forEach((_, index) => {
      if (index !== STAT_INDEX.SHOT_PCT && 
          index !== STAT_INDEX.FO_PCT && 
          index !== STAT_INDEX.SAVE_PCT &&
          index !== STAT_INDEX.SAOG) {
        totals[index] += playerStats[index] || 0;
      }
    });
  });
  
  // Calculate total percentages
  const totalShots = totals[STAT_INDEX.SHOTS];
  const totalGoals = totals[STAT_INDEX.GOALS];
  totals[STAT_INDEX.SHOT_PCT] = totalShots > 0 ? Math.round((totalGoals / totalShots) * 100) : 0;
  
  const totalFoAtt = totals[STAT_INDEX.FO_ATT];
  const totalFoWin = totals[STAT_INDEX.FO_WIN];
  totals[STAT_INDEX.FO_PCT] = totalFoAtt > 0 ? Math.round((totalFoWin / totalFoAtt) * 100) : 0;
  
  const totalGa = totals[STAT_INDEX.GA];
  const totalSaves = totals[STAT_INDEX.SAVES];
  totals[STAT_INDEX.SAOG] = totalGa + totalSaves;
  const totalSaog = totals[STAT_INDEX.SAOG];
  totals[STAT_INDEX.SAVE_PCT] = totalSaog > 0 ? Math.round((totalSaves / totalSaog) * 100) : 0;
  
  return totals;
};
// ============================================================================
// CUSTOM HOOKS
// ============================================================================

const useGameTimer = (games, setGames, updateGameInDb) => {
  React.useEffect(() => {
    const intervalId = setInterval(() => {
      setGames((prevGames) =>
        prevGames.map((g) => {
          if (!g.timerRunning) return g;

          const elapsed = (g.timerElapsedSec || 0) + 1;
          const updatedTimes = (g.playerTimesSec || []).map((t, idx) =>
            g.playerIn?.[idx] ? t + 1 : t
          );

          // Update in database every 5 seconds to reduce calls
          if (elapsed % 5 === 0) {
            updateGameInDb(g.id, {
              timer_elapsed_sec: elapsed,
            });
          }

          return {
            ...g,
            timerElapsedSec: elapsed,
            playerTimesSec: updatedTimes,
          };
        })
      );
    }, 1000);

    return () => clearInterval(intervalId);
  }, [setGames, updateGameInDb]);
};

// ============================================================================
// MAIN COMPONENT
// ============================================================================

export default function App() {
  // Navigation
  const [screen, setScreen] = React.useState("home");
  
  // Games
  const [games, setGames] = React.useState([]);
  const [selectedGameId, setSelectedGameId] = React.useState(null);
  
  // Roster
  const [roster, setRoster] = React.useState([]);
const [rosterForm, setRosterForm] = React.useState({
  number: "",
  firstName: "",
  lastName: "",
  position: "",
});
  
    // Team state (auth disabled for now — testing with a single default team)
  const [currentUser, setCurrentUser] = React.useState(null);
  const [currentTeam, setCurrentTeam] = React.useState(null);
  const [currentRole, setCurrentRole] = React.useState(null);

  // Game creation
const [gameForm, setGameForm] = React.useState({
  year: "",
  month: "",
  day: "",
  opponent: "",
  location: "home",  // ADD THIS - default to home
});
  const [showAddGameForm, setShowAddGameForm] = React.useState(false);
  
  // Game stats
  const [newPlayerName, setNewPlayerName] = React.useState("");
  
  // Play design
  const [playPieces, setPlayPieces] = React.useState([]);
  const [playActions, setPlayActions] = React.useState([]);
  const [playMode, setPlayMode] = React.useState("offense");
  const [fieldType, setFieldType] = React.useState("full");
  const [playName, setPlayName] = React.useState("");
  const [savedPlays, setSavedPlays] = React.useState([]);
  const [drawingAction, setDrawingAction] = React.useState(null);
  const [fieldTouchStart, setFieldTouchStart] = React.useState(null);
  const [dragInfo, setDragInfo] = React.useState(null);

  // Loading state
  const [loading, setLoading] = React.useState(true);

  const selectedGame = games.find((g) => g.id === selectedGameId) || null;

  // ============================================================================
  // SUPABASE DATA OPERATIONS
  // ============================================================================

const loadRoster = React.useCallback(async (teamId) => {
    const tid = teamId || currentTeam?.id;
    if (!tid) return [];
    try {
      const { data, error } = await supabase
        .from("roster")
        .select("*")
        .eq("team_id", tid)
        .order("created_at", { ascending: false });

      if (error) throw error;

      const transformedRoster = data?.map(player => ({
        id: player.id,
        number: player.number,
        firstName: player.first_name,
        lastName: player.last_name,
        position: player.position,
      })) || [];

      setRoster(transformedRoster);
      return transformedRoster;
    } catch (error) {
      console.error("Error loading roster:", error);
      return [];
    }
  }, [currentTeam]);

const loadGames = React.useCallback(async (teamId) => {
    const tid = teamId || currentTeam?.id;
    if (!tid) return [];
    try {
      const { data, error } = await supabase
        .from("games")
        .select(`*, game_players (*)`)
        .eq("team_id", tid)
        .order("created_at", { ascending: false });

      if (error) throw error;

      // ... rest of your existing transformation logic unchanged ...
      const transformedGames = data?.map(game => ({
        id: game.id,
        date: game.date,
        opponent: game.opponent,
        location: game.location || "home",
        timerRunning: game.timer_running,
        timerElapsedSec: game.timer_elapsed_sec,
        players: game.game_players.map(p => ({
          id: p.id,
          firstName: p.first_name,
          lastName: p.last_name,
          number: p.number,
          position: p.position,
        })),
        stats: game.game_players.map(p => [
          p.shots || 0, p.shots_on_goal || 0, p.goals || 0, 0,
          p.assists || 0, p.turnovers || 0,
          p.faceoff_attempts || 0, p.faceoff_wins || 0, 0,
          p.ground_balls || 0, p.caused_turnovers || 0,
          p.shots_against || 0, p.shots_against_on_goal || 0,
          p.goals_against || 0, p.saves || 0, 0,
        ]),
        playerTimesSec: game.game_players.map(p => p.player_time_sec || 0),
        playerIn: game.game_players.map(p => p.player_in || false),
      })) || [];

      setGames(transformedGames);
      return transformedGames;
    } catch (error) {
      console.error("Error loading games:", error);
      return [];
    }
  }, [currentTeam]);

const loadPlays = React.useCallback(async (teamId) => {
    const tid = teamId || currentTeam?.id;
    if (!tid) return [];
    try {
      const { data, error } = await supabase
        .from("plays")
        .select("*")
        .eq("team_id", tid)
        .order("created_at", { ascending: false });

      if (error) throw error;

      const transformedPlays = data?.map(play => ({
        id: play.id,
        name: play.name,
        fieldType: play.field_type,
        pieces: play.pieces || [],
        actions: play.actions || [],
      })) || [];

      setSavedPlays(transformedPlays);
      return transformedPlays;
    } catch (error) {
      console.error("Error loading plays:", error);
      return [];
    }
  }, [currentTeam]);

  // ADD THIS ENTIRE NEW FUNCTION:
  const syncRosterToGames = React.useCallback(async (currentRoster, currentGames) => {
    try {
      // Find games without players
      const gamesWithoutPlayers = currentGames.filter(game => game.players.length === 0);

      // If there are games without players and we have a roster, sync them
      if (gamesWithoutPlayers.length > 0 && currentRoster.length > 0) {
        const allGamePlayers = [];
        
        for (const game of gamesWithoutPlayers) {
          const playersForGame = currentRoster.map((p) => ({
            game_id: game.id,
            first_name: p.firstName,
            last_name: p.lastName,
            number: p.number,
            position: p.position,
          }));
          allGamePlayers.push(...playersForGame);
        }

        const { error: insertError } = await supabase
          .from('game_players')
          .insert(allGamePlayers);

        if (insertError) throw insertError;

        console.log(`✅ Synced roster to ${gamesWithoutPlayers.length} game(s)`);
        
        // Reload games to show updated data
        await loadGames();
        
        return true;
      }
      return false;
    } catch (error) {
      console.error('Error syncing roster to games:', error);
      return false;
    }
  }, [loadGames]);

  // Load all data on mount, using a single default team (auth disabled for now)
  React.useEffect(() => {
    const bootstrapTestTeam = async () => {
      setLoading(true);

      try {
        // Use the first team found, or create one if the table is empty
        const { data: existingTeams, error: teamsError } = await supabase
          .from("teams")
          .select("id, name")
          .limit(1);

        if (teamsError) throw teamsError;

        let team = existingTeams?.[0];

        if (!team) {
          const { data: newTeam, error: createError } = await supabase
            .from("teams")
            .insert([{ name: "Test Team" }])
            .select()
            .single();

          if (createError) throw createError;
          team = newTeam;
        }

        setCurrentTeam(team);
        setCurrentRole("head_coach");

        const [loadedRoster, loadedGames] = await Promise.all([
          loadRoster(team.id),
          loadGames(team.id),
          loadPlays(team.id),
        ]);

        if (loadedRoster.length > 0 && loadedGames.length > 0) {
          await syncRosterToGames(loadedRoster, loadedGames);
        }
      } catch (err) {
        console.error("Bootstrap error:", err);
      } finally {
        setLoading(false);
      }
    };

    bootstrapTestTeam();
  }, []);

  const updateGameInDb = React.useCallback(async (gameId, updates) => {
    try {
      const { error } = await supabase
        .from('games')
        .update(updates)
        .eq('id', gameId);
      
      if (error) throw error;
    } catch (error) {
      console.error('Error updating game:', error);
    }
  }, []);

  const updateGamePlayerInDb = React.useCallback(async (playerId, updates) => {
    try {
      const { error } = await supabase
        .from('game_players')
        .update(updates)
        .eq('id', playerId);
      
      if (error) throw error;
    } catch (error) {
      console.error('Error updating game player:', error);
    }
  }, []);

  // Use custom hook for game timer
  useGameTimer(games, setGames, updateGameInDb);

  // ============================================================================
  // GAME OPERATIONS
  // ============================================================================



      // Create the game
const createNewGame = React.useCallback(async () => {
  if (!gameForm.year.trim() || !gameForm.month.trim() || !gameForm.day.trim() || !gameForm.opponent.trim()) return;

  try {
    // Format the date
    const formattedDate = `${gameForm.month}/${gameForm.day}/${gameForm.year}`;

    // Create the game
    const { data: gameData, error: gameError } = await supabase
      .from('games')
      .insert([{
        date: formattedDate,
        opponent: gameForm.opponent.trim(),
        location: gameForm.location,
        team_id: currentTeam.id,
      }])
      .select()
      .single();

    if (gameError) throw gameError;

    // Add players from roster to the game
    if (roster.length > 0) {
      const playersFromRoster = roster.map((p) => ({
        game_id: gameData.id,
        first_name: p.firstName,
        last_name: p.lastName,
        number: p.number,
        position: p.position,
      }));

      const { error: playersError } = await supabase
        .from('game_players')
        .insert(playersFromRoster);

      if (playersError) throw playersError;
    }

    // **CRITICAL**: Reload games and wait for state to settle
    await loadGames();
    
    // Use a Promise with requestAnimationFrame to ensure state update
    await new Promise(resolve => {
      requestAnimationFrame(() => {
        requestAnimationFrame(() => {
          resolve();
        });
      });
    });
    
    // Reset form and navigate
    setGameForm({ year: "", month: "", day: "", opponent: "", location: "home" });
    setShowAddGameForm(false);
    
    // Don't set selectedGameId yet - let user click on the game
    setScreen("gameLog");
    
    alert('Game created successfully! Click on the game to view stats.');
  } catch (error) {
    console.error('Error creating game:', error);
    alert('Error creating game: ' + error.message);
  }
}, [gameForm, roster, loadGames]);

  const updateGame = React.useCallback((gameId, updates) => {
    setGames((prev) =>
      prev.map((g) => (g.id === gameId ? { ...g, ...updates } : g))
    );
  }, []);

  const toggleGameTimer = React.useCallback(async () => {
    if (!selectedGame) return;
    
    const newRunningState = !selectedGame.timerRunning;
    
    // Update local state immediately
    updateGame(selectedGameId, { timerRunning: newRunningState });
    
    // Update in database
    await updateGameInDb(selectedGameId, {
      timer_running: newRunningState,
    });
  }, [selectedGame, selectedGameId, updateGame, updateGameInDb]);

  const resetGameTimer = React.useCallback(async () => {
    if (!selectedGame) return;
    
    // Update local state
    updateGame(selectedGameId, {
      timerRunning: false,
      timerElapsedSec: 0,
      playerTimesSec: selectedGame.players.map(() => 0),
    });
    
    // Update in database
    await updateGameInDb(selectedGameId, {
      timer_running: false,
      timer_elapsed_sec: 0,
    });

    // Reset all player times
    for (const player of selectedGame.players) {
      if (player.id) {
        await updateGamePlayerInDb(player.id, {
          player_time_sec: 0,
        });
      }
    }
  }, [selectedGame, selectedGameId, updateGame, updateGameInDb, updateGamePlayerInDb]);

  const togglePlayerIn = React.useCallback(async (index) => {
    if (!selectedGame) return;
    
    const playerIn = selectedGame.playerIn || selectedGame.players.map(() => false);
    const updated = playerIn.map((val, i) => (i === index ? !val : val));
    
    // Update local state
    updateGame(selectedGameId, { playerIn: updated });
    
    // Update in database
    const player = selectedGame.players[index];
    if (player.id) {
      await updateGamePlayerInDb(player.id, {
        player_in: updated[index],
      });
    }
  }, [selectedGame, selectedGameId, updateGame, updateGamePlayerInDb]);

  // ============================================================================
  // ROSTER OPERATIONS
  // ============================================================================

const addRosterPlayer = React.useCallback(async () => {
  if (!rosterForm.firstName.trim() || !rosterForm.lastName.trim()) return;

  try {
const newPlayer = {
    number: rosterForm.number.trim(),
    first_name: rosterForm.firstName.trim(),
    last_name: rosterForm.lastName.trim(),
    position: rosterForm.position.trim(),
    team_id: currentTeam.id,   // <-- was user_id: user?.id
  };

    const { data, error } = await supabase
      .from('roster')
      .insert([newPlayer])
      .select()
      .single();

    if (error) throw error;

    const updatedRoster = [...roster, {
      id: data.id,
      number: data.number,
      firstName: data.first_name,
      lastName: data.last_name,
      position: data.position,
    }];
    
    setRoster(updatedRoster);
    setRosterForm({ number: "", firstName: "", lastName: "", position: "" });
    
    // ADD THESE LINES: After adding a roster player, sync to games without players
    await syncRosterToGames(updatedRoster, games);
  } catch (error) {
    console.error('Error adding roster player:', error);
  }
}, [rosterForm, roster, games, syncRosterToGames]); // ADD roster, games, syncRosterToGames to dependencies

  const removeRosterPlayer = React.useCallback(async (id) => {
    try {
      const { error } = await supabase
        .from('roster')
        .delete()
        .eq('id', id);

      if (error) throw error;

      setRoster((prev) => prev.filter((p) => p.id !== id));
    } catch (error) {
      console.error('Error removing roster player:', error);
    }
  }, []);

  // ============================================================================
  // PLAYER OPERATIONS
  // ============================================================================

const handleAddPlayer = React.useCallback(async () => {
  if (!newPlayerName.trim() || !selectedGame) return;

  try {
    // Split the name if it contains a comma (Last, First format)
    // or assume it's firstName lastName format
    let firstName = '';
    let lastName = '';
    
    if (newPlayerName.includes(',')) {
      const parts = newPlayerName.split(',').map(s => s.trim());
      lastName = parts[0];
      firstName = parts[1] || '';
    } else {
      const parts = newPlayerName.trim().split(' ');
      firstName = parts[0];
      lastName = parts.slice(1).join(' ') || '';
    }

    const newPlayer = {
      game_id: selectedGameId,
      first_name: firstName,
      last_name: lastName,
      number: "",
      position: "",
    };

    const { data, error } = await supabase
      .from('game_players')
      .insert([newPlayer])
      .select()
      .single();

    if (error) throw error;

    // Update local state
    updateGame(selectedGameId, {
      players: [...selectedGame.players, {
        id: data.id,
        firstName: data.first_name,
        lastName: data.last_name,
        number: data.number,
        position: data.position,
      }],
      stats: [...selectedGame.stats, Array(STAT_HEADERS.length).fill(0)],
      playerTimesSec: [...(selectedGame.playerTimesSec || []), 0],
      playerIn: [...(selectedGame.playerIn || []), false],
    });

    setNewPlayerName("");
  } catch (error) {
    console.error('Error adding player:', error);
  }
}, [newPlayerName, selectedGame, selectedGameId, updateGame]);

  const handleRemovePlayer = React.useCallback(async (index) => {
    if (!selectedGame) return;

    try {
      const player = selectedGame.players[index];
      
      if (player.id) {
        const { error } = await supabase
          .from('game_players')
          .delete()
          .eq('id', player.id);

        if (error) throw error;
      }

      // Update local state
      updateGame(selectedGameId, {
        players: selectedGame.players.filter((_, i) => i !== index),
        stats: selectedGame.stats.filter((_, i) => i !== index),
        playerTimesSec: (selectedGame.playerTimesSec || []).filter((_, i) => i !== index),
        playerIn: (selectedGame.playerIn || []).filter((_, i) => i !== index),
      });
    } catch (error) {
      console.error('Error removing player:', error);
    }
  }, [selectedGame, selectedGameId, updateGame]);

const handleStatChange = React.useCallback(async (row, col, delta) => {
  if (!selectedGame) return;
  
  // For all stats, process normally (no interception here)
  const updatedStats = selectedGame.stats.map((r, ri) => {
    if (ri !== row) return r;
    
    const newStats = [...r];
    newStats[col] = Math.max(0, newStats[col] + delta);
    
    // Cascade Goals changes to SOG and Shots
    if (col === STAT_INDEX.GOALS) {
      const goalsValue = newStats[STAT_INDEX.GOALS];
      const sogValue = newStats[STAT_INDEX.SOG];
      const shotsValue = newStats[STAT_INDEX.SHOTS];
      
      if (delta > 0) {
        if (goalsValue > sogValue) {
          newStats[STAT_INDEX.SOG] = goalsValue;
        }
        if (goalsValue > shotsValue) {
          newStats[STAT_INDEX.SHOTS] = goalsValue;
        }
      }
    }
    
    // Cascade SOG changes to Shots
    if (col === STAT_INDEX.SOG) {
      const sogValue = newStats[STAT_INDEX.SOG];
      const shotsValue = newStats[STAT_INDEX.SHOTS];
      
      if (delta > 0 && sogValue > shotsValue) {
        newStats[STAT_INDEX.SHOTS] = sogValue;
      }
    }
    
    // Cascade GA changes to SAOG and SA
    if (col === STAT_INDEX.GA) {
      const gaValue = newStats[STAT_INDEX.GA];
      const savesValue = newStats[STAT_INDEX.SAVES];
      const saogValue = gaValue + savesValue;
      const saValue = newStats[STAT_INDEX.SA];
      
      newStats[STAT_INDEX.SAOG] = saogValue;
      
      if (delta < 0) {
        // Decreasing GA - also decrease SA if needed
        if (saogValue < saValue) {
          newStats[STAT_INDEX.SA] = saogValue;
        }
      } else {
        // Increasing GA - also increase SA if needed
        if (saogValue > saValue) {
          newStats[STAT_INDEX.SA] = saogValue;
        }
      }
    }
    
    // Cascade Saves changes to SAOG and SA
    if (col === STAT_INDEX.SAVES) {
      const savesValue = newStats[STAT_INDEX.SAVES];
      const gaValue = newStats[STAT_INDEX.GA];
      const saogValue = gaValue + savesValue;
      const saValue = newStats[STAT_INDEX.SA];
      
      newStats[STAT_INDEX.SAOG] = saogValue;
      
      if (delta < 0) {
        // Decreasing Saves - also decrease SA if needed
        if (saogValue < saValue) {
          newStats[STAT_INDEX.SA] = saogValue;
        }
      } else {
        // Increasing Saves - also increase SA if needed
        if (saogValue > saValue) {
          newStats[STAT_INDEX.SA] = saogValue;
        }
      }
    }
    
    return newStats;
  });

  // Update local state
  updateGame(selectedGameId, { stats: updatedStats });

  // Update in database
  const player = selectedGame.players[row];
  if (player.id) {
    const statNames = [
      'shots', 'shots_on_goal', 'goals', null, 'assists', 'turnovers',
      'faceoff_attempts', 'faceoff_wins', null,
      'ground_balls', 'caused_turnovers',
      'shots_against', null, 'goals_against', 'saves', null
    ];
    
    const updates = {};
    
    // Add the primary stat change
    if (statNames[col]) {
      updates[statNames[col]] = updatedStats[row][col];
    }
    
    // Add cascading updates for Goals
    if (col === STAT_INDEX.GOALS && delta > 0) {
      if (updatedStats[row][STAT_INDEX.GOALS] > selectedGame.stats[row][STAT_INDEX.SOG]) {
        updates['shots_on_goal'] = updatedStats[row][STAT_INDEX.SOG];
      }
      if (updatedStats[row][STAT_INDEX.GOALS] > selectedGame.stats[row][STAT_INDEX.SHOTS]) {
        updates['shots'] = updatedStats[row][STAT_INDEX.SHOTS];
      }
    }
    
    // Add cascading updates for SOG
    if (col === STAT_INDEX.SOG && updatedStats[row][STAT_INDEX.SOG] > selectedGame.stats[row][STAT_INDEX.SHOTS]) {
      updates['shots'] = updatedStats[row][STAT_INDEX.SHOTS];
    }
    
    // Add cascading updates for GA
    if (col === STAT_INDEX.GA) {
      updates['shots_against_on_goal'] = updatedStats[row][STAT_INDEX.SAOG];
      if (updatedStats[row][STAT_INDEX.SAOG] !== selectedGame.stats[row][STAT_INDEX.SA]) {
        updates['shots_against'] = updatedStats[row][STAT_INDEX.SA];
      }
    }
    
    // Add cascading updates for Saves
    if (col === STAT_INDEX.SAVES) {
      updates['shots_against_on_goal'] = updatedStats[row][STAT_INDEX.SAOG];
      if (updatedStats[row][STAT_INDEX.SAOG] !== selectedGame.stats[row][STAT_INDEX.SA]) {
        updates['shots_against'] = updatedStats[row][STAT_INDEX.SA];
      }
    }
    
    await updateGamePlayerInDb(player.id, updates);
  }
}, [selectedGame, selectedGameId, updateGame, updateGamePlayerInDb]);

// ADD THIS ENTIRE NEW FUNCTION HERE:

// The rest of your code continues here...

  // ============================================================================
  // PLAY DESIGN OPERATIONS
  // ============================================================================

  const handleFieldGrant = React.useCallback((e) => {
    const { locationX, locationY } = e.nativeEvent;
    setFieldTouchStart({ x: locationX, y: locationY });

    if (["cut", "pass", "pick"].includes(playMode)) {
      setDrawingAction({
        type: playMode,
        points: [{ x: locationX, y: locationY }],
      });
    }
  }, [playMode]);

const handleFieldMove = React.useCallback((e) => {
  const { locationX, locationY } = e.nativeEvent;
  
  setDrawingAction((prev) => {
    if (!prev) return prev;
    const pts = prev.points || [];
    const last = pts[pts.length - 1];
    const dx = locationX - last.x;
    const dy = locationY - last.y;
    const dist = Math.sqrt(dx * dx + dy * dy);
    
    // Increased from 2 to 5 for smoother capture
    if (dist < 5) return prev;
    
    return {
      ...prev,
      points: [...pts, { x: locationX, y: locationY }],
    };
  });
}, []);

  const handleFieldRelease = React.useCallback((e) => {
    const { locationX, locationY } = e.nativeEvent;

    if (drawingAction?.points?.length > 1) {
      setPlayActions((prev) => [
        ...prev,
        {
          id: Date.now().toString() + Math.random().toString(36).slice(2),
          type: drawingAction.type,
          points: drawingAction.points,
        },
      ]);
      setDrawingAction(null);
      setFieldTouchStart(null);
      return;
    }

    if (["offense", "defense"].includes(playMode) && fieldTouchStart) {
      const dx = locationX - fieldTouchStart.x;
      const dy = locationY - fieldTouchStart.y;
      const dist = Math.sqrt(dx * dx + dy * dy);

      if (dist < 10) {
        setPlayPieces((prev) => [
          ...prev,
          {
            id: Date.now().toString() + Math.random().toString(36).slice(2),
            x: locationX,
            y: locationY,
            side: playMode,
          },
        ]);
      }
    }

    setFieldTouchStart(null);
    setDrawingAction(null);
  }, [drawingAction, playMode, fieldTouchStart]);

  const clearPlayDesign = React.useCallback(() => {
    setPlayPieces([]);
    setPlayActions([]);
    setDrawingAction(null);
    setFieldTouchStart(null);
    setDragInfo(null);
  }, []);

  const resetPlayDesignState = React.useCallback(() => {
    clearPlayDesign();
    setFieldType("full");
    setPlayMode("offense");
    setPlayName("");
  }, [clearPlayDesign]);

const handleSavePlay = React.useCallback(async () => {
  if (!playName.trim() || (playPieces.length === 0 && playActions.length === 0)) return;

  try {
  const play = {
    name: playName.trim(),
    field_type: fieldType,
    pieces: playPieces,
    actions: playActions,
    team_id: currentTeam.id,   // <-- was user_id: user?.id
  };

    const { data, error } = await supabase
      .from('plays')
      .insert([play])
      .select()
      .single();

    if (error) throw error;

    setSavedPlays((prev) => [...prev, {
      id: data.id,
      name: data.name,
      fieldType: data.field_type,
      pieces: data.pieces,
      actions: data.actions,
    }]);
    
    setPlayName(""); // Clear the name after saving
    alert('Play saved successfully!');
  } catch (error) {
    console.error('Error saving play:', error);
    alert('Error saving play: ' + error.message);
  }
}, [playName, fieldType, playPieces, playActions]);

  const handleLoadPlay = React.useCallback((playId) => {
    const play = savedPlays.find((p) => p.id === playId);
    if (!play) return;

    setFieldType(play.fieldType || "full");
    setPlayPieces(play.pieces || []);
    setPlayActions(play.actions || []);
    setDrawingAction(null);
    setFieldTouchStart(null);
    setDragInfo(null);
  }, [savedPlays]);

  const handleDeletePlay = React.useCallback(async (playId) => {
    try {
      const { error } = await supabase
        .from('plays')
        .delete()
        .eq('id', playId);

      if (error) throw error;

      setSavedPlays((prev) => prev.filter((p) => p.id !== playId));
    } catch (error) {
      console.error('Error deleting play:', error);
    }
  }, []);

  // ============================================================================
  // DRAG OPERATIONS
  // ============================================================================

  const dragHandlers = React.useMemo(() => ({
    startPiece: (id, pageX, pageY) => {
      setDragInfo({ type: "piece", id, lastX: pageX, lastY: pageY });
    },
    movePiece: (id, pageX, pageY) => {
      setDragInfo((prev) => {
        if (!prev || prev.type !== "piece" || prev.id !== id) return prev;
        const dx = pageX - prev.lastX;
        const dy = pageY - prev.lastY;

        setPlayPieces((pieces) =>
          pieces.map((p) =>
            p.id === id ? { ...p, x: p.x + dx, y: p.y + dy } : p
          )
        );

        return { ...prev, lastX: pageX, lastY: pageY };
      });
    },
    startAction: (id, pageX, pageY) => {
      setDragInfo({ type: "action", id, lastX: pageX, lastY: pageY });
    },
    moveAction: (id, pageX, pageY) => {
      setDragInfo((prev) => {
        if (!prev || prev.type !== "action" || prev.id !== id) return prev;
        const dx = pageX - prev.lastX;
        const dy = pageY - prev.lastY;

        setPlayActions((actions) =>
          actions.map((a) => {
            if (a.id !== id) return a;
            return {
              ...a,
              points: a.points.map((pt) => ({
                x: pt.x + dx,
                y: pt.y + dy,
              })),
            };
          })
        );

        return { ...prev, lastX: pageX, lastY: pageY };
      });
    },
    end: () => setDragInfo(null),
  }), []);

  // ============================================================================
  // RENDER HELPERS
  // ============================================================================

const renderFreehandPath = React.useCallback((action, color, isPreview = false) => {
  const points = action.points || [];
  if (points.length < 2) return null;

  const { type } = action;
  
  // Smooth the path by reducing points
  const smoothedPoints = points.filter((pt, idx) => {
    if (idx === 0 || idx === points.length - 1) return true;
    const prev = points[idx - 1];
    const dx = pt.x - prev.x;
    const dy = pt.y - prev.y;
    const dist = Math.sqrt(dx * dx + dy * dy);
    return dist > 8; // Only keep points that are 8px apart
  });

  if (smoothedPoints.length < 2) return null;

  // Calculate arrow position and angle for the end
  const lastPoint = smoothedPoints[smoothedPoints.length - 1];
  const secondLast = smoothedPoints[smoothedPoints.length - 2];
  const dx = lastPoint.x - secondLast.x;
  const dy = lastPoint.y - secondLast.y;
  const angle = (Math.atan2(dy, dx) * 180) / Math.PI;

  return (
    <View
      style={[
        styles.actionAbsoluteWrapper,
        isPreview && { opacity: 0.6 },
      ]}
      pointerEvents={isPreview ? "none" : "auto"}
    >
      {/* Draw line segments */}
      {smoothedPoints.map((pt, idx) => {
        if (idx === smoothedPoints.length - 1) return null;
        const next = smoothedPoints[idx + 1];
        
        const segmentDx = next.x - pt.x;
        const segmentDy = next.y - pt.y;
        const length = Math.sqrt(segmentDx * segmentDx + segmentDy * segmentDy);
        const segmentAngle = (Math.atan2(segmentDy, segmentDx) * 180) / Math.PI;
        
        const strokeWidth = type === "pick" ? 3 : 4;
        
        return (
          <View
            key={idx}
            style={{
              position: "absolute",
              left: pt.x,
              top: pt.y,
              width: length,
              height: strokeWidth,
              backgroundColor: type === "pass" ? "transparent" : color,
              transform: [{ rotate: `${segmentAngle}deg` }],
              transformOrigin: "left center",
            }}
          >
            {/* Dashed line for pass */}
            {type === "pass" && (
              <View style={{ flexDirection: "row", height: strokeWidth }}>
                {Array.from({ length: Math.ceil(length / 15) }).map((_, i) => (
                  <View
                    key={i}
                    style={{
                      width: 10,
                      height: strokeWidth,
                      backgroundColor: color,
                      marginRight: 5,
                    }}
                  />
                ))}
              </View>
            )}
          </View>
        );
      })}
      
      {/* Arrow head for cut and pass */}
      {["cut", "pass"].includes(type) && (
        <View
          style={[
            styles.arrowHeadTriangle,
            {
              left: lastPoint.x - 8,
              top: lastPoint.y - 9,
              transform: [{ rotate: `${angle}deg` }],
            },
          ]}
        />
      )}
      
      {/* Bar for pick */}
      {type === "pick" && (
        <View
          style={[
            styles.arrowPickBar,
            {
              left: lastPoint.x - 2,
              top: lastPoint.y - 8,
              transform: [{ rotate: `${angle + 90}deg` }],
            },
          ]}
        />
      )}
    </View>
  );
}, []);

  // ============================================================================
  // LOADING SCREEN
  // ============================================================================

  if (loading || !currentTeam) {
    return (
      <View style={[styles.container, styles.centerContent]}>
        <ActivityIndicator size="large" color="#007AFF" />
        <Text style={styles.loadingText}>Loading...</Text>
      </View>
    );
  }

  // ============================================================================
  // SCREEN COMPONENTS
  // ============================================================================

if (screen === "home") {
  const homeTiles = [
    { key: "gameLog", icon: "📊", label: "Game Log", onPress: () => setScreen("gameLog") },
    { key: "roster", icon: "👥", label: "Roster", onPress: () => setScreen("roster") },
    { key: "playCalls", icon: "📖", label: "Play Calls", onPress: () => setScreen("playCalls") },
    { key: "playDesign", icon: "✏️", label: "Whiteboard", onPress: () => { resetPlayDesignState(); setScreen("playDesign"); } },
    { key: "schedule", icon: "📅", label: "Schedule and Statistics", onPress: () => setScreen("schedule") },
    { key: "teamManagement", icon: "⚙️", label: "Team Settings", onPress: () => setScreen("teamManagement") },
  ];

  return (
    <View style={styles.homeContainer}>
      <Text style={styles.homeTitle}>LaxIQ</Text>

      <View style={styles.homeGrid}>
        {homeTiles.map((tile) => (
          <Pressable key={tile.key} style={styles.homeTile} onPress={tile.onPress}>
            <View style={styles.homeTileCard}>
              <Text style={styles.homeTileIcon}>{tile.icon}</Text>
              <Text style={styles.homeTileLabel}>{tile.label}</Text>
            </View>
          </Pressable>
        ))}
      </View>
    </View>
  );
}

  if (screen === "teamManagement") {
    return (
      <TeamManagementScreen
        onBack={() => setScreen("home")}
        currentUser={currentUser}
        currentTeam={currentTeam}
        currentRole={currentRole}
      />
    );
  }

  if (screen === "playDesign") {
    return (
      <PlayDesignScreen
        onBack={() => setScreen("home")}
        fieldType={fieldType}
        setFieldType={setFieldType}
        playName={playName}
        setPlayName={setPlayName}
        handleSavePlay={handleSavePlay}
        playMode={playMode}
        setPlayMode={setPlayMode}
        savedPlays={savedPlays}
        handleLoadPlay={handleLoadPlay}
        handleDeletePlay={handleDeletePlay}
        handleFieldGrant={handleFieldGrant}
        handleFieldMove={handleFieldMove}
        handleFieldRelease={handleFieldRelease}
        playPieces={playPieces}
        playActions={playActions}
        drawingAction={drawingAction}
        dragHandlers={dragHandlers}
        renderFreehandPath={renderFreehandPath}
      />
    );
  }

if (screen === "roster") {
  return (
    <RosterScreen
      onBack={() => setScreen("home")}
      roster={roster}
      rosterForm={rosterForm}
      setRosterForm={setRosterForm}
      addRosterPlayer={addRosterPlayer}
      removeRosterPlayer={removeRosterPlayer}
      loadRoster={loadRoster}
      syncRosterToGames={syncRosterToGames}
      games={games}
      currentTeam={currentTeam}        // <-- ADD THIS
    />
  );
}

if (screen === "gameLog") {
  return (
    <GameLogScreen
      onBack={() => setScreen("home")}
      games={games}
      onSelectGame={(id) => {
        setSelectedGameId(id);
        setScreen("gameMenu");
      }}
    />
  );
}

if (screen === "schedule") {
  return (
    <ScheduleScreen
      onBack={() => setScreen("home")}
      games={games}
      showAddGameForm={showAddGameForm}
      setShowAddGameForm={setShowAddGameForm}
      gameForm={gameForm}
      setGameForm={setGameForm}
      createNewGame={createNewGame}
      roster={roster}
      loadGames={loadGames}
      syncRosterToGames={syncRosterToGames}
      currentTeam={currentTeam}        // <-- ADD THIS
      onSelectGame={(id) => {
        setSelectedGameId(id);
        setScreen("scheduleGameStats");
      }}
    />
  );
}

  if (screen === "scheduleGameStats" && selectedGame) {
    return (
      <GameStatsScreen
        onBack={() => setScreen("schedule")}
        backLabel="← Back to Schedule"
        selectedGame={selectedGame}
        togglePlayerIn={togglePlayerIn}
        handleStatChange={handleStatChange}
        updateGame={updateGame}
        updateGamePlayerInDb={updateGamePlayerInDb}
        selectedGameId={selectedGameId}
        readOnly
      />
    );
  }

  if (screen === "gameMenu" && selectedGame) {
    return (
      <GameMenuScreen
        onBack={() => setScreen("gameLog")}
        selectedGame={selectedGame}
        onNavigateToStats={() => setScreen("gameStats")}
      />
    );
  }

if (screen === "gameStats" && selectedGame) {
  return (
    <GameStatsScreen
      onBack={() => setScreen("gameMenu")}
      selectedGame={selectedGame}
      toggleGameTimer={toggleGameTimer}
      resetGameTimer={resetGameTimer}
      togglePlayerIn={togglePlayerIn}
      handleStatChange={handleStatChange}
      updateGame={updateGame}
      updateGamePlayerInDb={updateGamePlayerInDb}
      selectedGameId={selectedGameId}
    />
  );
}

if (screen === "playCalls") {
  return (
    <PlayCallsScreen
      onBack={() => setScreen("home")}
      savedPlays={savedPlays}
      handleLoadPlay={(playId) => {
        handleLoadPlay(playId);
        setScreen("playDesign");
      }}
      handleDeletePlay={handleDeletePlay}
    />
  );
}

  return null;
}

// ============================================================================
// SUB-COMPONENTS
// ============================================================================

const PlayDesignScreen = ({
  onBack,
  fieldType,
  setFieldType,
  playName,
  setPlayName,
  handleSavePlay,
  playMode,
  setPlayMode,
  savedPlays,
  handleLoadPlay,
  handleDeletePlay,
  handleFieldGrant,
  handleFieldMove,
  handleFieldRelease,
  playPieces,
  playActions,
  drawingAction,
  dragHandlers,
  renderFreehandPath,
}) => {
  const [showSaveModal, setShowSaveModal] = React.useState(false);
  const [tempPlayName, setTempPlayName] = React.useState("");
  const [showFieldDropdown, setShowFieldDropdown] = React.useState(false);
  const [showSideDropdown, setShowSideDropdown] = React.useState(false);
  const [showMoveDropdown, setShowMoveDropdown] = React.useState(false);
  const [showFormationDropdown, setShowFormationDropdown] = React.useState(false);
  const [selectedFormation, setSelectedFormation] = React.useState(null);

  const handleSaveClick = () => {
    setTempPlayName("");
    setShowSaveModal(true);
  };

  const handleConfirmSave = () => {
    if (tempPlayName.trim()) {
      setPlayName(tempPlayName.trim());
      setTimeout(() => {
        handleSavePlay();
        setShowSaveModal(false);
        setTempPlayName("");
      }, 100);
    }
  };

  // Close all dropdowns
  const closeAllDropdowns = () => {
    setShowFieldDropdown(false);
    setShowSideDropdown(false);
    setShowMoveDropdown(false);
    setShowFormationDropdown(false);
  };

  // Determine which mode is active
  const isSideMode = playMode === "offense" || playMode === "defense";
  const isMoveMode = playMode === "cut" || playMode === "pass" || playMode === "pick";

  // Formation definitions (positions relative to field - percentages)
  const formations = {
    "1-4-1": [
      { x: 0.5, y: 0.15, type: "M" },  // Top middie
      { x: 0.25, y: 0.35, type: "A" }, // Left attack
      { x: 0.5, y: 0.35, type: "A" },  // Center attack
      { x: 0.75, y: 0.35, type: "A" }, // Right attack
      { x: 0.35, y: 0.55, type: "M" }, // Left middie
      { x: 0.65, y: 0.55, type: "M" }, // Right middie
    ],
    "2-2-2": [
      { x: 0.35, y: 0.15, type: "M" }, // Top left middie
      { x: 0.65, y: 0.15, type: "M" }, // Top right middie
      { x: 0.35, y: 0.35, type: "A" }, // Mid left
      { x: 0.65, y: 0.35, type: "A" }, // Mid right
      { x: 0.35, y: 0.55, type: "M" }, // Bottom left
      { x: 0.65, y: 0.55, type: "M" }, // Bottom right
    ],
    "2-3-1": [
      { x: 0.35, y: 0.15, type: "M" }, // Top left
      { x: 0.65, y: 0.15, type: "M" }, // Top right
      { x: 0.25, y: 0.35, type: "A" }, // Mid left
      { x: 0.5, y: 0.35, type: "A" },  // Mid center
      { x: 0.75, y: 0.35, type: "A" }, // Mid right
      { x: 0.5, y: 0.55, type: "M" },  // Bottom center
    ],
    "1-3-2": [
      { x: 0.5, y: 0.15, type: "M" },  // Top center
      { x: 0.25, y: 0.35, type: "A" }, // Mid left
      { x: 0.5, y: 0.35, type: "A" },  // Mid center
      { x: 0.75, y: 0.35, type: "A" }, // Mid right
      { x: 0.35, y: 0.55, type: "M" }, // Bottom left
      { x: 0.65, y: 0.55, type: "M" }, // Bottom right
    ],
    "3-3": [
      { x: 0.25, y: 0.25, type: "M" }, // Top left
      { x: 0.5, y: 0.25, type: "M" },  // Top center
      { x: 0.75, y: 0.25, type: "M" }, // Top right
      { x: 0.25, y: 0.5, type: "A" },  // Bottom left
      { x: 0.5, y: 0.5, type: "A" },   // Bottom center
      { x: 0.75, y: 0.5, type: "A" },  // Bottom right
    ],
    "Open Set": [
      { x: 0.2, y: 0.2, type: "M" },   // Top left corner
      { x: 0.8, y: 0.2, type: "M" },   // Top right corner
      { x: 0.2, y: 0.5, type: "A" },   // Mid left
      { x: 0.8, y: 0.5, type: "A" },   // Mid right
      { x: 0.35, y: 0.65, type: "M" }, // Bottom left
      { x: 0.65, y: 0.65, type: "A" }, // Bottom right
    ],
    "2-1-3": [
      { x: 0.35, y: 0.15, type: "M" }, // Top left
      { x: 0.65, y: 0.15, type: "M" }, // Top right
      { x: 0.5, y: 0.35, type: "A" },  // Mid center
      { x: 0.25, y: 0.55, type: "M" }, // Bottom left
      { x: 0.5, y: 0.55, type: "A" },  // Bottom center
      { x: 0.75, y: 0.55, type: "A" }, // Bottom right
    ],
  };

  const handleFormationSelect = (formationName) => {
    setSelectedFormation(formationName);
    setShowFormationDropdown(false);
    
    // Get field dimensions (assuming playField ref or standard size)
    // You'll need to adjust these based on your actual field size
    const fieldWidth = 327;  // Adjust based on your field
    const fieldHeight = 600; // Adjust based on your field
    
    const formation = formations[formationName];
    const newPieces = formation.map((pos, idx) => ({
      id: Date.now().toString() + Math.random().toString(36).slice(2) + idx,
      x: pos.x * fieldWidth,
      y: pos.y * fieldHeight,
      side: "offense",
      playerType: pos.type, // M for middie, A for attack
    }));
    
    // Add the pieces using the parent's setter
    playPieces.length = 0; // Clear existing pieces
    newPieces.forEach(piece => {
      playPieces.push(piece);
    });
  };

  return (
    <View style={styles.container}>
      <Text style={styles.whiteboardTitle}>Whiteboard</Text>

      <Pressable onPress={onBack} style={styles.backLinkAbsolute}>
        <Text style={styles.backLink}>← Back</Text>
      </Pressable>

      {/* First row: Field and Formation */}
      <View style={styles.controlsRow}>
        {/* Field Dropdown */}
        <View style={styles.dropdownContainer}>
          <Text style={styles.dropdownLabelSmall}>Field</Text>
          <Pressable
            style={styles.dropdownCompact}
            onPress={() => {
              setShowFieldDropdown(!showFieldDropdown);
              setShowSideDropdown(false);
              setShowMoveDropdown(false);
              setShowFormationDropdown(false);
            }}
          >
            <Text style={styles.dropdownTextCompact}>
  {fieldType === "mid" ? "Faceoff" : fieldType.charAt(0).toUpperCase() + fieldType.slice(1)}
</Text>
            <Text style={styles.dropdownArrow}>▼</Text>
          </Pressable>
          {showFieldDropdown && (
            <View style={styles.dropdownMenu}>
              {["full", "half", "mid"].map((type) => (
  <Pressable
    key={type}
    style={[
      styles.dropdownMenuItem,
      fieldType === type && styles.dropdownMenuItemActive
    ]}
    onPress={() => {
      setFieldType(type);
      setShowFieldDropdown(false);
    }}
  >
    <Text style={[
      styles.dropdownMenuItemText,
      fieldType === type && styles.dropdownMenuItemTextActive
    ]}>
      {type === "mid" ? "Faceoff" : type.charAt(0).toUpperCase() + type.slice(1)}
    </Text>
  </Pressable>
))}
            </View>
          )}
        </View>

        {/* Formation Dropdown */}
        <View style={styles.dropdownContainer}>
          <Text style={styles.dropdownLabelSmall}>Formation</Text>
          <Pressable
            style={styles.dropdownCompact}
            onPress={() => {
              setShowFormationDropdown(!showFormationDropdown);
              setShowFieldDropdown(false);
              setShowSideDropdown(false);
              setShowMoveDropdown(false);
            }}
          >
            <Text style={styles.dropdownTextCompact}>
              {selectedFormation || "Select"}
            </Text>
            <Text style={styles.dropdownArrow}>▼</Text>
          </Pressable>
          {showFormationDropdown && (
            <View style={[styles.dropdownMenu, styles.dropdownMenuTall]}>
              <ScrollView style={styles.dropdownMenuScroll}>
                {Object.keys(formations).map((formName) => (
                  <Pressable
                    key={formName}
                    style={[
                      styles.dropdownMenuItem,
                      selectedFormation === formName && styles.dropdownMenuItemActive
                    ]}
                    onPress={() => handleFormationSelect(formName)}
                  >
                    <Text style={[
                      styles.dropdownMenuItemText,
                      selectedFormation === formName && styles.dropdownMenuItemTextActive
                    ]}>
                      {formName}
                    </Text>
                  </Pressable>
                ))}
              </ScrollView>
            </View>
          )}
        </View>
      </View>

      {/* Second row: Side, Move, and Save */}
      <View style={styles.controlsRow}>
        {/* Offense/Defense Dropdown - GREEN when active */}
        <View style={styles.dropdownContainer}>
          <Text style={styles.dropdownLabelSmall}>Side</Text>
          <Pressable
            style={[
              styles.dropdownCompact,
              isSideMode && styles.dropdownCompactActive
            ]}
            onPress={() => {
              setShowSideDropdown(!showSideDropdown);
              setShowFieldDropdown(false);
              setShowMoveDropdown(false);
              setShowFormationDropdown(false);
            }}
          >
            <Text style={[
              styles.dropdownTextCompact,
              isSideMode && styles.dropdownTextActive
            ]}>
              {(playMode === "offense" || playMode === "defense") 
                ? playMode.charAt(0).toUpperCase() + playMode.slice(1)
                : "Offense"}
            </Text>
            <Text style={[
              styles.dropdownArrow,
              isSideMode && styles.dropdownArrowActive
            ]}>▼</Text>
          </Pressable>
          {showSideDropdown && (
            <View style={styles.dropdownMenu}>
              {["offense", "defense"].map((side) => (
                <Pressable
                  key={side}
                  style={[
                    styles.dropdownMenuItem,
                    playMode === side && styles.dropdownMenuItemActive
                  ]}
                  onPress={() => {
                    setPlayMode(side);
                    setShowSideDropdown(false);
                  }}
                >
                  <Text style={[
                    styles.dropdownMenuItemText,
                    playMode === side && styles.dropdownMenuItemTextActive
                  ]}>
                    {side.charAt(0).toUpperCase() + side.slice(1)}
                  </Text>
                </Pressable>
              ))}
            </View>
          )}
        </View>

        {/* Movement Dropdown - GREEN when active */}
        <View style={styles.dropdownContainer}>
          <Text style={styles.dropdownLabelSmall}>Move</Text>
          <Pressable
            style={[
              styles.dropdownCompact,
              isMoveMode && styles.dropdownCompactActive
            ]}
            onPress={() => {
              setShowMoveDropdown(!showMoveDropdown);
              setShowFieldDropdown(false);
              setShowSideDropdown(false);
              setShowFormationDropdown(false);
            }}
          >
            <Text style={[
              styles.dropdownTextCompact,
              isMoveMode && styles.dropdownTextActive
            ]}>
              {(playMode === "cut" || playMode === "pass" || playMode === "pick")
                ? playMode.charAt(0).toUpperCase() + playMode.slice(1)
                : "Cut"}
            </Text>
            <Text style={[
              styles.dropdownArrow,
              isMoveMode && styles.dropdownArrowActive
            ]}>▼</Text>
          </Pressable>
          {showMoveDropdown && (
            <View style={styles.dropdownMenu}>
              {["cut", "pass", "pick"].map((move) => (
                <Pressable
                  key={move}
                  style={[
                    styles.dropdownMenuItem,
                    playMode === move && styles.dropdownMenuItemActive
                  ]}
                  onPress={() => {
                    setPlayMode(move);
                    setShowMoveDropdown(false);
                  }}
                >
                  <Text style={[
                    styles.dropdownMenuItemText,
                    playMode === move && styles.dropdownMenuItemTextActive
                  ]}>
                    {move.charAt(0).toUpperCase() + move.slice(1)}
                  </Text>
                </Pressable>
              ))}
            </View>
          )}
        </View>

        {/* Save Button */}
        <Pressable 
          style={styles.saveButtonCompact} 
          onPress={handleSaveClick}
        >
          <Text style={styles.saveButtonText}>💾 Save</Text>
        </Pressable>
      </View>

      {/* Mode indicator text */}
      <Text style={styles.modeIndicator}>
        {isSideMode ? "📍 Tap to place players" : "✏️ Draw player movements"}
      </Text>

      {/* Close dropdowns when touching outside */}
      {(showFieldDropdown || showSideDropdown || showMoveDropdown || showFormationDropdown) && (
        <Pressable 
          style={styles.dropdownOverlay}
          onPress={closeAllDropdowns}
        />
      )}

      {savedPlays.length > 0 && (
        <View style={styles.savedPlaysBox}>
          <Text style={styles.savedPlaysTitle}>Saved Plays</Text>
          <ScrollView horizontal showsHorizontalScrollIndicator={false}>
            {savedPlays.map((p) => (
              <View key={p.id} style={styles.savedPlayPill}>
                <Pressable onPress={() => handleLoadPlay(p.id)}>
                  <Text style={styles.savedPlayName}>{p.name}</Text>
                </Pressable>
                <Pressable
                  style={styles.savedPlayDelete}
                  onPress={() => handleDeletePlay(p.id)}
                >
                  <Text style={styles.savedPlayDeleteText}>×</Text>
                </Pressable>
              </View>
            ))}
          </ScrollView>
        </View>
      )}

      <View style={styles.playFieldWrapper}>
        <View
          style={styles.playField}
          onStartShouldSetResponder={() => true}
          onMoveShouldSetResponder={() => true}
          onResponderGrant={handleFieldGrant}
          onResponderMove={handleFieldMove}
          onResponderRelease={handleFieldRelease}
          onResponderTerminate={handleFieldRelease}
        >
          <FieldLines fieldType={fieldType} />

          {playPieces.map((piece) => (
            <PlayPiece
              key={piece.id}
              piece={piece}
              dragHandlers={dragHandlers}
            />
          ))}

          {playActions.map((a) => (
            <View
              key={a.id}
              style={{ position: "absolute" }}
              onStartShouldSetResponder={() => true}
              onResponderGrant={(e) => {
                const { pageX, pageY } = e.nativeEvent;
                dragHandlers.startAction(a.id, pageX, pageY);
              }}
              onResponderMove={(e) => {
                const { pageX, pageY } = e.nativeEvent;
                dragHandlers.moveAction(a.id, pageX, pageY);
              }}
              onResponderRelease={dragHandlers.end}
              onResponderTerminate={dragHandlers.end}
            >
              {renderFreehandPath(a, "#000000", false)}
            </View>
          ))}

          {drawingAction && renderFreehandPath(drawingAction, "#000000", true)}
        </View>
      </View>

      {/* Save Modal */}
      {showSaveModal && (
        <View style={styles.modalOverlay}>
          <View style={styles.modalContent}>
            <Text style={styles.modalTitle}>Save Play</Text>
            <Text style={styles.modalSubtitle}>Enter a name for this play</Text>
            
            <TextInput
              style={[styles.input, { marginTop: 12 }]}
              placeholder="Play name (e.g. 1-4-1 Sweep)"
              placeholderTextColor="#A0A0A5"
              value={tempPlayName}
              onChangeText={setTempPlayName}
              autoFocus
            />

            <Pressable
              style={[styles.primaryButton, { alignSelf: 'stretch', marginTop: 16 }]}
              onPress={handleConfirmSave}
            >
              <Text style={styles.primaryButtonText}>Save Play</Text>
            </Pressable>

            <Pressable
              style={[styles.secondaryButton, { alignSelf: 'stretch', marginTop: 8 }]}
              onPress={() => {
                setShowSaveModal(false);
                setTempPlayName("");
              }}
            >
              <Text style={styles.secondaryButtonText}>Cancel</Text>
            </Pressable>
          </View>
        </View>
      )}
    </View>
  );
};

const RosterScreen = ({
  onBack,
  roster,
  rosterForm,
  setRosterForm,
  addRosterPlayer,
  removeRosterPlayer,
  loadRoster,
  syncRosterToGames,
  games,
  currentTeam,
}) => {
  const [isImporting, setIsImporting] = React.useState(false);
  const [showImportMenu, setShowImportMenu] = React.useState(false);
  const [showAddPlayerForm, setShowAddPlayerForm] = React.useState(false);

  const handleImportCSV = async () => {
    setIsImporting(true);
    try {
      const result = await DocumentPicker.getDocumentAsync({
        type: ['text/csv', 'text/comma-separated-values', 'application/vnd.ms-excel'],
        copyToCacheDirectory: true,
      });

      if (result.type === 'cancel' || !result.assets || result.assets.length === 0) {
        setIsImporting(false);
        return;
      }

      const file = result.assets[0];
      const response = await fetch(file.uri);
      const text = await response.text();
      const lines = text.split('\n').filter(line => line.trim());
      
      if (lines.length === 0) {
        alert('CSV file is empty');
        setIsImporting(false);
        return;
      }

      const playersToAdd = [];

      const startIndex = lines[0].toLowerCase().includes('number') || 
                        lines[0].toLowerCase().includes('name') ? 1 : 0;

      for (let i = startIndex; i < lines.length; i++) {
        const line = lines[i].trim();
        if (!line) continue;

        const parts = line.split(',').map(p => p.trim().replace(/^["']|["']$/g, ''));
        
        // Expecting format: number, last name, first name, position
        if (parts.length >= 3) {
          playersToAdd.push({
            number: parts[0] || '',
            last_name: parts[1] || '',
            first_name: parts[2] || '',
            position: parts[3] || '',
            team_id: currentTeam.id,
          });
        }
      }

      if (playersToAdd.length === 0) {
        alert('No valid players found in CSV');
        setIsImporting(false);
        return;
      }

      // Check if roster already exists
      if (roster.length > 0) {
        if (Platform.OS === 'web') {
          const userChoice = window.confirm(
            `You have ${roster.length} existing players.\n\nOK = Add new players only\nCancel = Overwrite all players`
          );
          await processImport(userChoice ? 'add' : 'overwrite', playersToAdd);
        } else {
          const addUnique = window.confirm('Add new players only? (Cancel to overwrite all)');
          await processImport(addUnique ? 'add' : 'overwrite', playersToAdd);
        }
      } else {
        await processImport('add', playersToAdd);
      }

    } catch (error) {
      console.error('Error importing roster:', error);
      alert('Error importing roster: ' + error.message);
    } finally {
      setIsImporting(false);
      setShowImportMenu(false);
    }
  };

const processImport = async (action, playersToAdd) => {
    try {
      if (action === 'overwrite') {
        const { error: deleteError } = await supabase
          .from('roster')
          .delete()
          .eq('team_id', currentTeam.id);

        if (deleteError) throw deleteError;
      }

      let finalPlayersToAdd = playersToAdd;

      if (action === 'add') {
        const existingPlayers = roster.map(p => 
          `${p.number}|${p.lastName.toLowerCase()}|${p.firstName.toLowerCase()}`
        );
        finalPlayersToAdd = playersToAdd.filter(p => 
          !existingPlayers.includes(
            `${p.number}|${p.last_name.toLowerCase()}|${p.first_name.toLowerCase()}`
          )
        );

        if (finalPlayersToAdd.length === 0) {
          alert('No new players to add.');
          return;
        }
      }

      const { data, error } = await supabase
        .from('roster')
        .insert(finalPlayersToAdd)
        .select();

      if (error) throw error;

      const message = action === 'overwrite' 
        ? `Successfully replaced roster with ${data.length} players!`
        : `Successfully added ${data.length} new players!`;

      alert(message);
      
      // ADD THESE LINES: Reload roster and sync to games
      const updatedRoster = await loadRoster();
      await syncRosterToGames(updatedRoster, games);
    } catch (error) {
      throw error;
    }
  };

  return (
    <View style={styles.container}>
      <Pressable onPress={onBack}>
        <Text style={styles.backLink}>← Back to Home</Text>
      </Pressable>

      <Text style={styles.title}>Team Roster</Text>

      <ScrollView style={styles.gamesScrollView}>
        {roster.length === 0 ? (
          <Text style={styles.helperText}>
            No players in the roster yet. Add players using the buttons below.
          </Text>
        ) : (
          roster.map((player) => (
            <View key={player.id} style={styles.rosterRow}>
              <Text style={styles.rosterNumber}>
                {player.number ? `#${player.number}` : "—"}
              </Text>
              <View style={{ flex: 1 }}>
                <Text style={styles.rosterName}>
                  {player.lastName}, {player.firstName}
                </Text>
                {player.position && (
                  <Text style={styles.rosterPositionText}>{player.position}</Text>
                )}
              </View>
            </View>
          ))
        )}
      </ScrollView>

      {/* Floating Action Buttons */}
      <View style={styles.floatingButtonContainer}>
        <Pressable
          style={styles.floatingButton}
          onPress={() => {
            setShowAddPlayerForm(false);
            setShowImportMenu(true);
          }}
        >
          <Text style={styles.floatingButtonText}>📁 Upload Roster</Text>
        </Pressable>

        <Pressable
          style={styles.floatingButton}
          onPress={() => {
            setShowImportMenu(false);
            setShowAddPlayerForm(true);
          }}
        >
          <Text style={styles.floatingButtonText}>+ Add Player</Text>
        </Pressable>
      </View>

      {/* Import Menu Modal */}
      {showImportMenu && (
        <View style={styles.modalOverlay}>
          <View style={styles.modalContent}>
            <Text style={styles.modalTitle}>Upload Roster</Text>
            <Text style={styles.modalInstructions}>
              Upload a CSV file with the following format:
              {'\n\n'}
              <Text style={styles.monoText}>number, last name, first name, position</Text>
              {'\n\n'}
              Example:
              {'\n'}
              <Text style={styles.monoText}>12, Smith, John, Attack</Text>
              {'\n'}
              <Text style={styles.monoText}>7, Johnson, Sarah, Midfield</Text>
            </Text>

            <Pressable
              style={[styles.primaryButton, isImporting && styles.buttonDisabled, { alignSelf: 'stretch' }]}
              onPress={handleImportCSV}
              disabled={isImporting}
            >
              <Text style={styles.primaryButtonText}>
                {isImporting ? 'Importing...' : 'Choose CSV File'}
              </Text>
            </Pressable>

            <Pressable
              style={[styles.secondaryButton, { alignSelf: 'stretch', marginTop: 8 }]}
              onPress={() => setShowImportMenu(false)}
            >
              <Text style={styles.secondaryButtonText}>Cancel</Text>
            </Pressable>
          </View>
        </View>
      )}

      {/* Add Player Form Modal */}
      {showAddPlayerForm && (
        <View style={styles.modalOverlay}>
          <View style={styles.modalContent}>
            <Text style={styles.modalTitle}>Add New Player</Text>
            
            <TextInput
              style={styles.input}
              placeholder="Jersey Number (e.g. 12)"
              placeholderTextColor="#A0A0A5"
              keyboardType="numeric"
              value={rosterForm.number}
              onChangeText={(text) => setRosterForm({ ...rosterForm, number: text })}
            />

            <TextInput
              style={styles.input}
              placeholder="Last Name (e.g. Smith)"
              placeholderTextColor="#A0A0A5"
              value={rosterForm.lastName}
              onChangeText={(text) => setRosterForm({ ...rosterForm, lastName: text })}
            />

            <TextInput
              style={styles.input}
              placeholder="First Name (e.g. John)"
              placeholderTextColor="#A0A0A5"
              value={rosterForm.firstName}
              onChangeText={(text) => setRosterForm({ ...rosterForm, firstName: text })}
            />

            <TextInput
              style={styles.input}
              placeholder="Position (e.g. Attack, Midfield)"
              placeholderTextColor="#A0A0A5"
              value={rosterForm.position}
              onChangeText={(text) => setRosterForm({ ...rosterForm, position: text })}
            />

            <Pressable
              style={[styles.primaryButton, { alignSelf: 'stretch' }]}
              onPress={() => {
                addRosterPlayer();
                setShowAddPlayerForm(false);
              }}
            >
              <Text style={styles.primaryButtonText}>Add to Roster</Text>
            </Pressable>

            <Pressable
              style={[styles.secondaryButton, { alignSelf: 'stretch', marginTop: 8 }]}
              onPress={() => setShowAddPlayerForm(false)}
            >
              <Text style={styles.secondaryButtonText}>Cancel</Text>
            </Pressable>
          </View>
        </View>
      )}
    </View>
  );
};

const GameLogScreen = ({
  onBack,
  games,
  onSelectGame,
}) => {
  // Helper function to parse date string (M/D/YYYY) to Date object
  const parseDate = (dateStr) => {
    const [month, day, year] = dateStr.split('/').map(Number);
    return new Date(year, month - 1, day);
  };

  // Sort games by date (earliest first)
  const sortedGames = React.useMemo(() => {
    return [...games].sort((a, b) => {
      const dateA = parseDate(a.date);
      const dateB = parseDate(b.date);
      return dateA - dateB;
    });
  }, [games]);

  return (
    <View style={styles.container}>
      <Pressable onPress={onBack}>
        <Text style={styles.backLink}>← Back to Home</Text>
      </Pressable>

      <Text style={styles.title}>Game Log</Text>

      <ScrollView style={styles.gamesScrollView}>
        {sortedGames.length === 0 ? (
          <Text style={styles.helperText}>
            No games yet. Add games in the Schedule screen.
          </Text>
        ) : (
          sortedGames.map((g, index) => {
            const isHome = g.location === 'home';
            return (
              <Pressable
                key={g.id}
                style={[
                  styles.gameRow,
                  isHome ? styles.gameRowHome : styles.gameRowAway,
                ]}
                onPress={() => onSelectGame(g.id)}
              >
                <Text style={[
                  styles.gameRowTitle,
                  isHome ? styles.gameRowTitleHome : styles.gameRowTitleAway,
                ]}>
                  {isHome ? g.opponent : `@ ${g.opponent}`}
                </Text>
                <Text style={[
                  styles.gameRowSubtitle,
                  isHome ? styles.gameRowSubtitleHome : styles.gameRowSubtitleAway,
                ]}>
                  {g.date}
                </Text>
              </Pressable>
            );
          })
        )}
      </ScrollView>
    </View>
  );
};

const ScheduleScreen = ({
  onBack,
  games,
  showAddGameForm,
  setShowAddGameForm,
  gameForm,
  setGameForm,
  createNewGame,
  roster,
  loadGames,
  syncRosterToGames,
  currentTeam,
  onSelectGame,
}) => {
  const [isImporting, setIsImporting] = React.useState(false);
  const [showImportMenu, setShowImportMenu] = React.useState(false);

  const handleImportCSV = async () => {
    setIsImporting(true);
    try {
      const result = await DocumentPicker.getDocumentAsync({
        type: ['text/csv', 'text/comma-separated-values', 'application/vnd.ms-excel'],
        copyToCacheDirectory: true,
      });

      if (result.type === 'cancel' || !result.assets || result.assets.length === 0) {
        setIsImporting(false);
        return;
      }

      const file = result.assets[0];
      const response = await fetch(file.uri);
      const text = await response.text();
      const lines = text.split('\n').filter(line => line.trim());
      
      if (lines.length === 0) {
        alert('CSV file is empty');
        setIsImporting(false);
        return;
      }

      const gamesToAdd = [];

      const startIndex = lines[0].toLowerCase().includes('year') || 
                        lines[0].toLowerCase().includes('month') ||
                        lines[0].toLowerCase().includes('opponent') ? 1 : 0;

// Update this section in handleImportCSV
for (let i = startIndex; i < lines.length; i++) {
  const line = lines[i].trim();
  if (!line) continue;

  const parts = line.split(',').map(p => p.trim().replace(/^["']|["']$/g, ''));
  
  // Expecting format: year, month, day, opponent, location
  if (parts.length >= 4) {
    const year = parts[0];
    const month = parts[1];
    const day = parts[2];
    const opponent = parts[3];
    const location = parts[4]?.toLowerCase() || 'home';  // Default to home if not specified
    
    gamesToAdd.push({
      date: `${month}/${day}/${year}`,
      opponent: opponent,
      location: location === 'away' ? 'away' : 'home',  // Validate location
      team_id: currentTeam.id, 
    });
  }
}

      if (gamesToAdd.length === 0) {
        alert('No valid games found in CSV');
        setIsImporting(false);
        return;
      }

      if (games.length > 0) {
        if (Platform.OS === 'web') {
          const userChoice = window.confirm(
            `You have ${games.length} existing games.\n\nOK = Add new games only\nCancel = Overwrite all games`
          );
          await processImport(userChoice ? 'add' : 'overwrite', gamesToAdd);
        } else {
          const addUnique = window.confirm('Add new games only? (Cancel to overwrite all)');
          await processImport(addUnique ? 'add' : 'overwrite', gamesToAdd);
        }
      } else {
        await processImport('add', gamesToAdd);
      }

    } catch (error) {
      console.error('Error importing schedule:', error);
      alert('Error importing schedule: ' + error.message);
    } finally {
      setIsImporting(false);
      setShowImportMenu(false);
    }
  };

const processImport = async (action, gamesToAdd) => {
    try {
      if (action === 'overwrite') {
        const { error: deleteError } = await supabase
          .from('games')
  
          .delete()
          .eq('team_id', currentTeam.id); 

        if (deleteError) throw deleteError;
      }

      let finalGamesToAdd = gamesToAdd;

      if (action === 'add') {
        const existingGames = games.map(g => `${g.date}|${g.opponent.toLowerCase()}`);
        finalGamesToAdd = gamesToAdd.filter(g => 
          !existingGames.includes(`${g.date}|${g.opponent.toLowerCase()}`)
        );

        if (finalGamesToAdd.length === 0) {
          alert('No new games to add.');
          return;
        }
      }

      const { data: insertedGames, error: gamesError } = await supabase
        .from('games')
        .insert(finalGamesToAdd)
        .select();

      if (gamesError) throw gamesError;

      // Add roster players to the new games if roster exists
      if (roster.length > 0) {
        const allGamePlayers = [];
        
        for (const game of insertedGames) {
          const playersForGame = roster.map((p) => ({
            game_id: game.id,
            first_name: p.firstName,
            last_name: p.lastName,
            number: p.number,
            position: p.position,
          }));
          allGamePlayers.push(...playersForGame);
        }

        const { error: playersError } = await supabase
          .from('game_players')
          .insert(allGamePlayers);

        if (playersError) throw playersError;
      }

      const message = action === 'overwrite' 
        ? `Successfully replaced all games with ${insertedGames.length} new games!`
        : `Successfully added ${insertedGames.length} new games!`;
      
      alert(message);
      
      // ADD THESE LINES: Reload games and sync roster to any games that still don't have players
      const updatedGames = await loadGames();
      if (roster.length > 0) {
        await syncRosterToGames(roster, updatedGames);
      }
    } catch (error) {
      throw error;
    }
  };

  return (
    <View style={styles.container}>
      <Pressable onPress={onBack}>
        <Text style={styles.backLink}>← Back to Home</Text>
      </Pressable>

      <Text style={styles.title}>Schedule</Text>

      <ScrollView style={styles.gamesScrollView}>
  {games.length === 0 ? (
    <Text style={styles.helperText}>
      No games scheduled yet. Add games using the buttons below.
    </Text>
  ) : (
    games.map((g) => {
      const isHome = g.location === 'home';
      return (
        <Pressable
          key={g.id}
          style={[
            styles.scheduleRow,
            isHome ? styles.scheduleRowHome : styles.scheduleRowAway,
          ]}
          onPress={() => onSelectGame(g.id)}
        >
          <Text style={[
            styles.scheduleDate,
            isHome ? styles.scheduleDateHome : styles.scheduleDateAway,
          ]}>
            {g.date}
          </Text>
          <Text style={[
            styles.scheduleOpponent,
            isHome ? styles.scheduleOpponentHome : styles.scheduleOpponentAway,
          ]}>
            {isHome ? g.opponent : `@ ${g.opponent}`}
          </Text>
        </Pressable>
      );
    })
  )}
</ScrollView>

      {/* Floating Action Buttons */}
      <View style={styles.floatingButtonContainer}>
        <Pressable
          style={styles.floatingButton}
          onPress={() => {
            setShowAddGameForm(false);
            setShowImportMenu(true);
          }}
        >
          <Text style={styles.floatingButtonText}>📁 Upload Schedule</Text>
        </Pressable>

        <Pressable
          style={styles.floatingButton}
          onPress={() => {
            setShowImportMenu(false);
            setShowAddGameForm(true);
          }}
        >
          <Text style={styles.floatingButtonText}>+ Add New Game</Text>
        </Pressable>
      </View>

      {/* Import Menu Modal */}
      {showImportMenu && (
        <View style={styles.modalOverlay}>
          <View style={styles.modalContent}>
            <Text style={styles.modalTitle}>Upload Schedule</Text>
            <Text style={styles.modalInstructions}>
  Upload a CSV file with the following format:
  {'\n\n'}
  <Text style={styles.monoText}>year, month, day, opponent, location</Text>
  {'\n\n'}
  Example:
  {'\n'}
  <Text style={styles.monoText}>2025, 3, 15, North High School, home</Text>
  {'\n'}
  <Text style={styles.monoText}>2025, 3, 22, South Academy, away</Text>
</Text>

            <Pressable
              style={[styles.primaryButton, isImporting && styles.buttonDisabled, { alignSelf: 'stretch' }]}
              onPress={handleImportCSV}
              disabled={isImporting}
            >
              <Text style={styles.primaryButtonText}>
                {isImporting ? 'Importing...' : 'Choose CSV File'}
              </Text>
            </Pressable>

            <Pressable
              style={[styles.secondaryButton, { alignSelf: 'stretch', marginTop: 8 }]}
              onPress={() => setShowImportMenu(false)}
            >
              <Text style={styles.secondaryButtonText}>Cancel</Text>
            </Pressable>
          </View>
        </View>
      )}

      {/* Add Game Form Modal */}
{/* Add Game Form Modal */}
{showAddGameForm && (
  <View style={styles.modalOverlay}>
    <View style={styles.modalContent}>
      <Text style={styles.modalTitle}>Add New Game</Text>
      
      <View style={styles.dateInputRow}>
        <TextInput
          style={[styles.input, styles.dateInputSmall]}
          placeholder="Year"
          placeholderTextColor="#A0A0A5"
          keyboardType="numeric"
          maxLength={4}
          value={gameForm.year || ''}
          onChangeText={(text) => setGameForm({ ...gameForm, year: text })}
        />
        <TextInput
          style={[styles.input, styles.dateInputSmall]}
          placeholder="Month"
          placeholderTextColor="#A0A0A5"
          keyboardType="numeric"
          maxLength={2}
          value={gameForm.month || ''}
          onChangeText={(text) => setGameForm({ ...gameForm, month: text })}
        />
        <TextInput
          style={[styles.input, styles.dateInputSmall]}
          placeholder="Day"
          placeholderTextColor="#A0A0A5"
          keyboardType="numeric"
          maxLength={2}
          value={gameForm.day || ''}
          onChangeText={(text) => setGameForm({ ...gameForm, day: text })}
        />
      </View>

      <TextInput
        style={styles.input}
        placeholder="Opponent (e.g. North HS)"
        placeholderTextColor="#A0A0A5"
        value={gameForm.opponent}
        onChangeText={(text) => setGameForm({ ...gameForm, opponent: text })}
      />

      {/* ADD THIS LOCATION SELECTOR */}
      <View style={styles.locationSelectorRow}>
        <Text style={styles.locationLabel}>Location:</Text>
        <View style={styles.locationButtons}>
          <Pressable
            style={[
              styles.locationButton,
              gameForm.location === 'home' && styles.locationButtonActive,
            ]}
            onPress={() => setGameForm({ ...gameForm, location: 'home' })}
          >
            <Text
              style={[
                styles.locationButtonText,
                gameForm.location === 'home' && styles.locationButtonTextActive,
              ]}
            >
              Home
            </Text>
          </Pressable>
          <Pressable
            style={[
              styles.locationButton,
              gameForm.location === 'away' && styles.locationButtonActive,
            ]}
            onPress={() => setGameForm({ ...gameForm, location: 'away' })}
          >
            <Text
              style={[
                styles.locationButtonText,
                gameForm.location === 'away' && styles.locationButtonTextActive,
              ]}
            >
              Away
            </Text>
          </Pressable>
        </View>
      </View>

      <Pressable
        style={[styles.primaryButton, { alignSelf: 'stretch' }]}
        onPress={createNewGame}
      >
        <Text style={styles.primaryButtonText}>Save Game</Text>
      </Pressable>

      <Pressable
        style={[styles.secondaryButton, { alignSelf: 'stretch', marginTop: 8 }]}
        onPress={() => setShowAddGameForm(false)}
      >
        <Text style={styles.secondaryButtonText}>Cancel</Text>
      </Pressable>
    </View>
  </View>
)}

    </View>
  );
};

const GameMenuScreen = ({ onBack, selectedGame, onNavigateToStats }) => (
  <View style={styles.container}>
    <Pressable onPress={onBack}>
      <Text style={styles.backLink}>← Back to Game Log</Text>
    </Pressable>

    <Text style={styles.gameTitle}>vs {selectedGame.opponent}</Text>
    <Text style={styles.gameSubtitle}>{selectedGame.date}</Text>

    <View style={{ marginTop: 24 }}>
      <Pressable style={styles.bigButton} onPress={onNavigateToStats}>
        <Text style={styles.bigButtonText}>Stats</Text>
      </Pressable>

      <Pressable
        style={[styles.bigButton, { marginTop: 16 }]}
        onPress={() => {}}
      >
        <Text style={styles.bigButtonText}>Game Film (coming soon)</Text>
      </Pressable>
    </View>
  </View>
);

const PlayCallsScreen = ({
  onBack,
  savedPlays,
  handleLoadPlay,
  handleDeletePlay,
}) => {
  const [searchQuery, setSearchQuery] = React.useState("");
  const [selectedPlay, setSelectedPlay] = React.useState(null);

  const filteredPlays = React.useMemo(() => {
    if (!searchQuery.trim()) return savedPlays;
    
    const query = searchQuery.toLowerCase();
    return savedPlays.filter(play => 
      play.name.toLowerCase().includes(query)
    );
  }, [savedPlays, searchQuery]);

  return (
    <View style={styles.container}>
      <Pressable onPress={onBack}>
        <Text style={styles.backLink}>← Back to Home</Text>
      </Pressable>

      <Text style={styles.title}>Play Calls</Text>

      {savedPlays.length === 0 ? (
        <View style={styles.emptyStateContainer}>
          <Text style={styles.emptyStateTitle}>No Plays Yet</Text>
          <Text style={styles.emptyStateText}>
            Create plays in the Whiteboard and save them to build your playbook.
          </Text>
          <Pressable 
            style={[styles.primaryButton, { alignSelf: 'center', marginTop: 16 }]}
            onPress={onBack}
          >
            <Text style={styles.primaryButtonText}>Go to Whiteboard</Text>
          </Pressable>
        </View>
      ) : (
        <>
          <TextInput
            style={[styles.input, styles.searchInput]}
            placeholder="Search plays..."
            placeholderTextColor="#A0A0A5"
            value={searchQuery}
            onChangeText={setSearchQuery}
          />

          <ScrollView style={styles.playCallsScrollView}>
            {filteredPlays.map((play) => (
              <View key={play.id} style={styles.playCallCard}>
                <Pressable
                  style={styles.playCallCardContent}
                  onPress={() => setSelectedPlay(selectedPlay?.id === play.id ? null : play)}
                >
                  <View style={styles.playCallHeader}>
                    <Text style={styles.playCallName}>{play.name}</Text>
                    <Text style={styles.playCallFieldType}>
                      {play.fieldType === 'full' ? '⚡ Full Field' : 
                       play.fieldType === 'half' ? '🏃 Half Field' : 
                       '⚔️ Midfield'}
                    </Text>
                  </View>
                  
                  <View style={styles.playCallStats}>
                    <View style={styles.playCallStat}>
                      <Text style={styles.playCallStatLabel}>Players:</Text>
                      <Text style={styles.playCallStatValue}>
                        {play.pieces?.length || 0}
                      </Text>
                    </View>
                    <View style={styles.playCallStat}>
                      <Text style={styles.playCallStatLabel}>Actions:</Text>
                      <Text style={styles.playCallStatValue}>
                        {play.actions?.length || 0}
                      </Text>
                    </View>
                  </View>

                  {selectedPlay?.id === play.id && (
                    <View style={styles.playCallActions}>
                      <Pressable
                        style={[styles.primaryButton, { flex: 1, marginRight: 8 }]}
                        onPress={() => handleLoadPlay(play.id)}
                      >
                        <Text style={styles.primaryButtonText}>Open in Whiteboard</Text>
                      </Pressable>
                      <Pressable
                        style={[styles.destructiveButton, styles.deletePlayButton]}
                        onPress={() => {
                          if (Platform.OS === 'web') {
                            if (window.confirm(`Delete "${play.name}"?`)) {
                              handleDeletePlay(play.id);
                              setSelectedPlay(null);
                            }
                          } else {
                            if (confirm(`Delete "${play.name}"?`)) {
                              handleDeletePlay(play.id);
                              setSelectedPlay(null);
                            }
                          }
                        }}
                      >
                        <Text style={styles.destructiveButtonText}>Delete</Text>
                      </Pressable>
                    </View>
                  )}
                </Pressable>
              </View>
            ))}
          </ScrollView>
        </>
      )}
    </View>
  );
};

const GameStatsScreen = ({
  onBack,
  backLabel = "← Back to Game",
  selectedGame,
  toggleGameTimer,
  resetGameTimer,
  togglePlayerIn,
  handleStatChange,
  updateGame,
  updateGamePlayerInDb,
  selectedGameId,
  readOnly = false,
}) => {
  const [sortColumn, setSortColumn] = React.useState(null);
  const [sortDirection, setSortDirection] = React.useState('asc');
  const [showAssistModal, setShowAssistModal] = React.useState(false);
  const [goalScorerIndex, setGoalScorerIndex] = React.useState(null);
  const [correctionMode, setCorrectionMode] = React.useState(false);
const [selectedStatCell, setSelectedStatCell] = React.useState(null); // { row, col }
const [pendingCorrections, setPendingCorrections] = React.useState({});
const [showCorrectionConfirm, setShowCorrectionConfirm] = React.useState(false);
// NEW: Add ref for syncing scroll
const totalRowScrollRef = React.useRef(null);
  const handleSort = (column) => {
    if (sortColumn === column) {
      setSortDirection(sortDirection === 'asc' ? 'desc' : 'asc');
    } else {
      setSortColumn(column);
      setSortDirection('asc');
    }
  };

  // Calculate dynamic column widths based on content
  const columnWidths = React.useMemo(() => {
    if (selectedGame.players.length === 0) {
      return { number: 60, position: 80, name: 100 };
    }

    const charWidth = 8;
    const padding = 16;

    const longestNumber = Math.max(
      2,
      ...selectedGame.players.map(p => (p.number || '—').toString().length)
    );

    const longestPosition = Math.max(
      3,
      ...selectedGame.players.map(p => (p.position || '—').length)
    );

    const longestName = Math.max(
      6,
      ...selectedGame.players.map(p => p.lastName.length)
    );

    return {
      number: (longestNumber * charWidth) + padding,
      position: (longestPosition * charWidth) + padding,
      name: (longestName * charWidth) + padding,
    };
  }, [selectedGame.players]);

  const playerTimesSec = selectedGame.playerTimesSec || selectedGame.players.map(() => 0);
  const playerIn = selectedGame.playerIn || selectedGame.players.map(() => false);

const sortedPlayers = React.useMemo(() => {
  const playersWithIndex = selectedGame.players.map((p, idx) => ({ player: p, index: idx }));

  return playersWithIndex.sort((a, b) => {
    // FIRST: Always sort by In/Out status (In players first)
    const aIn = playerIn[a.index] ? 1 : 0;
    const bIn = playerIn[b.index] ? 1 : 0;
    
    if (aIn !== bIn) {
      return bIn - aIn; // In (1) comes before Out (0)
    }

    // SECOND: If no column selected, maintain original order within In/Out groups
    if (!sortColumn) {
      return 0;
    }

    // THIRD: Apply user's selected sort within the In/Out groups
    let aVal, bVal;

    if (sortColumn === 'name') {
      aVal = a.player.lastName.toLowerCase();
      bVal = b.player.lastName.toLowerCase();
    } else if (sortColumn === 'number') {
      aVal = parseInt(a.player.number) || 0;
      bVal = parseInt(b.player.number) || 0;
    } else if (sortColumn === 'position') {
      aVal = a.player.position?.toLowerCase() || '';
      bVal = b.player.position?.toLowerCase() || '';
    } else if (sortColumn === 'inOut') {
      // When explicitly sorting by In/Out, we already handled it above
      return 0;
    } else if (sortColumn === 'minutes') {
      aVal = playerTimesSec[a.index] || 0;
      bVal = playerTimesSec[b.index] || 0;
    } else if (sortColumn.startsWith('stat-')) {
      const statIndex = parseInt(sortColumn.split('-')[1]);
      aVal = selectedGame.stats[a.index][statIndex] || 0;
      bVal = selectedGame.stats[b.index][statIndex] || 0;
    }

    if (aVal < bVal) return sortDirection === 'asc' ? -1 : 1;
    if (aVal > bVal) return sortDirection === 'asc' ? 1 : -1;
    return 0;
  });
}, [selectedGame.players, selectedGame.stats, sortColumn, sortDirection, playerTimesSec, playerIn]);

const handleStatChangeWithAssist = React.useCallback((row, col, delta) => {
  // If this is a goal being added, show assist modal
  if (col === STAT_INDEX.GOALS && delta > 0) {
    setGoalScorerIndex(row);
    setShowAssistModal(true);
    return;
  }
  
  // Otherwise, call the original handler
  handleStatChange(row, col, delta);
}, [handleStatChange]);

  // ADD THIS FUNCTION HERE - INSIDE GameStatsScreen
const handleGoalWithAssist = React.useCallback(async (assistPlayerIndex) => {
  if (goalScorerIndex === null || !selectedGame) return;
  
  const updatedStats = selectedGame.stats.map((r, ri) => {
    const newStats = [...r];
    
    // Add goal to scorer
    if (ri === goalScorerIndex) {
      newStats[STAT_INDEX.GOALS] += 1;
      const goalsValue = newStats[STAT_INDEX.GOALS];
      const sogValue = newStats[STAT_INDEX.SOG];
      const shotsValue = newStats[STAT_INDEX.SHOTS];
      
      if (goalsValue > sogValue) {
        newStats[STAT_INDEX.SOG] = goalsValue;
      }
      if (goalsValue > shotsValue) {
        newStats[STAT_INDEX.SHOTS] = goalsValue;
      }
    }
    
    // Add assist to assister (if selected)
    if (assistPlayerIndex !== null && ri === assistPlayerIndex) {
      newStats[STAT_INDEX.ASSISTS] += 1;
    }
    
    return newStats;
  });
  
  // Update local state
  updateGame(selectedGameId, { stats: updatedStats });
  
  // Update database for scorer
  const scorer = selectedGame.players[goalScorerIndex];
  if (scorer.id) {
    await updateGamePlayerInDb(scorer.id, {
      goals: updatedStats[goalScorerIndex][STAT_INDEX.GOALS],
      shots_on_goal: updatedStats[goalScorerIndex][STAT_INDEX.SOG],
      shots: updatedStats[goalScorerIndex][STAT_INDEX.SHOTS],
    });
  }
  
  // Update database for assister (if applicable)
  if (assistPlayerIndex !== null) {
    const assister = selectedGame.players[assistPlayerIndex];
    if (assister.id) {
      await updateGamePlayerInDb(assister.id, {
        assists: updatedStats[assistPlayerIndex][STAT_INDEX.ASSISTS],
      });
    }
  }
  
  // Close modal
  setShowAssistModal(false);
  setGoalScorerIndex(null);
}, [goalScorerIndex, selectedGame, selectedGameId, updateGame, updateGamePlayerInDb]);
const handleCorrectionStatChange = React.useCallback((row, col, delta) => {
  setPendingCorrections(prev => {
    const key = `${row}-${col}`;
    const currentValue = selectedGame.stats[row][col];
    const pendingValue = prev[key] !== undefined ? prev[key] : currentValue;
    const newValue = Math.max(0, pendingValue + delta);
    
    // If newValue equals original, remove from pending
    if (newValue === currentValue) {
      const newPending = { ...prev };
      delete newPending[key];
      return newPending;
    }
    
    return { ...prev, [key]: newValue };
  });
}, [selectedGame]);

const applyCorrections = React.useCallback(async () => {
  if (Object.keys(pendingCorrections).length === 0) {
    setCorrectionMode(false);
    setSelectedStatCell(null);
    setShowCorrectionConfirm(false);
    return;
  }

  // Apply all pending corrections
  for (const [key, value] of Object.entries(pendingCorrections)) {
    const [row, col] = key.split('-').map(Number);
    await handleStatChange(row, col, value - selectedGame.stats[row][col]);
  }

  // Clear state
  setPendingCorrections({});
  setCorrectionMode(false);
  setSelectedStatCell(null);
  setShowCorrectionConfirm(false);
}, [pendingCorrections, selectedGame, handleStatChange]);

const cancelCorrections = React.useCallback(() => {
  setPendingCorrections({});
  setCorrectionMode(false);
  setSelectedStatCell(null);
  setShowCorrectionConfirm(false);
}, []);

const exitCorrectionMode = React.useCallback(() => {
  if (Object.keys(pendingCorrections).length > 0) {
    setShowCorrectionConfirm(true);
  } else {
    cancelCorrections();
  }
}, [pendingCorrections, cancelCorrections]);
  const isHome = selectedGame.location === 'home';

// NEW: Calculate total stats
const totalStats = React.useMemo(() => {
  return calculateTotalStats(selectedGame.stats);
}, [selectedGame.stats]);

// NEW: Calculate total time
const totalTime = React.useMemo(() => {
  return playerTimesSec.reduce((sum, time) => sum + time, 0);
}, [playerTimesSec]);

return (
  <View style={styles.container}>
    <Pressable onPress={onBack}>
      <Text style={styles.backLink}>{backLabel}</Text>
    </Pressable>

    {/* Game Header with Timer */}
{/* Game Header with Timer */}
    <View style={[styles.gameStatsHeader, styles.scheduleStatsHeaderContainer]}>
      <View style={styles.scheduleStatsHeaderRow}>
        {/* Game Info Badge */}
        <View style={[
          styles.gameHeaderBadge,
          isHome ? styles.gameHeaderBadgeHome : styles.gameHeaderBadgeAway,
          styles.scheduleStatsBadge,
        ]}>
          <Text style={[
            styles.gameHeaderOpponent,
            isHome ? styles.gameHeaderOpponentHome : styles.gameHeaderOpponentAway
          ]}>
            {isHome ? selectedGame.opponent : `@ ${selectedGame.opponent}`}
          </Text>
          <Text style={[
            styles.gameHeaderDate,
            isHome ? styles.gameHeaderDateHome : styles.gameHeaderDateAway
          ]}>
            {selectedGame.date}
          </Text>
        </View>

        {/* Correction Mode Toggle */}
        <Pressable
          style={[
            styles.correctionModeButton,
            correctionMode && styles.correctionModeButtonActive,
            styles.scheduleStatsCorrectionButton,
          ]}
          onPress={() => {
            if (correctionMode) {
              exitCorrectionMode();
            } else {
              setCorrectionMode(true);
            }
          }}
        >
          <Text style={[
            styles.correctionModeButtonText,
            correctionMode && styles.correctionModeButtonTextActive
          ]}>
            {correctionMode ? '✓ Exit Correction Mode' : '✎ Correction Mode'}
          </Text>
        </Pressable>
      </View>

      {/* Timer Section */}
      {!readOnly && (
        <View style={styles.timerSection}>
          <Text style={styles.timerValue}>
            {formatSeconds(selectedGame.timerElapsedSec || 0)}
          </Text>
          <View style={styles.timerControls}>
            <Pressable
              style={[
                styles.timerButton,
                styles.timerButtonStart,
                selectedGame.timerRunning && styles.timerButtonInactive
              ]}
              onPress={() => !selectedGame.timerRunning && toggleGameTimer()}
            >
              <Text style={[
                styles.timerButtonText,
                selectedGame.timerRunning && styles.timerButtonTextInactive
              ]}>
                Start
              </Text>
            </Pressable>
            <Pressable
              style={[
                styles.timerButton,
                styles.timerButtonStop,
                !selectedGame.timerRunning && styles.timerButtonInactive
              ]}
              onPress={() => selectedGame.timerRunning && toggleGameTimer()}
            >
              <Text style={[
                styles.timerButtonText,
                !selectedGame.timerRunning && styles.timerButtonTextInactive
              ]}>
                Stop
              </Text>
            </Pressable>
            <Pressable
              style={styles.timerButtonReset}
              onPress={resetGameTimer}
            >
              <Text style={styles.timerButtonResetText}>Reset</Text>
            </Pressable>
          </View>
        </View>
      )}
    </View>

    {/* Stats Table */}
{/* Stats Table */}
{selectedGame.players.length === 0 ? (
  <Text style={styles.helperText}>
    No players in this game. Go to the Roster screen to add players, and they'll automatically sync to your games.
  </Text>
) : (
  <View style={styles.statsContainer}>
    <ScrollView 
      horizontal 
      style={styles.statsScrollView}
      contentContainerStyle={{ paddingBottom: 80 }}
      ref={(scrollView) => {
        // Store reference for syncing
        if (scrollView && !scrollView._totalScrollRef) {
          scrollView._totalScrollRef = React.createRef();
        }
      }}
      onScroll={(e) => {
        // Sync total row scroll with main table scroll
        const offsetX = e.nativeEvent.contentOffset.x;
        if (totalRowScrollRef.current) {
          totalRowScrollRef.current.scrollTo({ x: offsetX, animated: false });
        }
      }}
      scrollEventThrottle={16}
    >
      <View>
        <StatsTableHeader
          sortColumn={sortColumn}
          sortDirection={sortDirection}
          onSort={handleSort}
          columnWidths={columnWidths}
          readOnly={readOnly}
        />
        {sortedPlayers.map(({ player, index: originalIndex }) => (
          <StatsTableRow
            key={`${player.id}-${originalIndex}`}
            player={player}
            rowIndex={originalIndex}
            stats={selectedGame.stats[originalIndex]}
            playerTime={playerTimesSec[originalIndex]}
            isPlayerIn={playerIn[originalIndex]}
            togglePlayerIn={togglePlayerIn}
            handleStatChange={handleStatChangeWithAssist}
            columnWidths={columnWidths}
            correctionMode={correctionMode}
            selectedStatCell={selectedStatCell}
            setSelectedStatCell={setSelectedStatCell}
            pendingCorrections={pendingCorrections}
            handleCorrectionStatChange={handleCorrectionStatChange}
            readOnly={readOnly}
          />
        ))}
      </View>
    </ScrollView>

    {/* Pinned Total Row */}
{/* Pinned Total Row */}
    <View style={styles.totalRowContainer}>
      <ScrollView 
        horizontal 
        showsHorizontalScrollIndicator={false}
        ref={totalRowScrollRef}
        scrollEnabled={false}
      >
        <View style={[styles.row, styles.totalRow]}>
          <View style={[styles.statCell, { width: columnWidths.number }]} />
          <View style={[styles.statCell, { width: columnWidths.position }]} />
          <View style={[styles.statCell, { width: columnWidths.name }]} />
          {!readOnly && <View style={styles.statCell} />}
          <View style={styles.statCell} />
          {totalStats.map((value, colIndex) => (
            <View key={colIndex} style={styles.statCell}>
              <Text style={styles.totalText}>
                {colIndex === STAT_INDEX.SHOT_PCT || 
                 colIndex === STAT_INDEX.FO_PCT || 
                 colIndex === STAT_INDEX.SAVE_PCT
                  ? `${value}%`
                  : value}
              </Text>
            </View>
          ))}
        </View>
      </ScrollView>
    </View>
  </View>
)}
     {/* ADD THE ASSIST MODAL HERE - BEFORE THE CLOSING </View> */}
      {showAssistModal && (
        <View style={styles.modalOverlay}>
          <View style={styles.modalContent}>
            <Text style={styles.modalTitle}>Who assisted?</Text>
            <Text style={styles.modalSubtitle}>
              Goal by: {selectedGame.players[goalScorerIndex]?.lastName}
            </Text>
            
            <ScrollView style={styles.assistPlayerList}>
              <Pressable
                style={styles.assistPlayerOption}
                onPress={() => handleGoalWithAssist(null)}
              >
                <Text style={styles.assistPlayerText}>No Assist (Unassisted Goal)</Text>
              </Pressable>
              
              {selectedGame.players
                .map((player, index) => ({ player, index }))
                .filter(({ index }) => 
                  index !== goalScorerIndex && 
                  playerIn[index]
                )
                .map(({ player, index }) => (
                  <Pressable
                    key={index}
                    style={styles.assistPlayerOption}
                    onPress={() => handleGoalWithAssist(index)}
                  >
                    <Text style={styles.assistPlayerText}>
                      #{player.number || '—'} {player.lastName}
                    </Text>
                  </Pressable>
                ))}
            </ScrollView>
            
            <Pressable
              style={[styles.secondaryButton, { alignSelf: 'stretch', marginTop: 12 }]}
              onPress={() => {
                setShowAssistModal(false);
                setGoalScorerIndex(null);
              }}
            >
              <Text style={styles.secondaryButtonText}>Cancel</Text>
            </Pressable>
          </View>
        </View>
      )}
      {/* Correction Confirmation Modal */}
      {showCorrectionConfirm && (
        <View style={styles.modalOverlay}>
          <View style={styles.modalContent}>
            <Text style={styles.modalTitle}>Apply Corrections?</Text>
            <Text style={styles.modalSubtitle}>
              You have {Object.keys(pendingCorrections).length} pending stat correction{Object.keys(pendingCorrections).length !== 1 ? 's' : ''}
            </Text>
            
            <Pressable
              style={[styles.primaryButton, { alignSelf: 'stretch', marginTop: 16 }]}
              onPress={applyCorrections}
            >
              <Text style={styles.primaryButtonText}>Yes, Apply Changes</Text>
            </Pressable>
            
            <Pressable
              style={[styles.secondaryButton, { alignSelf: 'stretch', marginTop: 8 }]}
              onPress={cancelCorrections}
            >
              <Text style={styles.secondaryButtonText}>No, Discard Changes</Text>
            </Pressable>
          </View>
        </View>
      )}
  </View>
);
};

const StatsTableHeader = ({ sortColumn, sortDirection, onSort, columnWidths, readOnly = false }) => (
  <View>
    {/* Category Headers */}
    <View style={[styles.row, styles.categoryHeaderRow]}>
      <View style={[styles.statCell, { width: columnWidths.number }]} />
      <View style={[styles.statCell, { width: columnWidths.position }]} />
      <View style={[styles.statCell, { width: columnWidths.name }]} />
      {!readOnly && <View style={styles.statCell} />}
      <View style={styles.statCell} />

      {/* Offensive */}
      <View style={[styles.categoryHeader, { width: STAT_COL_WIDTH * OFFENSIVE_STATS.length }]}>
        <Text style={styles.categoryHeaderText}>Offensive</Text>
      </View>
      
      {/* Faceoff */}
      <View style={[styles.categoryHeader, { width: STAT_COL_WIDTH * FACEOFF_STATS.length }]}>
        <Text style={styles.categoryHeaderText}>Faceoff</Text>
      </View>
      
      {/* Defensive */}
      <View style={[styles.categoryHeader, { width: STAT_COL_WIDTH * DEFENSIVE_STATS.length }]}>
        <Text style={styles.categoryHeaderText}>Defensive</Text>
      </View>
      
      {/* Goalie */}
      <View style={[styles.categoryHeader, { width: STAT_COL_WIDTH * GOALIE_STATS.length }]}>
        <Text style={styles.categoryHeaderText}>Goalie</Text>
      </View>
    </View>

    {/* Column Headers */}
    <View style={[styles.row, styles.headerRow]}>
      <Pressable 
        style={[styles.statCell, { width: columnWidths.number }]}
        onPress={() => onSort('number')}
      >
        <Text style={styles.headerText}>
          # {sortColumn === 'number' && (sortDirection === 'asc' ? '↑' : '↓')}
        </Text>
      </Pressable>
      <Pressable 
        style={[styles.statCell, { width: columnWidths.position }]}
        onPress={() => onSort('position')}
      >
        <Text style={styles.headerText}>
          Pos {sortColumn === 'position' && (sortDirection === 'asc' ? '↑' : '↓')}
        </Text>
      </Pressable>
      <Pressable 
        style={[styles.statCell, { width: columnWidths.name }]}
        onPress={() => onSort('name')}
      >
        <Text style={styles.headerText}>
          Player {sortColumn === 'name' && (sortDirection === 'asc' ? '↑' : '↓')}
        </Text>
      </Pressable>
      {!readOnly && (
        <Pressable
          style={styles.statCell}
          onPress={() => onSort('inOut')}
        >
          <Text style={styles.headerText}>
            In/Out {sortColumn === 'inOut' && (sortDirection === 'asc' ? '↑' : '↓')}
          </Text>
        </Pressable>
      )}
      <Pressable
        style={styles.statCell}
        onPress={() => onSort('minutes')}
      >
        <Text style={styles.headerText}>
          Min {sortColumn === 'minutes' && (sortDirection === 'asc' ? '↑' : '↓')}
        </Text>
      </Pressable>
      {STAT_HEADERS.map((h, index) => (
        <Pressable 
          key={h} 
          style={styles.statCell}
          onPress={() => onSort(`stat-${index}`)}
        >
          <Text style={styles.headerText}>
            {h} {sortColumn === `stat-${index}` && (sortDirection === 'asc' ? '↑' : '↓')}
          </Text>
        </Pressable>
      ))}
    </View>
  </View>
);

const StatsTableRow = ({
  player,
  rowIndex,
  stats,
  playerTime,
  isPlayerIn,
  togglePlayerIn,
  handleStatChange,
  columnWidths,
  correctionMode,
  selectedStatCell,
  setSelectedStatCell,
  pendingCorrections,
  handleCorrectionStatChange,
  readOnly = false,
}) => {
  // Calculate derived stats
  const calculatedStats = [...stats];
  
  // Apply pending corrections
  Object.entries(pendingCorrections).forEach(([key, value]) => {
    const [row, col] = key.split('-').map(Number);
    if (row === rowIndex) {
      calculatedStats[col] = value;
    }
  });
  
  // Shot %
  const shots = calculatedStats[STAT_INDEX.SHOTS] || 0;
  const goals = calculatedStats[STAT_INDEX.GOALS] || 0;
  calculatedStats[STAT_INDEX.SHOT_PCT] = shots > 0 ? Math.round((goals / shots) * 100) : 0;
  
  // FO %
  const foAtt = calculatedStats[STAT_INDEX.FO_ATT] || 0;
  const foWin = calculatedStats[STAT_INDEX.FO_WIN] || 0;
  calculatedStats[STAT_INDEX.FO_PCT] = foAtt > 0 ? Math.round((foWin / foAtt) * 100) : 0;
  
  // SAOG (calculated as GA + Saves)
  const ga = calculatedStats[STAT_INDEX.GA] || 0;
  const saves = calculatedStats[STAT_INDEX.SAVES] || 0;
  calculatedStats[STAT_INDEX.SAOG] = ga + saves;
  
  // Save %
  const saog = calculatedStats[STAT_INDEX.SAOG];
  calculatedStats[STAT_INDEX.SAVE_PCT] = saog > 0 ? Math.round((saves / saog) * 100) : 0;

  // Define which stats are non-editable
  const isNonEditable = (index) => {
    return index === STAT_INDEX.SHOT_PCT || 
           index === STAT_INDEX.FO_PCT || 
           index === STAT_INDEX.SAOG ||
           index === STAT_INDEX.SAVE_PCT;
  };

  const hasPendingChange = (col) => {
    return pendingCorrections[`${rowIndex}-${col}`] !== undefined;
  };

  return (
    <View style={styles.row}>
      <View style={[styles.statCell, { width: columnWidths.number }]}>
        <Text style={styles.smallText}>{player.number || "—"}</Text>
      </View>
      <View style={[styles.statCell, { width: columnWidths.position }]}>
        <Text style={styles.smallText}>{player.position || "—"}</Text>
      </View>
      <View style={[styles.statCell, { width: columnWidths.name }]}>
        <Text style={styles.smallText}>{player.lastName}</Text>
      </View>

      {!readOnly && (
        <View style={styles.statCell}>
          <Pressable
            style={[
              styles.inOutButton,
              isPlayerIn && styles.inOutButtonActive,
            ]}
            onPress={() => togglePlayerIn(rowIndex)}
          >
            <Text
              style={[
                styles.inOutButtonText,
                isPlayerIn && styles.inOutButtonTextActive,
              ]}
            >
              {isPlayerIn ? "In" : "Out"}
            </Text>
          </Pressable>
        </View>
      )}

      <View style={styles.statCell}>
        <Text style={styles.smallText}>{formatSeconds(playerTime)}</Text>
      </View>

      {calculatedStats.map((value, colIndex) => (
        <View key={colIndex} style={styles.statCell}>
          {isNonEditable(colIndex) ? (
            <View style={styles.statReadOnlyContainer}>
              <Text style={styles.statReadOnlyValue}>
                {colIndex === STAT_INDEX.SHOT_PCT || colIndex === STAT_INDEX.FO_PCT || colIndex === STAT_INDEX.SAVE_PCT
                  ? `${value}%`
                  : value}
              </Text>
            </View>
          ) : correctionMode ? (
            // CORRECTION MODE: Click to reveal buttons
            <Pressable
              style={[
                styles.statCorrectionCell,
                hasPendingChange(colIndex) && styles.statCorrectionCellPending
              ]}
              onPress={() => setSelectedStatCell({ row: rowIndex, col: colIndex })}
            >
              {selectedStatCell?.row === rowIndex && selectedStatCell?.col === colIndex ? (
                <View style={styles.statControlRow}>
                  <Pressable
                    style={styles.statButton}
                    onPress={() => handleCorrectionStatChange(rowIndex, colIndex, -1)}
                  >
                    <Text style={styles.statButtonText}>−</Text>
                  </Pressable>
                  <Text style={[
                    styles.statValue,
                    hasPendingChange(colIndex) && styles.statValuePending
                  ]}>
                    {value}
                  </Text>
                  <Pressable
                    style={styles.statButton}
                    onPress={() => handleCorrectionStatChange(rowIndex, colIndex, 1)}
                  >
                    <Text style={styles.statButtonText}>+</Text>
                  </Pressable>
                </View>
              ) : (
                <Text style={[
                  styles.statValue,
                  hasPendingChange(colIndex) && styles.statValuePending
                ]}>
                  {value}
                </Text>
              )}
            </Pressable>
          ) : readOnly ? (
            // READ-ONLY MODE: no stat input outside correction mode
            <Text style={styles.statValue}>{value}</Text>
          ) : (
            // NORMAL MODE: Only + button, only for "In" players
            isPlayerIn ? (
              <View style={styles.statControlRow}>
                <Pressable
                  style={styles.statButtonSingle}
                  onPress={() => handleStatChange(rowIndex, colIndex, 1)}
                >
                  <Text style={styles.statButtonText}>+</Text>
                </Pressable>
                <Text style={styles.statValue}>{value}</Text>
              </View>
            ) : (
              <Text style={[styles.statValue, styles.statValueDisabled]}>{value}</Text>
            )
          )}
        </View>
      ))}
    </View>
  );
};
const FieldLines = ({ fieldType }) => {
  if (fieldType === "full") {
    // Full field: 110 yards long × 60 yards wide (11:6 ratio)
    // Using percentages based on actual lacrosse field dimensions
    return (
      <>
        {/* Midfield line (50% - center) */}
        <View style={styles.fullHorizontalMidline} />
        
        {/* Restraining lines (20 yards from each goal) */}
        {/* Top restraining line: 20/110 = 18.18% from top */}
        <View style={styles.fullHorizontalTopRestraining} />
        
        {/* Bottom restraining line: 20/110 = 18.18% from bottom */}
        <View style={styles.fullHorizontalBottomRestraining} />
        
        {/* Wing area lines (10 yards on each side of center) */}
        {/* Left wing: 10/110 = 9.09% from center */}
        <View style={styles.fullWingLineLeft} />
        
        {/* Right wing: 10/110 = 9.09% from center */}

         <View style={styles.fullWingLineRight} />
        <View style={styles.fullAlleyTopLeft} />

         <View style={styles.fullAlleyTopRight} />

          <View style={styles.fullAlleyBottomLeft} />

           <View style={styles.fullAlleyBottomRight} />

           
        
        {/* Creases (9 yard radius, positioned 15 yards from end line) */}
        {/* Top crease: 15/110 = 13.64% from top */}
        <View style={styles.fullCreaseTop} />
        
        {/* Bottom crease: 15/110 = 13.64% from bottom */}
        <View style={styles.fullCreaseBottom} />
        
        {/* GLE lines (2 yards behind crease = 17 yards from end line) */}
        {/* Top GLE: 17/110 = 15.45% from top */}
        
        
        {/* Bottom GLE: 17/110 = 15.45% from bottom */}
        
        
        {/* End lines */}
        <View style={styles.fullEndLineTop} />
        <View style={styles.fullEndLineBottom} />
        
        {/* Triangles in creases (goals) */}
        <View style={styles.fullCreaseTriangleTop} />
        <View style={styles.fullCreaseTriangleBottom} />
      </>
    );
  }

  if (fieldType === "half") {
    // Half field: Just the attack/offensive half (55 yards × 60 yards)
    // Shows from end line to midfield
    return (
      <>
        {/* Midfield line (at top - 0%) */}
        <View style={styles.halfMidline} />
        
        {/* Restraining line (20/55 = 36.36% from top) */}
        <View style={styles.halfRestraining} />
        
        {/* Crease (15/55 = 27.27% from bottom) */}
        <View style={styles.halfCrease} />
        
        {/* GLE line (17/55 = 30.91% from bottom) */}
        <View style={styles.halfGLE} />
        
        {/* End line (at bottom) */}
        <View style={styles.halfEndLine} />
        
        {/* Triangle in crease */}
        <View style={styles.halfCreaseTriangle} />
      </>
    );
  }

  if (fieldType === "mid") {
    // Faceoff/Mid field: Just the center area (30 yards × 60 yards)
    // Shows 15 yards on each side of center
    return (
      <>
        {/* Center X line (vertical midline) */}
        <View style={styles.midVerticalMidline} />
        
        {/* Wing area lines (10 yards from center = 33.33% from center) */}
        <View style={styles.midWingLineLeft} />
        <View style={styles.midWingLineRight} />
        
        {/* Horizontal bounds (15 yards on each side) */}
        <View style={styles.midTopBound} />
        <View style={styles.midBottomBound} />
      </>
    );
  }

  return null;
};

const PlayPiece = ({ piece, dragHandlers }) => {
  // Determine label based on piece type
  let label;
  if (piece.side === "offense") {
    // If playerType exists (from formation), show M or A, otherwise X
    label = piece.playerType || "X";
  } else {
    label = "O";
  }
  const color = piece.side === "offense" ? "#111827" : "#FBBF24";

  return (
    <View
      style={[
        styles.playPieceWrapper,
        { left: piece.x - 14, top: piece.y - 14 },
      ]}
      onStartShouldSetResponder={() => true}
      onResponderGrant={(e) => {
        const { pageX, pageY } = e.nativeEvent;
        dragHandlers.startPiece(piece.id, pageX, pageY);
      }}
      onResponderMove={(e) => {
        const { pageX, pageY } = e.nativeEvent;
        dragHandlers.movePiece(piece.id, pageX, pageY);
      }}
      onResponderRelease={dragHandlers.end}
      onResponderTerminate={dragHandlers.end}
    >
      <Text style={[styles.playPieceText, { color }]}>{label}</Text>
    </View>
  );
};

// ============================================================================
// STYLES
// ============================================================================

const styles = StyleSheet.create({
  // ============================================================================
  // GENERAL / LAYOUT STYLES
  // ============================================================================
  
  container: {
    flex: 1,
    paddingTop: 50,
    paddingHorizontal: 16,
    backgroundColor: "#F2F2F7",
  },
  
  centerContent: {
    justifyContent: "center",
    alignItems: "center",
  },
  
  loadingText: {
    marginTop: 16,
    fontSize: 16,
    color: "#6B7280",
  },
  
  title: {
    fontSize: 26,
    fontWeight: "bold",
    textAlign: "center",
    marginBottom: 24,
    color: "#111827",
  },
  
  sectionTitle: {
    fontSize: 18,
    fontWeight: "600",
    marginBottom: 8,
    color: "#111827",
  },
  
  backLink: {
    color: "#007AFF",
    fontSize: 16,
    marginTop: 16,
    marginBottom: 8,
  },
  
  helperText: {
    textAlign: "center",
    fontStyle: "italic",
    color: "#6B7280",
    marginTop: 10,
  },
  
  helperTextSmall: {
    fontSize: 12,
    color: "#6B7280",
    fontStyle: "italic",
    marginTop: 4,
  },
  
  smallText: {
    fontSize: 12,
    textAlign: "center",
    color: "#4B5563",
  },
  
  // ============================================================================
  // HOME SCREEN GRID
  // ============================================================================

  homeContainer: {
    flex: 1,
    paddingTop: 50,
    backgroundColor: "#F2F2F7",
  },

  homeTitle: {
    fontSize: 26,
    fontWeight: "bold",
    textAlign: "center",
    marginBottom: 16,
    color: "#111827",
  },

  homeGrid: {
    flex: 1,
    flexDirection: "row",
    flexWrap: "wrap",
  },

  homeTile: {
    width: "50%",
    height: "33.33%",
    padding: 8,
  },

  homeTileCard: {
    flex: 1,
    backgroundColor: "#007AFF",
    borderRadius: 24,
    borderWidth: 3,
    borderColor: "#000000",
    justifyContent: "center",
    alignItems: "center",
    shadowColor: "#000",
    shadowOpacity: 0.2,
    shadowOffset: { width: 0, height: 3 },
    shadowRadius: 5,
    elevation: 4,
  },

  homeTileIcon: {
    fontSize: 56,
    marginBottom: 10,
  },

  homeTileLabel: {
    color: "#FFFFFF",
    fontSize: 20,
    fontWeight: "800",
    textAlign: "center",
    paddingHorizontal: 6,
  },

  // ============================================================================
  // BUTTON STYLES
  // ============================================================================

  bigButton: {
    alignSelf: "center",
    paddingHorizontal: 50,
    paddingVertical: 16,
    backgroundColor: "#007AFF",
    borderRadius: 28,
    shadowColor: "#000",
    shadowOpacity: 0.15,
    shadowOffset: { width: 0, height: 4 },
    shadowRadius: 8,
    elevation: 4,
    marginTop: 16,
  },
  
  bigButtonText: {
    color: "#FFFFFF",
    fontSize: 18,
    fontWeight: "600",
    textAlign: "center",
  },
  
  primaryButton: {
    paddingVertical: 12,
    paddingHorizontal: 16,
    borderRadius: 28,
    backgroundColor: "#007AFF",
    shadowColor: "#000",
    shadowOpacity: 0.15,
    shadowOffset: { width: 0, height: 3 },
    shadowRadius: 6,
    elevation: 3,
    alignSelf: "flex-start",
    marginBottom: 12,
  },
  
  primaryButtonText: {
    color: "#FFFFFF",
    fontWeight: "600",
    fontSize: 16,
  },
  
  secondaryButton: {
    paddingVertical: 12,
    paddingHorizontal: 16,
    borderRadius: 28,
    backgroundColor: "#FFFFFF",
    borderWidth: 2,
    borderColor: "#007AFF",
    shadowColor: "#000",
    shadowOpacity: 0.08,
    shadowOffset: { width: 0, height: 2 },
    shadowRadius: 4,
    elevation: 2,
    alignSelf: "flex-start",
    marginBottom: 8,
  },
  
  secondaryButtonText: {
    color: "#007AFF",
    fontWeight: "600",
    fontSize: 16,
  },
  
  buttonDisabled: {
    opacity: 0.5,
  },
  
  destructiveButton: {
    paddingHorizontal: 10,
    paddingVertical: 6,
    backgroundColor: "#FF3B30",
    borderRadius: 999,
  },
  
  destructiveButtonText: {
    color: "#FFFFFF",
    fontWeight: "700",
    fontSize: 14,
  },
  
  floatingButtonContainer: {
    flexDirection: 'row',
    justifyContent: 'space-around',
    paddingVertical: 16,
    paddingHorizontal: 8,
    backgroundColor: '#F2F2F7',
    borderTopWidth: 1,
    borderTopColor: '#E5E5EA',
  },
  
  floatingButton: {
    flex: 1,
    marginHorizontal: 4,
    paddingVertical: 14,
    paddingHorizontal: 16,
    backgroundColor: '#007AFF',
    borderRadius: 28,
    shadowColor: '#000',
    shadowOpacity: 0.15,
    shadowOffset: { width: 0, height: 4 },
    shadowRadius: 8,
    elevation: 4,
    alignItems: 'center',
  },
  
  floatingButtonText: {
    color: '#FFFFFF',
    fontSize: 16,
    fontWeight: '600',
  },
  
  // ============================================================================
  // FORM / INPUT STYLES
  // ============================================================================
  
  formBox: {
    backgroundColor: "#FFFFFF",
    padding: 18,
    borderRadius: 16,
    borderWidth: 1,
    borderColor: "#E5E5EA",
    shadowColor: "#000",
    shadowOpacity: 0.08,
    shadowOffset: { width: 0, height: 4 },
    shadowRadius: 8,
    elevation: 3,
    marginBottom: 24,
  },
  
  input: {
    borderWidth: 1.5,
    borderColor: "#D1D1D6",
    borderRadius: 14,
    fontSize: 18,
    color: "#000",
    shadowColor: "#000",
    shadowOpacity: 0.05,
    shadowOffset: { width: 0, height: 2 },
    shadowRadius: 4,
    elevation: 2,
    marginRight: 8,
    marginBottom: 10,
    paddingHorizontal: 12,
    paddingVertical: 8,
  },
  
  searchInput: {
    marginBottom: 16,
    marginRight: 0,
  },
  
  dateInputRow: {
    flexDirection: 'row',
    gap: 8,
    marginBottom: 12,
  },
  
  dateInputSmall: {
    flex: 1,
    marginBottom: 0,
    marginRight: 0,
  },
  
  cellInput: {
    width: "100%",
    textAlign: "center",
    backgroundColor: "#FFFFFF",
    borderWidth: 1.5,
    borderColor: "#D1D1D6",
    borderRadius: 12,
    paddingVertical: 8,
    paddingHorizontal: 8,
    fontSize: 16,
    color: "#000",
    shadowColor: "#000",
    shadowOpacity: 0.05,
    shadowOffset: { width: 0, height: 1 },
    shadowRadius: 3,
    elevation: 1,
  },
  
  // ============================================================================
  // MODAL STYLES
  // ============================================================================
  
  modalOverlay: {
    position: 'absolute',
    top: 0,
    left: 0,
    right: 0,
    bottom: 0,
    backgroundColor: 'rgba(0, 0, 0, 0.5)',
    justifyContent: 'center',
    alignItems: 'center',
    paddingHorizontal: 20,
  },
  
  modalContent: {
    backgroundColor: '#FFFFFF',
    borderRadius: 20,
    padding: 24,
    width: '100%',
    maxWidth: 400,
    shadowColor: '#000',
    shadowOpacity: 0.25,
    shadowOffset: { width: 0, height: 8 },
    shadowRadius: 16,
    elevation: 8,
  },
  
  modalTitle: {
    fontSize: 22,
    fontWeight: '700',
    color: '#111827',
    marginBottom: 16,
    textAlign: 'center',
  },
  
  modalSubtitle: {
    fontSize: 14,
    color: '#6B7280',
    marginBottom: 8,
    textAlign: 'center',
  },
  
  modalInstructions: {
    fontSize: 15,
    color: '#4B5563',
    marginBottom: 20,
    lineHeight: 22,
  },
  
  monoText: {
    fontFamily: Platform.OS === 'ios' ? 'Courier' : 'monospace',
    fontSize: 13,
    color: '#111827',
    backgroundColor: '#F3F4F6',
    paddingHorizontal: 4,
    paddingVertical: 2,
  },
  
  // ============================================================================
  // GAME / ROSTER LIST STYLES
  // ============================================================================
  
  gamesScrollView: {
    flex: 1,
    marginBottom: 16,
  },
  
  gameRow: {
    borderRadius: 14,
    paddingVertical: 16,
    paddingHorizontal: 14,
    marginBottom: 10,
    borderWidth: 1,
    shadowColor: '#000',
    shadowOpacity: 0.05,
    shadowOffset: { width: 0, height: 2 },
    shadowRadius: 4,
    elevation: 2,
  },
  
  gameRowHome: {
    backgroundColor: '#111827',
    borderColor: '#111827',
  },
  
  gameRowAway: {
    backgroundColor: '#FFFFFF',
    borderColor: '#E5E5EA',
  },
  
  gameRowTitle: {
    fontSize: 16,
    fontWeight: "600",
    color: "#111827",
  },
  
  gameRowTitleHome: {
    color: '#FFFFFF',
  },
  
  gameRowTitleAway: {
    color: '#111827',
  },
  
  gameRowSubtitle: {
    fontSize: 14,
    color: "#6B7280",
    marginTop: 2,
  },
  
  gameRowSubtitleHome: {
    color: '#D1D5DB',
  },
  
  gameRowSubtitleAway: {
    color: '#6B7280',
  },
  
  scheduleRow: {
    borderRadius: 14,
    paddingVertical: 12,
    paddingHorizontal: 14,
    marginBottom: 10,
    borderWidth: 1,
    shadowColor: '#000',
    shadowOpacity: 0.05,
    shadowOffset: { width: 0, height: 2 },
    shadowRadius: 4,
    elevation: 2,
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
  },
  
  scheduleRowHome: {
    backgroundColor: '#111827',
    borderColor: '#111827',
  },
  
  scheduleRowAway: {
    backgroundColor: '#FFFFFF',
    borderColor: '#E5E5EA',
  },
  
  scheduleDateHome: {
    fontSize: 14,
    fontWeight: '600',
    color: '#D1D5DB',
  },
  
  scheduleDateAway: {
    fontSize: 14,
    fontWeight: '600',
    color: '#6B7280',
  },
  
  scheduleOpponentHome: {
    fontSize: 16,
    fontWeight: '600',
    color: '#FFFFFF',
  },
  
  scheduleOpponentAway: {
    fontSize: 16,
    fontWeight: '600',
    color: '#111827',
  },
  
  rosterRow: {
    flexDirection: "row",
    alignItems: "center",
    paddingVertical: 10,
    paddingHorizontal: 12,
    backgroundColor: "#FFFFFF",
    borderRadius: 14,
    marginBottom: 8,
    borderWidth: 1,
    borderColor: "#E5E5EA",
    shadowColor: "#000",
    shadowOpacity: 0.04,
    shadowOffset: { width: 0, height: 1 },
    shadowRadius: 2,
    elevation: 1,
  },
  
  rosterNumber: {
    width: 60,
    fontWeight: "600",
    color: "#111827",
  },
  
  rosterName: {
    fontSize: 16,
    color: "#111827",
  },
  
  rosterPositionText: {
    fontSize: 13,
    color: "#6B7280",
  },
  
  locationSelectorRow: {
    marginBottom: 16,
  },
  
  locationLabel: {
    fontSize: 14,
    fontWeight: '600',
    color: '#374151',
    marginBottom: 8,
  },
  
  locationButtons: {
    flexDirection: 'row',
    gap: 8,
  },
  
  locationButton: {
    flex: 1,
    paddingVertical: 10,
    paddingHorizontal: 16,
    borderRadius: 12,
    borderWidth: 2,
    borderColor: '#D1D5DB',
    backgroundColor: '#F9FAFB',
    alignItems: 'center',
  },
  
  locationButtonActive: {
    backgroundColor: '#007AFF',
    borderColor: '#007AFF',
  },
  
  locationButtonText: {
    fontSize: 15,
    fontWeight: '600',
    color: '#374151',
  },
  
  locationButtonTextActive: {
    color: '#FFFFFF',
  },
  
  // ============================================================================
  // GAME STATS HEADER STYLES
  // ============================================================================
  
  gameStatsHeader: {
    marginBottom: 16,
  },

  scheduleStatsHeaderContainer: {
    marginBottom: 4,
  },

  scheduleStatsHeaderRow: {
    flexDirection: 'row',
    alignItems: 'stretch',
  },

  scheduleStatsBadge: {
    flex: 2,
    alignSelf: 'auto',
    marginRight: 8,
    marginBottom: 0,
  },

  scheduleStatsCorrectionButton: {
    flex: 1,
    alignSelf: 'auto',
    marginTop: 0,
    marginBottom: 0,
    justifyContent: 'center',
    alignItems: 'center',
  },

  gameHeaderBadge: {
    alignSelf: 'center',
    paddingHorizontal: 24,
    paddingVertical: 12,
    borderRadius: 16,
    marginBottom: 20,
    shadowColor: '#000',
    shadowOpacity: 0.1,
    shadowOffset: { width: 0, height: 2 },
    shadowRadius: 4,
    elevation: 3,
  },
  
  gameHeaderBadgeHome: {
    backgroundColor: '#111827',
  },
  
  gameHeaderBadgeAway: {
    backgroundColor: '#FFFFFF',
    borderWidth: 2,
    borderColor: '#111827',
  },
  
  gameHeaderOpponent: {
    fontSize: 20,
    fontWeight: '700',
    textAlign: 'center',
  },
  
  gameHeaderOpponentHome: {
    color: '#FFFFFF',
  },
  
  gameHeaderOpponentAway: {
    color: '#111827',
  },
  
  gameHeaderDate: {
    fontSize: 14,
    fontWeight: '500',
    textAlign: 'center',
    marginTop: 4,
  },
  
  gameHeaderDateHome: {
    color: '#D1D5DB',
  },
  
  gameHeaderDateAway: {
    color: '#6B7280',
  },
  
  gameTitle: {
    fontSize: 20,
    fontWeight: "700",
    marginTop: 8,
    color: "#111827",
  },
  
  gameSubtitle: {
    fontSize: 16,
    color: "#4B5563",
    marginBottom: 8,
  },
  
  // ============================================================================
  // TIMER STYLES
  // ============================================================================
  
  timerSection: {
    backgroundColor: '#FFFFFF',
    borderRadius: 16,
    padding: 16,
    marginTop: 12,
    marginBottom: 0,
    borderWidth: 1,
    borderColor: '#E5E5EA',
    shadowColor: '#000',
    shadowOpacity: 0.05,
    shadowOffset: { width: 0, height: 2 },
    shadowRadius: 4,
    elevation: 2,
  },
  
  timerValue: {
    fontSize: 32,
    fontWeight: '700',
    color: '#111827',
    textAlign: 'center',
    marginBottom: 12,
  },
  
  timerControls: {
    flexDirection: 'row',
    justifyContent: 'center',
    gap: 12,
  },
  
  timerButton: {
    flex: 1,
    maxWidth: 120,
    paddingVertical: 12,
    paddingHorizontal: 24,
    borderRadius: 12,
    backgroundColor: '#10B981',
    shadowColor: '#000',
    shadowOpacity: 0.15,
    shadowOffset: { width: 0, height: 2 },
    shadowRadius: 4,
    elevation: 3,
  },
  
  timerButtonStart: {
    backgroundColor: '#10B981',
  },
  
  timerButtonStop: {
    backgroundColor: '#EF4444',
  },
  
  timerButtonInactive: {
    backgroundColor: '#D1D5DB',
    shadowOpacity: 0.05,
  },
  
  timerButtonReset: {
    paddingVertical: 8,
    paddingHorizontal: 16,
    borderRadius: 10,
    minWidth: 70,
    backgroundColor: '#FFFFFF',
    borderWidth: 2,
    borderColor: '#D1D5DB',
  },
  
  timerButtonText: {
    color: '#FFFFFF',
    fontWeight: '700',
    fontSize: 16,
    textAlign: 'center',
  },
  
  timerButtonTextInactive: {
    color: '#9CA3AF',
  },
  
  timerButtonResetText: {
    color: '#6B7280',
    fontWeight: '600',
    fontSize: 14,
    textAlign: 'center',
  },
  
  // ============================================================================
  // STATS TABLE STYLES
  // ============================================================================
  
  statsContainer: {
    flex: 1,
    position: 'relative',
  },
  
  statsScrollView: {
    flex: 1,
  },
  
  row: {
    flexDirection: "row",
    alignItems: "center",
    borderBottomWidth: 1,
    borderColor: "#E5E5EA",
    minHeight: 44,
  },
  
  headerRow: {
    backgroundColor: "#E5E5EA",
  },
  
  headerText: {
    fontWeight: "600",
    color: "#111827",
  },
  
  categoryHeaderRow: {
    backgroundColor: '#F3F4F6',
    borderBottomWidth: 1,
    borderBottomColor: '#D1D5DB',
    minHeight: 26,
  },
  
  categoryHeader: {
    justifyContent: 'center',
    alignItems: 'center',
    paddingVertical: 6,
    borderRightWidth: 1,
    borderRightColor: '#D1D5DB',
  },
  
  categoryHeaderText: {
    fontSize: 11,
    fontWeight: '700',
    color: '#6B7280',
    textTransform: 'uppercase',
    letterSpacing: 0.5,
  },
  
  statCell: {
    width: STAT_COL_WIDTH,
    justifyContent: "center",
    alignItems: "center",
    paddingVertical: 4,
    paddingHorizontal: 4,
  },
  
  statControlRow: {
    flexDirection: "row",
    alignItems: "center",
    justifyContent: "center",
    gap: 4,
  },
  
  statButton: {
    width: 28,
    height: 28,
    borderRadius: 14,
    backgroundColor: "#007AFF",
    justifyContent: "center",
    alignItems: "center",
    shadowColor: "#000",
    shadowOpacity: 0.1,
    shadowOffset: { width: 0, height: 1 },
    shadowRadius: 2,
    elevation: 1,
  },
  
  statButtonSingle: {
    width: 32,
    height: 32,
    borderRadius: 16,
    backgroundColor: '#007AFF',
    justifyContent: 'center',
    alignItems: 'center',
    shadowColor: '#000',
    shadowOpacity: 0.1,
    shadowOffset: { width: 0, height: 1 },
    shadowRadius: 2,
    elevation: 1,
    marginRight: 8,
  },
  
  statButtonText: {
    color: "#FFFFFF",
    fontSize: 18,
    fontWeight: "700",
    lineHeight: 20,
  },
  
  statValue: {
    fontSize: 16,
    fontWeight: "600",
    color: "#111827",
    minWidth: 24,
    textAlign: "center",
  },
  
  statValueDisabled: {
    color: '#D1D5DB',
  },
  
  statValuePending: {
    color: '#D97706',
    fontWeight: '700',
  },
  
  statReadOnlyContainer: {
    backgroundColor: '#F9FAFB',
    paddingVertical: 6,
    paddingHorizontal: 8,
    borderRadius: 8,
    minWidth: 50,
  },
  
  statReadOnlyValue: {
    fontSize: 14,
    fontWeight: '600',
    color: '#6B7280',
    textAlign: 'center',
  },
  
  statCorrectionCell: {
    paddingVertical: 6,
    paddingHorizontal: 8,
    borderRadius: 8,
    minWidth: 60,
  },
  
  statCorrectionCellPending: {
    backgroundColor: '#FEF3C7',
  },
  
  inOutButton: {
    paddingHorizontal: 10,
    paddingVertical: 6,
    borderRadius: 999,
    borderWidth: 1,
    borderColor: "#D1D5DB",
    backgroundColor: "#F9FAFB",
  },
  
  inOutButtonActive: {
    backgroundColor: "#10B981",
    borderColor: "#059669",
  },
  
  inOutButtonText: {
    fontSize: 12,
    fontWeight: "600",
    color: "#111827",
  },
  
  inOutButtonTextActive: {
    color: "#FFFFFF",
  },
  
  totalRowContainer: {
    position: 'absolute',
    bottom: 0,
    left: 0,
    right: 0,
    backgroundColor: '#F3F4F6',
    borderTopWidth: 3,
    borderTopColor: '#111827',
    shadowColor: '#000',
    shadowOpacity: 0.2,
    shadowOffset: { width: 0, height: -4 },
    shadowRadius: 8,
    elevation: 8,
    zIndex: 10,
  },
  
  totalRow: {
    backgroundColor: '#F3F4F6',
    borderBottomWidth: 0,
    minHeight: 50,
  },
  
  totalText: {
    fontSize: 14,
    fontWeight: '700',
    color: '#111827',
    textAlign: 'center',
  },
  
  correctionModeButton: {
    alignSelf: 'center',
    paddingVertical: 8,
    paddingHorizontal: 16,
    borderRadius: 12,
    backgroundColor: '#FFFFFF',
    borderWidth: 2,
    borderColor: '#F59E0B',
    marginTop: 8,
    marginBottom: 8,
  },
  
  correctionModeButtonActive: {
    backgroundColor: '#F59E0B',
  },
  
  correctionModeButtonText: {
    fontSize: 14,
    fontWeight: '700',
    color: '#F59E0B',
    textAlign: 'center',
  },
  
  correctionModeButtonTextActive: {
    color: '#FFFFFF',
  },
  
  assistPlayerList: {
    maxHeight: 300,
    marginVertical: 12,
  },
  
  assistPlayerOption: {
    paddingVertical: 14,
    paddingHorizontal: 16,
    backgroundColor: '#F9FAFB',
    borderRadius: 12,
    marginBottom: 8,
    borderWidth: 1,
    borderColor: '#E5E5EA',
  },
  
  assistPlayerText: {
    fontSize: 16,
    fontWeight: '600',
    color: '#111827',
  },
  
  // ============================================================================
  // WHITEBOARD / PLAY DESIGN STYLES
  // ============================================================================
  
  whiteboardTitle: {
    fontSize: 28,
    fontWeight: '800',
    textAlign: 'center',
    marginBottom: 20,
    marginTop: 8,
    color: '#111827',
  },
  
  backLinkAbsolute: {
    position: 'absolute',
    top: 50,
    left: 16,
    zIndex: 10,
  },
  
  controlsRow: {
    flexDirection: 'row',
    alignItems: 'flex-end',
    justifyContent: 'space-between',
    marginBottom: 16,
    gap: 8,
  },
  
  dropdownContainer: {
    flex: 1,
  },
  
  dropdownLabelSmall: {
    fontSize: 12,
    fontWeight: '600',
    color: '#6B7280',
    marginBottom: 4,
  },
  
  dropdownCompact: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    backgroundColor: '#FFFFFF',
    borderWidth: 2,
    borderColor: '#D1D5DB',
    borderRadius: 10,
    paddingVertical: 10,
    paddingHorizontal: 12,
    shadowColor: '#000',
    shadowOpacity: 0.05,
    shadowOffset: { width: 0, height: 2 },
    shadowRadius: 4,
    elevation: 2,
  },
  
  dropdownCompactActive: {
    backgroundColor: '#10B981',
    borderColor: '#059669',
  },
  
  dropdownTextCompact: {
    fontSize: 14,
    fontWeight: '600',
    color: '#111827',
    flex: 1,
  },
  
  dropdownTextActive: {
    color: '#FFFFFF',
  },
  
  dropdownArrow: {
    fontSize: 12,
    color: '#6B7280',
    marginLeft: 8,
  },
  
  dropdownArrowActive: {
    color: '#FFFFFF',
  },
  
  dropdownMenu: {
    position: 'absolute',
    top: '100%',
    left: 0,
    right: 0,
    marginTop: 4,
    backgroundColor: '#FFFFFF',
    borderRadius: 10,
    borderWidth: 2,
    borderColor: '#D1D5DB',
    shadowColor: '#000',
    shadowOpacity: 0.15,
    shadowOffset: { width: 0, height: 4 },
    shadowRadius: 8,
    elevation: 5,
    zIndex: 1000,
  },
  
  dropdownMenuTall: {
    maxHeight: 250,
  },
  
  dropdownMenuScroll: {
    maxHeight: 250,
  },
  
  dropdownMenuItem: {
    paddingVertical: 12,
    paddingHorizontal: 16,
    borderBottomWidth: 1,
    borderBottomColor: '#F3F4F6',
  },
  
  dropdownMenuItemActive: {
    backgroundColor: '#EFF6FF',
  },
  
  dropdownMenuItemText: {
    fontSize: 14,
    fontWeight: '600',
    color: '#374151',
  },
  
  dropdownMenuItemTextActive: {
    color: '#007AFF',
  },
  
  dropdownOverlay: {
    position: 'absolute',
    top: 0,
    left: 0,
    right: 0,
    bottom: 0,
    zIndex: 999,
  },
  
  saveButtonCompact: {
    backgroundColor: '#007AFF',
    paddingVertical: 10,
    paddingHorizontal: 16,
    borderRadius: 10,
    shadowColor: '#000',
    shadowOpacity: 0.15,
    shadowOffset: { width: 0, height: 3 },
    shadowRadius: 6,
    elevation: 3,
    justifyContent: 'center',
    alignItems: 'center',
    minWidth: 90,
  },
  
  saveButtonText: {
    color: '#FFFFFF',
    fontSize: 14,
    fontWeight: '700',
  },
  
  modeIndicator: {
    fontSize: 13,
    fontWeight: '600',
    color: '#6B7280',
    textAlign: 'center',
    marginBottom: 12,
    marginTop: -8,
  },
  
  savedPlaysBox: {
    paddingVertical: 6,
    marginBottom: 4,
  },
  
  savedPlaysTitle: {
    fontSize: 13,
    fontWeight: "600",
    color: "#374151",
    marginBottom: 4,
  },
  
  savedPlayPill: {
    flexDirection: "row",
    alignItems: "center",
    backgroundColor: "#111827",
    paddingHorizontal: 10,
    paddingVertical: 6,
    borderRadius: 999,
    marginRight: 8,
  },
  
  savedPlayName: {
    color: "#F9FAFB",
    fontSize: 13,
    fontWeight: "600",
  },
  
  savedPlayDelete: {
    marginLeft: 6,
  },
  
  savedPlayDeleteText: {
    color: "#FCA5A5",
    fontSize: 16,
    fontWeight: "700",
  },
  
  playFieldWrapper: {
    flex: 1,
    marginTop: 8,
    marginBottom: 24,
  },
  
  playField: {
    flex: 1,
    borderRadius: 16,
    borderWidth: 2,
    borderColor: "#F9FAFB",
    backgroundColor: "#047857",
    overflow: "hidden",
    position: "relative",
  },
  
  playPieceWrapper: {
    position: "absolute",
    width: 28,
    height: 28,
    justifyContent: "center",
    alignItems: "center",
  },
  
  playPieceText: {
    fontSize: 24,
    fontWeight: "700",
  },
  
  actionAbsoluteWrapper: {
    position: "absolute",
    top: 0,
    left: 0,
    right: 0,
    bottom: 0,
    width: '100%',
    height: '100%',
  },
  
  arrowHeadTriangle: {
    position: "absolute",
    width: 0,
    height: 0,
    borderTopWidth: 9,
    borderTopColor: "transparent",
    borderBottomWidth: 9,
    borderBottomColor: "transparent",
    borderLeftWidth: 16,
    borderLeftColor: "#000000",
  },
  
  arrowPickBar: {
    position: "absolute",
    width: 16,
    height: 4,
    backgroundColor: "#000000",
    borderRadius: 2,
  },
  
  // ============================================================================
  // PLAY CALLS SCREEN STYLES
  // ============================================================================
  
  emptyStateContainer: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    paddingHorizontal: 32,
  },
  
  emptyStateTitle: {
    fontSize: 22,
    fontWeight: '700',
    color: '#111827',
    marginBottom: 12,
    textAlign: 'center',
  },
  
  emptyStateText: {
    fontSize: 16,
    color: '#6B7280',
    textAlign: 'center',
    lineHeight: 24,
  },
  
  playCallsScrollView: {
    flex: 1,
    marginBottom: 16,
  },
  
  playCallCard: {
    backgroundColor: '#FFFFFF',
    borderRadius: 16,
    marginBottom: 12,
    borderWidth: 1,
    borderColor: '#E5E5EA',
    shadowColor: '#000',
    shadowOpacity: 0.08,
    shadowOffset: { width: 0, height: 2 },
    shadowRadius: 8,
    elevation: 3,
    overflow: 'hidden',
  },
  
  playCallCardContent: {
    padding: 16,
  },
  
  playCallHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginBottom: 12,
  },
  
  playCallName: {
    fontSize: 18,
    fontWeight: '700',
    color: '#111827',
    flex: 1,
  },
  
  playCallFieldType: {
    fontSize: 13,
    fontWeight: '600',
    color: '#6B7280',
    backgroundColor: '#F3F4F6',
    paddingHorizontal: 10,
    paddingVertical: 4,
    borderRadius: 8,
  },
  
  playCallStats: {
    flexDirection: 'row',
    gap: 16,
    marginBottom: 12,
  },
  
  playCallStat: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 4,
  },
  
  playCallStatLabel: {
    fontSize: 14,
    color: '#6B7280',
    fontWeight: '500',
  },
  
  playCallStatValue: {
    fontSize: 14,
    fontWeight: '700',
    color: '#111827',
  },
  
  playCallActions: {
    flexDirection: 'row',
    marginTop: 12,
    paddingTop: 12,
    borderTopWidth: 1,
    borderTopColor: '#E5E5EA',
  },
  
  deletePlayButton: {
    paddingHorizontal: 16,
    paddingVertical: 12,
  },
  
  // ============================================================================
// FULL FIELD STYLES (110 yards × 60 yards)
// ============================================================================

fullHorizontalMidline: {
  position: "absolute",
  left: 0,
  right: 0,
  top: "50%",
  height: 2,
  backgroundColor: "#F9FAFB",
},

fullHorizontalTopRestraining: {
  position: "absolute",
  left: 0,
  right: 0,
  top: "31.82%",  // 20 yards from top end line
  height: 2,
  backgroundColor: "#F9FAFB",
},

fullHorizontalBottomRestraining: {
  position: "absolute",
  left: 0,
  right: 0,
  bottom: "31.82%",  // 20 yards from bottom end line
  height: 2,
  backgroundColor: "#F9FAFB",
},

fullWingLineLeft: {
  position: "absolute",
  top: "40.91%",  // Start at top restraining line
  bottom: "40.91%",  // End at bottom restraining line
  left: "16.67%",  // 5 yards left of center (10 yard wing area total)
  width: 2,
  backgroundColor: "#F9FAFB",
},

fullWingLineRight: {
  position: "absolute",
  top: "40.91%",  // 
  bottom: "40.91%",  // End at bottom restraining line
  right: "16.67%",  // 5 yards right of center (10 yard wing area total)
  width: 2,
  backgroundColor: "#F9FAFB",
},

fullAlleyTopLeft: {
  position: "absolute",
  top: "0%",  // Start at top restraining line
  bottom: "68.18%",  // End at bottom restraining line
  left: "16.67%",  // 5 yards right of center (10 yard wing area total)
  width: 2,
  backgroundColor: "#F9FAFB",
},

fullAlleyTopRight: {
  position: "absolute",
  top: "0%",  // Start at top restraining line
  bottom: "68.18%",  // End at bottom restraining line
  right: "16.67%",  // 5 yards right of center (10 yard wing area total)
  width: 2,
  backgroundColor: "#F9FAFB",
},

fullAlleyBottomLeft: {
  position: "absolute",
  top: "68.18%",  // Start at top restraining line
  bottom: "0%",  // End at bottom restraining line
  left: "16.67%",  // 5 yards right of center (10 yard wing area total)
  width: 2,
  backgroundColor: "#F9FAFB",
},

fullAlleyBottomRight: {
  position: "absolute",
  top: "68.18%",  // Start at top restraining line
  bottom: "0%",  // End at bottom restraining line
  right: "16.67%",  // 5 yards right of center (10 yard wing area total)
  width: 2,
  backgroundColor: "#F9FAFB",
},

fullCreaseTop: {
  position: "absolute",
  left: "50%",
  top: "13.64%",  // 15 yards from top end line (goal position)
  marginLeft: -27,
  width: 54,
  height: 54,
  borderRadius: 27,
  borderWidth: 2,
  borderColor: "#F9FAFB",
},

fullCreaseBottom: {
  position: "absolute",
  left: "50%",
  bottom: "13.64%",  // 15 yards from bottom end line (goal position)
  marginLeft: -27,
  width: 54,
  height: 54,
  borderRadius: 27,
  borderWidth: 2,
  borderColor: "#F9FAFB",
},

fullEndLineTop: {
  position: "absolute",
  left: 0,
  right: 0,
  top: 0,
  height: 3,
  backgroundColor: "#F9FAFB",
},

fullEndLineBottom: {
  position: "absolute",
  left: 0,
  right: 0,
  bottom: 0,
  height: 3,
  backgroundColor: "#F9FAFB",
},

fullCreaseTriangleTop: {
  position: "absolute",
  left: "50%",
  top: "13.64%",
  marginLeft: -8.8,
  marginTop: 18,
  width: 0,
  height: 0,
  backgroundColor: "transparent",
  borderStyle: "solid",
  borderLeftWidth: 8.8,
  borderRightWidth: 8.8,
  borderBottomWidth: 15.4,
  borderLeftColor: "transparent",
  borderRightColor: "transparent",
  borderBottomColor: "#F9FAFB",
},

fullCreaseTriangleBottom: {
  position: "absolute",
  left: "50%",
  bottom: "13.64%",
  marginLeft: -8.8,
  marginBottom: 18,
  width: 0,
  height: 0,
  backgroundColor: "transparent",
  borderStyle: "solid",
  borderLeftWidth: 8.8,
  borderRightWidth: 8.8,
  borderTopWidth: 15.4,
  borderLeftColor: "transparent",
  borderRightColor: "transparent",
  borderTopColor: "#F9FAFB",
},

// ============================================================================
// HALF FIELD STYLES (55 yards × 60 yards - Attack/Offensive Half)
// ============================================================================

halfMidline: {
  position: "absolute",
  left: 0,
  right: 0,
  top: 0,
  height: 2,
  backgroundColor: "#F9FAFB",
},

halfRestraining: {
  position: "absolute",
  left: 0,
  right: 0,
  top: "36.36%",  // 20 yards from midfield (20/55 of half field)
  height: 2,
  backgroundColor: "#F9FAFB",
},

halfCrease: {
  position: "absolute",
  left: "50%",
  bottom: "27.27%",  // 15 yards from bottom end line (15/55 of half field)
  marginLeft: -27,
  width: 54,
  height: 54,
  borderRadius: 27,
  borderWidth: 2,
  borderColor: "#F9FAFB",
},

halfGLE: {
  position: "absolute",
  left: "25%",
  right: "25%",
  bottom: "23.64%",  // 13 yards from bottom (13/55 of half field)
  height: 2,
  backgroundColor: "#F9FAFB",
},

halfEndLine: {
  position: "absolute",
  left: 0,
  right: 0,
  bottom: 0,
  height: 3,
  backgroundColor: "#F9FAFB",
},

halfCreaseTriangle: {
  position: "absolute",
  left: "50%",
  bottom: "27.27%",
  marginLeft: -8.8,
  marginBottom: 18,
  width: 0,
  height: 0,
  backgroundColor: "transparent",
  borderStyle: "solid",
  borderLeftWidth: 8.8,
  borderRightWidth: 8.8,
  borderTopWidth: 15.4,
  borderLeftColor: "transparent",
  borderRightColor: "transparent",
  borderTopColor: "#F9FAFB",
},

// ============================================================================
// MID/FACEOFF FIELD STYLES (30 yards × 60 yards - Center Area)
// ============================================================================

midVerticalMidline: {
  position: "absolute",
  top: 0,
  bottom: 0,
  left: "50%",
  width: 2,
  backgroundColor: "#F9FAFB",
},

midWingLineLeft: {
  position: "absolute",
  top: 0,  // Full height for faceoff area
  bottom: 0,
  left: "45%",  // 5 yards left of center
  width: 2,
  backgroundColor: "#F9FAFB",
},

midWingLineRight: {
  position: "absolute",
  top: 0,
  bottom: 0,
  right: "45%",  // 5 yards right of center
  width: 2,
  backgroundColor: "#F9FAFB",
},

midTopBound: {
  position: "absolute",
  left: 0,
  right: 0,
  top: 0,
  height: 2,
  backgroundColor: "#F9FAFB",
},

midBottomBound: {
  position: "absolute",
  left: 0,
  right: 0,
  bottom: 0,
  height: 2,
  backgroundColor: "#F9FAFB",
},
});
