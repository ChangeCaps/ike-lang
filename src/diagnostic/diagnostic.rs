use crate::diagnostic::Span;

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum Level {
    Error,
    Warn,
}

#[derive(Clone, Debug, PartialEq)]
pub struct Diagnostic {
    pub level:   Level,
    pub message: String,
    pub labels:  Vec<Label>,
}

#[derive(Clone, Debug, PartialEq)]
pub struct Label {
    pub message: String,
    pub span:    Span,
}

impl Diagnostic {
    pub fn new(level: Level, message: impl ToString) -> Self {
        Self {
            level,
            message: message.to_string(),
            labels: Vec::new(),
        }
    }

    pub fn error(message: impl ToString) -> Self {
        Self::new(Level::Error, message)
    }

    pub fn warn(message: impl ToString) -> Self {
        Self::new(Level::Warn, message)
    }

    pub fn label(mut self, span: Span, message: impl ToString) -> Self {
        let label = Label {
            message: message.to_string(),
            span,
        };

        self.labels.push(label);
        self
    }

    pub fn span(self, span: Span) -> Self {
        self.label(span, "")
    }
}

pub trait Emitter {
    fn emit(&mut self, diagnostic: Diagnostic);
}

impl Emitter for Vec<Diagnostic> {
    fn emit(&mut self, diagnostic: Diagnostic) {
        self.push(diagnostic);
    }
}

pub struct PanicEmitter;

impl Emitter for PanicEmitter {
    fn emit(&mut self, diagnostic: Diagnostic) {
        panic!("{diagnostic:?}");
    }
}
