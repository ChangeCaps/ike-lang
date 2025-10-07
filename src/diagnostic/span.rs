use std::fmt;

use crate::diagnostic::SourceId;

#[derive(Clone, Copy, PartialEq, Eq, Hash)]
pub struct Span {
    pub source: SourceId,
    pub start:  u32,
    pub end:    u32,
}

impl Span {
    pub const fn new(source: SourceId, start: u32, end: u32) -> Self {
        Self { source, start, end }
    }

    pub fn join(self, other: Self) -> Self {
        assert_eq!(self.source, other.source);

        Self {
            source: self.source,
            start:  self.start.min(other.start),
            end:    self.end.max(other.end),
        }
    }

    pub fn len(self) -> u32 {
        self.end - self.start
    }
}

impl fmt::Debug for Span {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        let source = match self.source.index() {
            u32::MAX => String::from("dummy"),
            index => index.to_string(),
        };

        write!(f, "{}..{}:{}", self.start, self.end, source)
    }
}
