use std::panic::Location;

use super::{Sources, Span};

pub trait Emitter {
    fn emit(&mut self, diagnostic: Diagnostic);
}

pub struct DebugEmitter;

impl Emitter for DebugEmitter {
    fn emit(&mut self, diagnostic: Diagnostic) {
        eprintln!("{diagnostic:?}");
    }
}

impl Emitter for Vec<Diagnostic> {
    fn emit(&mut self, diagnostic: Diagnostic) {
        self.push(diagnostic);
    }
}

#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Report {
    pub diagnostics: Vec<Diagnostic>,
}

impl Report {
    pub const fn new() -> Self {
        Self {
            diagnostics: Vec::new(),
        }
    }

    pub fn is_empty(&self) -> bool {
        self.diagnostics.is_empty()
    }

    pub fn push(&mut self, diagnostic: Diagnostic) {
        self.diagnostics.push(diagnostic);
    }
}

impl From<Diagnostic> for Report {
    fn from(diagnostic: Diagnostic) -> Self {
        Self {
            diagnostics: vec![diagnostic],
        }
    }
}

impl IntoIterator for Report {
    type Item = Diagnostic;
    type IntoIter = std::vec::IntoIter<Diagnostic>;

    fn into_iter(self) -> Self::IntoIter {
        self.diagnostics.into_iter()
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Level {
    Error,
    Warn,
    Note,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Diagnostic {
    pub level: Level,
    pub message: String,
    pub labels: Vec<Label>,
    pub location: &'static Location<'static>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Label {
    pub message: Option<String>,
    pub span: Span,
}

impl Diagnostic {
    #[track_caller]
    pub fn new(level: Level, message: impl ToString) -> Self {
        Self {
            level,
            message: message.to_string(),
            labels: Vec::new(),
            location: Location::caller(),
        }
    }

    #[track_caller]
    pub fn error(message: impl ToString) -> Self {
        Self::new(Level::Error, message)
    }

    #[track_caller]
    pub fn warn(message: impl ToString) -> Self {
        Self::new(Level::Warn, message)
    }

    #[track_caller]
    pub fn note(message: impl ToString) -> Self {
        Self::new(Level::Note, message)
    }

    pub fn with_label(mut self, span: Span, message: impl ToString) -> Self {
        self.labels.push(Label {
            message: Some(message.to_string()),
            span,
        });

        self
    }

    pub fn with_span(mut self, span: Span) -> Self {
        self.labels.push(Label {
            message: None,
            span,
        });

        self
    }

    pub fn print(&self, sources: &Sources) {
        use colors::*;

        let (color, level) = match self.level {
            Level::Error => (RED, "error"),
            Level::Warn => (YELLOW, "warning"),
            Level::Note => (BLUE, "note"),
        };

        eprintln!("{color}{level}{RESET}: {BOLD}{}{RESET}", self.message);

        let mut indent = 0;

        for label in &self.labels {
            let source = &sources[label.span.id];
            let (line, _) = label.span.compute_start_line_column(&source.content);

            indent = indent.max(line.to_string().chars().count());
        }

        let mut prev_path = None;

        for label in &self.labels {
            let source = &sources[label.span.id];
            let (line, column) = label.span.compute_start_line_column(&source.content);

            if prev_path != Some(&source.path) {
                let sep = match prev_path {
                    Some(_) => ":::",
                    None => "-->",
                };

                eprintln!(
                    "{}{BLUE}{BOLD}{sep}{RESET} {}:{line}:{column}",
                    " ".repeat(indent),
                    source.path.display(),
                );
            } else {
                eprintln!("{}{BLUE}{BOLD}...{RESET}", " ".repeat(indent));
            }

            prev_path = Some(&source.path);

            let content = source.content.lines().nth(line as usize - 1).unwrap();
            let length = (label.span.hi - label.span.lo) as usize;

            eprintln!("{} {BLUE}{BOLD}|{RESET}", " ".repeat(indent));

            eprintln!(
                "{BLUE}{BOLD}{line}{} |{RESET} {content}",
                " ".repeat(indent - line.to_string().chars().count()),
            );

            eprintln!(
                "{} {BLUE}{BOLD}|{RESET} {}{color}{} {}{RESET}",
                " ".repeat(indent),
                " ".repeat(column as usize - 1),
                "^".repeat(length.min(content.len() + 1 - column as usize)),
                label.message.as_deref().unwrap_or(""),
            );

            eprintln!("{} {BLUE}{BOLD}|{RESET}", " ".repeat(indent));
        }
    }
}

mod colors {
    pub const RESET: &str = "\x1b[0m";
    pub const BOLD: &str = "\x1b[1m";

    pub const RED: &str = "\x1b[31m";
    pub const YELLOW: &str = "\x1b[33m";
    pub const BLUE: &str = "\x1b[34m";
}
