//! Play Tak against the engine in a terminal: `tak-cli [size 4|5|6] [easy|medium|hard]`.
//! Moves are PTN (e.g. `a1`, `Fb2`, `Sc3`, `Cd4`, `2a1>`). White moves first; you are white.

use std::io::{self, BufRead, Write};
use tak_core::{Game, Level, Outcome};

fn play<const S: usize>(level: Level) {
    let mut game = Game::<S>::new();
    let stdin = io::stdin();
    loop {
        println!("\n{}", game.tps());
        if let Some(o) = game.outcome() {
            println!(
                "{}",
                match o {
                    Outcome::WhiteWins => "White wins",
                    Outcome::BlackWins => "Black wins",
                    Outcome::Draw => "Draw",
                }
            );
            return;
        }
        // Moves alternate; the human is white, so odd plies belong to the engine.
        let human_turn = format!("{:?}", game.side_to_move()) == "White";
        if human_turn {
            print!("your move> ");
            io::stdout().flush().unwrap();
            let mut line = String::new();
            if stdin.lock().read_line(&mut line).unwrap() == 0 {
                return;
            }
            let line = line.trim();
            if line == "moves" {
                println!("{}", game.legal_moves().join(" "));
            } else if let Err(e) = game.play(line) {
                println!("{e}");
            }
        } else {
            let (mv, win) = game.ai_move(level);
            println!("engine plays {mv} (win estimate {:.0}%)", win * 100.0);
            game.play(&mv).unwrap();
        }
    }
}

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let size = args.first().map(String::as_str).unwrap_or("5");
    let level = match args.get(1).map(String::as_str) {
        Some("easy") => Level::Easy,
        Some("hard") => Level::Hard,
        _ => Level::Medium,
    };
    match size {
        "4" => play::<4>(level),
        "6" => play::<6>(level),
        _ => play::<5>(level),
    }
}
