//! GDExtension bridge: exposes `TakGame` to Godot. All rules and AI live in `tak-core`.

use godot::prelude::*;
use std::sync::mpsc::{channel, Receiver, TryRecvError};
use std::thread;
use tak_core::{AnyGame, Level, Outcome};

struct TakExtension;

#[gdextension]
unsafe impl ExtensionLibrary for TakExtension {}

/// One game. The engine search runs on a Rust thread (`start_ai`), polled with `poll_ai`,
/// so Godot never has to touch the game from another thread.
#[derive(GodotClass)]
#[class(base = RefCounted, no_init)]
struct TakGame {
    game: AnyGame,
    pending: Option<Receiver<(String, f32)>>,
}

fn level_from(i: i64) -> Level {
    match i {
        0 => Level::Easy,
        1 => Level::Medium,
        _ => Level::Hard,
    }
}

#[godot_api]
impl TakGame {
    /// Returns null for unsupported sizes (only 4, 5 and 6 have a tuned engine).
    #[func]
    fn create(size: i64) -> Option<Gd<TakGame>> {
        let game = AnyGame::new(usize::try_from(size).ok()?)?;
        Some(Gd::from_object(TakGame { game, pending: None }))
    }

    #[func]
    fn size(&self) -> i64 {
        self.game.size() as i64
    }

    #[func]
    fn white_to_move(&self) -> bool {
        self.game.white_to_move()
    }

    #[func]
    fn legal_moves(&self) -> PackedStringArray {
        self.game.legal_moves().iter().map(|m| GString::from(m.as_str())).collect()
    }

    /// Empty string on success, otherwise the error message.
    #[func]
    fn play(&mut self, ptn: GString) -> GString {
        match self.game.play(&ptn.to_string()) {
            Ok(()) => GString::new(),
            Err(e) => GString::from(e.as_str()),
        }
    }

    /// 0 = still playing, 1 = white wins, 2 = black wins, 3 = draw.
    #[func]
    fn outcome(&self) -> i64 {
        match self.game.outcome() {
            None => 0,
            Some(Outcome::WhiteWins) => 1,
            Some(Outcome::BlackWins) => 2,
            Some(Outcome::Draw) => 3,
        }
    }

    /// level: 0 easy, 1 medium, 2 hard. Starts a background search; no-op if one is running.
    #[func]
    fn start_ai(&mut self, level: i64) {
        if self.pending.is_some() {
            return;
        }
        let game = self.game.clone();
        let level = level_from(level);
        let (tx, rx) = channel();
        thread::spawn(move || {
            let _ = tx.send(game.ai_move(level));
        });
        self.pending = Some(rx);
    }

    #[func]
    fn is_thinking(&self) -> bool {
        self.pending.is_some()
    }

    /// Empty until the search finishes, then `{ "move": String, "win": float }` once.
    #[func]
    fn poll_ai(&mut self) -> VarDictionary {
        let Some(rx) = &self.pending else {
            return VarDictionary::new();
        };
        match rx.try_recv() {
            Ok((mv, win)) => {
                self.pending = None;
                let mv = GString::from(mv.as_str());
                vdict! { "move" => &mv, "win" => win as f64 }
            }
            Err(TryRecvError::Empty) => VarDictionary::new(),
            Err(TryRecvError::Disconnected) => {
                self.pending = None;
                VarDictionary::new()
            }
        }
    }

    /// Blocking search, for tests and scripts.
    #[func]
    fn ai_move(&self, level: i64) -> VarDictionary {
        let (mv, win) = self.game.ai_move(level_from(level));
        let mv = GString::from(mv.as_str());
        vdict! { "move" => &mv, "win" => win as f64 }
    }

    #[func]
    fn tps(&self) -> GString {
        GString::from(self.game.tps().as_str())
    }
}
