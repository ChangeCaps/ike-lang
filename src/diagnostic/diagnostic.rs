use std::panic::Location;

use super::Span;

pub trait Emitter {
    fn emit(&mut self, diagnostic: Diagnostic);
}

pub struct DebugEmitter;

impl Emitter for DebugEmitter {
    fn emit(&mut self, diagnostic: Diagnostic) {
        eprintln!("{:?}", diagnostic);
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
    level: Level,
    message: String,
    labels: Vec<Label>,
    location: &'static Location<'static>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Label {
    message: Option<String>,
    span: Span,
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
}
