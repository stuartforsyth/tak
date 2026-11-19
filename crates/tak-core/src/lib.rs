//! Thin wrapper over Tiltak's rules and search: the one place the game and (later) the
//! server touch the engine. Moves cross the boundary as PTN strings.

use board_game_traits::{Color, GameResult as TiltakResult, Position as _};
use pgn_traits::PgnPosition;
use std::time::Duration;
use tiltak::position::{Komi, Move, Position};
use tiltak::search::{MctsSetting, MonteCarloTree};

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Outcome {
    WhiteWins,
    BlackWins,
    Draw,
}

/// Search strength. Easy and Medium use Tiltak's own weaker-bot settings (rollouts,
/// temperature, noise); Hard is the plain engine.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Level {
    Easy,
    Medium,
    Hard,
}

impl Level {
    fn nodes(self) -> u64 {
        match self {
            Level::Easy => 200,
            Level::Medium => 5_000,
            Level::Hard => 100_000,
        }
    }

    fn settings<const S: usize>(self) -> MctsSetting<S> {
        let base = MctsSetting::default();
        match self {
            Level::Easy => base
                .add_rollout_depth(200)
                .add_rollout_temperature(0.2)
                .add_dirichlet(0.25),
            Level::Medium => base.add_rollout_depth(200).add_rollout_temperature(0.2),
            Level::Hard => base,
        }
    }
}

#[derive(Clone)]
pub struct Game<const S: usize> {
    position: Position<S>,
    /// Positions before each move played, so undo is exact.
    history: Vec<Position<S>>,
}

impl<const S: usize> Game<S> {
    /// 6x6 has no tuned evaluation at zero komi, so it starts with a two-stone komi.
    pub fn new() -> Self {
        let half_komi = if S >= 6 { 4 } else { 0 };
        let komi = Komi::from_half_komi(half_komi).expect("komi in range");
        Game {
            position: Position::start_position_with_komi(komi),
            history: vec![],
        }
    }

    pub fn side_to_move(&self) -> Color {
        self.position.side_to_move()
    }

    pub fn legal_moves(&self) -> Vec<String> {
        let mut moves = vec![];
        self.position.generate_moves(&mut moves);
        moves.iter().map(|m| self.position.move_to_san(m)).collect()
    }

    pub fn play(&mut self, ptn: &str) -> Result<(), String> {
        let mv: Move<S> = self
            .position
            .move_from_san(ptn)
            .map_err(|e| format!("bad move {ptn:?}: {e}"))?;
        let mut legal = vec![];
        self.position.generate_moves(&mut legal);
        if !legal.contains(&mv) {
            return Err(format!("illegal move {ptn:?}"));
        }
        self.history.push(self.position.clone());
        self.position.do_move(mv);
        Ok(())
    }

    /// Takes back the last move. Returns false at the start of the game.
    pub fn undo(&mut self) -> bool {
        match self.history.pop() {
            Some(p) => {
                self.position = p;
                true
            }
            None => false,
        }
    }

    /// Number of moves (plies) played so far.
    pub fn plies(&self) -> usize {
        self.history.len()
    }

    pub fn outcome(&self) -> Option<Outcome> {
        self.position.game_result().map(|r| match r {
            TiltakResult::WhiteWin => Outcome::WhiteWins,
            TiltakResult::BlackWin => Outcome::BlackWins,
            TiltakResult::Draw => Outcome::Draw,
        })
    }

    /// Returns the engine's move (PTN) and its estimated win probability for the side to move.
    pub fn ai_move(&self, level: Level) -> (String, f32) {
        let mut tree = MonteCarloTree::new(self.position.clone(), level.settings());
        for _ in 0..level.nodes() {
            if tree.select().is_err() {
                break;
            }
        }
        let (mv, score) = tree.best_move().expect("game is not over");
        (self.position.move_to_san(&mv), score)
    }

    /// Time-limited variant, for callers that must keep a frame budget.
    pub fn ai_move_timed(&self, level: Level, max: Duration) -> (String, f32) {
        let mut tree = MonteCarloTree::new(self.position.clone(), level.settings());
        tree.search_for_time(max, |_| {});
        let (mv, score) = tree.best_move().expect("game is not over");
        (self.position.move_to_san(&mv), score)
    }

    /// Text rendering of the board (TPS), for display and saving.
    pub fn tps(&self) -> String {
        self.position.to_fen()
    }
}

impl<const S: usize> Default for Game<S> {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn five_by_five_opening_has_25_moves() {
        assert_eq!(Game::<5>::new().legal_moves().len(), 25);
    }

    #[test]
    fn illegal_and_garbage_moves_rejected() {
        let mut g = Game::<5>::new();
        assert!(g.play("zz").is_err());
        assert!(g.play("a1+").is_err()); // nothing to move
        assert!(g.play("a1").is_ok());
    }

    #[test]
    fn ai_plays_a_legal_move_at_every_level() {
        for level in [Level::Easy, Level::Medium] {
            let mut g = Game::<5>::new();
            let (mv, _) = g.ai_move(level);
            assert!(g.legal_moves().contains(&mv));
            g.play(&mv).unwrap();
        }
    }

    #[test]
    fn six_by_six_starts_and_moves() {
        let g = Game::<6>::new();
        assert_eq!(g.legal_moves().len(), 36);
        let (mv, _) = g.ai_move(Level::Easy);
        assert!(g.legal_moves().contains(&mv));
    }

    #[test]
    fn road_win_detected() {
        // Opening plies place the opponent's stone, so white's own stones start at ply 3.
        let mut g = Game::<4>::new();
        for m in ["d4", "a4", "a1", "d3", "a2", "d2"] {
            g.play(m).unwrap();
            assert_eq!(g.outcome(), None);
        }
        g.play("a3").unwrap();
        assert_eq!(g.outcome(), Some(Outcome::WhiteWins));
    }
}

/// Board-size-erased game, so callers (the Godot bridge, a server) need no const generics.
#[derive(Clone)]
pub enum AnyGame {
    S4(Game<4>),
    S5(Game<5>),
    S6(Game<6>),
}

macro_rules! each {
    ($self:expr, $g:ident => $e:expr) => {
        match $self {
            AnyGame::S4($g) => $e,
            AnyGame::S5($g) => $e,
            AnyGame::S6($g) => $e,
        }
    };
}

impl AnyGame {
    pub fn new(size: usize) -> Option<Self> {
        match size {
            4 => Some(AnyGame::S4(Game::new())),
            5 => Some(AnyGame::S5(Game::new())),
            6 => Some(AnyGame::S6(Game::new())),
            _ => None,
        }
    }
    pub fn size(&self) -> usize {
        match self {
            AnyGame::S4(_) => 4,
            AnyGame::S5(_) => 5,
            AnyGame::S6(_) => 6,
        }
    }
    pub fn white_to_move(&self) -> bool {
        each!(self, g => g.side_to_move() == Color::White)
    }
    pub fn legal_moves(&self) -> Vec<String> {
        each!(self, g => g.legal_moves())
    }
    pub fn play(&mut self, ptn: &str) -> Result<(), String> {
        each!(self, g => g.play(ptn))
    }
    pub fn outcome(&self) -> Option<Outcome> {
        each!(self, g => g.outcome())
    }
    pub fn undo(&mut self) -> bool {
        each!(self, g => g.undo())
    }
    pub fn plies(&self) -> usize {
        each!(self, g => g.plies())
    }
    pub fn ai_move(&self, level: Level) -> (String, f32) {
        each!(self, g => g.ai_move(level))
    }
    pub fn tps(&self) -> String {
        each!(self, g => g.tps())
    }
}

#[cfg(test)]
mod any_tests {
    use super::*;

    #[test]
    fn undo_restores_position_exactly() {
        let mut g = AnyGame::new(5).unwrap();
        assert!(!g.undo());
        let start = g.tps();
        g.play("a1").unwrap();
        g.play("e5").unwrap();
        g.play("c3").unwrap();
        let after_two = {
            let mut h = AnyGame::new(5).unwrap();
            h.play("a1").unwrap();
            h.play("e5").unwrap();
            h.tps()
        };
        assert_eq!(g.plies(), 3);
        assert!(g.undo());
        assert_eq!(g.tps(), after_two);
        assert!(g.undo() && g.undo());
        assert_eq!(g.tps(), start);
        assert_eq!(g.plies(), 0);
        assert!(!g.undo());
        // Replaying after undo works.
        g.play("b2").unwrap();
    }

    #[test]
    fn any_game_dispatches_by_size() {
        assert!(AnyGame::new(7).is_none());
        let mut g = AnyGame::new(4).unwrap();
        assert_eq!(g.size(), 4);
        assert!(g.white_to_move());
        g.play("a1").unwrap();
        assert!(!g.white_to_move());
    }
}
